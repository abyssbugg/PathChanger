#!/bin/bash
#
# PathChanger Installation Script
# Builds and installs to /Applications (SINGLE copy - no duplicates in Spotlight)
#

set -e

echo "=================================="
echo "PathChanger Installer"
echo "=================================="

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Step 1: Clean existing PathChanger app bundles to prevent Spotlight duplicates
echo ""
echo "[1/4] Cleaning up all existing copies..."

# Remove from /Applications
if [ -d "/Applications/PathChanger.app" ]; then
    rm -rf "/Applications/PathChanger.app"
    echo "      Removed: /Applications/PathChanger.app"
fi

# Remove from project build folder
if [ -d "$SCRIPT_DIR/build/PathChanger.app" ]; then
    rm -rf "$SCRIPT_DIR/build/PathChanger.app"
    echo "      Removed: build/PathChanger.app"
fi

# Remove from project dist folder
if [ -d "$SCRIPT_DIR/dist/PathChanger.app" ]; then
    rm -rf "$SCRIPT_DIR/dist/PathChanger.app"
    echo "      Removed: dist/PathChanger.app"
fi


echo "      Cleanup complete!"

# Step 2: Build the app
echo ""
echo "[2/4] Building latest version..."
./build-app-bundle.sh > /dev/null 2>&1

if [ ! -d "build/PathChanger.app" ]; then
    echo "ERROR: Build failed!"
    exit 1
fi

echo "      Build successful!"

# Step 3: Install to /Applications (MOVE, not copy - ensures single instance)
echo ""
echo "[3/4] Installing to /Applications..."
mv "build/PathChanger.app" "/Applications/"
echo "      Installed!"

# Step 4: Verify single instance
echo ""
echo "[4/4] Verifying single installation..."
APP_COUNT=$(find /Applications "$SCRIPT_DIR" -name "PathChanger.app" -type d 2>/dev/null | wc -l | tr -d ' ')
if [ "$APP_COUNT" -eq "1" ]; then
    echo "      ✓ Only ONE PathChanger.app exists"
else
    echo "      ⚠ Warning: Found $APP_COUNT copies (may need manual cleanup)"
fi

echo ""
echo "=================================="
echo "SUCCESS! PathChanger installed."
echo "=================================="
echo ""
echo "Open from Spotlight: Cmd+Space → 'PathChanger'"
echo ""
echo "To update: ./install.sh"
echo ""
