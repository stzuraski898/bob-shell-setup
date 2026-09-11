#!/usr/bin/env bash
# collect-object-history-v2.sh
#
# v2.1 — correctness fixes over v2:
#   - end-line race eliminated: full inventory parsed into arrays before any
#     worker is launched; end = next_start - 1 (exact), last = EOF line count
#   - function_id is now unique across overloads: Scope__name__<sig-hash>
#   - ctags decl + def records are grouped by canonical identity then merged;
#     first-wins no longer silently drops .cc definitions
#   - --follow runs separately for .cc and .h; results are unioned
#   - 02-messages.txt operates on the exact SHA union from 01 (.cc ∪ .h)
#   - evidence tier labelling: [L]=direct [G][S]=heuristic [B]=current-blame
#   - 00-HEADER: "uncapped multi-evidence provenance" (not "complete")
#   - blame SHA parsed from porcelain header lines (not grep-oE)
#   - 07-classes.txt uses ctags (same parser as functions)
#   - merge vs non-merge commit counts labelled explicitly in 09
#
# Requires: git, ctags (universal-ctags preferred; exuberant-ctags works)
# Usage (run from inside a ceph worktree):
#   bash collect-object-history-v2.sh [output_dir]
#
# Deploy and run on sockeni07:
#   scp collect-object-history-v2.sh szuraski@sockeni07:~/tmp/
#   ssh szuraski@sockeni07 'mkdir -p ~/tmp && rm -rf "/home/szuraski/BobOutput/Object History/raw" && cd /home/szuraski/ceph && bash ~/tmp/collect-object-history-v2.sh 2>&1 | tee ~/tmp/collect-object-history-v2.log'
#
# Output layout:
#   <output_dir>/<ClassName>/
#     00-HEADER.txt          metadata, HEAD SHA, run timestamp
#     01-commits.txt         ALL non-merge commits touching .cc ∪ .h (SHA list)
#     01b-commits-all.txt    ALL commits including merges
#     02-messages.txt        full message for every SHA in 01 (.cc ∪ .h)
#     03-signal-commits.txt  signal-annotated subset of 01
#     04-signal-diffs.txt    diffs for signal commits
#     05-blame.txt           git blame -w -M -C on current source
#     06-todos.txt           TODO/FIXME/HACK lines
#     07-classes.txt         class/struct definitions (via ctags)
#     08-functions.txt       function inventory: function_id | qualified | sig |
#                              decl_file:line | def_file:line | kind
#     09-function-commits.txt  function → SHA index with evidence tags
#                              evidence tiers:
#                                [L] direct  — git log -L line-range
#                                [B] current — git blame (current-line authors)
#                                [S] heuristic — pickaxe on qualified name
#                                [G] heuristic — grep on bare name
#     10-commits-detail.txt  one block per unique SHA in 09 (deduped)

set -euo pipefail

safe() { "$@" || true; }

# ---------------------------------------------------------------------------
# Parallelism
# ---------------------------------------------------------------------------

FUNC_WORKERS="${FUNC_WORKERS:-8}"
CLASS_WORKERS="${CLASS_WORKERS:-4}"

acquire_slot() {
  local max="$1"
  while [[ $(jobs -rp | wc -l) -ge "${max}" ]]; do
    wait -n 2>/dev/null || true
  done
}

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

CEPH_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo ".")"
OUTPUT_DIR="${1:-/home/szuraski/BobOutput/Object History/raw}"

SIGNAL_PATTERN="fix|fixes|fixed|bug|regression|revert|reverts|reverted|handle|support|allow|prevent|reject|validate|implement|introduce|TODO|FIXME|HACK|workaround"

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

log()  { echo "[collect-object-history-v2] $*" >&2; }
warn() { echo "[collect-object-history-v2] WARNING: $*" >&2; }

# Check for ctags — prefer universal-ctags.
# Exuberant-ctags does NOT support --output-format=u-ctags and will silently
# produce a different tab format where kind/line/signature are not separate
# fields.  Detect which variant we have and refuse to use exuberant-ctags.
CTAGS_BIN=""
CTAGS_IS_UNIVERSAL=0
for candidate in universal-ctags ctags; do
  if command -v "${candidate}" &>/dev/null; then
    if "${candidate}" --version 2>&1 | grep -qi "universal ctags"; then
      CTAGS_BIN="${candidate}"
      CTAGS_IS_UNIVERSAL=1
      break
    elif [[ -z "${CTAGS_BIN}" ]]; then
      # Exuberant-ctags: record it as a fallback but flag the limitation
      CTAGS_BIN="${candidate}"
    fi
  fi
done
if [[ -z "${CTAGS_BIN}" ]]; then
  warn "ctags not found — function/class inventory will be empty"
elif [[ "${CTAGS_IS_UNIVERSAL}" -eq 0 ]]; then
  warn "ctags is exuberant-ctags, not universal-ctags — u-ctags format not supported"
  warn "function definitions (kind:f) will not be detected; only declarations (kind:p) will be emitted"
  warn "install universal-ctags for accurate def_file:line and correct -L ranges"
fi

# True if a commit has actual hunk lines (not just diff headers) for a file.
commit_touches_file() {
  local sha="$1" file="$2" file2="${3:-}"
  local result
  result=$(git diff-tree --no-commit-id --unified=0 -r "${sha}" \
    -- "${file}" ${file2:+"${file2}"} 2>/dev/null \
    | grep -cE "^[+-][^+-]" 2>/dev/null) || result=0
  [[ "${result}" -gt 0 ]]
}

