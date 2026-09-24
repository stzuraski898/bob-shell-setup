#!/usr/bin/env bash
# run-remaining.sh
# Runs generate_tests.py in serial for ServiceMap, MgrClient, and DaemonServer.
# Each target writes its output to the ceph test tree and prints timing.
#
# Usage (from the bob-shell-setup root):
#   cd /home/steven/Projects/bob-shell-setup
#   bash gemma-agents/run-remaining.sh
#
# To run a single target manually instead, see the individual commands below.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GENERATOR="${SCRIPT_DIR}/generate_tests.py"
PROMPT_DIR="${SCRIPT_DIR}/Inputs/prompts"
CEPH_MGR="/home/steven/Projects/ceph/src/mgr"
CEPH_TEST="/home/steven/Projects/ceph/src/test/mgr"

run_target() {
  local class="$1"
  local source="${CEPH_MGR}/${class}.cc"
  local output="${CEPH_TEST}/test_$(echo "${class}" | tr '[:upper:]' '[:lower:]')_gemma.cc"
  local prompt="${PROMPT_DIR}/${class}.md"

  echo ""
  echo "════════════════════════════════════════════════════════"
  echo "  Target : ${class}"
  echo "  Source : ${source}"
  echo "  Output : ${output}"
  echo "  Prompt : ${prompt}"
  echo "════════════════════════════════════════════════════════"

  local start
  start=$(date +%s)

  python3 "${GENERATOR}" \
    --source  "${source}" \
    --output  "${output}" \
    --prompt-file "${prompt}" \
    --no-feedback

  local end
  end=$(date +%s)
  echo "[done] ${class} finished in $(( end - start ))s"
  echo "       lines: $(wc -l < "${output}")"
  echo "       tail:"
  tail -4 "${output}"
}

run_target "ServiceMap"
run_target "MgrClient"
run_target "DaemonServer"

echo ""
echo "All three targets complete."
