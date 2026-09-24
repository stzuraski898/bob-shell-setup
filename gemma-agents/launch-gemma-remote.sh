#!/usr/bin/env bash
# launch-gemma-remote.sh
# Runs generate_tests.py on sockeni07 using Ollama + Gemma 4 over SSH.
#
# What it does:
#   1. Syncs generate_tests.py and all Inputs/prompts/ to sockeni07
#   2. Syncs the required ceph source files to sockeni07
#   3. Runs generate_tests.py on the remote machine for each target in serial
#   4. Copies the generated test files back to the local ceph tree
#
# Prerequisites (one-time):
#   ./gemma-agents/setup-gemma-remote.sh
#
# sockeni07 advantages over local machine:
#   503 GB RAM / 222 GB free  →  gemma4:27b fits entirely in CPU RAM
#   No GPU required            →  pure CPU inference, no VRAM contention
#   Idle server                →  no competing workloads
#
# Usage (from the bob-shell-setup root):
#   chmod +x gemma-agents/launch-gemma-remote.sh
#   ./gemma-agents/launch-gemma-remote.sh
#   ./gemma-agents/launch-gemma-remote.sh --model gemma4:latest
#   ./gemma-agents/launch-gemma-remote.sh --target DaemonKey   # single target
#   ./gemma-agents/launch-gemma-remote.sh --no-feedback        # skip build loop

set -euo pipefail

REMOTE_HOST="szuraski@sockeni07"
REMOTE_WORK="/home/szuraski/gemma-test-gen"
REMOTE_CEPH="/home/szuraski/ceph"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOCAL_CEPH="/home/steven/Projects/ceph"
MODEL="gemma4:27b"
NO_FEEDBACK=""
ONLY_TARGET=""

# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --model)       MODEL="$2";        shift 2 ;;
    --target)      ONLY_TARGET="$2";  shift 2 ;;
    --no-feedback) NO_FEEDBACK="--no-feedback"; shift ;;
    --host)        REMOTE_HOST="$2";  shift 2 ;;
    *)
      echo "Unknown argument: $1" >&2
      echo "Usage: $0 [--model <name>] [--target <ClassName>] [--no-feedback] [--host <user@host>]" >&2
      exit 1
      ;;
  esac
done

# ---------------------------------------------------------------------------
# Target definitions: ClassName → (source basename, output basename)
# The source file fed to Gemma is the .cc file; the header is included in
# the prompt text so Gemma already has the full interface.
# ---------------------------------------------------------------------------
declare -A SOURCE_FILE=(
  [DaemonHealthMetric]="DaemonHealthMetric.cc"
  [DaemonKey]="DaemonKey.cc"
  [ServiceMap]="ServiceMap.cc"
  [MgrClient]="MgrClient.cc"
  [DaemonServer]="DaemonServer.cc"
)
declare -A OUTPUT_FILE=(
  [DaemonHealthMetric]="test_daemonhealthmetric_gemma.cc"
  [DaemonKey]="test_daemonkey_gemma.cc"
  [ServiceMap]="test_servicemap_gemma.cc"
  [MgrClient]="test_mgrclient_gemma.cc"
  [DaemonServer]="test_daemonserver_gemma.cc"
)

# Build list of targets to run
declare -a TARGETS=()
if [[ -n "$ONLY_TARGET" ]]; then
  if [[ -z "${SOURCE_FILE[$ONLY_TARGET]+x}" ]]; then
    echo "Unknown target: ${ONLY_TARGET}" >&2
    echo "Valid targets: ${!SOURCE_FILE[*]}" >&2
    exit 1
  fi
  TARGETS=("$ONLY_TARGET")
else
  TARGETS=(DaemonHealthMetric DaemonKey ServiceMap MgrClient DaemonServer)
fi

# ---------------------------------------------------------------------------
# Verify Ollama is reachable on the remote host
# ---------------------------------------------------------------------------
echo "=== Checking Ollama on ${REMOTE_HOST} ==="
if ! ssh "${REMOTE_HOST}" 'export PATH="/usr/local/bin:${HOME}/.local/bin:${PATH}"; curl -sf http://127.0.0.1:11434/api/tags >/dev/null 2>&1'; then
  echo ""
  echo "ERROR: ollama serve is not running on ${REMOTE_HOST}." >&2
  echo "Run:  ./gemma-agents/setup-gemma-remote.sh" >&2
  exit 1
fi
echo "  Ollama is reachable."

# Check the model is available
HAVE_MODEL=$(ssh "${REMOTE_HOST}" bash -s -- "${MODEL%%:*}" <<'REMOTE'
export PATH="/usr/local/bin:${HOME}/.local/bin:${PATH}"
ollama list 2>/dev/null | grep -c "$1" || true
REMOTE
)
if [[ "$HAVE_MODEL" -eq 0 ]]; then
  echo "ERROR: model '${MODEL}' not found on ${REMOTE_HOST}. Run setup-gemma-remote.sh first." >&2
  exit 1
