#!/usr/bin/env bash
# setup-gemma-remote.sh
# One-time setup: installs Ollama and pulls gemma4:27b on sockeni07.
# Run this once from your LOCAL laptop before using launch-gemma-remote.sh.
#
# sockeni07 specs:
#   RAM  : 503 GB total, ~222 GB free  (no VRAM needed — pure CPU inference)
#   Disk : 149 GB free on /  (gemma4:27b is ~17 GB)
#   GPU  : none (CPU inference via Ollama)
#
# Why gemma4:27b instead of gemma4:latest (12b)?
#   sockeni07 has 369 GB available RAM — the 27b model fits easily and
#   produces noticeably better C++ test output than the 12b variant.
#   If you prefer faster runs at lower quality, change MODEL to gemma4:latest.
#
# Usage:
#   chmod +x setup-gemma-remote.sh
#   ./setup-gemma-remote.sh
#   ./setup-gemma-remote.sh --model gemma4:latest   # use 12b instead

set -euo pipefail

REMOTE_HOST="szuraski@sockeni07"
MODEL="gemma4:31b"
REMOTE_OLLAMA_DIR="/home/szuraski/.ollama"
REMOTE_BIN="/home/szuraski/.local/bin"

# Parse CLI arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --model)
      MODEL="$2"
      shift 2
      ;;
    --host)
      REMOTE_HOST="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      echo "Usage: $0 [--model <name>] [--host <user@host>]" >&2
      exit 1
      ;;
  esac
done

echo "=== Setting up Gemma on ${REMOTE_HOST} ==="
echo "    Model : ${MODEL}"
echo ""

# Step 1 — install Ollama if not already present
# The official installer uses sudo to place Ollama in /usr/local/bin and
# registers a systemd service; it also works without sudo when the user has
# sudoers access (which szuraski does on sockeni07).
echo "[1/3] Installing Ollama on ${REMOTE_HOST} …"
ssh "${REMOTE_HOST}" bash <<'REMOTE'
set -euo pipefail

# Prefer /usr/local/bin (system install) then ~/.local/bin (user install)
export PATH="/usr/local/bin:${HOME}/.local/bin:${PATH}"

if command -v ollama &>/dev/null; then
  echo "  Ollama already installed: $(ollama --version 2>/dev/null || true)"
  exit 0
fi

curl -fsSL https://ollama.com/install.sh | sh
echo "  Installed: $(ollama --version 2>/dev/null || true)"
REMOTE

echo ""

# Step 2 — ensure ollama serve is running
# The systemd service started by the installer handles this automatically.
# Fall back to a manual nohup start if systemd didn't bring it up.
echo "[2/3] Ensuring ollama serve is running on ${REMOTE_HOST} …"
ssh "${REMOTE_HOST}" bash <<'REMOTE'
set -euo pipefail
export PATH="/usr/local/bin:${HOME}/.local/bin:${PATH}"

if curl -sf http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
  echo "  ollama serve already running."
  exit 0
fi

echo "  Starting ollama serve …"
nohup ollama serve >/tmp/ollama-serve.log 2>&1 &
echo "  Waiting for API to become ready …"
for i in $(seq 1 30); do
  if curl -sf http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
    echo "  ollama serve is ready (waited ${i}s)."
    exit 0
  fi
  sleep 1
done
echo "ERROR: ollama serve did not become ready after 30s. Check /tmp/ollama-serve.log" >&2
exit 1
REMOTE

echo ""

# Step 3 — pull the model (idempotent — safe to re-run)
# Use a heredoc so the model name is passed as a plain variable without
# shell quoting issues across the SSH boundary.
echo "[3/3] Pulling ${MODEL} on ${REMOTE_HOST} (this may take a while) …"
ssh "${REMOTE_HOST}" bash -s -- "${MODEL}" <<'REMOTE'
set -euo pipefail
export PATH="/usr/local/bin:${HOME}/.local/bin:${PATH}"
MODEL="$1"
ollama pull "${MODEL}"
REMOTE

echo ""
echo "=== Setup complete ==="
echo "    Run:  ./gemma-agents/launch-gemma-remote.sh"
