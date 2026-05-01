#!/bin/bash
set -e

cd "$(dirname "$0")"

echo "Cleaning previous build..."
swift package clean 2>/dev/null || true
rm -rf build dist 2>/dev/null || true

echo "Building app bundle..."
./build-app-bundle.sh "$@"

echo "Preparing dist copy..."
mkdir -p dist
rm -rf dist/PathChanger.app
cp -R build/PathChanger.app dist/PathChanger.app

echo ""
echo "Build complete! App located at:"
echo "  dist/PathChanger.app"
echo ""
echo "To launch: open dist/PathChanger.app"
