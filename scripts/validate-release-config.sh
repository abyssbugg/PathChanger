#!/bin/zsh
#
# Release configuration validator (fail-closed).
#
# Asserts that the shipping bundle identity is coherent before a release drill runs:
#
#   1. Resources/Info.plist exists.
#   2. CFBundleShortVersionString is MAJOR.MINOR.PATCH.
#   3. SUFeedURL points at this repository's releases on GitHub
#      (https scheme, host github.com, repo path abyssbugg/PathChanger).
#   4. SUPublicEDKey is a non-empty base64 Ed25519 public key. Length check only:
#      a 32-byte Ed25519 key is exactly 44 base64 characters including the trailing
#      '=' pad. No decoding or signature verification happens here — Sparkle checks
#      signatures at update time, and this script must not fake that assurance.
#   5. Resources/PathChanger.entitlements parses (plutil -lint).
#
# Invoked by .github/workflows/release-validation.yml ("Validate Release
# Configuration"), which chmods +x before running it. Every check prints one PASS
# line; the first failure prints a FAIL line to stderr and exits non-zero.

set -euo pipefail

# Resolve the repository root from this script's own location.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PLIST="$PROJECT_ROOT/Resources/Info.plist"
ENTITLEMENTS="$PROJECT_ROOT/Resources/PathChanger.entitlements"

pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

# zsh treats a quoted pattern in =~ literally, so every regex lives in a variable.
SEMVER_REGEX='^[0-9]+\.[0-9]+\.[0-9]+$'
BASE64_ED25519_REGEX='^[A-Za-z0-9+/]{43}=$'

# 1. Info.plist exists.
if [[ -f "$PLIST" ]]; then
    pass "Resources/Info.plist exists ($PLIST)"
else
    fail "Resources/Info.plist does not exist ($PLIST)"
fi

# 2. CFBundleShortVersionString is MAJOR.MINOR.PATCH.
if ! bundle_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST" 2>/dev/null)"; then
    fail "Resources/Info.plist has no printable CFBundleShortVersionString"
fi
if [[ "$bundle_version" =~ $SEMVER_REGEX ]]; then
    pass "CFBundleShortVersionString matches MAJOR.MINOR.PATCH ($bundle_version)"
else
    fail "CFBundleShortVersionString is not MAJOR.MINOR.PATCH: '$bundle_version'"
fi

# 3. SUFeedURL points at github.com/abyssbugg/PathChanger. The character after the
#    repo path must be '/' or end-of-string so a sibling repo cannot prefix-match.
if ! su_feed_url="$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$PLIST" 2>/dev/null)"; then
    fail "Resources/Info.plist has no printable SUFeedURL"
fi
if [[ "$su_feed_url" == "https://github.com/abyssbugg/PathChanger" ]] \
   || [[ "$su_feed_url" == "https://github.com/abyssbugg/PathChanger/"* ]]; then
    pass "SUFeedURL points at github.com/abyssbugg/PathChanger ($su_feed_url)"
else
    fail "SUFeedURL does not point at https://github.com/abyssbugg/PathChanger: '$su_feed_url'"
fi

# 4. SUPublicEDKey is a non-empty base64 Ed25519 public key (44 characters).
if ! su_public_ed_key="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$PLIST" 2>/dev/null)"; then
    fail "Resources/Info.plist has no printable SUPublicEDKey"
fi
if [[ ${#su_public_ed_key} -eq 44 ]] && [[ "$su_public_ed_key" =~ $BASE64_ED25519_REGEX ]]; then
    pass "SUPublicEDKey is non-empty base64 with the Ed25519 public-key length (44 characters)"
else
    fail "SUPublicEDKey is not a 44-character base64 string: '${su_public_ed_key:-<empty>}'"
fi

# 5. Entitlements parse cleanly.
if /usr/bin/plutil -lint "$ENTITLEMENTS" >/dev/null 2>&1; then
    pass "Resources/PathChanger.entitlements parses (plutil -lint OK)"
else
    fail "Resources/PathChanger.entitlements does not parse (plutil -lint failed): $ENTITLEMENTS"
fi

printf 'Release configuration validation passed: 5/5 checks\n'
