#!/usr/bin/env bash
set -euo pipefail

echo "==> Ensuring PyInstaller and Pillow are installed..."
python3 -m pip install --quiet --upgrade pyinstaller pillow

echo "==> Building standalone executable using PyInstaller..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${REPO_ROOT}/gui"
pyinstaller --clean --noconfirm --distpath "${REPO_ROOT}/dist" --workpath "${REPO_ROOT}/build" bob-agents-gui.spec

# Set custom file icon for GNOME/Nautilus file manager
if command -v gio &>/dev/null && [[ -f "${REPO_ROOT}/dist/bob-agents-gui" ]] && [[ -f "${REPO_ROOT}/gui/logo.png" ]]; then
    gio set -t string "${REPO_ROOT}/dist/bob-agents-gui" metadata::custom-icon "file://${REPO_ROOT}/gui/logo.png" || true
fi

echo "==> Build complete!"
echo "    Artifact(s) available in: ./dist/"
