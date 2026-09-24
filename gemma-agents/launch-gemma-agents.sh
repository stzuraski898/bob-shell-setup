#!/usr/bin/env bash
# launch-gemma-agents.sh
# Opens Tilix with N tabs, each running generate_tests.py against a source file
# listed in the instructions file, using local Ollama + Gemma 4.
#
# Prerequisites:
#   1. ollama serve  (must be running)
#   2. ollama pull gemma4:latest
#   3. pip install ollama pytest  (in whatever Python env you use)
#
# Hardware note (Intel Core Ultra 7 165H / RTX 1000 Ada, ~16 GB free RAM):
#   gemma4:latest is ~9.6 GB. Start with --agents 1 and benchmark before
#   increasing. Two simultaneous Gemma instances will likely saturate RAM
#   and slow each other down significantly.
#
# Instructions file format (one entry per agent, blank line between entries):
#
#   path/to/source_file.cc
#   path/to/output_test_file.cc
#
#   path/to/another_source.cc
#   path/to/another_test.cc
#
# Optional prompt files: place a <basename>.md file alongside each source entry
# in Inputs/prompts/ (e.g. Inputs/prompts/DaemonKey.md) to feed class contracts
# and intent artefacts to the model as its system prompt.  The --prompt-dir flag
# sets the directory to search (default: Inputs/prompts/).
#
# Usage:
#   chmod +x launch-gemma-agents.sh
#   ./launch-gemma-agents.sh
#   ./launch-gemma-agents.sh --instructions Inputs/gemma-instructions
#   ./launch-gemma-agents.sh --agents 2
#   ./launch-gemma-agents.sh --model gemma4:27b
#   ./launch-gemma-agents.sh --prompt-dir /path/to/prompts

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTRUCTIONS_FILE="${SCRIPT_DIR}/Inputs/gemma-instructions"
GENERATOR="${SCRIPT_DIR}/generate_tests.py"
PROMPT_DIR="${SCRIPT_DIR}/Inputs/prompts"
MODEL="gemma4:latest"
MAX_AGENTS=1          # safe default for this hardware; increase with caution
MAX_ITERATIONS=5      # feedback loop: how many fix attempts before giving up

# Parse CLI arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --instructions)
      INSTRUCTIONS_FILE="$2"
      shift 2
      ;;
    --agents)
      MAX_AGENTS="$2"
      shift 2
      ;;
    --model)
      MODEL="$2"
      shift 2
      ;;
    --prompt-dir)
      PROMPT_DIR="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      echo "Usage: $0 [--instructions <path>] [--agents <n>] [--model <name>] [--prompt-dir <path>]" >&2
      exit 1
      ;;
  esac
done

# Verify Ollama is reachable
if ! curl -sf http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
  echo "Error: Ollama is not running on 127.0.0.1:11434." >&2
  echo "Start it with:  ollama serve" >&2
  exit 1
fi

# Verify the generator script exists
if [[ ! -f "$GENERATOR" ]]; then
  echo "Error: generate_tests.py not found at ${GENERATOR}" >&2
  exit 1
fi

# Verify instructions file exists
if [[ ! -f "$INSTRUCTIONS_FILE" ]]; then
  echo "Error: Instructions file not found: ${INSTRUCTIONS_FILE}" >&2
  echo "Create it with source/output pairs (one per line, blank line between entries)." >&2
  exit 1
fi

# Parse the instructions file into parallel arrays: source_file[] and output_file[]
declare -a source_file=()
declare -a output_file=()

src=""
while IFS= read -r line || [[ -n "$line" ]]; do
  if [[ -z "$line" ]]; then
    src=""
  elif [[ -z "$src" ]]; then
    src="$line"
  else
    source_file+=("$src")
    output_file+=("$line")
    src=""
  fi
done < "$INSTRUCTIONS_FILE"

AGENT_COUNT=${#source_file[@]}
if [[ $AGENT_COUNT -lt 1 ]]; then
  echo "Error: No entries found in ${INSTRUCTIONS_FILE}" >&2
  exit 1
fi

if [[ $AGENT_COUNT -gt $MAX_AGENTS ]]; then
  echo "Warning: ${AGENT_COUNT} entries found but --agents is capped at ${MAX_AGENTS}." >&2
  echo "         Launching first ${MAX_AGENTS} agent(s). Increase --agents to run more." >&2
  AGENT_COUNT=$MAX_AGENTS
fi

echo "Launching ${AGENT_COUNT} agent(s) with model '${MODEL}'"
echo "Instructions: ${INSTRUCTIONS_FILE}"
echo ""

# Resolve an optional prompt file for a given source path.
# Looks for <PROMPT_DIR>/<basename-without-ext>.md, then .txt.
# Prints the path if found, empty string if not.
resolve_prompt_file() {
  local src="$1"
  local base
  base="$(basename "${src%.*}")"
  for ext in md txt; do
    local candidate="${PROMPT_DIR}/${base}.${ext}"
    if [[ -f "$candidate" ]]; then
      echo "$candidate"
      return
    fi
  done
  echo ""
}

# Build the command for agent N
agent_cmd() {
  local idx="$1"
  local src="${source_file[$idx]}"
  local out="${output_file[$idx]}"
  local prompt_file
  prompt_file="$(resolve_prompt_file "$src")"
  local prompt_arg=""
  if [[ -n "$prompt_file" ]]; then
    prompt_arg="--prompt-file ${prompt_file@Q}"
    echo "[agent $((idx+1))] Using prompt: ${prompt_file}" >&2
  fi
  echo "python3 ${GENERATOR@Q} --source ${src@Q} --output ${out@Q} --model ${MODEL@Q} --max-iterations ${MAX_ITERATIONS} ${prompt_arg}; echo 'Agent $((idx+1)) finished. Press Enter to close.'; read"
}

# Tab 1 — open a new Tilix window
tilix \
  --action=app-new-window \
  -e "bash -c $(agent_cmd 0)" &

sleep 2

# Tabs 2–N
for (( i=1; i<AGENT_COUNT; i++ )); do
  tilix \
    --action=app-new-session \
    -e "bash -c $(agent_cmd $i)" &
  sleep 0.5
done

wait
