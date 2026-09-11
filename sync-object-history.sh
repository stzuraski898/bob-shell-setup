#!/usr/bin/env bash
# sync-object-history.sh
#
# Pull the v3 object-history corpus from sockeni07 to a local directory for
# review and assessment.  Runs rsync over SSH — no git involvement.
#
# Usage:
#   bash sync-object-history.sh [options]
#
# Options:
#   --host HOST      Remote hostname  (default: sockeni07)
#   --user USER      Remote username  (default: szuraski)
#   --remote PATH    Remote corpus root (default: /home/szuraski/BobOutput/Object History/v3)
#   --local PATH     Local destination  (default: ./Object-History-v3)
#   --intent         Also sync intent artefacts (*-intent.md) from the
#                    /home/szuraski/BobOutput/Object History/ directory
#   --dry-run        Pass --dry-run to rsync (show what would transfer)
#
# Examples:
#   bash sync-object-history.sh
#   bash sync-object-history.sh --intent
#   bash sync-object-history.sh --host mysrv --user me --dry-run
#
# Output layout after sync:
#   Object-History-v3/
#     INDEX.txt
#     <ClassName>/
#       commits.txt
#       blame.txt
#       functions.txt
#       diffs/
#         <sha>.diff
#   Object-History-intent/          (only with --intent)
#     <ClassName>-intent.md

set -euo pipefail

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
REMOTE_HOST="sockeni07"
REMOTE_USER="szuraski"
REMOTE_CORPUS="/home/szuraski/BobOutput/Object History/v3"
LOCAL_CORPUS="./Object-History-v3"
SYNC_INTENT=0
RSYNC_EXTRA=()

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --host)    REMOTE_HOST="$2";   shift 2 ;;
    --user)    REMOTE_USER="$2";   shift 2 ;;
    --remote)  REMOTE_CORPUS="$2"; shift 2 ;;
    --local)   LOCAL_CORPUS="$2";  shift 2 ;;
    --intent)  SYNC_INTENT=1;      shift   ;;
    --dry-run) RSYNC_EXTRA+=("--dry-run"); shift ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

REMOTE="${REMOTE_USER}@${REMOTE_HOST}"

echo "[sync] Remote: ${REMOTE}:${REMOTE_CORPUS}"
echo "[sync] Local:  ${LOCAL_CORPUS}"
[[ ${#RSYNC_EXTRA[@]} -gt 0 ]] && echo "[sync] Flags:  ${RSYNC_EXTRA[*]}"
echo ""

# ---------------------------------------------------------------------------
# Sync corpus
# ---------------------------------------------------------------------------
mkdir -p "${LOCAL_CORPUS}"

rsync -avz --progress \
  "${RSYNC_EXTRA[@]+"${RSYNC_EXTRA[@]}"}" \
  --compress-level=9 \
  -e ssh \
  "${REMOTE}:${REMOTE_CORPUS}/" \
  "${LOCAL_CORPUS}/"

echo ""

# ---------------------------------------------------------------------------
# Sync intent artefacts (optional)
# ---------------------------------------------------------------------------
if [[ "${SYNC_INTENT}" -eq 1 ]]; then
  LOCAL_INTENT="./Object-History-intent"
  REMOTE_INTENT_DIR="/home/szuraski/BobOutput/Object History"

  echo "[sync] Syncing intent artefacts (*-intent.md)..."
  mkdir -p "${LOCAL_INTENT}"

  # rsync with --include/--exclude to pull only *-intent.md files
  rsync -avz --progress \
    "${RSYNC_EXTRA[@]+"${RSYNC_EXTRA[@]}"}" \
    --compress-level=9 \
    --include="*-intent.md" \
    --exclude="*" \
    -e ssh \
    "${REMOTE}:${REMOTE_INTENT_DIR}/" \
    "${LOCAL_INTENT}/"

  echo ""
  INTENT_COUNT=$(find "${LOCAL_INTENT}" -name "*-intent.md" 2>/dev/null | wc -l)
  echo "[sync] ${INTENT_COUNT} intent artefact(s) synced to ${LOCAL_INTENT}/"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "[sync] Corpus sync complete."
echo ""

if [[ -f "${LOCAL_CORPUS}/INDEX.txt" ]]; then
  echo "--- INDEX.txt ---"
  cat "${LOCAL_CORPUS}/INDEX.txt"
else
  echo "[sync] Note: INDEX.txt not found — collection may not have completed yet."
fi
