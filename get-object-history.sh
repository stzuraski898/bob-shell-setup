#!/usr/bin/env bash
# get-object-history.sh
#
# Retrieves pre-collected git history for a class or a specific method.
# Works against a remote host (default: szuraski@sockeni07) or a local
# directory if HISTORY_RAW_DIR points to one that already exists locally.
#
# Usage:
#   bash get-object-history.sh <ClassName>                  # all methods + SHA lists
#   bash get-object-history.sh <ClassName> <method_name>    # full history for one method
#   bash get-object-history.sh <ClassName> --signals        # signal commits, all methods
#   bash get-object-history.sh --list                       # list all collected classes
#
# Configuration (environment variables):
#   HISTORY_HOST      SSH host to fetch from      (default: szuraski@sockeni07)
#   HISTORY_RAW_DIR   Remote (or local) raw path  (default: /home/szuraski/BobOutput/Object History/raw)
#
# If HISTORY_RAW_DIR exists as a local directory, SSH is skipped entirely.
# Otherwise the needed files are fetched from HISTORY_HOST via scp into a
# temp directory and cleaned up on exit.
#
# Examples:
#   bash get-object-history.sh ActivePyModules dispatch_remote
#   bash get-object-history.sh DaemonServer --signals
#   bash get-object-history.sh --list
#   HISTORY_RAW_DIR="Inputs/Object History/raw" bash get-object-history.sh ThreadMonitor

set -euo pipefail

HISTORY_HOST="${HISTORY_HOST:-szuraski@sockeni07}"
HISTORY_RAW_DIR="${HISTORY_RAW_DIR:-/home/szuraski/BobOutput/Object History/raw}"

# ---------------------------------------------------------------------------
# Transport: local or remote
# ---------------------------------------------------------------------------

TMPDIR_CREATED=""

# Decide whether we need SSH. If the raw dir exists locally, use it directly.
if [[ -d "${HISTORY_RAW_DIR}" ]]; then
  WORK_DIR="${HISTORY_RAW_DIR}"
else
  # Fetch files into a temp directory.
  TMPDIR_CREATED=$(mktemp -d)
  trap 'rm -rf "${TMPDIR_CREATED}"' EXIT

  # We don't know which class is needed yet — fetch INDEX and the class
  # directory lazily (see fetch_class() below). For --list we only need INDEX.
  WORK_DIR="${TMPDIR_CREATED}"
fi

# Fetch a single file from the remote into WORK_DIR, preserving relative path.
# No-op if the file already exists locally (idempotent).
fetch_file() {
  local remote_rel="$1"
  local local_path="${WORK_DIR}/${remote_rel}"
  [[ -f "${local_path}" ]] && return 0
  mkdir -p "$(dirname "${local_path}")"
  # Double-quoting the scp argument is sufficient — bash passes the space
  # correctly to scp without any backslash escaping.
  scp -q "${HISTORY_HOST}:${HISTORY_RAW_DIR}/${remote_rel}" "${local_path}" 2>/dev/null \
    || { echo "ERROR: could not fetch ${remote_rel} from ${HISTORY_HOST}" >&2; return 1; }
}

