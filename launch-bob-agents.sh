#!/usr/bin/env bash
# launch-bob-agents.sh
# Opens Tilix with 5 tabs, each SSH-ing into sockeni07 and starting Bob Shell
# in its own git worktree (/home/szuraski/ceph-agent-1 … -agent-5).
# Uses API-key auth — no browser or port-forward needed.
#
# Prerequisites:
#   1. Run setup-worktrees.sh on sockeni07 once to create the worktrees.
#   2. export BOBSHELL_API_KEY="your-api-key-here"
#
# Optional:
#   Place per-agent instructions in ./Inputs/bob-instructions
#   Format — one entry per agent, blank line between entries:
#
#     tracker.ceph.com/12345
#     Fix the OSD crash in the bluestore layer
#
#     tracker.ceph.com/678910
#     Investigate slow recovery after node failure
#
#   Agents with no matching entry open with no initial prompt.
#
# Usage (on your LOCAL laptop):
#   chmod +x launch-bob-agents.sh
#   ./launch-bob-agents.sh

set -euo pipefail

REMOTE_HOST="szuraski@sockeni07"
MAIN_DIR="/home/szuraski/ceph"
API_KEY="${BOBSHELL_API_KEY:-}"
INSTRUCTIONS_FILE="$(dirname "$0")/Inputs/bob-instructions"

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
    bob_cmd="bob run --max-turns 10000 -w ${dir@Q} -- ${bob_prompt@Q}"
  else
    bob_cmd="bob chat -w ${dir@Q}"
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

# Upload all agent scripts first (no TTY needed)
declare -a remote_scripts=()
for i in 1 2 3 4 5; do
  remote_scripts+=( "$(upload_agent_script "$i")" )
done

# Tab 1 — open a new Tilix window, execute the pre-uploaded script via SSH
tilix \
  --action=app-new-window \
  -e "bash -c 'ssh -t ${REMOTE_HOST} bash ${remote_scripts[0]}'" &

# Wait for the window to appear and register on DBus before adding tabs
sleep 2

# Tabs 2–5 — add sessions to the same window
for i in 2 3 4 5; do
  tilix \
    --action=app-new-session \
    -e "bash -c 'ssh -t ${REMOTE_HOST} bash ${remote_scripts[$((i-1))]}'" &
  sleep 0.5
done

wait
