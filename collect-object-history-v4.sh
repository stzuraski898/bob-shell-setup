#!/usr/bin/env bash
# collect-object-history-v4.sh
#
# Rename-aware corpus collector.  Replaces v3.
#
# The core improvement over v3: each class's file history is resolved through
# renames before collecting commits and diffs.  This means commits that touched
# the class while it lived at a former path (e.g. MgrPyModule.cc before it
# became ActivePyModule.cc) are included and their diffs are scoped to the
# correct historical path.
#
# How rename resolution works
# ---------------------------
# For each file (.cc and .h separately):
#   git log --follow --name-status --format='COMMIT:%H' -- <current_path>
#
# produces a stream of (sha, status-lines) records that we walk with awk to
# build a list of path segments:
#   <path> <sha_newest_in_segment> <sha_oldest_in_segment>
#
# newest segment first, oldest last.  When collecting commits we query git log
# for each segment scoped to its path.  When writing diffs we use the path
# that was active at the time of the commit, avoiding the v3 "new file mode"
# contamination that occurred when git show was called with the current path
# on a commit that predates the rename.
#
# Per-class output (<output_dir>/<ClassName>/):
#   commits.txt        one-liner per non-merge commit (newest first, rename-aware)
#   blame.txt          git blame -w -M -C on .cc (and .h if separate)
#   functions.txt      ctags: name | file:line per function definition
#   rename_chain.txt   resolved file path history (.cc and .h separately)
#   diffs/
#     <sha>.diff       git show scoped to the historically-correct path
#
# Requires: git, ctags (universal-ctags preferred; exuberant-ctags OK)
#
# Usage (from inside a ceph worktree):
#   bash collect-object-history-v4.sh [output_dir]
#
# Deploy and run on sockeni07:
#   scp collect-object-history-v4.sh szuraski@sockeni07:~/tmp/
#   ssh szuraski@sockeni07 'cd /home/szuraski/ceph && \
#     bash ~/tmp/collect-object-history-v4.sh 2>&1 | tee ~/tmp/collect-v4.log'

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

CEPH_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo ".")"
OUTPUT_DIR="${1:-/home/szuraski/BobOutput/Object History/v4}"

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

LOG_LOCK="${TMPDIR:-/tmp}/collect-v4-$$.lock"
touch "${LOG_LOCK}"

log() {
  if command -v flock &>/dev/null; then
    flock "${LOG_LOCK}" echo "[collect-v4] $*" >&2
  else
    echo "[collect-v4] $*" >&2
  fi
}

CTAGS_BIN=""
for candidate in universal-ctags ctags; do
  if command -v "${candidate}" &>/dev/null; then
    CTAGS_BIN="${candidate}"
    break
  fi
done
[[ -z "${CTAGS_BIN}" ]] && log "WARNING: ctags not found — functions.txt will be empty"

# ---------------------------------------------------------------------------
# resolve_rename_chain <current_path>
#
# Writes one line per path segment to stdout:
#   <path> <sha_newest_in_segment> <sha_oldest_in_segment>
#
# Lines are ordered newest-first.  The newest segment is always the current
# path.  sha_newest / sha_oldest are the first and last commit SHAs within
# that segment; these are used later to map each SHA to its correct path.
#
# git log --follow --name-status emits blocks of:
#   COMMIT:<sha>
#   <blank>
#   R100\t<old>\t<new>   ← rename (old_path → new_path)
#   M\t<path>            ← modify
#   A\t<path>            ← add (file first appeared here)
#   <blank>
#
# We walk the stream: each R line means the path changes for all commits older
# than the current one, so we close the current segment and open a new one at
# the old path.
# ---------------------------------------------------------------------------

resolve_rename_chain() {
  local current_path="$1"

  git log --follow --name-status --format='COMMIT:%H' -- "${current_path}" \
    2>/dev/null \
  | awk -v start="${current_path}" '
    BEGIN {
      cur_path = start
      seg_new  = ""
      seg_old  = ""
    }

    /^COMMIT:/ {
      sha = substr($0, 8)
      if (seg_new == "") seg_new = sha
      seg_old = sha
      next
    }

    /^R/ {
      # $2 = old path, $3 = new path
      if (seg_new != "") print cur_path " " seg_new " " seg_old
      cur_path = $2
      seg_new  = seg_old
      seg_old  = seg_old
      next
    }

    END {
      if (seg_new != "") print cur_path " " seg_new " " seg_old
    }
  '
}

