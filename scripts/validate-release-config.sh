#!/bin/bash
# Validate CI/release configuration that must hold before production packaging.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

fail() {
    echo "✗ $1" >&2
    exit 1
}

pass() {
    echo "✓ $1"
}

require_file() {
    local path="$1"
    [ -f "$path" ] || fail "Required file missing: $path"
    pass "Required file exists: $path"
}

plist_value() {
    /usr/libexec/PlistBuddy -c "Print :$1" "$2"
}

require_file "Package.swift"
require_file "Package.resolved"
require_file "Resources/Info.plist"
require_file "Resources/PathChanger.entitlements"
require_file ".github/workflows/ci.yml"
require_file ".github/workflows/release.yml"
require_file ".github/workflows/release-validation.yml"
require_file "build-app-bundle.sh"

plutil -lint Resources/Info.plist >/dev/null
plutil -lint Resources/PathChanger.entitlements >/dev/null
pass "Info.plist and entitlements are valid plists"

BUNDLE_ID="$(plist_value CFBundleIdentifier Resources/Info.plist)"
[ "$BUNDLE_ID" = "com.pathchanger.app" ] || fail "Unexpected bundle identifier: $BUNDLE_ID"
pass "Bundle identifier is deterministic"

SHORT_VERSION="$(plist_value CFBundleShortVersionString Resources/Info.plist)"
[[ "$SHORT_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "CFBundleShortVersionString must be semver: $SHORT_VERSION"
pass "Bundle short version is semver: $SHORT_VERSION"

BUILD_VERSION="$(plist_value CFBundleVersion Resources/Info.plist)"
[[ "$BUILD_VERSION" =~ ^[0-9]+$ ]] || fail "CFBundleVersion must be numeric: $BUILD_VERSION"
pass "Bundle build version is numeric: $BUILD_VERSION"

if /usr/libexec/PlistBuddy -c "Print :com.apple.security.get-task-allow" Resources/PathChanger.entitlements >/tmp/pathchanger-get-task-allow 2>/dev/null; then
    if grep -qx "true" /tmp/pathchanger-get-task-allow; then
        rm -f /tmp/pathchanger-get-task-allow
        fail "get-task-allow must not be enabled in distribution entitlements"
    fi
fi
rm -f /tmp/pathchanger-get-task-allow

for entitlement in \
    com.apple.security.cs.allow-unsigned-executable-memory \
    com.apple.security.cs.disable-library-validation \
    com.apple.security.cs.allow-dyld-environment-variables
do
    if /usr/libexec/PlistBuddy -c "Print :$entitlement" Resources/PathChanger.entitlements >/tmp/pathchanger-entitlement-check 2>/dev/null; then
        if grep -qx "true" /tmp/pathchanger-entitlement-check; then
            rm -f /tmp/pathchanger-entitlement-check
            fail "High-risk entitlement must not be enabled: $entitlement"
        fi
    fi
done
rm -f /tmp/pathchanger-entitlement-check
pass "Distribution entitlements exclude debug/high-risk code-signing permissions"

SPARKLE_RESOLVED_VERSION="$(python3 - <<'PY'
import json
with open("Package.resolved", encoding="utf-8") as fh:
    data = json.load(fh)
for pin in data.get("pins", []):
    if pin.get("identity") == "sparkle":
        print(pin.get("state", {}).get("version", ""))
        break
PY
)"
[ -n "$SPARKLE_RESOLVED_VERSION" ] || fail "Sparkle pin missing from Package.resolved"
grep -Eq "SPARKLE_VERSION(:[[:space:]]*|=)\"?$SPARKLE_RESOLVED_VERSION\"?" .github/workflows/release.yml || \
    fail "Release workflow Sparkle tool version must match Package.resolved ($SPARKLE_RESOLVED_VERSION)"
pass "Sparkle release tooling matches Package.resolved ($SPARKLE_RESOLVED_VERSION)"

grep -q "REQUIRE_PRODUCTION_SIGNING=1" .github/workflows/release.yml || \
    fail "Release workflow must require production signing in build-app-bundle.sh"
grep -q "MACOS_CERTIFICATE_P12_BASE64" .github/workflows/release.yml || \
    fail "Release workflow must import a Developer ID certificate"
grep -q "xcrun notarytool submit" .github/workflows/release.yml || \
    fail "Release workflow must submit the DMG for notarization"
grep -q "xcrun stapler staple" .github/workflows/release.yml || \
    fail "Release workflow must staple notarization tickets"
grep -q "xcrun stapler validate" .github/workflows/release.yml || \
    fail "Release workflow must validate stapled tickets"
grep -q "SPARKLE_PRIVATE_KEY" .github/workflows/release.yml || \
    fail "Release workflow must require Sparkle signing"
pass "Release workflow enforces signing, notarization, stapling, and Sparkle signing"

grep -q "workflow_dispatch:" .github/workflows/release-validation.yml || \
    fail "Release validation workflow must be manually dispatchable"
grep -q "contents: read" .github/workflows/release-validation.yml || \
    fail "Release validation workflow must not request release publishing permissions"
if grep -q "gh release upload\|release upload" .github/workflows/release-validation.yml; then
    fail "Release validation workflow must not upload production release assets"
fi
grep -q "xcrun notarytool submit" .github/workflows/release-validation.yml || \
    fail "Release validation workflow must submit artifacts for notarization"
grep -q "spctl --assess" .github/workflows/release-validation.yml || \
    fail "Release validation workflow must run Gatekeeper assessment"
grep -Fq "com\.apple\.(FinderInfo|ResourceFork|provenance|fileprovider\.fpfs#P)" .github/workflows/release-validation.yml || \
    fail "Release validation workflow must fail on provenance xattr contamination in CI"
pass "Release validation workflow is dispatchable, non-publishing, and notarization-gated"

grep -q 'APP_BUNDLE_BUILD_ROOT="${APP_BUNDLE_BUILD_ROOT:-${TMPDIR:-/tmp}/pathchanger-app-build}"' build-app-bundle.sh || \
    fail "App bundle script must default outside the workspace to avoid file-provider metadata contamination"
grep -q "Production bundle builds require a Developer ID signing identity" build-app-bundle.sh || \
    fail "App bundle script must reject ad-hoc signing for production builds"
pass "App bundle script has deterministic output and production signing gate"

if grep -n "|| true" .github/workflows/ci.yml .github/workflows/release.yml; then
    fail "CI/release workflows must not contain tolerated failures"
fi
pass "CI/release workflows do not tolerate failed commands"

echo "Release configuration validation passed."
