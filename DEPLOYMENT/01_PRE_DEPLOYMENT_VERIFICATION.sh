#!/bin/zsh
# PathChanger Pre-Deployment Verification Script
# Purpose: Automated verification of all deployment requirements
# Usage: ./01_PRE_DEPLOYMENT_VERIFICATION.sh

set -e
set -u
set -o pipefail

REQUIRE_PRODUCTION_SIGNING="${REQUIRE_PRODUCTION_SIGNING:-0}"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo "${BLUE}PathChanger Pre-Deployment Verification${NC}"
echo "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo ""

FAILED_CHECKS=0
PASSED_CHECKS=0

# ============================================================================
# 1. ENVIRONMENT CHECKS
# ============================================================================
echo "${BLUE}1. Environment Verification${NC}"
echo "───────────────────────────────────────────────────────"

# Check Xcode installation
if ! xcode-select -p &>/dev/null; then
    echo "${RED}✗ FAIL${NC}: Xcode not installed or not selected"
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
else
    XCODE_PATH=$(xcode-select -p)
    echo "${GREEN}✓ PASS${NC}: Xcode installed at ${XCODE_PATH}"
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
fi

# Check Swift version (should be 5.7+)
if ! command -v swift &>/dev/null; then
    echo "${RED}✗ FAIL${NC}: Swift not found"
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
else
    SWIFT_VERSION=$(swift --version | awk '{print $4}')
    echo "${GREEN}✓ PASS${NC}: Swift ${SWIFT_VERSION} installed"
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
fi

# Check Git availability
if ! command -v git &>/dev/null; then
    echo "${RED}✗ FAIL${NC}: Git not found"
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
else
    echo "${GREEN}✓ PASS${NC}: Git installed"
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
fi

echo ""

# ============================================================================
# 2. CODEBASE HEALTH CHECKS
# ============================================================================
echo "${BLUE}2. Codebase Health Verification${NC}"
echo "───────────────────────────────────────────────────────"

PROJECT_ROOT="$(cd "$(dirname "${0:A}")/.." && pwd)"
cd "$PROJECT_ROOT"

# Validate release configuration invariants before running heavier checks.
if scripts/validate-release-config.sh; then
    echo "${GREEN}✓ PASS${NC}: Release configuration gates valid"
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
else
    echo "${RED}✗ FAIL${NC}: Release configuration gates failed"
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
fi

# Check build success
if swift build &>/dev/null 2>&1; then
    echo "${GREEN}✓ PASS${NC}: Debug build successful"
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
else
    echo "${RED}✗ FAIL${NC}: Debug build failed"
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
fi

# Check release build
if swift build -c release &>/dev/null 2>&1; then
    echo "${GREEN}✓ PASS${NC}: Release build successful"
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
else
    echo "${RED}✗ FAIL${NC}: Release build failed"
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
fi

# Check for compilation warnings/errors
if BUILD_OUTPUT=$(swift build 2>&1); then
    BUILD_WARNINGS=$(printf "%s\n" "$BUILD_OUTPUT" | awk 'tolower($0) ~ /warning|error/')
else
    BUILD_WARNINGS="$BUILD_OUTPUT"
fi
if [ -z "$BUILD_WARNINGS" ]; then
    echo "${GREEN}✓ PASS${NC}: No compilation warnings or errors"
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
else
    echo "${YELLOW}⚠ WARNING${NC}: Build produced output (review manually)"
fi

echo ""

# ============================================================================
# 3. FILE STRUCTURE VERIFICATION
# ============================================================================
echo "${BLUE}3. File Structure Verification${NC}"
echo "───────────────────────────────────────────────────────"

# Check essential files
REQUIRED_FILES=(
    "Package.swift"
    "Resources/Info.plist"
    "PathChanger/PathChangerApp.swift"
    "Resources/PathChanger.entitlements"
    ".github/workflows/ci.yml"
    ".github/workflows/release.yml"
    "build-app-bundle.sh"
    "scripts/validate-release-config.sh"
    "scripts/location_bridge.py"
    "scripts/pair_wifi.py"
    "Tests/PathChangerTests/PerformanceTests.swift"
)

for file in "${REQUIRED_FILES[@]}"; do
    if [ -f "$PROJECT_ROOT/$file" ]; then
        echo "${GREEN}✓ PASS${NC}: $file exists"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
    else
        echo "${RED}✗ FAIL${NC}: $file missing"
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
    fi
done

echo ""

# ============================================================================
# 4. ENTITLEMENTS VERIFICATION
# ============================================================================
echo "${BLUE}4. Entitlements Verification${NC}"
echo "───────────────────────────────────────────────────────"

ENTITLEMENTS_FILE="$PROJECT_ROOT/Resources/PathChanger.entitlements"

# Check for problematic entitlements
if grep -q "get-task-allow" "$ENTITLEMENTS_FILE" 2>/dev/null; then
    echo "${RED}✗ FAIL${NC}: Found get-task-allow entitlement (must be removed for distribution)"
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
else
    echo "${GREEN}✓ PASS${NC}: get-task-allow entitlement not found (correct)"
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
fi

# Validate entitlements plist structure. Hardened runtime itself is enforced at signing time,
# not by a plist entitlement, so production verification delegates that gate to
# build-app-bundle.sh and scripts/validate-release-config.sh.
if plutil -lint "$ENTITLEMENTS_FILE" &>/dev/null; then
    echo "${GREEN}✓ PASS${NC}: Entitlements plist is valid"
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
else
    echo "${RED}✗ FAIL${NC}: Entitlements plist is invalid"
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
fi

echo ""

