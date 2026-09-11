#!/usr/bin/env bash
# collect-object-history-v3.sh
#
# Minimal raw-corpus collector.  Each class is processed in a background
# subshell — all 27 classes run in parallel.  With 192 cores and 503 GiB RAM
# on sockeni07 the bottleneck is git object store I/O, not CPU, so there is no
# benefit to throttling below the class count.
#
# NOTE: --follow is intentionally NOT used for git log.
#   git log --follow walks through renames and includes commits from before a
#   file was at its current path.  When combined with git show -- <path>, those
#   commits produce "new file mode" diffs (the file being introduced at an old
#   path) that are completely unrelated to the class under analysis.  This
#   contaminated the corpus with hundreds of unrelated commits per class.
#   Without --follow, git log returns only commits that actually touched the
#   file at its current path — which is exactly what we want.
#
# Per-class output (<output_dir>/<ClassName>/):
#   commits.txt      one-liner per non-merge commit touching .cc ∪ .h (newest first)
#   blame.txt        git blame -w -M -C on .cc (and .h if separate)
#   functions.txt    ctags: name | file:line per function definition (kind f or p)
#   diffs/
#     <sha>.diff     git show scoped to the two files for every commit in commits.txt
#
# Requires: git, ctags (universal-ctags preferred; exuberant-ctags OK for line numbers)
#
# Usage (from inside a ceph worktree):
#   bash collect-object-history-v3.sh [output_dir]
#
# Deploy and run on sockeni07:
#   scp collect-object-history-v3.sh szuraski@sockeni07:~/tmp/
#   ssh szuraski@sockeni07 'cd /home/szuraski/ceph && \
#     bash ~/tmp/collect-object-history-v3.sh 2>&1 | tee ~/tmp/collect-v3.log'

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

CEPH_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo ".")"
OUTPUT_DIR="${1:-/home/szuraski/BobOutput/Object History/v3}"

declare -A CLASS_FILES=(
  [ActivePyModule]="src/mgr/ActivePyModule.cc:src/mgr/ActivePyModule.h"
  [ActivePyModules]="src/mgr/ActivePyModules.cc:src/mgr/ActivePyModules.h"
  [ClusterState]="src/mgr/ClusterState.cc:src/mgr/ClusterState.h"
  [DaemonHealthMetric]="src/mgr/DaemonHealthMetric.cc:src/mgr/DaemonHealthMetric.h"
  [DaemonHealthMetricCollector]="src/mgr/DaemonHealthMetricCollector.cc:src/mgr/DaemonHealthMetricCollector.h"
  [DaemonKey]="src/mgr/DaemonKey.cc:src/mgr/DaemonKey.h"
  [DaemonPerfCounters]="src/mgr/DaemonPerfCounters.cc:src/mgr/DaemonPerfCounters.h"
  [DaemonServer]="src/mgr/DaemonServer.cc:src/mgr/DaemonServer.h"
  [DaemonState]="src/mgr/DaemonState.cc:src/mgr/DaemonState.h"
  [Gil]="src/mgr/Gil.cc:src/mgr/Gil.h"
  [MDSPerfMetricCollector]="src/mgr/MDSPerfMetricCollector.cc:src/mgr/MDSPerfMetricCollector.h"
  [MetricCollector]="src/mgr/MetricCollector.cc:src/mgr/MetricCollector.h"
  [MgrCap]="src/mgr/MgrCap.cc:src/mgr/MgrCap.h"
  [MgrClient]="src/mgr/MgrClient.cc:src/mgr/MgrClient.h"
  [MgrMapCache]="src/mgr/MgrMapCache.cc:src/mgr/MgrMapCache.h"
  [MgrOpRequest]="src/mgr/MgrOpRequest.cc:src/mgr/MgrOpRequest.h"
  [MgrStandby]="src/mgr/MgrStandby.cc:src/mgr/MgrStandby.h"
  [Mgr]="src/mgr/Mgr.cc:src/mgr/Mgr.h"
  [OSDPerfMetricCollector]="src/mgr/OSDPerfMetricCollector.cc:src/mgr/OSDPerfMetricCollector.h"
  [PerfCounterInstance]="src/mgr/PerfCounterInstance.cc:src/mgr/PerfCounterInstance.h"
  [PyFormatter]="src/mgr/PyFormatter.cc:src/mgr/PyFormatter.h"
  [PyModule]="src/mgr/PyModule.cc:src/mgr/PyModule.h"
  [PyModuleRegistry]="src/mgr/PyModuleRegistry.cc:src/mgr/PyModuleRegistry.h"
  [PyModuleRunner]="src/mgr/PyModuleRunner.cc:src/mgr/PyModuleRunner.h"
  [ServiceMap]="src/mgr/ServiceMap.cc:src/mgr/ServiceMap.h"
  [StandbyPyModules]="src/mgr/StandbyPyModules.cc:src/mgr/StandbyPyModules.h"
  [ThreadMonitor]="src/mgr/ThreadMonitor.cc:src/mgr/ThreadMonitor.h"
)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Serialise log output so concurrent subshells don't interleave lines.
# Uses a lock file + flock; falls back to a plain echo if flock is unavailable.
LOG_LOCK="${TMPDIR:-/tmp}/collect-v3-$$.lock"
touch "${LOG_LOCK}"