# ---------------------------------------------------------------------------
# build_sha_to_path_map <chain_file>
#
# Reads segment lines from stdin ("path sha_new sha_old") and writes:
#   <sha> <path>
# for every commit in each segment that touched that path.
# ---------------------------------------------------------------------------

build_sha_to_path_map() {
  local chain_file="$1"
  while IFS=' ' read -r path seg_new seg_old; do
    # commits strictly between seg_old and seg_new
    git log --no-merges --format="%H" "${seg_old}~1..${seg_new}" -- "${path}" \
      2>/dev/null \
    | while IFS= read -r sha; do echo "${sha} ${path}"; done
    # seg_old itself (excluded by ~1 above)
    git log --no-merges --format="%H" -1 "${seg_old}" -- "${path}" \
      2>/dev/null \
    | while IFS= read -r sha; do echo "${sha} ${path}"; done
  done < "${chain_file}"
}

# ---------------------------------------------------------------------------
# Per-class worker — runs in a background subshell
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

  # ---- rename_chain.txt ---------------------------------------------------
  local chain_cc="${OUT}/chain_cc.tmp"
  local chain_h="${OUT}/chain_h.tmp"

  resolve_rename_chain "${SRC_CC}" > "${chain_cc}"
  if [[ "${SRC_H}" != "${SRC_CC}" ]]; then
    resolve_rename_chain "${SRC_H}" > "${chain_h}"
  else
    cp "${chain_cc}" "${chain_h}"
  fi

  {
    echo "# Rename chain for ${SRC_CC} (newest segment first)"
    echo "# Format: path sha_newest sha_oldest"
    echo "#"
    cat "${chain_cc}"
    if [[ "${SRC_H}" != "${SRC_CC}" ]]; then
      echo "#"
      echo "# Rename chain for ${SRC_H}"
      echo "#"
      cat "${chain_h}"
    fi
  } > "${OUT}/rename_chain.txt"

  # ---- sha→path maps ------------------------------------------------------
  local map_cc="${OUT}/map_cc.tmp"
  local map_h="${OUT}/map_h.tmp"

  build_sha_to_path_map "${chain_cc}" > "${map_cc}"
  if [[ "${SRC_H}" != "${SRC_CC}" ]]; then
    build_sha_to_path_map "${chain_h}" > "${map_h}"
  else
    cp "${map_cc}" "${map_h}"
  fi

  # ---- commits.txt --------------------------------------------------------
  {
    echo "# Non-merge commits touching ${SRC_CC} and/or ${SRC_H} (rename-aware, newest first)"
    echo "# Format: SHA date author | subject"
    echo "# collected_at: ${RUN_TS}  head: ${HEAD_SHA}"
    echo "#"
    {
      awk '{print $1}' "${map_cc}" 2>/dev/null || true
      awk '{print $1}' "${map_h}"  2>/dev/null || true
    } | sort -u \
      | git log --no-walk --stdin \
          --format="%H %ad %aN | %s" --date=short \
          2>/dev/null || true
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
  # Use the historically-correct path for each commit so git show never
  # produces a spurious "new file mode" diff.
  while IFS= read -r line; do
    local sha="${line%% *}"
    [[ "${sha}" =~ ^[0-9a-f]{40}$ ]] || continue
    local diff_file="${DIFFS_DIR}/${sha}.diff"
    [[ -f "${diff_file}" ]] && continue  # idempotent

    local hist_cc hist_h
    hist_cc=$(awk -v s="${sha}" '$1==s{print $2; exit}' "${map_cc}" 2>/dev/null || true)
    hist_h=$(awk  -v s="${sha}" '$1==s{print $2; exit}' "${map_h}"  2>/dev/null || true)

    # Fall back to current paths if not found in map (shouldn't happen)
    [[ -z "${hist_cc}" ]] && hist_cc="${SRC_CC}"
    [[ -z "${hist_h}"  ]] && hist_h="${SRC_H}"

    if [[ "${hist_cc}" == "${hist_h}" ]]; then
      git show "${sha}" -- "${hist_cc}" > "${diff_file}" 2>/dev/null || true
    else
      git show "${sha}" -- "${hist_cc}" "${hist_h}" > "${diff_file}" 2>/dev/null || true
    fi
  done < "${OUT}/commits.txt"

  # Clean up temp files
  rm -f "${chain_cc}" "${chain_h}" "${map_cc}" "${map_h}"

  local DIFF_COUNT
  DIFF_COUNT=$(find "${DIFFS_DIR}" -name "*.diff" | wc -l)

  # ---- commit_function_map.txt --------------------------------------------
  # Maps each commit to the current functions it touched, using git's own
  # hunk context annotation on @@ lines rather than line-number ranges.
  #
  # Git annotates every @@ hunk header with the nearest enclosing function
  # signature above the hunk, e.g.:
  #   @@ -123,10 +125,12 @@ DaemonServer::handle_report(...)
  # This works across the full history including pre-rename commits because
  # it is derived from the diff content itself, not from current line numbers.
  #
  # We then match those extracted names against the current functions.txt to
  # anchor them to current function identities.  A commit that predates a
  # rename but modified what is now handle_report() will correctly map to
  # handle_report — even though the line numbers have shifted.
  #
  # Format per line: <sha> | <func1> <func2> ...
  # Commits that touched no recognised function emit: <sha> | (no functions)
  {
    echo "# Commit → function map for ${CLASS}"
    echo "# Format: SHA | func1 func2 ..."
    echo "# collected_at: ${RUN_TS}  head: ${HEAD_SHA}"
    echo "# Method: git @@ hunk context matched against current functions.txt"
    echo "#"

    # Build a set of current function names (bare name only, no file:line)
    # for matching against git's hunk context strings.
    local func_names="${OUT}/func_names.tmp"
    grep -v "^#" "${OUT}/functions.txt" \
      | awk -F' \\| ' '{print $1}' \
      | sort -u > "${func_names}"

    while IFS= read -r line; do
      local sha="${line%% *}"
      [[ "${sha}" =~ ^[0-9a-f]{40}$ ]] || continue
      local diff_file="${DIFFS_DIR}/${sha}.diff"
      [[ -f "${diff_file}" ]] || continue

      local touched_funcs
      touched_funcs=$(awk -v func_names="${func_names}" '
        BEGIN {
          # Load current function names into a lookup set
          while ((getline fn < func_names) > 0) known[fn] = 1
          close(func_names)
        }
        /^@@ / {
          # Git appends the enclosing function context after the last @@ :
          #   @@ -a,b +c,d @@ ClassName::method_name(args...)
          # Strip everything up to and including the second @@ then extract
          # the first token, which is typically Class::method or just method.
          ctx = $0
          sub(/^@@[^@]*@@[ \t]*/, "", ctx)   # remove @@ -a,b +c,d @@ prefix
          sub(/\(.*/, "", ctx)               # strip argument list
          sub(/^[ \t]+/, "", ctx)            # trim leading whitespace
          sub(/[ \t]+$/, "", ctx)            # trim trailing whitespace
          if (ctx == "") next

          # ctx may be "ClassName::method" — check full form and bare name
          bare = ctx
          sub(/.*::/, "", bare)

          if (ctx  in known) funcs_seen[ctx]  = 1
          if (bare in known) funcs_seen[bare] = 1
        }
        END {
          result = ""
          for (f in funcs_seen) result = result (result=="" ? "" : " ") f
          print result
        }
      ' "${diff_file}")

      if [[ -z "${touched_funcs}" ]]; then
        echo "${sha} | (no functions)"
      else
        echo "${sha} | ${touched_funcs}"
      fi
    done < "${OUT}/commits.txt"

    rm -f "${func_names}"
  } > "${OUT}/commit_function_map.txt"

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

for CLASS in $(echo "${!CLASS_FILES[@]}" | tr ' ' '\n' | sort); do
  IFS=':' read -r SRC_CC SRC_H <<< "${CLASS_FILES[$CLASS]}"
  collect_class "${CLASS}" "${SRC_CC}" "${SRC_H}" &
done

FAILED=0
for job in $(jobs -p); do
  wait "${job}" || { log "WARNING: worker PID ${job} exited non-zero"; FAILED=$(( FAILED + 1 )); }
done

# ---------------------------------------------------------------------------
# Index
# ---------------------------------------------------------------------------
{
  echo "# Object History v4 Index (rename-aware)"
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
  log "Collection complete (v4) with ${FAILED} worker failure(s)."
else
  log "Collection complete (v4). All workers succeeded."
fi
log "Index: ${OUTPUT_DIR}/INDEX.txt"