# Fetch all files for a class directory in one scp -r round-trip.
fetch_class() {
  local class="$1"
  # Already fetched if the sentinel file exists (not just the dir, which
  # mkdir -p may have created as an empty placeholder).
  [[ -f "${WORK_DIR}/${class}/00-HEADER.txt" ]] && return 0
  if [[ -n "${TMPDIR_CREATED}" ]]; then
    # No trailing slash on remote — scp copies the directory contents
    # into the (already-created) local target directory.
    mkdir -p "${WORK_DIR}/${class}"
    scp -q -r "${HISTORY_HOST}:${HISTORY_RAW_DIR}/${class}" \
        "${WORK_DIR}/" 2>/dev/null \
      || { echo "ERROR: could not fetch class '${class}' from ${HISTORY_HOST}" >&2
           echo "       Use --list to see available classes." >&2
           exit 1; }
  fi
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

die()  { echo "ERROR: $*" >&2; exit 1; }

# Print the detail block for a single SHA from 10-commits-detail.txt.
# Falls back to 02-messages.txt if 10 doesn't exist yet.
print_sha_detail() {
  local out_dir="$1" sha="$2"
  local detail="${out_dir}/10-commits-detail.txt"
  local messages="${out_dir}/02-messages.txt"

  if [[ -f "${detail}" ]]; then
    awk -v sha="${sha}" '
      /^=== / { in_block = ($0 ~ sha) }
      in_block { print }
      /^=== / && !($0 ~ sha) && in_block { exit }
    ' "${detail}" | head -120
  elif [[ -f "${messages}" ]]; then
    awk -v sha="${sha}" '
      /^=== / { in_block = ($0 ~ sha) }
      in_block { print }
      /^=== / && !($0 ~ sha) && in_block { exit }
    ' "${messages}" | head -80
  else
    echo "(no detail available for ${sha})"
  fi
}

# Extract the SHA list for a method from 09-function-commits.txt.
get_shas_for_method() {
  local file="$1" method="$2"
  awk -v method="${method}" '
    /^### / { in_section = ($0 ~ method) }
    in_section && /^[[:space:]]+[0-9a-f]{40}/ {
      gsub(/^[[:space:]]+/, "")
      gsub(/[[:space:]].*$/, "")
      print
    }
  ' "${file}"
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

if [[ $# -eq 0 ]]; then
  echo "Usage:"
  echo "  $0 <ClassName>                 list all methods and their commit SHAs"
  echo "  $0 <ClassName> <method_name>   full history for one method"
  echo "  $0 <ClassName> --signals       signal commits only, all methods"
  echo "  $0 --list                      list all collected classes"
  echo "  $0 --all [output_dir]          fetch every class to a local directory"
  echo ""
  echo "  HISTORY_HOST=${HISTORY_HOST}"
  echo "  HISTORY_RAW_DIR=${HISTORY_RAW_DIR}"
  exit 0
fi

# ---------------------------------------------------------------------------
# Mode: --list
# ---------------------------------------------------------------------------

if [[ "$1" == "--list" ]]; then
  local_index="${WORK_DIR}/INDEX.txt"
  if [[ ! -f "${local_index}" ]]; then
    fetch_file "INDEX.txt"
  fi
  echo "# Classes available on ${HISTORY_HOST}:${HISTORY_RAW_DIR}"
  echo ""
  cat "${local_index}"
  exit 0
fi

# ---------------------------------------------------------------------------
# Mode: --all  — rsync the entire raw directory to a local path
# ---------------------------------------------------------------------------

if [[ "$1" == "--all" ]]; then
  DEST="${2:-./Object-History-raw}"
  mkdir -p "${DEST}"
  echo "# Syncing all class data from ${HISTORY_HOST}:${HISTORY_RAW_DIR}"
  echo "# Destination: ${DEST}"
  echo ""
  # rsync is one SSH connection for the whole tree — much faster than
  # per-class scp calls. Falls back to scp -r if rsync is not available.
  if command -v rsync &>/dev/null; then
    rsync -av --delete \
      "${HISTORY_HOST}:${HISTORY_RAW_DIR}/" \
      "${DEST}/"
  else
    echo "rsync not found — falling back to scp -r"
    scp -r "${HISTORY_HOST}:${HISTORY_RAW_DIR}/" "${DEST}/"
  fi
  echo ""
  echo "# Done. To use this local copy:"
  echo "#   HISTORY_RAW_DIR=\"${DEST}\" bash $0 <ClassName> <method>"
  exit 0
fi

# ---------------------------------------------------------------------------
# All other modes — fetch class directory first
# ---------------------------------------------------------------------------

CLASS="$1"
MODE="${2:-}"

fetch_class "${CLASS}"

CLASS_DIR="${WORK_DIR}/${CLASS}"
HEADER="${CLASS_DIR}/00-HEADER.txt"
INDEX="${CLASS_DIR}/09-function-commits.txt"

[[ -f "${HEADER}" ]] || die "Missing 00-HEADER.txt for ${CLASS}"
[[ -f "${INDEX}" ]]  || die "Missing 09-function-commits.txt for ${CLASS} — re-run collect-object-history.sh"

# ---------------------------------------------------------------------------
# Print header (always shown)
# ---------------------------------------------------------------------------

echo "# Object history: ${CLASS}"
echo "# $(grep "^head_sha:"     "${HEADER}" | head -1)"
echo "# $(grep "^collected_at:" "${HEADER}" | head -1)"
echo "# Source: $(grep "^source_cc:" "${HEADER}" | head -1 | sed 's/source_cc:[[:space:]]*//')"
if [[ -n "${TMPDIR_CREATED}" ]]; then
  echo "# Fetched from: ${HISTORY_HOST}"
fi
echo ""

# ---------------------------------------------------------------------------
# Mode: list all methods
# ---------------------------------------------------------------------------

if [[ -z "${MODE}" ]]; then
  echo "## Methods and commit SHAs"
  echo ""
  awk '
    /^### /                      { print }
    /^[[:space:]]+[0-9a-f]{40}/ { print }
    /^[[:space:]]+# none/        { print }
    /^$/                         { print "" }
  ' "${INDEX}"
  exit 0
fi

# ---------------------------------------------------------------------------
# Mode: --signals
# ---------------------------------------------------------------------------

if [[ "${MODE}" == "--signals" ]]; then
  DETAIL="${CLASS_DIR}/10-commits-detail.txt"
  [[ -f "${DETAIL}" ]] || die "10-commits-detail.txt not found — re-run collect-object-history.sh"

  echo "## Signal commits (signal: yes) for ${CLASS}"
  echo ""

  ALL_SHAS=$(awk '/^[[:space:]]+[0-9a-f]{40}/ {
    gsub(/^[[:space:]]+/,""); gsub(/[[:space:]].*$/,""); print
  }' "${INDEX}" | sort -u)

  found=0
  while IFS= read -r sha; do
    [[ -z "${sha}" ]] && continue
    sig=$(awk -v sha="${sha}" '
      /^=== / { in_block = ($0 ~ sha) }
      in_block && /^signal:/ { print $2; exit }
    ' "${DETAIL}")
    if [[ "${sig}" == "yes" ]]; then
      found=$((found + 1))
      methods_list=$(awk -v sha="${sha}" '
        /^### / { cur = substr($0, 5) }
        $0 ~ sha { print "  " cur }
      ' "${INDEX}" | sort -u | tr '\n' ' ')
      echo "### ${sha}"
      echo "# referenced by:${methods_list}"
      print_sha_detail "${CLASS_DIR}" "${sha}"
      echo ""
    fi
  done <<< "${ALL_SHAS}"

  [[ "${found}" -eq 0 ]] && echo "# no signal commits found for ${CLASS}"
  exit 0
fi

# ---------------------------------------------------------------------------
# Mode: specific method
# ---------------------------------------------------------------------------

METHOD="${MODE}"
SEARCH_NAME="${METHOD##*::}"   # strips "ClassName::" prefix if present

SHAS=$(get_shas_for_method "${INDEX}" "${SEARCH_NAME}")

if [[ -z "${SHAS}" ]]; then
  echo "## Method: ${METHOD}"
  echo "# not found in 09-function-commits.txt"
  echo ""
  echo "# Available methods:"
  grep "^### " "${INDEX}" | sed 's/^### /  /'
  exit 1
fi

echo "## Method: ${METHOD}"
echo ""
SHA_COUNT=$(echo "${SHAS}" | grep -c "." || true)
echo "# ${SHA_COUNT} commit(s) tracked"
echo ""

while IFS= read -r sha; do
  [[ -z "${sha}" ]] && continue
  print_sha_detail "${CLASS_DIR}" "${sha}"
  echo ""
done <<< "${SHAS}"
