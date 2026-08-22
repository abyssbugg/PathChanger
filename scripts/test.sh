#!/bin/bash
#
# PathChanger test runner
#
# Wraps `swift test` and works around two local-environment blockers that stop the
# XCTest bundle from running on macOS:
#
#   1. This checkout lives inside an iCloud / file-provider synced directory
#      (~/Desktop). The provider continuously stamps com.apple.provenance on sources
#      and com.apple.FinderInfo on the generated resource bundle, and codesign refuses
#      to sign anything carrying FinderInfo:
#        "resource fork, Finder information, or similar detritus not allowed"
#      Stripping and retrying inside the synced tree is a race because the provider can
#      re-apply the attributes before codesign runs. Build output therefore lives under
#      ~/Library/Caches by default, via SwiftPM's --scratch-path.
#
#   2. The test bundle links Sparkle via @rpath, but SwiftPM places the framework at
#      Products/<config>/Sparkle.framework while dyld searches
#      Products/<config>/PackageFrameworks/. Linking the expected location lets the
#      bundle load.
#
# Neither workaround changes build semantics: both act only on generated artifacts,
# never on source content. CI builds from a fresh clone outside a synced directory and
# is unaffected either way.
#
# The proper long-term fix for (1) is to move the repository somewhere that is not
# iCloud-synced, for example ~/Developer/PathChanger.
#
# Usage:
#   ./scripts/test.sh                  # run the full suite with coverage
#   ./scripts/test.sh --no-coverage    # skip coverage instrumentation
#   ./scripts/test.sh --filter Foo     # pass any extra args through to `swift test`
#
# Override the build location with PATHCHANGER_SCRATCH_PATH if you need to.
#
# Device- and privilege-dependent suites stay skipped unless you explicitly export
# PATHCHANGER_RUN_DEVICE_TESTS=1. This script never sets it for you.

set -euo pipefail

# Resolve the repository root from this script's own location.
# Note: ${BASH_SOURCE[0]} requires bash, which is why the shebang above is not zsh.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ ! -f "$PROJECT_ROOT/Package.swift" ]; then
    echo "error: could not locate Package.swift at $PROJECT_ROOT" >&2
    exit 1
fi

cd "$PROJECT_ROOT"

CONFIGURATION="debug"
COVERAGE=1
PASSTHROUGH=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-coverage)
            COVERAGE=0
            shift
            ;;
        -c|--configuration)
            CONFIGURATION="$2"
            shift 2
            ;;
        *)
            PASSTHROUGH+=("$1")
            shift
            ;;
    esac
done

# Keep build output outside the synced tree. ~/Library/Caches is never file-provider
# managed, so nothing re-stamps the generated bundle between build and codesign.
SCRATCH_PATH="${PATHCHANGER_SCRATCH_PATH:-$HOME/Library/Caches/PathChanger/build}"
mkdir -p "$SCRATCH_PATH"
echo "==> Build output: $SCRATCH_PATH"

echo "==> Stripping extended attributes from sources"
# Only touches xattrs, never file content.
xattr -cr PathChanger Tests PathChangerCompanion 2>/dev/null || true

COMMON_ARGS=(-c "$CONFIGURATION" --scratch-path "$SCRATCH_PATH")
if [ "$COVERAGE" -eq 1 ]; then
    COMMON_ARGS+=(--enable-code-coverage)
fi

echo "==> Building test bundle ($CONFIGURATION), pass 1"
set +e
swift build --build-tests "${COMMON_ARGS[@]}"
FIRST_PASS=$?
set -e

echo "==> Clearing extended attributes from build output"
xattr -cr "$SCRATCH_PATH" 2>/dev/null || true

if [ "$FIRST_PASS" -ne 0 ]; then
    echo "==> Re-running build so codesign can retry against the cleaned bundle, pass 2"
    swift build --build-tests "${COMMON_ARGS[@]}"
fi

# Xcode 16+/Swift 6 SwiftBuild layout puts products under
# <scratch>/out/Products/<Config>. Older SwiftPM uses <scratch>/<config>.
for PRODUCTS_DIR in "$SCRATCH_PATH"/out/Products/*/; do
    [ -d "$PRODUCTS_DIR" ] || continue
    if [ -d "${PRODUCTS_DIR}Sparkle.framework" ] && [ ! -e "${PRODUCTS_DIR}PackageFrameworks/Sparkle.framework" ]; then
        echo "==> Linking Sparkle.framework into ${PRODUCTS_DIR}PackageFrameworks/"
        mkdir -p "${PRODUCTS_DIR}PackageFrameworks"
        ln -sfn ../Sparkle.framework "${PRODUCTS_DIR}PackageFrameworks/Sparkle.framework"
    fi
done

echo "==> Running tests"
TEST_ARGS=("${COMMON_ARGS[@]}" --skip-build)
if [ ${#PASSTHROUGH[@]} -gt 0 ]; then
    TEST_ARGS+=("${PASSTHROUGH[@]}")
fi

swift test "${TEST_ARGS[@]}"