fi
echo "  Model '${MODEL}' is available."
echo ""

# ---------------------------------------------------------------------------
# Step 1 — sync generate_tests.py and prompts to the remote machine
# ---------------------------------------------------------------------------
echo "[sync] Uploading generate_tests.py and prompts to ${REMOTE_HOST}:${REMOTE_WORK}/ …"
ssh "${REMOTE_HOST}" "mkdir -p ${REMOTE_WORK@Q}/Inputs/prompts ${REMOTE_WORK@Q}/output"
rsync -az --info=progress2 \
  "${SCRIPT_DIR}/generate_tests.py" \
  "${REMOTE_HOST}:${REMOTE_WORK}/"
rsync -az --info=progress2 \
  "${SCRIPT_DIR}/Inputs/prompts/" \
  "${REMOTE_HOST}:${REMOTE_WORK}/Inputs/prompts/"

# ---------------------------------------------------------------------------
# Step 2 — sync the required ceph source files
# ---------------------------------------------------------------------------
echo "[sync] Uploading ceph mgr source files …"
ssh "${REMOTE_HOST}" "mkdir -p ${REMOTE_CEPH@Q}/src/mgr ${REMOTE_CEPH@Q}/src/test/mgr"

# Collect all source + header files needed across targets
declare -a SYNC_FILES=()
for target in "${TARGETS[@]}"; do
  src="${SOURCE_FILE[$target]}"
  base="${src%.cc}"
  SYNC_FILES+=( "${LOCAL_CEPH}/src/mgr/${src}" )
  [[ -f "${LOCAL_CEPH}/src/mgr/${base}.h" ]] && SYNC_FILES+=( "${LOCAL_CEPH}/src/mgr/${base}.h" )
done

# Deduplicate and rsync
printf '%s\n' "${SYNC_FILES[@]}" | sort -u | while read -r f; do
  rsync -az "${f}" "${REMOTE_HOST}:${REMOTE_CEPH}/src/mgr/"
done

echo ""

# ---------------------------------------------------------------------------
# Step 3 — run each target on the remote machine in serial
# ---------------------------------------------------------------------------
for target in "${TARGETS[@]}"; do
  src="${SOURCE_FILE[$target]}"
  out="${OUTPUT_FILE[$target]}"
  prompt="Inputs/prompts/${target}.md"

  echo "════════════════════════════════════════════════════════"
  echo "  Target  : ${target}"
  echo "  Model   : ${MODEL}"
  echo "════════════════════════════════════════════════════════"

  local_start=$(date +%s)

  ssh "${REMOTE_HOST}" bash -s -- "${src}" "${out}" "${prompt}" "${MODEL}" "${NO_FEEDBACK:-}" <<REMOTE
set -euo pipefail
export PATH="/usr/local/bin:\${HOME}/.local/bin:\${PATH}"
cd "${REMOTE_WORK}"
src="\$1"; out="\$2"; prompt="\$3"; model="\$4"; no_feedback="\$5"

# Ensure ollama serve is running (it may have timed out)
if ! curl -sf http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
  echo "  [remote] restarting ollama serve …"
  nohup ollama serve >/tmp/ollama-serve.log 2>&1 &
  sleep 5
fi

python3 generate_tests.py \\
  --source  "${REMOTE_CEPH}/src/mgr/\${src}" \\
  --output  "${REMOTE_WORK}/output/\${out}" \\
  --prompt-file "\${prompt}" \\
  --model "\${model}" \\
  \${no_feedback}
REMOTE

  local_end=$(date +%s)
  echo "[done] ${target} finished in $(( local_end - local_start ))s"

  # Step 4 — copy output back
  echo "[pull] Copying ${out} to ${LOCAL_CEPH}/src/test/mgr/ …"
  rsync -az \
    "${REMOTE_HOST}:${REMOTE_WORK}/output/${out}" \
    "${LOCAL_CEPH}/src/test/mgr/${out}"

  lines=$(wc -l < "${LOCAL_CEPH}/src/test/mgr/${out}")
  echo "       ${lines} lines written locally."
  echo ""
done

echo "=== All targets complete ==="
echo ""
echo "Generated files:"
for target in "${TARGETS[@]}"; do
  out="${OUTPUT_FILE[$target]}"
  local_path="${LOCAL_CEPH}/src/test/mgr/${out}"
  if [[ -f "$local_path" ]]; then
    printf "  %-45s  %4d lines\n" "${out}" "$(wc -l < "${local_path}")"
  fi
done
