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
# Mint a private, unique 0700 workspace (CWE-377/CWE-367). Clean it on exit so a
# predictable path cannot be pre-seeded or reused across runs by another account.
if [ -n "${APP_BUNDLE_BUILD_ROOT:-}" ]; then
    APP_BUILD_ROOT="$APP_BUNDLE_BUILD_ROOT"
    mkdir -p "$APP_BUILD_ROOT"
else
    APP_BUILD_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/pathchanger-app-build.XXXXXXXX")"
    trap 'rm -rf "$APP_BUILD_ROOT"' EXIT
fi
chmod 700 "$APP_BUILD_ROOT"
DIST_BUILD_ROOT="${APP_BUNDLE_DIST_ROOT:-$(pwd)/dist}"
APP_BUNDLE_BUILD_ROOT="$APP_BUILD_ROOT" ./build-app-bundle.sh "$@"

echo "Preparing dist copy..."
mkdir -p "$DIST_BUILD_ROOT"
rm -rf "$DIST_BUILD_ROOT/PathChanger.app"
ditto --noextattr --norsrc "$APP_BUILD_ROOT/PathChanger.app" "$DIST_BUILD_ROOT/PathChanger.app"
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
    if [ "$DIST_BUILD_ROOT" = "$(pwd)/dist" ]; then
        echo "WARNING: Forbidden extended attributes remain in $DIST_BUILD_ROOT/PathChanger.app" >&2
        echo "         This can be re-applied by macOS File Provider on synced folders (for example Desktop/Documents)." >&2
        echo "         Continuing because the bundle itself was built from sanitized artifacts." >&2
    else
        echo "Forbidden extended attributes remain in $DIST_BUILD_ROOT/PathChanger.app" >&2
        exit 1
    fi
fi

echo ""
echo "Verifying signature of dist bundle (post-copy integrity check)..."
codesign --verify --deep --strict --verbose=2 "$DIST_BUILD_ROOT/PathChanger.app" \
    || { echo "ERROR: dist bundle failed signature verification after copy" >&2; exit 1; }

echo ""
echo "Build complete! App located at:"
if [ "$DIST_BUILD_ROOT" = "$(pwd)/dist" ]; then
    echo "  dist/PathChanger.app"
else
    echo "  $DIST_BUILD_ROOT/PathChanger.app"
fi
echo ""
if [ "$DIST_BUILD_ROOT" = "$(pwd)/dist" ]; then
    echo "To launch: open dist/PathChanger.app"
else
    echo "To launch: open \"$DIST_BUILD_ROOT/PathChanger.app\""
fi