# ============================================================================
# 5. GIT REPOSITORY VERIFICATION
# ============================================================================
echo "${BLUE}5. Git Repository Verification${NC}"
echo "───────────────────────────────────────────────────────"

# Check if in Git repository
if git rev-parse --git-dir > /dev/null 2>&1; then
    echo "${GREEN}✓ PASS${NC}: Inside Git repository"
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
    
    # Check for uncommitted changes
    if [ -z "$(git status --porcelain)" ]; then
        echo "${GREEN}✓ PASS${NC}: All changes committed"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
    else
        if [ "$REQUIRE_PRODUCTION_SIGNING" = "1" ]; then
            echo "${RED}✗ FAIL${NC}: Uncommitted changes detected during production verification"
            FAILED_CHECKS=$((FAILED_CHECKS + 1))
        else
            echo "${YELLOW}⚠ WARNING${NC}: Uncommitted changes detected:"
            git status --porcelain | head -10
        fi
    fi
    
    # Get last commit info
    LAST_COMMIT=$(git log -1 --oneline)
    echo "${GREEN}✓ PASS${NC}: Last commit: $LAST_COMMIT"
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
else
    echo "${RED}✗ FAIL${NC}: Not in Git repository"
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
fi

echo ""

# ============================================================================
# 6. SECURITY CHECKS
# ============================================================================
echo "${BLUE}6. Security Verification${NC}"
echo "───────────────────────────────────────────────────────"

# Check for debug symbols in release build
if swift build -c release 2>&1 | grep -q "DWARF"; then
    echo "${YELLOW}⚠ WARNING${NC}: Debug symbols in release build (expected)"
fi

# Check Info.plist structure
INFO_PLIST="$PROJECT_ROOT/Resources/Info.plist"
if [ -f "$INFO_PLIST" ]; then
    if plutil -lint "$INFO_PLIST" &>/dev/null; then
        echo "${GREEN}✓ PASS${NC}: Info.plist is valid"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
    else
        echo "${RED}✗ FAIL${NC}: Info.plist is invalid"
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
    fi
fi

echo ""

# ============================================================================
# 7. DEPENDENCY VERIFICATION
# ============================================================================
echo "${BLUE}7. Dependency Verification${NC}"
echo "───────────────────────────────────────────────────────"

# Check Package.swift syntax
if swift package describe &>/dev/null; then
    echo "${GREEN}✓ PASS${NC}: Package.swift syntax valid"
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
else
    echo "${RED}✗ FAIL${NC}: Package.swift syntax error"
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
fi

echo "${BLUE}Dependencies:${NC}"
PACKAGE_DESCRIPTION=$(swift package describe 2>/dev/null)
if ! printf "%s\n" "$PACKAGE_DESCRIPTION" | grep -A 100 "dependencies:"; then
    echo "No external dependencies"
fi

echo ""

# ============================================================================
# 8. CERTIFICATE READINESS
# ============================================================================
echo "${BLUE}8. Code Signing Certificate Readiness${NC}"
echo "───────────────────────────────────────────────────────"

# List available Developer ID certificates
if DEVELOPER_CERTS=$(security find-identity -v -p codesigning | grep "Developer ID Application"); then
    :
else
    DEVELOPER_CERTS=""
fi

if [ -z "$DEVELOPER_CERTS" ]; then
    if [ "$REQUIRE_PRODUCTION_SIGNING" = "1" ]; then
        echo "${RED}✗ FAIL${NC}: No Developer ID certificates found for production verification"
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
    else
        echo "${YELLOW}⚠ WARNING${NC}: No Developer ID certificates found"
        echo "  Action: Import your Developer ID certificate via Keychain"
        echo "  Location: https://developer.apple.com/account/resources/certificates"
    fi
else
    echo "${GREEN}✓ PASS${NC}: Developer ID certificates found:"
    echo "$DEVELOPER_CERTS" | head -3
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
fi

echo ""

# ============================================================================
# 9. PERFORMANCE BASELINE
# ============================================================================
echo "${BLUE}9. Performance Baseline Check${NC}"
echo "───────────────────────────────────────────────────────"

# Check if performance test file exists
if [ -f "$PROJECT_ROOT/Tests/PathChangerTests/PerformanceTests.swift" ]; then
    echo "${GREEN}✓ PASS${NC}: Performance test suite exists"
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
    
    # Show test count
    TEST_COUNT=$(awk '/func test/ { count++ } END { print count + 0 }' "$PROJECT_ROOT/Tests/PathChangerTests/PerformanceTests.swift")
    echo "  Tests defined: $TEST_COUNT"
else
    echo "${RED}✗ FAIL${NC}: Performance test suite missing"
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
fi

echo ""

# ============================================================================
# SUMMARY
# ============================================================================
echo "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo "${BLUE}Verification Summary${NC}"
echo "${BLUE}═══════════════════════════════════════════════════════${NC}"

TOTAL_CHECKS=$((PASSED_CHECKS + FAILED_CHECKS))
PASS_PERCENTAGE=$((PASSED_CHECKS * 100 / TOTAL_CHECKS))

echo "Checks Passed:  ${GREEN}${PASSED_CHECKS}${NC}/${TOTAL_CHECKS}"
echo "Checks Failed:  ${RED}${FAILED_CHECKS}${NC}/${TOTAL_CHECKS}"
echo "Success Rate:   ${PASS_PERCENTAGE}%"
echo ""

if [ $FAILED_CHECKS -eq 0 ]; then
    echo "${GREEN}✓ All critical checks passed - Ready for deployment!${NC}"
    exit 0
else
    echo "${RED}✗ Some checks failed - Please review above and fix issues${NC}"
    exit 1
fi
