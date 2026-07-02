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
require_file "Resources/Info.plist"
require_file "Resources/PathChanger.entitlements"
require_file ".github/workflows/ci.yml"
require_file ".github/workflows/release.yml"
require_file ".github/workflows/release-validation.yml"
require_file "build-app-bundle.sh"
require_file "DEPLOYMENT/README.md"

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

if grep -qi "sparkle" Package.swift; then
    fail "Package.swift must not include Sparkle dependencies while updater wiring is disabled"
fi
if grep -qi "sparkle" build-app-bundle.sh .github/workflows/ci.yml .github/workflows/release.yml .github/workflows/release-validation.yml; then
    fail "Build and workflow configuration must not include Sparkle wiring in clean-disable mode"
fi
pass "Sparkle updater path is cleanly disabled with no package/workflow/build-script wiring"
grep -q "build-app-bundle.sh" .github/workflows/release.yml || \
    fail "Release workflow must build an app bundle"
grep -q "PathChanger-\${VERSION}-macOS.zip" .github/workflows/release.yml || \
    fail "Release workflow must produce GitHub zip artifacts"
grep -q "PathChanger-\${VERSION}-macOS.sha256" .github/workflows/release.yml || \
    fail "Release workflow must produce SHA-256 checksum artifacts"
if grep -q "REQUIRE_PRODUCTION_SIGNING=1\\|MACOS_CERTIFICATE_P12_BASE64\\|xcrun notarytool\\|xcrun stapler" .github/workflows/release.yml; then
    fail "Release workflow must not require Apple Developer signing/notarization for GitHub-direct distribution"
fi
pass "Release workflow uses ad-hoc GitHub-direct packaging without Apple-signing gates"

grep -q "workflow_dispatch:" .github/workflows/release-validation.yml || \
    fail "Release validation workflow must be manually dispatchable"
grep -q "contents: read" .github/workflows/release-validation.yml || \
    fail "Release validation workflow must not request release publishing permissions"
if grep -q "gh release upload\|release upload" .github/workflows/release-validation.yml; then
    fail "Release validation workflow must not upload production release assets"
fi
grep -q "PathChanger-\${VERSION}-macOS.zip" .github/workflows/release-validation.yml || \
    fail "Release validation workflow must verify zip packaging"
grep -q "shasum -a 256 -c" .github/workflows/release-validation.yml || \
    fail "Release validation workflow must verify SHA-256 checksums"
if grep -q "xcrun notarytool\\|xcrun stapler\\|MACOS_CERTIFICATE_P12_BASE64\\|APPLE_TEAM_ID" .github/workflows/release-validation.yml; then
    fail "Release validation workflow must not require Apple Developer notarization/signing secrets"
fi
pass "Release validation workflow is dispatchable, non-publishing, and GitHub-direct distribution aligned"

for legacy_doc in \
    DEPLOYMENT/02_CODE_SIGNING_PROCEDURES.md \
    DEPLOYMENT/03_SECURITY_VERIFICATION_CHECKLIST.md \
    DEPLOYMENT/04_PERFORMANCE_BASELINE.md \
    DEPLOYMENT/05_UAT_SIGN_OFF.md
do
    [ ! -f "$legacy_doc" ] || fail "Contradictory legacy deployment document must be removed: $legacy_doc"
done
pass "Contradictory legacy deployment documents were removed"

grep -q "PathChanger Authoritative Release Process (GitHub Direct)" DEPLOYMENT/README.md || \
    fail "DEPLOYMENT/README.md must explicitly declare authoritative GitHub-direct release process"

if grep -nE "notariz|notarytool|stapler|\\.dmg|hdiutil create|/Users/" README.md DEPLOYMENT/README.md; then
    fail "Top-level release documents must not contain deprecated release paths, DMG/notarization flows, or machine-specific paths"
fi
pass "Top-level release documents contain no deprecated release process references"

if grep -n "via.placeholder.com" README.md; then
    fail "README must not contain placeholder screenshot asset references"
fi
pass "README contains no placeholder screenshot references"

if grep -n "PathChanger-New.app" README.md; then
    fail "Documentation must not advertise PathChanger-New.app"
fi
if grep -n -- "--install-main" README.md; then
    fail "Documentation must not advertise removed installer flags"
fi
pass "Install documentation matches canonical /Applications/PathChanger.app target"

if grep -nE '⌘⇧S|⌘⌥↑|⌘⌥↓' README.md PathChanger/UI/SettingsView.swift; then
    fail "Documentation and Settings must not advertise unsupported shortcut commands"
fi
pass "Shortcut documentation matches implemented commands"

if grep -nE '\([0-9]+/[0-9]+ tests passing\)|\([0-9]+ tests\)' README.md CONTRIBUTING.md; then
    fail "Documentation must not hard-code XCTest counts"
fi
pass "Documentation avoids hard-coded XCTest counts"

if [ ! -d Resources/sample_routes ] && grep -n "Resources/sample_routes/" README.md; then
    fail "README must not claim bundled sample GPX routes unless assets exist"
fi
pass "README sample route claims match bundled assets"

if grep -nE '/tmp/pathchanger_tunnel\.log|tunneld\.log' README.md DEPLOYMENT/TUNNEL_MODES.md; then
    fail "Tunnel log documentation must match ~/Library/Logs/PathChanger/tunnel.log"
fi
grep -q "~/Library/Logs/PathChanger/tunnel.log" README.md || \
    fail "README must document ~/Library/Logs/PathChanger/tunnel.log"
grep -q "~/Library/Logs/PathChanger/tunnel.log" DEPLOYMENT/TUNNEL_MODES.md || \
    fail "Tunnel mode docs must document ~/Library/Logs/PathChanger/tunnel.log"
pass "Tunnel log documentation matches runtime path"

if grep -nE 'xcrun notarytool|xcrun stapler|Notarize:|Staple:' build-app-bundle.sh; then
    fail "Build scripts must not advertise notarization/stapling for GitHub-direct distribution"
fi
pass "Build scripts avoid notarization/stapling guidance for GitHub-direct distribution"

if grep -nE '03_SECURITY_VERIFICATION_CHECKLIST\.md|04_PERFORMANCE_BASELINE\.md' DEPLOYMENT/TUNNEL_MODES.md; then
    fail "Deployment docs must not link removed legacy release documents"
fi
pass "Deployment docs do not link removed legacy release documents"

grep -q 'APP_BUNDLE_BUILD_ROOT="${APP_BUNDLE_BUILD_ROOT:-${TMPDIR:-/tmp}/pathchanger-app-build}"' build-app-bundle.sh || \
    fail "App bundle script must default outside the workspace to avoid file-provider metadata contamination"
grep -q 'DIST_BUILD_ROOT="${APP_BUNDLE_DIST_ROOT:-$(pwd)/dist}"' build.sh || \
    fail "build.sh must default dist output inside the repository for durable local artifacts"
if grep -q 'ln -s "\$DIST_BUILD_ROOT/PathChanger.app" dist/PathChanger.app' build.sh; then
    fail "build.sh must not leave dist/PathChanger.app as a cache-backed symlink"
fi
pass "Build scripts produce deterministic app bundle output and durable dist artifacts"

if grep -n "|| true" .github/workflows/ci.yml .github/workflows/release.yml; then
    fail "CI/release workflows must not contain tolerated failures"
fi
pass "CI/release workflows do not tolerate failed commands"

echo "Release configuration validation passed."
