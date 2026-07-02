#!/bin/bash
#
# PathChanger Installation Script
# Installs exactly one canonical app bundle at:
#   /Applications/PathChanger.app
# and removes all prior /Applications/PathChanger*.app bundles first.
#
# Usage:
#   ./install.sh
#

set -euo pipefail

echo "=================================="
echo "PathChanger Installer"
echo "=================================="

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

TARGET_APP="/Applications/PathChanger.app"

echo ""
echo "[1/3] Building latest version into dist/..."
./build.sh > /dev/null 2>&1

if [ ! -d "$SCRIPT_DIR/dist/PathChanger.app" ]; then
    echo "ERROR: Build failed - dist/PathChanger.app not found"
    exit 1
fi
echo "      Build successful."

echo ""
echo "[2/3] Removing prior PathChanger installations from /Applications ..."
PRIOR_APPS=$(find /Applications -maxdepth 1 -type d -name "PathChanger*.app" -print)
if [ -n "$PRIOR_APPS" ]; then
    while IFS= read -r app; do
        [ -n "$app" ] || continue
        rm -rf "$app"
    done <<< "$PRIOR_APPS"
fi
echo "      Cleanup complete."

echo ""
echo "[3/3] Installing to $TARGET_APP ..."
cp -R "$SCRIPT_DIR/dist/PathChanger.app" "$TARGET_APP"
echo "      Installed."

echo ""
echo "=================================="
echo "Install complete."
echo "=================================="
echo ""
echo "Installed app: $TARGET_APP"
echo "Launch: open \"$TARGET_APP\""
echo ""
