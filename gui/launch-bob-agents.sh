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
# --instructions can point to either:
#
#   A DIRECTORY  (new, preferred)
#     Each *.md file in the directory = one agent's prompt, sorted by filename.
#     Files may start with an optional YAML-style frontmatter block:
#
#       ---
#       tracker: https://tracker.ceph.com/issues/12345
#       ---
#       <prompt body>
#
#     If the frontmatter is absent or tracker is "none"/empty, only the prompt
#     body is passed to bob.  Files without a .md extension are ignored.
#     Name files with numeric prefixes (01-, 02-, …) to control launch order.
#
#   A FILE  (legacy, still supported)
#     Format A — tracker URL + prompt separated by blank lines:
#       https://tracker.ceph.com/12345
#       Fix the OSD crash in the bluestore layer
#
#     Format B — Whiteboard Defense / section-delimiter format:
#       ## 1. Title
#       ```markdown
#       prompt body
#       ```
#
# Usage:
#   ./launch-bob-agents.sh
#   ./launch-bob-agents.sh --local
#   ./launch-bob-agents.sh --no-worktrees
#   ./launch-bob-agents.sh --dry-run
#   ./launch-bob-agents.sh --local --no-worktrees --dry-run \
#       --instructions Inputs/Prompts/history-assessment/

set -euo pipefail

IS_LOCAL=0
DRY_RUN=0
USE_WORKTREES=1
REMOTE_HOST="${BOB_REMOTE_HOST:-szuraski@sockeni07}"
MAIN_DIR="/home/szuraski/ceph"
WORKSPACE_ROOT="/home/szuraski"
API_KEY="${BOBSHELL_API_KEY:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
INSTRUCTIONS_PATH="${REPO_ROOT}/Inputs/Prompts"
INPUTS_DIR="${REPO_ROOT}/Inputs"

# Parse CLI arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --local)
      IS_LOCAL=1
      shift
      ;;
    --no-worktrees|--no-worktree)
      USE_WORKTREES=0
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --instructions)
      INSTRUCTIONS_PATH="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      echo "Usage: $0 [--local] [--no-worktrees] [--dry-run] [--instructions <dir|file>]" >&2
      exit 1
      ;;
  esac
done

if [[ $IS_LOCAL -eq 1 ]]; then
  if [[ $USE_WORKTREES -eq 0 ]]; then
    MAIN_DIR="${SCRIPT_DIR}"
    WORKSPACE_ROOT="${SCRIPT_DIR}"
  else
    MAIN_DIR="${HOME}/Projects/ceph"
    WORKSPACE_ROOT="${HOME}/Projects"
  fi
fi
REMOTE_INPUTS_DIR="${WORKSPACE_ROOT}/bob-shell-inputs"

if [[ -z "$API_KEY" && $DRY_RUN -eq 0 ]]; then
  echo "Error: BOBSHELL_API_KEY is not set." >&2
  echo "Run:  export BOBSHELL_API_KEY=\"your-api-key-here\"  then re-run this script." >&2
  exit 1
fi

# ── Instruction loading ───────────────────────────────────────────────────────
# Populates parallel arrays: tracker_url[] and prompt[]

declare -a tracker_url=()
declare -a prompt=()