# Stable 8-char hash of an arbitrary string (for overload disambiguation).
# Uses md5sum when available, falls back to cksum.
short_hash() {
  local s="$1"
  if command -v md5sum &>/dev/null; then
    printf '%s' "${s}" | md5sum | cut -c1-8
  else
    printf '%s' "${s}" | cksum | awk '{printf "%08x\n", $1}'
  fi
}

# ---------------------------------------------------------------------------
# Pass 1: Build function inventory using ctags
#
# Strategy (fixes v2 issues 3 & 4):
#   a) Run ctags on BOTH .h and .cc, collecting ALL records into a temp file.
#   b) Parse into two associative arrays keyed by canonical signature:
#        decl_records[key]  — from the .h (prototype/p kind)
#        def_records[key]   — from the .cc (function/f kind)
#   c) Merge: for each key seen in either array, emit ONE record with both
#      locations populated (decl_file:line and def_file:line).
#   d) function_id = Scope__name__<8-char hash of canonical sig>  (unique per overload)
#
# Output format (pipe-separated, no spaces around |):
#   function_id|qualified_name|signature|decl_file:line|def_file:line|kind
# ---------------------------------------------------------------------------

build_function_inventory() {
  local class="$1" abs_cc="$2" abs_h="$3" src_cc="$4" src_h="$5"
  local out_file="$6"

  {
    echo "# Function inventory for ${class}"
    echo "# Built by ctags — includes overloads, inline functions, header-only methods"
    echo "# function_id = Scope__name__<sig-hash> — unique per overload"
    echo "# Format: function_id|qualified_name|signature|decl_file:line|def_file:line|kind"
    echo "#"

    if [[ -z "${CTAGS_BIN}" ]]; then
      echo "# WARNING: ctags not available — inventory is empty"
      return
    fi

    local tmpfile
    tmpfile=$(mktemp)

    for f in "${abs_h}" "${abs_cc}"; do
      [[ -f "${f}" ]] || continue
      if [[ "${CTAGS_IS_UNIVERSAL}" -eq 1 ]]; then
        # Universal-ctags: u-ctags format gives separate field:value pairs
        "${CTAGS_BIN}" \
          --language-force=C++ \
          --c++-kinds=f+p \
          --fields=+nkS \
          --output-format=u-ctags \
          -f - "${f}" 2>/dev/null \
        | grep -v "^!" >> "${tmpfile}" || true
      else
        # Exuberant-ctags: use --fields=+nkS without --output-format
        # Output is: name TAB file TAB /pattern/ TAB kind TAB lineno TAB ...
        # kind and lineno are positional (columns 4 and 5) not field:value tagged.
        # Emit a synthetic u-ctags-like line so the awk parser still works.
        "${CTAGS_BIN}" \
          --language-force=C++ \
          --c++-kinds=f+p \
          --fields=+nkS \
          -f - "${f}" 2>/dev/null \
        | grep -v "^!" \
        | awk 'BEGIN{FS="\t"} NF>=5 {
            name=$1; file=$2; kind=$4; lineno=""; sig=""
            for(i=5;i<=NF;i++){
              if($i~/^[0-9]+$/ && lineno=="") lineno=$i
              if($i~/^\(/) sig=$i
            }
            # Emit synthetic fields that the downstream awk can parse
            print name "\t" file "\t/pattern/\t" kind "\tline:" lineno "\tkind:" kind "\tsignature:" sig
          }' >> "${tmpfile}" || true
      fi
    done

    # Parse and merge: group by (scope::name + sig), track decl vs def separately.
    # Emit one merged record per unique canonical signature.
    awk -v class="${class}" -v src_cc="${src_cc}" -v src_h="${src_h}" \
        -v ceph_root="${CEPH_ROOT}" '
      function short_hash(s,   cmd, result) {
        # Inline 8-char hash via md5sum or cksum
        cmd = "printf '"'"'%s'"'"' \"" s "\" | md5sum 2>/dev/null || printf '"'"'%s'"'"' \"" s "\" | cksum"
        cmd | getline result
        close(cmd)
        # md5sum returns "abc123...  -", cksum returns "12345678 N"
        if (result ~ /[0-9a-f]{32}/) {
          return substr(result, 1, 8)
        } else {
          # cksum: convert decimal to 8-char hex
          split(result, a, " ")
          return sprintf("%08x", a[1] + 0)
        }
      }
      BEGIN { FS="\t" }
      /^[^!]/ {
        name = $1
        file = $2
        kind = ""
        lineno = ""
        sig = ""
        scope = ""

        # Scan the ENTIRE raw line with regex rather than field-by-field.
        # Rationale: universal-ctags occasionally omits a field (e.g. typeref)
        # which collapses two tab-separated tokens into one, e.g. "fline:322"
        # instead of "f\tline:322".  A whole-line regex match is immune to
        # this tab-collapse regardless of which fields are present or absent.
        raw = $0
        if (match(raw, /\tline:([0-9]+)/, a))   lineno = a[1]
        if (match(raw, /\tkind:([^\t]+)/, a))   kind   = a[1]
        if (match(raw, /\tsignature:([^\t]*)/, a)) sig = a[1]
        if (match(raw, /\tclass:([^\t]+)/, a))  scope  = a[1]
        if (match(raw, /\tstruct:([^\t]+)/, a)) scope  = a[1]

        # Fallback: kind still empty — two possible causes:
        #   a) column 4 is a bare kind letter "f" or "p" (normal u-ctags)
        #   b) column 4 is "fline:N" or "pline:N" (tab-collapsed, no typeref)
        if (kind == "") {
          if (NF >= 4 && ($4 == "f" || $4 == "p")) {
            kind = $4
          } else if (NF >= 4 && match($4, /^([fp])line:/, a)) {
            kind = a[1]
          }
        }
        # Fallback for line: scan for bare "line:N" anywhere in the record
        if (lineno == "" && match(raw, /line:([0-9]+)/, a)) lineno = a[1]

        # Only records belonging to our target class
        if (scope == "" && kind == "f") scope = class
        if (scope != class && scope != "") next
        if (scope == "") scope = class

        qualified = scope "::" name
        canon_key = qualified sig        # unique per overload

        # Track the file path relative to ceph_root
        rel_file = file
        sub(ceph_root "/", "", rel_file)

        # Store line number; choose slot based on kind
        if (kind == "p") {
          # prototype/declaration → goes in decl slot
          if (!(canon_key in decl_line)) {
            decl_line[canon_key] = lineno
            decl_file[canon_key] = rel_file
          }
        } else if (kind == "f") {
          # function definition
          if (!(canon_key in def_line)) {
            def_line[canon_key] = lineno
            def_file[canon_key] = rel_file
          }
        }

        # Record metadata for this key (first seen wins for name/sig/scope)
        if (!(canon_key in names)) {
          names[canon_key] = name
          sigs[canon_key]  = sig
          scopes[canon_key] = scope
          # preserve order of first appearance
          order[order_n++] = canon_key
        }
      }
      END {
        for (i = 0; i < order_n; i++) {
          key = order[i]
          name    = names[key]
          sig     = sigs[key]
          scope   = scopes[key]
          qualified = scope "::" name

          # Build unique function_id: Scope__name__hash
          safe_base = scope "__" name
          gsub(/[^a-zA-Z0-9_]/, "_", safe_base)
          h = short_hash(key)
          func_id = safe_base "__" h

          d_file = (key in decl_file) ? decl_file[key] : "-"
          d_line = (key in decl_line) ? decl_line[key] : "-"
          f_file = (key in def_file)  ? def_file[key]  : "-"
          f_line = (key in def_line)  ? def_line[key]  : "-"

          kind_out = (key in def_line) ? "f" : "p"

          print func_id "|" qualified "|" name sig "|" d_file ":" d_line "|" f_file ":" f_line "|" kind_out
        }
      }
    ' "${tmpfile}"

    rm -f "${tmpfile}"
  } > "${out_file}"
}

