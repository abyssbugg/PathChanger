#!/bin/bash
set -e

cd "$(dirname "$0")"

echo "Cleaning previous build..."
swift package clean 2>/dev/null || true
rm -rf build dist 2>/dev/null || true

echo "Building app bundle..."
APP_BUILD_ROOT="${APP_BUNDLE_BUILD_ROOT:-${TMPDIR:-/tmp}/pathchanger-app-build}"
APP_BUNDLE_BUILD_ROOT="$APP_BUILD_ROOT" ./build-app-bundle.sh "$@"

echo "Preparing dist copy..."
mkdir -p dist
rm -rf dist/PathChanger.app
ditto --noextattr --norsrc "$APP_BUILD_ROOT/PathChanger.app" dist/PathChanger.app
xattr -cr dist/PathChanger.app
xattr -crs dist/PathChanger.app
dot_clean -m dist/PathChanger.app
xattr -cr dist/PathChanger.app
xattr -crs dist/PathChanger.app
if xattr -lr dist/PathChanger.app 2>/dev/null | grep -E 'com\.apple\.(FinderInfo|ResourceFork|fileprovider\.fpfs#P)'; then
    echo "Forbidden extended attributes remain in dist/PathChanger.app" >&2
    exit 1
fi

echo ""
echo "Build complete! App located at:"
echo "  dist/PathChanger.app"
echo ""
echo "To launch: open dist/PathChanger.app"
