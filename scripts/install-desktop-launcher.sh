#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

DIST_BIN="${REPO_ROOT}/dist/bob-agents-gui"
if [[ ! -f "$DIST_BIN" ]]; then
    echo "Executable not found at ${DIST_BIN}."
    echo "Building executable first..."
    "${REPO_ROOT}/scripts/build-executable.sh"
fi

echo "==> Installing desktop launcher and icons for user ($(whoami))..."

# Install binary to ~/.local/bin
mkdir -p "${HOME}/.local/bin"
cp -f "${DIST_BIN}" "${HOME}/.local/bin/bob-agents-gui"
chmod +x "${HOME}/.local/bin/bob-agents-gui"

# Install icon to standard icon directories (different sizes/formats)
mkdir -p "${HOME}/.local/share/icons/hicolor/scalable/apps"
mkdir -p "${HOME}/.local/share/icons/hicolor/48x48/apps"
mkdir -p "${HOME}/.local/share/icons/hicolor/128x128/apps"
mkdir -p "${HOME}/.local/share/pixmaps"

cp -f "${REPO_ROOT}/gui/logo.png" "${HOME}/.local/share/icons/hicolor/128x128/apps/bob-agents-gui.png"
cp -f "${REPO_ROOT}/gui/logo.png" "${HOME}/.local/share/icons/hicolor/48x48/apps/bob-agents-gui.png"
cp -f "${REPO_ROOT}/gui/logo.png" "${HOME}/.local/share/pixmaps/bob-agents-gui.png"

# Install .desktop file
mkdir -p "${HOME}/.local/share/applications"
sed -e "s|Exec=bob-agents-gui|Exec=${HOME}/.local/bin/bob-agents-gui|g" \
    -e "s|Icon=bob-agents-gui|Icon=${HOME}/.local/share/icons/hicolor/128x128/apps/bob-agents-gui.png|g" \
    "${REPO_ROOT}/gui/bob-agents-gui.desktop" > "${HOME}/.local/share/applications/bob-agents-gui.desktop"

chmod +x "${HOME}/.local/share/applications/bob-agents-gui.desktop"

# Refresh desktop database if tool is available
if command -v update-desktop-database &>/dev/null; then
    update-desktop-database "${HOME}/.local/share/applications" || true
fi

echo "==> Installation complete!"
echo "    App is now registered in the application launcher with its icon."
echo "    Binary location: ~/.local/bin/bob-agents-gui"
