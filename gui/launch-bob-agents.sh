#!/usr/bin/env bash
# launch-bob-agents.sh
# Opens Tilix with N tabs, each SSH-ing into sockeni07 and starting Bob Shell
# in its own git worktree (/home/szuraski/ceph-agent-1 … -agent-N).
# Uses API-key auth — no browser or port-forward needed.
#
# Prerequisites:
#   1. Run setup-worktrees.sh on sockeni07 once to create the worktrees.
#   2. export BOBSHELL_API_KEY="your-api-key-here"
#
# Optional:
#   Place per-agent instructions in ./Inputs/bob-instructions (default)
#   or pass a custom file with --instructions <path>.
#   Format — one entry per agent, blank line between entries:
#
#     tracker.ceph.com/12345
#     Fix the OSD crash in the bluestore layer
#
#     tracker.ceph.com/678910
#     Investigate slow recovery after node failure
#
#   The number of agents launched equals the number of entries in the file.
#   Agents with no matching entry open with no initial prompt (minimum 1 agent).
#
# Usage (on your LOCAL laptop):
#   chmod +x launch-bob-agents.sh
#   ./launch-bob-agents.sh
#   ./launch-bob-agents.sh --instructions Outputs/assessment-prompts.txt

set -euo pipefail

REMOTE_HOST="szuraski@sockeni07"
MAIN_DIR="/home/szuraski/ceph"
WORKSPACE_ROOT="/home/szuraski"
API_KEY="${BOBSHELL_API_KEY:-}"
SCRIPT_DIR="$(dirname "$0")"
INSTRUCTIONS_FILE="${SCRIPT_DIR}/Inputs/bob-instructions"
INPUTS_DIR="${SCRIPT_DIR}/Inputs"
REMOTE_INPUTS_DIR="${WORKSPACE_ROOT}/bob-shell-inputs"

# Parse CLI arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --instructions)
      INSTRUCTIONS_FILE="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      echo "Usage: $0 [--instructions <path>]" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$API_KEY" ]]; then
  echo "Error: BOBSHELL_API_KEY is not set." >&2
  echo "Run:  export BOBSHELL_API_KEY=\"your-api-key-here\"  then re-run this script." >&2
  exit 1
fi

# Parse the instructions file into parallel arrays: tracker_url[] and prompt[]
# Each entry is a URL line followed by a prompt line, separated by blank lines.
declare -a tracker_url=()
declare -a prompt=()

if [[ -f "$INSTRUCTIONS_FILE" ]]; then
  url=""
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ -z "$line" ]]; then
      # Blank line — reset for next entry
      url=""
    elif [[ -z "$url" ]]; then
      # First non-blank line of an entry is the tracker URL
      url="$line"
    else
      # Second non-blank line is the prompt
      tracker_url+=("$url")
      prompt+=("$line")
      url=""
    fi
  done < "$INSTRUCTIONS_FILE"
fi

# Write a temporary wrapper script on the remote host for agent N, then return
# its remote path. Using a remote script file avoids all quoting/escaping issues
# across the SSH boundary and keeps stdin free for TTY (raw mode).
upload_agent_script() {
  local n="$1"
  local idx=$(( n - 1 ))
  local dir="${MAIN_DIR}-agent-${n}"
  local remote_script="/tmp/bob-agent-${n}.sh"

  local agent_branch="agent/${n}"

  local bob_cmd
  if [[ $idx -lt ${#prompt[@]} ]]; then
    local bob_prompt="${tracker_url[$idx]} ${prompt[$idx]}"
    bob_cmd="bob run --max-turns 10000 -w ${WORKSPACE_ROOT@Q} -- ${bob_prompt@Q}"
  else
    bob_cmd="bob chat -w ${WORKSPACE_ROOT@Q}"
  fi

  # Write the script to the remote host via SSH (stdin used here, not TTY)
  ssh "${REMOTE_HOST}" "cat > ${remote_script} && chmod +x ${remote_script}" <<SCRIPT
#!/usr/bin/env bash
export BOBSHELL_API_KEY=${API_KEY@Q}
cd ${dir@Q}
${bob_cmd}
# Return the worktree to its stable agent branch once the run completes
git -C ${dir@Q} checkout ${agent_branch@Q}
exec bash
SCRIPT

  echo "${remote_script}"
}

# Sync Inputs/ to the remote host so agents can read guides and other reference files
ssh "${REMOTE_HOST}" "mkdir -p ${REMOTE_INPUTS_DIR@Q}"
rsync -az --delete "${INPUTS_DIR}/" "${REMOTE_HOST}:${REMOTE_INPUTS_DIR}/"

# Determine agent count — one agent per entry in the instructions file,
# minimum 1 (so the script is always useful even with an empty file).
AGENT_COUNT=${#prompt[@]}
[[ $AGENT_COUNT -lt 1 ]] && AGENT_COUNT=1

echo "Launching ${AGENT_COUNT} agent(s) from: ${INSTRUCTIONS_FILE}"

# Upload all agent scripts first (no TTY needed)
declare -a remote_scripts=()
for (( i=1; i<=AGENT_COUNT; i++ )); do
  remote_scripts+=( "$(upload_agent_script "$i")" )
done

# Tab 1 — open a new Tilix window, execute the pre-uploaded script via SSH
tilix \
  --action=app-new-window \
  -e "bash -c 'ssh -t ${REMOTE_HOST} bash ${remote_scripts[0]}'" &

# Wait for the window to appear and register on DBus before adding tabs
sleep 2

# Tabs 2–N — add sessions to the same window
for (( i=2; i<=AGENT_COUNT; i++ )); do
  tilix \
    --action=app-new-session \
    -e "bash -c 'ssh -t ${REMOTE_HOST} bash ${remote_scripts[$((i-1))]}'" &
  sleep 0.5
done

wait