# ---------------------------------------------------------------------------
# Pass 1b: Build class inventory using ctags (replaces grep-based 07)
# ---------------------------------------------------------------------------

build_class_inventory() {
  local class="$1" abs_h="$2" src_h="$3" out_file="$4"

  {
    echo "# Classes and structs in ${src_h} (via ctags)"
    echo "# Format: name | kind | line | scope"
    echo "#"

    if [[ -z "${CTAGS_BIN}" ]]; then
      echo "# WARNING: ctags not available"
      return
    fi

    [[ -f "${abs_h}" ]] || { echo "# header not found"; return; }

    "${CTAGS_BIN}" \
      --language-force=C++ \
      --c++-kinds=cs \
      --fields=+nk \
      --output-format=u-ctags \
      -f - "${abs_h}" 2>/dev/null \
    | grep -v "^!" \
    | awk -v src_h="${src_h}" -v ceph_root="${CEPH_ROOT}" '
        BEGIN { FS="\t" }
        /^[^!]/ {
          name = $1; file = $2; kind = ""; lineno = ""
          for (i = 4; i <= NF; i++) {
            if ($i ~ /^line:/) lineno = substr($i, 6)
            if ($i ~ /^kind:/) kind   = substr($i, 6)
          }
          # Skip forward declarations (ctags marks them kind "p" for structs or
          # we detect them by absence of a body; use the file line count heuristic:
          # if kind is "c" or "s" it is a real definition)
          if (kind == "c" || kind == "s") {
            print name " | " kind " | " lineno " | " src_h
          }
        }
      ' || echo "# ctags parse error"
  } > "${out_file}"
}

# ---------------------------------------------------------------------------
# Pass 2: For one function, collect commits via four evidence passes
#
# Evidence tiers (ordered by reliability):
#   [L] direct     — git log -L start,end:file  (line-range; most precise)
#   [B] current    — git blame current lines     (who introduced them now)
#   [S] heuristic  — git log -S qualified        (pickaxe on exact string)
#   [G] heuristic  — git log -G bare_name        (grep on bare name)
#
# Fix 5: --follow runs separately for .cc and .h; results are unioned per pass.
# Fix 9: blame SHAs extracted from porcelain header lines, not grep-oE.
# ---------------------------------------------------------------------------

