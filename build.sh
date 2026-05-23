#!/bin/bash
set -e

cd "$(dirname "$0")"

sanitize_bundle_metadata() {
    local bundle="$1"
    [ -d "$bundle" ] || return 0

    xattr -cr "$bundle" 2>/dev/null || true
    xattr -crs "$bundle" 2>/dev/null || true
    xattr -dr com.apple.FinderInfo "$bundle" 2>/dev/null || true
    xattr -dr com.apple.ResourceFork "$bundle" 2>/dev/null || true
    xattr -dr "com.apple.fileprovider.fpfs#P" "$bundle" 2>/dev/null || true

    find "$bundle" -print0 | while IFS= read -r -d '' path; do
        xattr -d com.apple.FinderInfo "$path" 2>/dev/null || true
        xattr -d com.apple.ResourceFork "$path" 2>/dev/null || true
        xattr -d "com.apple.fileprovider.fpfs#P" "$path" 2>/dev/null || true
    done
}

contains_forbidden_metadata() {
    local bundle="$1"
    xattr -lr "$bundle" 2>/dev/null | grep -E 'com\.apple\.(FinderInfo|ResourceFork|fileprovider\.fpfs#P)'
}

echo "Cleaning previous build..."
swift package clean 2>/dev/null || true
rm -rf build dist 2>/dev/null || true

echo "Building app bundle..."
APP_BUILD_ROOT="${APP_BUNDLE_BUILD_ROOT:-${TMPDIR:-/tmp}/pathchanger-app-build}"
DIST_BUILD_ROOT="${APP_BUNDLE_DIST_ROOT:-$HOME/Library/Caches/PathChanger/InternalBuild}"
APP_BUNDLE_BUILD_ROOT="$APP_BUILD_ROOT" ./build-app-bundle.sh "$@"

echo "Preparing dist copy..."
rm -rf "$DIST_BUILD_ROOT"
mkdir -p "$DIST_BUILD_ROOT"
mkdir -p dist
rm -rf dist/PathChanger.app
ditto --noextattr --norsrc "$APP_BUILD_ROOT/PathChanger.app" "$DIST_BUILD_ROOT/PathChanger.app"
ln -s "$DIST_BUILD_ROOT/PathChanger.app" dist/PathChanger.app
sanitize_bundle_metadata "$DIST_BUILD_ROOT/PathChanger.app"
dot_clean -m "$DIST_BUILD_ROOT/PathChanger.app"
for _ in 1 2 3 4 5; do
    sanitize_bundle_metadata "$DIST_BUILD_ROOT/PathChanger.app"
    if ! contains_forbidden_metadata "$DIST_BUILD_ROOT/PathChanger.app" >/dev/null; then
        break
    fi
    sleep 0.2
done
sleep 1
sanitize_bundle_metadata "$DIST_BUILD_ROOT/PathChanger.app"
if contains_forbidden_metadata "$DIST_BUILD_ROOT/PathChanger.app"; then
    echo "Forbidden extended attributes remain in dist/PathChanger.app" >&2
    exit 1
fi

echo ""
echo "Build complete! App located at:"
echo "  dist/PathChanger.app"
echo ""
echo "To launch: open dist/PathChanger.app"