load_from_directory() {
  local dir="$1"
  # Collect *.md files, sorted lexicographically
  local -a files=()
  while IFS= read -r -d '' f; do
    files+=("$f")
  done < <(find "$dir" -maxdepth 1 -name '*.md' -print0 | sort -z)

  if [[ ${#files[@]} -eq 0 ]]; then
    echo "Warning: no *.md files found in ${dir}" >&2
    return
  fi

  for f in "${files[@]}"; do
    local url="none"
    local body=""
    local in_frontmatter=0
    local frontmatter_done=0
    local first_fence=1  # tracks whether we've seen the opening ---

    while IFS= read -r line || [[ -n "$line" ]]; do
      # Opening frontmatter fence
      if [[ $frontmatter_done -eq 0 && $first_fence -eq 1 && "$line" == "---" ]]; then
        in_frontmatter=1
        first_fence=0
        continue
      fi
      # Closing frontmatter fence
      if [[ $in_frontmatter -eq 1 && "$line" == "---" ]]; then
        in_frontmatter=0
        frontmatter_done=1
        continue
      fi
      # Parse frontmatter keys
      if [[ $in_frontmatter -eq 1 ]]; then
        if [[ "$line" =~ ^tracker:[[:space:]]*(.*) ]]; then
          local val="${BASH_REMATCH[1]}"
          # Strip surrounding quotes if present
          val="${val#\"}" ; val="${val%\"}"
          val="${val#\'}" ; val="${val%\'}"
          [[ -n "$val" && "$val" != "none" ]] && url="$val"
        fi
        continue
      fi
      # Accumulate prompt body (skip leading blank lines before body starts)
      if [[ -z "$body" && -z "$line" ]]; then
        continue
      fi
      if [[ -z "$body" ]]; then
        body="$line"
      else
        body="${body}"$'\n'"${line}"
      fi
    done < "$f"

    # Trim trailing whitespace from body
    body="$(echo "$body" | sed -e 's/[[:space:]]*$//')"

    if [[ -n "$body" ]]; then
      tracker_url+=("$url")
      prompt+=("$body")
    else
      echo "Warning: ${f} has no prompt body — skipping" >&2
    fi
  done
}

load_from_file() {
  local file="$1"

  # Detect Whiteboard Defense / section-delimiter format
  if grep -qE '^## [0-9]+\. ' "$file" || grep -q '```markdown' "$file"; then
    local current_entry="" in_section=0 current_url=""
    while IFS= read -r line || [[ -n "$line" ]]; do
      if [[ "$line" =~ ^##[[:space:]]+[0-9]+\.[[:space:]]+(.*) ]]; then
        if [[ -n "$current_entry" ]]; then
          tracker_url+=("${current_url:-none}")
          prompt+=("$(echo -e "$current_entry" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')")
          current_entry=""
        fi
        in_section=1
        current_url="${BASH_REMATCH[1]}"
      elif [[ "$line" =~ ^---[[:space:]]*$ ]]; then
        if [[ $in_section -eq 1 && -n "$current_entry" ]]; then
          tracker_url+=("${current_url:-none}")
          prompt+=("$(echo -e "$current_entry" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')")
          current_entry="" ; current_url=""
        fi
      elif [[ $in_section -eq 1 ]]; then
        [[ "$line" =~ ^\`\`\`(markdown)?$ ]] && continue
        if [[ -z "$current_entry" ]]; then
          current_entry="$line"
        else
          current_entry="${current_entry}"$'\n'"${line}"
        fi
      fi
    done < "$file"

    if [[ $in_section -eq 1 && -n "$current_entry" ]]; then
      tracker_url+=("${current_url:-none}")
      prompt+=("$(echo -e "$current_entry" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')")
    fi
  else
    # Standard 2-line tracker + prompt format
    local url=""
    while IFS= read -r line || [[ -n "$line" ]]; do
      if [[ -z "$line" ]]; then
        url=""
      elif [[ -z "$url" ]]; then
        url="$line"
      else
        tracker_url+=("$url")
        prompt+=("$line")
        url=""
      fi
    done < "$file"
  fi
}

# Route to the right loader
if [[ -d "$INSTRUCTIONS_PATH" ]]; then
  load_from_directory "$INSTRUCTIONS_PATH"
elif [[ -f "$INSTRUCTIONS_PATH" ]]; then
  load_from_file "$INSTRUCTIONS_PATH"
else
  echo "Warning: instructions path not found: ${INSTRUCTIONS_PATH}" >&2
fi

# ── Agent count ───────────────────────────────────────────────────────────────

AGENT_COUNT=${#prompt[@]}
[[ $AGENT_COUNT -lt 1 ]] && AGENT_COUNT=1

# ── Dry-run output ────────────────────────────────────────────────────────────

if [[ $DRY_RUN -eq 1 ]]; then
  echo "============================================================"
  echo " DRY RUN: Agent Orchestration Plan"
  echo "============================================================"
  echo " Mode:             $([ $IS_LOCAL -eq 1 ] && echo "Local (no SSH)" || echo "Remote (${REMOTE_HOST})")"
  echo " Worktrees:        $([ $USE_WORKTREES -eq 1 ] && echo "Enabled (agent-1..N)" || echo "Disabled (Single workspace / current directory)")"
  echo " Instructions:     ${INSTRUCTIONS_PATH}"
  echo " Source type:      $([ -d "${INSTRUCTIONS_PATH}" ] && echo "Directory (per-agent .md files)" || echo "File (legacy format)")"
  echo " Total Agents:     ${AGENT_COUNT}"
  echo " Workspace Root:   ${WORKSPACE_ROOT}"
  echo " Main Directory:   ${MAIN_DIR}"
  if [[ $IS_LOCAL -eq 0 ]]; then
    echo " Inputs Sync:      ${INPUTS_DIR}/ -> ${REMOTE_HOST}:${REMOTE_INPUTS_DIR}/"
  fi
  echo "============================================================"
  echo ""

  for (( i=1; i<=AGENT_COUNT; i++ )); do
    idx=$(( i - 1 ))
    if [[ $USE_WORKTREES -eq 1 ]]; then
      dir="${MAIN_DIR}-agent-${i}"
      branch="agent/${i}"
    else
      dir="${MAIN_DIR}"
      branch="(n/a - no worktrees)"
    fi
    echo "------------------------------------------------------------"
    echo " Agent #${i}"
    echo "------------------------------------------------------------"
    echo " Working Dir: ${dir}"
    echo " Branch:      ${branch}"
    if [[ $idx -lt ${#prompt[@]} ]]; then
      if [[ "${tracker_url[$idx]}" != "none" && -n "${tracker_url[$idx]}" ]]; then
        echo " Tracker:     ${tracker_url[$idx]}"
        echo " Prompt:      ${prompt[$idx]:0:120}…"
        echo " Command:     bob run --max-turns 10000 -w '${WORKSPACE_ROOT}' -- '${tracker_url[$idx]} ${prompt[$idx]:0:80}…'"
      else
        echo " Prompt:      ${prompt[$idx]:0:120}…"
        echo " Command:     bob run --max-turns 10000 -w '${WORKSPACE_ROOT}' -- '${prompt[$idx]:0:80}…'"
      fi
    else
      echo " Mode:        Interactive (no prompt provided)"
      echo " Command:     bob chat -w '${WORKSPACE_ROOT}'"
    fi
    echo ""
  done
  echo "Dry run complete. No processes started and no files written."
  exit 0
fi

# ── Generate per-agent wrapper scripts ───────────────────────────────────────

generate_agent_script() {
  local n="$1"
  local idx=$(( n - 1 ))
  local dir
  local git_checkout_cmd=""

  if [[ $USE_WORKTREES -eq 1 ]]; then
    dir="${MAIN_DIR}-agent-${n}"
    local agent_branch="agent/${n}"
    git_checkout_cmd="git -C ${dir@Q} checkout ${agent_branch@Q}"
  else
    dir="${MAIN_DIR}"
  fi

  local script_path="/tmp/bob-agent-${n}.sh"

  local bob_cmd
  if [[ $idx -lt ${#prompt[@]} ]]; then
    local bob_prompt
    if [[ "${tracker_url[$idx]}" != "none" && -n "${tracker_url[$idx]}" ]]; then
      bob_prompt="${tracker_url[$idx]} ${prompt[$idx]}"
    else
      bob_prompt="${prompt[$idx]}"
    fi
    bob_cmd="bob run --max-turns 10000 -w ${WORKSPACE_ROOT@Q} -- ${bob_prompt@Q}"
  else
    bob_cmd="bob chat -w ${WORKSPACE_ROOT@Q}"
  fi

  if [[ $IS_LOCAL -eq 1 ]]; then
    cat > "${script_path}" <<SCRIPT
#!/usr/bin/env bash
export BOBSHELL_API_KEY=${API_KEY@Q}
cd ${dir@Q}
${bob_cmd}
${git_checkout_cmd}
exec bash
SCRIPT
    chmod 700 "${script_path}"
  else
    ssh "${REMOTE_HOST}" "cat > ${script_path} && chmod +x ${script_path}" <<SCRIPT
#!/usr/bin/env bash
export BOBSHELL_API_KEY=${API_KEY@Q}
cd ${dir@Q}
${bob_cmd}
${git_checkout_cmd}
exec bash
SCRIPT
  fi

  echo "${script_path}"
}

# ── Launch ────────────────────────────────────────────────────────────────────

if [[ $IS_LOCAL -eq 0 ]]; then
  ssh "${REMOTE_HOST}" "mkdir -p ${REMOTE_INPUTS_DIR@Q}"
  rsync -az --delete "${INPUTS_DIR}/" "${REMOTE_HOST}:${REMOTE_INPUTS_DIR}/"
fi

if [[ $IS_LOCAL -eq 1 ]]; then
  echo "Launching ${AGENT_COUNT} local agent(s) from: ${INSTRUCTIONS_PATH}"
else
  echo "Launching ${AGENT_COUNT} remote agent(s) on ${REMOTE_HOST} from: ${INSTRUCTIONS_PATH}"
fi

declare -a agent_scripts=()
for (( i=1; i<=AGENT_COUNT; i++ )); do
  agent_scripts+=( "$(generate_agent_script "$i")" )
done

get_tab_cmd() {
  local script="$1"
  if [[ $IS_LOCAL -eq 1 ]]; then
    echo "bash ${script}"
  else
    echo "ssh -t ${REMOTE_HOST} bash ${script}"
  fi
}

tilix \
  --action=app-new-window \
  -e "bash -c '$(get_tab_cmd "${agent_scripts[0]}")'" &

sleep 2

for (( i=2; i<=AGENT_COUNT; i++ )); do
  tilix \
    --action=app-new-session \
    -e "bash -c '$(get_tab_cmd "${agent_scripts[$((i-1))]}")'" &
  sleep 0.5
done

wait