collect_function_commits() {
  local func_id="$1"
  local qualified="$2"     # e.g. DaemonServer::handle_command
  local bare_name="$3"     # e.g. handle_command
  local def_file="$4"      # relative path of definition file (.cc or .h)
  local start_line="$5"    # current definition start line
  local end_line="$6"      # current definition end line (exact, from inventory)
  local decl_file="$7"     # header file path (may equal def_file for header-only)
  local out_file="$8"      # where to write "sha [evidence,...]" lines
  local shas_file="$9"     # accumulator for dedup across functions

  local abs_def="${CEPH_ROOT}/${def_file}"
  [[ -f "${abs_def}" ]] || { echo "  # no definition file: ${def_file}" > "${out_file}"; return; }

  local tmp_L tmp_G tmp_S tmp_B
  tmp_L=$(mktemp); tmp_G=$(mktemp); tmp_S=$(mktemp); tmp_B=$(mktemp)

  # Pass L — line-range tracking (direct evidence, most reliable).
  # IMPORTANT: git log -L is INCOMPATIBLE with --follow.  When both are
  # given, git silently produces no output.  Do not use --follow here.
  # Without --follow, git stops at renames — acceptable because the -S
  # and -G passes cover rename history via the file path argument.
  if [[ -n "${start_line}" && "${start_line}" != "-" ]]; then
    safe git log --no-patch --format="%H" \
      -L "${start_line},${end_line}:${def_file}" 2>/dev/null \
    | grep -v "^$" > "${tmp_L}" || true
  fi

  # Pass G — heuristic: any diff line containing bare function name.
  # Run separately for .cc and .h, then union.
  {
    safe git log --follow --no-patch --format="%H" \
      -G "\\b${bare_name}\\b" -- "${def_file}" 2>/dev/null | grep -v "^$" || true
    if [[ "${decl_file}" != "${def_file}" ]]; then
      safe git log --follow --no-patch --format="%H" \
        -G "\\b${bare_name}\\b" -- "${decl_file}" 2>/dev/null | grep -v "^$" || true
    fi
  } | sort -u > "${tmp_G}"

  # Pass S — heuristic: exact qualified name string added/removed.
  # Run separately for .cc and .h, then union.
  {
    safe git log --follow --no-patch --format="%H" \
      -S "${qualified}" -- "${def_file}" 2>/dev/null | grep -v "^$" || true
    if [[ "${decl_file}" != "${def_file}" ]]; then
      safe git log --follow --no-patch --format="%H" \
        -S "${qualified}" -- "${decl_file}" 2>/dev/null | grep -v "^$" || true
    fi
  } | sort -u > "${tmp_S}"

  # Pass B — current-blame: who introduced current lines in this range.
  # Parse porcelain header lines: lines starting with a 40-hex SHA.
  # (Not grep-oE which would also match non-header lines.)
  if [[ -n "${start_line}" && "${start_line}" != "-" ]]; then
    safe git blame --porcelain -w -M -C \
      -L "${start_line},${end_line}" -- "${def_file}" 2>/dev/null \
    | awk '/^[0-9a-f]{40} / { print substr($0,1,40) }' \
    | sort -u > "${tmp_B}" || true
  fi

  # Union all SHAs, annotate which passes found each one
  sort -u "${tmp_L}" "${tmp_G}" "${tmp_S}" "${tmp_B}" | while IFS= read -r sha; do
    [[ -z "${sha}" ]] && continue
    ev=""
    grep -qF "${sha}" "${tmp_L}" && ev="${ev}L"
    grep -qF "${sha}" "${tmp_B}" && ev="${ev}B"
    grep -qF "${sha}" "${tmp_S}" && ev="${ev}S"
    grep -qF "${sha}" "${tmp_G}" && ev="${ev}G"
    [[ -z "${ev}" ]] && ev="?"
    echo "  ${sha}  [${ev}]"
    echo "${sha}" >> "${shas_file}"
  done > "${out_file}"

  [[ -s "${out_file}" ]] || echo "  # none" > "${out_file}"

  rm -f "${tmp_L}" "${tmp_G}" "${tmp_S}" "${tmp_B}"
}

# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------

cd "${CEPH_ROOT}"

HEAD_SHA=$(git rev-parse HEAD)
HEAD_DATE=$(git log -1 --format="%ci" HEAD)
RUN_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

log "HEAD: ${HEAD_SHA} (${HEAD_DATE})"
log "Output dir: ${OUTPUT_DIR}"
log "Processing ${#CLASS_FILES[@]} classes"
[[ -n "${CTAGS_BIN}" ]] && log "ctags: ${CTAGS_BIN}" || log "WARNING: ctags not found"

mkdir -p "${OUTPUT_DIR}"