log() {
  if command -v flock &>/dev/null; then
    flock "${LOG_LOCK}" echo "[collect-v3] $*" >&2
  else
    echo "[collect-v3] $*" >&2
  fi
}

# Detect ctags — prefer universal-ctags for accurate kind:f output.
CTAGS_BIN=""
for candidate in universal-ctags ctags; do
  if command -v "${candidate}" &>/dev/null; then
    CTAGS_BIN="${candidate}"
    break
  fi
done
[[ -z "${CTAGS_BIN}" ]] && log "WARNING: ctags not found — functions.txt will be empty"

# ---------------------------------------------------------------------------
# Per-class worker function
# Runs in a background subshell.  All state is local; the only shared
# resources are the (already-created) output directory and the log lock.
# ---------------------------------------------------------------------------

collect_class() {
  local CLASS="$1"
  local SRC_CC="$2"
  local SRC_H="$3"

  local ABS_CC="${CEPH_ROOT}/${SRC_CC}"
  local ABS_H="${CEPH_ROOT}/${SRC_H}"
  local OUT="${OUTPUT_DIR}/${CLASS}"
  local DIFFS_DIR="${OUT}/diffs"
  mkdir -p "${DIFFS_DIR}"

  log "--- ${CLASS} ---"

  # ---- commits.txt --------------------------------------------------------
  {
    echo "# Non-merge commits touching ${SRC_CC} and/or ${SRC_H} (newest first)"
    echo "# Format: SHA date author | subject"
    echo "# collected_at: ${RUN_TS}  head: ${HEAD_SHA}"
    echo "#"
    {
      git log --no-merges --format="%H" -- "${SRC_CC}" 2>/dev/null || true
      [[ -f "${ABS_H}" && "${SRC_H}" != "${SRC_CC}" ]] && \
        git log --no-merges --format="%H" -- "${SRC_H}" 2>/dev/null || true
    } | sort -u | \
    git log --no-walk --stdin --format="%H %ad %aN | %s" --date=short 2>/dev/null \
      || true
  } > "${OUT}/commits.txt"

  local COMMIT_COUNT
  COMMIT_COUNT=$(grep -c "^[0-9a-f]" "${OUT}/commits.txt" 2>/dev/null || echo 0)

  # ---- blame.txt ----------------------------------------------------------
  {
    echo "# git blame -w -M -C ${SRC_CC}"
    echo "#"
    git blame -w -M -C -- "${ABS_CC}" 2>/dev/null || echo "# (file not found or empty)"
    if [[ -f "${ABS_H}" && "${SRC_H}" != "${SRC_CC}" ]]; then
      echo ""
      echo "# git blame -w -M -C ${SRC_H}"
      echo "#"
      git blame -w -M -C -- "${ABS_H}" 2>/dev/null || echo "# (file not found or empty)"
    fi
  } > "${OUT}/blame.txt"

  # ---- functions.txt ------------------------------------------------------
  {
    echo "# Function list for ${CLASS} (via ctags)"
    echo "# Format: qualified_name | file:line"
    echo "#"
    if [[ -n "${CTAGS_BIN}" ]]; then
      for src_file in "${ABS_CC}" "${ABS_H}"; do
        [[ -f "${src_file}" ]] || continue
        local rel="${src_file#${CEPH_ROOT}/}"
        "${CTAGS_BIN}" \
          --language-force=C++ \
          --c++-kinds=f+p \
          --fields=+nk \
          -f - "${src_file}" 2>/dev/null \
        | grep -v "^!" \
        | awk -v rel="${rel}" 'BEGIN{FS="\t"} {
            name=$1; lineno=""; kind=""
            raw=$0
            if (match(raw, /\tline:([0-9]+)/, a)) lineno=a[1]
            if (match(raw, /\tkind:([^\t]+)/, a)) kind=a[1]
            if (lineno=="" && NF>=5) lineno=$5
            if (kind==""  && NF>=4) kind=$4
            if (lineno != "" && (kind=="f" || kind=="p"))
              print name " | " rel ":" lineno
          }' || true
      done
    else
      echo "# ctags not available"
    fi
  } > "${OUT}/functions.txt"

  local FUNC_COUNT
  FUNC_COUNT=$(grep -v "^#" "${OUT}/functions.txt" | grep -c "." 2>/dev/null || echo 0)

  # ---- diffs/<sha>.diff ---------------------------------------------------
  while IFS= read -r line; do
    local sha="${line%% *}"
    [[ "${sha}" =~ ^[0-9a-f]{40}$ ]] || continue
    local diff_file="${DIFFS_DIR}/${sha}.diff"
    [[ -f "${diff_file}" ]] && continue  # idempotent
    git show "${sha}" -- "${SRC_CC}" "${SRC_H}" > "${diff_file}" 2>/dev/null || true
  done < "${OUT}/commits.txt"

  local DIFF_COUNT
  DIFF_COUNT=$(find "${DIFFS_DIR}" -name "*.diff" | wc -l)

  log "  ${CLASS}: ${COMMIT_COUNT} commits, ${FUNC_COUNT} functions, ${DIFF_COUNT} diffs -> ${OUT}/"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

