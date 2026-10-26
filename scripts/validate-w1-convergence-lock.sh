#!/bin/zsh
#
# W1 convergence lock (fail-closed).
#
# Static assertions that the SwiftPM dependency contract has not drifted between the
# SwiftPM build path and the XcodeGen wrapper build path:
#
#   1. Package.swift pins Sparkle with exact: and the pinned version is read back out
#      of Package.swift. A `from:` range once let the two lockfiles drift apart
#      (2.8.1 vs 2.9.5), so the framework you shipped depended on which build path
#      you used — see the comment on the Sparkle dependency in Package.swift.
#   2. The root Package.resolved references that same version.
#   3. PathChanger.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
#      references that same version.
#   4. scripts/validate-xcode-wrapper.py exits 0 (run with python3).
#
# Invoked by .github/workflows/release-validation.yml ("Validate Release
# Configuration"), which chmods +x before running it. Every check prints one PASS
# line; the first failure prints a FAIL line to stderr and exits non-zero.

set -euo pipefail

# Resolve the repository root from this script's own location.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PACKAGE_SWIFT="$PROJECT_ROOT/Package.swift"
ROOT_RESOLVED="$PROJECT_ROOT/Package.resolved"
WRAPPER_RESOLVED="$PROJECT_ROOT/PathChanger.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
WRAPPER_VALIDATOR="$PROJECT_ROOT/scripts/validate-xcode-wrapper.py"

pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

[[ -f "$PACKAGE_SWIFT" ]] || fail "Package.swift not found ($PACKAGE_SWIFT)"

# 1. Package.swift pins Sparkle with exact:. sed prints the pinned version only when
#    the Sparkle dependency line carries `exact: "MAJOR.MINOR.PATCH"`; an empty
#    result means the exact pin is gone or malformed, which fails below.
sparkle_pin="$(sed -nE 's/.*https:\/\/github\.com\/sparkle-project\/Sparkle.*exact: *"([0-9]+\.[0-9]+\.[0-9]+)".*/\1/p' "$PACKAGE_SWIFT" | head -n 1)"
if [[ -n "$sparkle_pin" ]]; then
    pass "Package.swift pins Sparkle with exact: ($sparkle_pin)"
else
    fail "Package.swift does not pin Sparkle with exact: \"MAJOR.MINOR.PATCH\" on its dependency line ($PACKAGE_SWIFT)"
fi

# 2./3. Both lockfiles must reference the exact same Sparkle version. The quoted
#       form anchors the match so 2.8.1 cannot substring-match 2.8.10.
sparkle_pin_regex="${sparkle_pin//./\\.}"
VERSION_PATTERN="\"version\"[[:space:]]*:[[:space:]]*\"$sparkle_pin_regex\""

if [[ -f "$ROOT_RESOLVED" ]] && grep -qE "$VERSION_PATTERN" "$ROOT_RESOLVED"; then
    pass "Package.resolved references Sparkle $sparkle_pin ($ROOT_RESOLVED)"
else
    fail "root Package.resolved does not reference Sparkle $sparkle_pin ($ROOT_RESOLVED)"
fi

if [[ -f "$WRAPPER_RESOLVED" ]] && grep -qE "$VERSION_PATTERN" "$WRAPPER_RESOLVED"; then
    pass "Xcode wrapper Package.resolved references Sparkle $sparkle_pin ($WRAPPER_RESOLVED)"
else
    fail "Xcode wrapper Package.resolved does not reference Sparkle $sparkle_pin ($WRAPPER_RESOLVED)"
fi

# 4. Generated-project parity validator still passes.
if python3 "$WRAPPER_VALIDATOR"; then
    pass "scripts/validate-xcode-wrapper.py exited 0"
else
    fail "scripts/validate-xcode-wrapper.py exited non-zero"
fi

printf 'W1 convergence-lock validation passed: 4/4 checks\n'