for CLASS in $(echo "${!CLASS_FILES[@]}" | tr ' ' '\n' | sort); do
  acquire_slot "${CLASS_WORKERS}"
  (
  IFS=':' read -r SRC_CC SRC_H <<< "${CLASS_FILES[$CLASS]}"

  log "--- ${CLASS} ---"

  OUT="${OUTPUT_DIR}/${CLASS}"
  mkdir -p "${OUT}"

  ABS_CC="${CEPH_ROOT}/${SRC_CC}"
  ABS_H="${CEPH_ROOT}/${SRC_H}"

  TARGET_FILE="${SRC_CC}"
  if [[ ! -f "${ABS_CC}" ]]; then
    TARGET_FILE="${SRC_H}"
    warn "${CLASS}: no .cc found, using header"
  fi
  ABS_TARGET="${CEPH_ROOT}/${TARGET_FILE}"

  # ----------------------------------------------------------------
  # 00-HEADER.txt
  # ----------------------------------------------------------------
  {
    echo "class:        ${CLASS}"
    echo "source_cc:    ${SRC_CC}"
    echo "source_h:     ${SRC_H}"
    echo "head_sha:     ${HEAD_SHA}"
    echo "head_date:    ${HEAD_DATE}"
    echo "collected_at: ${RUN_TIMESTAMP}"
    echo "version:      v2.1"
    echo "worktree:     $(pwd)"
    echo "branch:       $(git branch --show-current 2>/dev/null || echo 'detached')"
    echo "ctags:        ${CTAGS_BIN:-none} (universal=${CTAGS_IS_UNIVERSAL})"
    [[ ! -f "${ABS_CC}" ]] && echo "warning:      source_cc not found — header-only class"
    [[ ! -f "${ABS_H}" ]]  && echo "warning:      source_h not found"
    echo "provenance:   uncapped multi-evidence heuristic"
    echo "coverage:     git log -L (direct) + pickaxe/grep/blame (heuristic)"
    echo "limitation:   indirect changes (struct fields, macros, dependency edits)"
    echo "              are not captured — no git command can guarantee semantic"
    echo "              completeness across call-site or type changes"
    echo "evidence_key: L=line-range(direct) B=blame(current) S=pickaxe(heuristic) G=grep(heuristic)"
    echo "evidence_note: L and B are high-confidence; S and G are candidate/related evidence"
  } > "${OUT}/00-HEADER.txt"

  # ----------------------------------------------------------------
  # 01-commits.txt — canonical SHA union of .cc ∪ .h (non-merge)
  # 01b-commits-all.txt — ALL commits including merges
  #
  # Fix 6/10: 02-messages.txt and all downstream files operate on this
  # exact SHA union, not just TARGET_FILE.
  # ----------------------------------------------------------------

  # Build the authoritative non-merge SHA set for this class
  {
    git log --follow --no-merges --format="%H" -- "${SRC_CC}" 2>/dev/null || true
    if [[ -f "${ABS_H}" && "${SRC_H}" != "${SRC_CC}" ]]; then
      git log --follow --no-merges --format="%H" -- "${SRC_H}" 2>/dev/null || true
    fi
  } | sort -u > "${OUT}/.canonical-shas.tmp"

  {
    echo "# All non-merge commits touching ${SRC_CC} ∪ ${SRC_H} (newest first)"
    echo "# This is the authoritative SHA set used by all downstream files."
    echo "# Format: SHA date author | subject"
    echo "#"
    # Re-emit in reverse-chron order using the canonical set
    git log --no-merges --format="%H %ad %aN | %s" --date=short \
      -- "${SRC_CC}" "${SRC_H}" 2>/dev/null \
    | grep -Ff "${OUT}/.canonical-shas.tmp" \
    || echo "# ERROR: git log failed"
  } > "${OUT}/01-commits.txt"

  {
    echo "# ALL commits including merges touching ${SRC_CC} ∪ ${SRC_H}"
    echo "# non-merge function provenance: see 09-function-commits.txt"
    echo "# merge commits: separate ancestry dataset — not incorporated into function history"
    echo "#"
    git log --format="%H %ad %aN | %s" --date=short \
      -- "${SRC_CC}" "${SRC_H}" 2>/dev/null || echo "# ERROR"
  } > "${OUT}/01b-commits-all.txt"

  TOTAL=$(wc -l < "${OUT}/.canonical-shas.tmp")
  log "  ${TOTAL} commits (non-merge, .cc ∪ .h)"

  # ----------------------------------------------------------------
  # 02-messages.txt — full message for every SHA in the canonical set
  # Fix 6: was TARGET_FILE only; now uses the .cc ∪ .h SHA union.
  # ----------------------------------------------------------------
  {
    echo "# Full commit messages for all non-merge commits touching ${SRC_CC} ∪ ${SRC_H}"
    echo "# SHA source: 01-commits.txt (.cc ∪ .h canonical union)"
    echo "# Each block: === SHA ==="
    echo "#"
    while IFS= read -r sha; do
      [[ -z "${sha}" ]] && continue
      echo "=== ${sha} ==="
      git show --no-patch \
        --format="%H%nauthor: %aN <%aE>%ndate:   %ad%nsubject: %s%n%nbody:%n%b" \
        --date=short "${sha}" 2>/dev/null || echo "ERROR: ${sha}"
      echo ""
    done < "${OUT}/.canonical-shas.tmp"
  } > "${OUT}/02-messages.txt"

  # ----------------------------------------------------------------
  # 03-signal-commits.txt
  # ----------------------------------------------------------------
  {
    echo "# Signal commits: subject or body matches intent keywords"
    echo "# ANNOTATION of 01-commits.txt — not a filter on provenance"
    echo "# Pattern: ${SIGNAL_PATTERN}"
    echo "#"
    while IFS= read -r sha; do
      [[ -z "${sha}" ]] && continue
      body=$(git show --no-patch --format="%s%n%b" "${sha}" 2>/dev/null)
      if echo "${body}" | grep -qiE "${SIGNAL_PATTERN}"; then
        if commit_touches_file "${sha}" "${SRC_CC}" "${SRC_H}"; then
          git log -1 --format="%H %ad %aN | %s" --date=short "${sha}" 2>/dev/null || true
        fi
      fi
    done < "${OUT}/.canonical-shas.tmp"
  } > "${OUT}/03-signal-commits.txt"

  SIGNAL_COUNT=$(grep -v "^#" "${OUT}/03-signal-commits.txt" | grep -c "." || true)
  log "  ${SIGNAL_COUNT} signal commits (annotation)"

  # ----------------------------------------------------------------
  # 04-signal-diffs.txt
  # ----------------------------------------------------------------
  {
    echo "# Diffs for signal commits (scoped to ${SRC_CC} and ${SRC_H})"
    echo "# Each block: === SHA: subject ==="
    echo "#"
    grep -v "^#" "${OUT}/03-signal-commits.txt" | grep "." \
    | while IFS= read -r line; do
        sha="${line%% *}"
        subject=$(git log -1 --format="%s" "${sha}" 2>/dev/null || echo "unknown")
        echo "=== ${sha}: ${subject} ==="
        git show "${sha}" -- "${SRC_CC}" "${SRC_H}" 2>/dev/null \
          || echo "ERROR: could not diff ${sha}"
        echo ""
      done
  } > "${OUT}/04-signal-diffs.txt"

  # ----------------------------------------------------------------
  # 05-blame.txt — -M -C tracks code movement across files
  # git blame exits non-zero on new/empty files; capture to variable
  # first so set -e cannot kill the subshell before the fallback runs.
  # ----------------------------------------------------------------
  {
    echo "# git blame -w -M -C ${TARGET_FILE}"
    echo "#"
    cc_blame=$(git blame -w -M -C -- "${TARGET_FILE}" 2>/dev/null || true)
    if [[ -n "${cc_blame}" ]]; then
      echo "${cc_blame}"
    else
      echo "# ERROR: blame failed or file is empty"
    fi
    if [[ "${TARGET_FILE}" != "${SRC_H}" && -f "${ABS_H}" ]]; then
      echo ""
      echo "# git blame -w -M -C ${SRC_H}"
      echo "#"
      h_blame=$(git blame -w -M -C -- "${SRC_H}" 2>/dev/null || true)
      if [[ -n "${h_blame}" ]]; then
        echo "${h_blame}"
      else
        echo "# ERROR: blame failed or file is empty"
      fi
    fi
  } > "${OUT}/05-blame.txt"

  # ----------------------------------------------------------------
  # 06-todos.txt
  # ----------------------------------------------------------------
  {
    echo "# TODO / FIXME / HACK in current source"
    echo "#"
    # grep exits 1 on no matches; capture output first to avoid killing the
    # subshell under set -e when piped into sed.
    cc_todos=$(grep -n "TODO\|FIXME\|HACK" "${ABS_CC}" 2>/dev/null || true)
    if [[ -n "${cc_todos}" ]]; then
      echo "${cc_todos}" | sed "s|^|${SRC_CC}:|"
    else
      echo "# none in ${SRC_CC}"
    fi
    h_todos=$(grep -n "TODO\|FIXME\|HACK" "${ABS_H}" 2>/dev/null || true)
    if [[ -n "${h_todos}" ]]; then
      echo "${h_todos}" | sed "s|^|${SRC_H}:|"
    else
      echo "# none in ${SRC_H}"
    fi
  } > "${OUT}/06-todos.txt"

  # ----------------------------------------------------------------
  # 07-classes.txt — via ctags (fix 10: replaces grep-based approach)
  # ----------------------------------------------------------------
  build_class_inventory "${CLASS}" "${ABS_H}" "${SRC_H}" "${OUT}/07-classes.txt"

  # ----------------------------------------------------------------
  # 08-functions.txt — ctags-derived inventory (v2.1 merged decl+def)
  # ----------------------------------------------------------------
  build_function_inventory \
    "${CLASS}" "${ABS_CC}" "${ABS_H}" "${SRC_CC}" "${SRC_H}" \
    "${OUT}/08-functions.txt"

  FUNC_COUNT=$(grep -v "^#" "${OUT}/08-functions.txt" | grep -c "." || true)
  log "  ${FUNC_COUNT} functions in inventory"

  # ----------------------------------------------------------------
  # 09-function-commits.txt and 10-commits-detail.txt
  #
  # Fix 1+2 (race + wrong end-line):
  #   Phase A — parse the ENTIRE 08-functions.txt into indexed arrays.
  #             Compute end_line[i] = start[i+1] - 1 for all but the last;
  #             for the last, use the actual line count of its source file.
  #   Phase B — launch one worker per function, now that all ranges are known.
  #             No sleep, no race.
  # ----------------------------------------------------------------

  FUNC_WORK_DIR="${OUT}/.func-work"
  rm -rf "${FUNC_WORK_DIR}"
  mkdir -p "${FUNC_WORK_DIR}"

  # ---- Phase A: parse inventory into arrays ----
  declare -a F_ID=()
  declare -a F_QUAL=()
  declare -a F_BARE=()
  declare -a F_DEF=()
  declare -a F_START=()
  declare -a F_DECL=()

  while IFS='|' read -r func_id qualified bare_name_sig decl_loc def_loc kind; do
    [[ "${func_id}" == "#"* || -z "${func_id}" ]] && continue

    func_id="${func_id// /}"
    qualified="${qualified// /}"

    decl_file_raw="${decl_loc%%:*}"
    decl_file_raw="${decl_file_raw// /}"
    def_file_raw="${def_loc%%:*}"
    def_file_raw="${def_file_raw// /}"
    def_line="${def_loc##*:}"
    def_line="${def_line// /}"

    bare_name="${bare_name_sig%%(*}"
    bare_name="${bare_name// /}"

    # Resolve definition file: prefer .cc entry; fall back to decl or TARGET
    if [[ "${def_file_raw}" == "-" || -z "${def_file_raw}" ]]; then
      if [[ "${decl_file_raw}" != "-" && -n "${decl_file_raw}" ]]; then
        resolved_def="${decl_file_raw#${CEPH_ROOT}/}"
      else
        resolved_def="${TARGET_FILE}"
      fi
    else
      resolved_def="${def_file_raw#${CEPH_ROOT}/}"
    fi

    [[ -z "${def_line}" || "${def_line}" == "-" ]] && def_line="1"

    resolved_decl="${decl_file_raw#${CEPH_ROOT}/}"
    [[ "${resolved_decl}" == "-" || -z "${resolved_decl}" ]] && resolved_decl="${SRC_H}"

    F_ID+=("${func_id}")
    F_QUAL+=("${qualified}")
    F_BARE+=("${bare_name}")
    F_DEF+=("${resolved_def}")
    F_START+=("${def_line}")
    F_DECL+=("${resolved_decl}")
  done < "${OUT}/08-functions.txt"

  NFUNCS="${#F_ID[@]}"

  # Compute end lines for each function.
  # Strategy: find the nearest function start in the SAME FILE that is
  # GREATER than this_start (i.e. the next function by line number, not
  # by array index).  Using array order is wrong because ctags emits
  # functions in order of first appearance across both files interleaved,
  # not sorted by line number within a file.  An out-of-order next entry
  # produces end < start, which git log -L silently ignores.
  declare -a F_END=()
  for (( i=0; i<NFUNCS; i++ )); do
    this_file="${F_DEF[$i]}"
    this_start="${F_START[$i]}"
    end_val=""
    nearest_start=999999999

    # Scan ALL other entries in the same file; find the smallest start
    # line that is strictly greater than this_start.
    for (( j=0; j<NFUNCS; j++ )); do
      [[ $j -eq $i ]] && continue
      if [[ "${F_DEF[$j]}" == "${this_file}" ]]; then
        s="${F_START[$j]}"
        if (( s > this_start && s < nearest_start )); then
          nearest_start=$s
          end_val=$(( s - 1 ))
        fi
      fi
    done

    # No later function in this file — use actual line count of the file.
    if [[ -z "${end_val}" ]]; then
      abs_path="${CEPH_ROOT}/${this_file}"
      if [[ -f "${abs_path}" ]]; then
        end_val=$(wc -l < "${abs_path}")
      else
        end_val=$(( this_start + 200 ))
      fi
    fi

    F_END+=("${end_val}")
  done

  # ---- Phase B: launch workers (all ranges are now known — no race) ----
  for (( i=0; i<NFUNCS; i++ )); do
    acquire_slot "${FUNC_WORKERS}"
    (
      local_seq="${i}"
      local_func_id="${F_ID[$i]}"
      local_qual="${F_QUAL[$i]}"
      local_bare="${F_BARE[$i]}"
      local_def="${F_DEF[$i]}"
      local_start="${F_START[$i]}"
      local_end="${F_END[$i]}"
      local_decl="${F_DECL[$i]}"
      local_shas="${FUNC_WORK_DIR}/${local_seq}.shas"
      local_out="${FUNC_WORK_DIR}/${local_seq}.out"

      log "    [09] ${local_qual} ${local_def}:${local_start}-${local_end}"
      touch "${local_shas}"

      collect_function_commits \
        "${local_func_id}" \
        "${local_qual}" \
        "${local_bare}" \
        "${local_def}" \
        "${local_start}" \
        "${local_end}" \
        "${local_decl}" \
        "${FUNC_WORK_DIR}/${local_seq}.commits" \
        "${local_shas}"

      {
        echo "### ${local_qual}"
        echo "# function_id: ${local_func_id}"
        echo "# definition:  ${local_def}:${local_start}-${local_end}"
        echo "# declaration: ${local_decl}"
        cat "${FUNC_WORK_DIR}/${local_seq}.commits" 2>/dev/null
        echo ""
      } > "${local_out}"
    ) &
  done

  # Unset arrays so they don't bleed into next class iteration
  unset F_ID F_QUAL F_BARE F_DEF F_START F_DECL F_END

  wait

  # Merge into 09-function-commits.txt
  {
    echo "# Function → SHA index for ${CLASS} (v2.1)"
    echo "# evidence tiers:"
    echo "#   [L] direct    — git log -L line-range (high confidence)"
    echo "#   [B] current   — git blame current lines (high confidence)"
    echo "#   [S] heuristic — pickaxe on qualified name (candidate evidence)"
    echo "#   [G] heuristic — grep on bare name (candidate evidence)"
    echo "# provenance: uncapped — all commits retained"
    echo "# signal annotation: see 10-commits-detail.txt"
    echo "# non-merge commits only; merge ancestry: see 01b-commits-all.txt"
    echo "#"
    for (( i=0; i<NFUNCS; i++ )); do
      [[ -f "${FUNC_WORK_DIR}/${i}.out" ]] && cat "${FUNC_WORK_DIR}/${i}.out"
    done
  } > "${OUT}/09-function-commits.txt"

  # Deduplicate all seen SHAs across all functions
  cat "${FUNC_WORK_DIR}"/*.shas 2>/dev/null | sort -u > "${OUT}/.seen-shas.tmp" || true
  rm -rf "${FUNC_WORK_DIR}"

  FUNC_ENTRIES=$(grep -c "^### " "${OUT}/09-function-commits.txt" 2>/dev/null) || FUNC_ENTRIES=0
  log "  ${FUNC_ENTRIES} function entries in 09"

  # ----------------------------------------------------------------
  # 10-commits-detail.txt — one block per unique SHA in 09
  # ----------------------------------------------------------------
  {
    echo "# Commit detail for all SHAs referenced in 09-function-commits.txt"
    echo "# class: ${CLASS}  source: ${TARGET_FILE}"
    echo "# signal: annotated (yes/no) — not a filter"
    echo "#"

    UNIQUE_SHAS=$(sort -u "${OUT}/.seen-shas.tmp" 2>/dev/null) || UNIQUE_SHAS=""
    SHA_COUNT=$(echo "${UNIQUE_SHAS}" | grep -c "." 2>/dev/null) || SHA_COUNT=0
    log "  [10] ${SHA_COUNT} unique SHAs"

    if [[ -z "${UNIQUE_SHAS}" ]]; then
      echo "# no commits found for any function in this class"
    else
      echo "${UNIQUE_SHAS}" | while IFS= read -r sha; do
        [[ -z "${sha}" ]] && continue

        meta=$(safe git log -1 --format="%ad|%aN|%s" --date=short "${sha}" 2>/dev/null) || meta=""
        [[ -z "${meta}" ]] && continue

        cdate="${meta%%|*}"; rest="${meta#*|}"
        cauthor="${rest%%|*}"; csubject="${rest#*|}"
        cbody=$(safe git show --no-patch --format="%b" "${sha}" 2>/dev/null) || cbody=""

        if echo "${csubject}${cbody}" | grep -qiE "${SIGNAL_PATTERN}"; then
          csignal="yes"
        else
          csignal="no"
        fi

        echo "=== ${sha} ==="
        echo "date:    ${cdate}"
        echo "author:  ${cauthor}"
        echo "subject: ${csubject}"
        echo "signal:  ${csignal}"
        echo ""
        echo "body:"
        [[ -n "${cbody}" ]] && echo "${cbody}" || echo "(none)"
        echo ""
        echo "diff:"
        safe git show "${sha}" -- "${SRC_CC}" "${SRC_H}" 2>/dev/null \
          || echo "(diff unavailable)"
        echo ""
      done
    fi
  } > "${OUT}/10-commits-detail.txt"

  rm -f "${OUT}/.seen-shas.tmp" "${OUT}/.canonical-shas.tmp"

  DETAIL_BLOCKS=$(grep -c "^=== " "${OUT}/10-commits-detail.txt" 2>/dev/null) || DETAIL_BLOCKS=0
  log "  ${DETAIL_BLOCKS} commit blocks in 10"
  log "  Done -> ${OUT}/"
  ) &
done

wait

# ---------------------------------------------------------------------------
# Summary index
# ---------------------------------------------------------------------------
{
  echo "# Object History Collection Index (v2.1)"
  echo "# Generated: ${RUN_TIMESTAMP}"
  echo "# HEAD: ${HEAD_SHA} (${HEAD_DATE})"
  echo "# Worktree: $(pwd)"
  echo "# evidence: L=line-range(direct) B=blame(current) S=pickaxe(heuristic) G=grep(heuristic)"
  echo "#"
  printf "%-35s %8s %8s %8s %8s\n" "Class" "Commits" "Signals" "Functions" "Details"
  printf "%-35s %8s %8s %8s %8s\n" "-----" "-------" "-------" "---------" "-------"
  for CLASS in $(echo "${!CLASS_FILES[@]}" | tr ' ' '\n' | sort); do
    OUT="${OUTPUT_DIR}/${CLASS}"
    # awk-based counts: never exits non-zero, never produces double values
    # .canonical-shas.tmp is deleted on successful run; fall back to 01-commits.txt
    commits=$(awk '/^[^#]/{n++} END{print n+0}' "${OUT}/01-commits.txt" 2>/dev/null || echo 0)
    signals=$(awk '/^[^#]/{n++} END{print n+0}' "${OUT}/03-signal-commits.txt" 2>/dev/null || echo 0)
    funcs=$(   awk '/^[^#]/{n++} END{print n+0}' "${OUT}/08-functions.txt"      2>/dev/null || echo 0)
    details=$( awk '/^===[[:space:]]/{n++} END{print n+0}' "${OUT}/10-commits-detail.txt" 2>/dev/null || echo 0)
    printf "%-35s %8s %8s %8s %8s\n" "${CLASS}" "${commits}" "${signals}" "${funcs}" "${details}"
  done
} > "${OUTPUT_DIR}/INDEX.txt"

log ""
log "Collection complete (v2.1)."
log "Index: ${OUTPUT_DIR}/INDEX.txt"
log ""
log "Key changes vs v2:"
log "  end-line race eliminated: full inventory parsed before workers launch"
log "  end-line is exact: next_start-1 (or EOF for last fn in file)"
log "  function_id unique per overload: Scope__name__<sig-hash>"
log "  ctags decl+def merged correctly: one record per canonical signature"
log "  --follow runs separately for .cc and .h (unioned per pass)"
log "  02-messages.txt operates on .cc ∪ .h SHA union (not TARGET_FILE only)"
log "  evidence tiers: [L][B]=direct/current  [S][G]=heuristic"
log "  00-HEADER: 'uncapped multi-evidence provenance' (not 'complete')"
log "  blame SHAs parsed from porcelain header lines (not grep-oE)"
log "  07-classes.txt via ctags (not grep)"