cd "${CEPH_ROOT}"

HEAD_SHA=$(git rev-parse HEAD)
HEAD_DATE=$(git log -1 --format="%ci" HEAD)
RUN_TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

log "HEAD: ${HEAD_SHA} (${HEAD_DATE})"
log "Output dir: ${OUTPUT_DIR}"
log "Launching ${#CLASS_FILES[@]} workers in parallel..."

mkdir -p "${OUTPUT_DIR}"

# Launch one background subshell per class.  27 classes on 192 cores — no
# throttle needed; all classes fit comfortably in parallel.
for CLASS in $(echo "${!CLASS_FILES[@]}" | tr ' ' '\n' | sort); do
  IFS=':' read -r SRC_CC SRC_H <<< "${CLASS_FILES[$CLASS]}"
  collect_class "${CLASS}" "${SRC_CC}" "${SRC_H}" &
done

# Wait for all workers to finish, collecting exit statuses.
FAILED=0
for job in $(jobs -p); do
  wait "${job}" || { log "WARNING: worker PID ${job} exited non-zero"; FAILED=$(( FAILED + 1 )); }
done

# ---------------------------------------------------------------------------
# Index (written after all workers finish)
# ---------------------------------------------------------------------------
{
  echo "# Object History v3 Index"
  echo "# collected_at: ${RUN_TS}"
  echo "# head: ${HEAD_SHA} (${HEAD_DATE})"
  echo "#"
  printf "%-35s %8s %8s %8s\n" "Class" "Commits" "Functions" "Diffs"
  printf "%-35s %8s %8s %8s\n" "-----" "-------" "---------" "-----"
  for CLASS in $(echo "${!CLASS_FILES[@]}" | tr ' ' '\n' | sort); do
    OUT="${OUTPUT_DIR}/${CLASS}"
    commits=$(grep -c "^[0-9a-f]" "${OUT}/commits.txt" 2>/dev/null || echo 0)
    funcs=$(grep -v "^#" "${OUT}/functions.txt" | grep -c "." 2>/dev/null || echo 0)
    diffs=$(find "${OUT}/diffs" -name "*.diff" 2>/dev/null | wc -l)
    printf "%-35s %8s %8s %8s\n" "${CLASS}" "${commits}" "${funcs}" "${diffs}"
  done
} > "${OUTPUT_DIR}/INDEX.txt"

rm -f "${LOG_LOCK}"

log ""
if [[ "${FAILED}" -gt 0 ]]; then
  log "Collection complete (v3) with ${FAILED} worker failure(s)."
else
  log "Collection complete (v3). All workers succeeded."
fi
log "Index: ${OUTPUT_DIR}/INDEX.txt"
