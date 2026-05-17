#!/bin/bash
# Script to build PathChanger.app bundle from Swift Package
# Supports both ad-hoc signing (development) and Developer ID signing (production)

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

fail() {
    echo -e "${RED}✗ $1${NC}" >&2
    exit 1
}

warn_or_fail_for_production() {
    local message="$1"
    if [ "$REQUIRE_PRODUCTION_SIGNING" = "1" ]; then
        fail "$message"
    fi
    echo -e "${YELLOW}⚠ $message${NC}"
}

REMOVABLE_FORBIDDEN_XATTR_PATTERN='com\.apple\.(FinderInfo|ResourceFork|fileprovider\.fpfs#P)'
PROVENANCE_XATTR_PATTERN='com\.apple\.provenance'

sanitize_bundle_metadata() {
    local path="$1"
    [ -d "$path" ] || fail "Cannot sanitize missing bundle path: $path"

    dot_clean -m "$path"
    xattr -cr "$path"
    xattr -crs "$path"
    xattr -dr com.apple.FinderInfo "$path" 2>/dev/null || true
    xattr -dr com.apple.ResourceFork "$path" 2>/dev/null || true
    xattr -dr com.apple.provenance "$path" 2>/dev/null || true
    xattr -dr "com.apple.fileprovider.fpfs#P" "$path" 2>/dev/null || true
    xattr -cr "$path"
    xattr -crs "$path"
    find "$path" -name ".DS_Store" -delete 2>/dev/null || true
    find "$path" -name "._*" -delete 2>/dev/null || true
}

verify_no_forbidden_xattrs() {
    local path="$1"
    local forbidden_output
    local provenance_output
    local probe

    forbidden_output="$(xattr -lr "$path" 2>/dev/null | grep -E "$REMOVABLE_FORBIDDEN_XATTR_PATTERN" || true)"
    if [ -n "$forbidden_output" ]; then
        echo "$forbidden_output" >&2
        fail "Forbidden extended attributes remain in $path"
    fi

    provenance_output="$(xattr -lr "$path" 2>/dev/null | grep -E "$PROVENANCE_XATTR_PATTERN" || true)"
    if [ -n "$provenance_output" ]; then
        probe="$(mktemp)"
        if xattr -p com.apple.provenance "$probe" >/dev/null 2>&1; then
            rm -f "$probe"
            echo -e "${YELLOW}⚠ com.apple.provenance is still reported after sanitation; this host attaches it to newly-created files and does not allow script removal${NC}"
        else
            rm -f "$probe"
            echo "$provenance_output" >&2
            fail "com.apple.provenance remains in $path"
        fi
    fi
}

# Configuration
APP_NAME="PathChanger"
APP_BUNDLE_NAME="$APP_NAME.app"
APP_BUNDLE_BUILD_ROOT="${APP_BUNDLE_BUILD_ROOT:-${TMPDIR:-/tmp}/pathchanger-app-build}"
APP_DIR="$APP_BUNDLE_BUILD_ROOT/$APP_BUNDLE_NAME"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"
ENTITLEMENTS_FILE="Resources/PathChanger.entitlements"
BUILD_CONFIGURATION="${BUILD_CONFIGURATION:-release}"
REQUIRE_PRODUCTION_SIGNING="${REQUIRE_PRODUCTION_SIGNING:-0}"

# Check for signing identity argument
SIGNING_IDENTITY="${1:--}"  # Default to ad-hoc if not specified

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  PathChanger macOS App Bundle Builder  ${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

# Display signing mode
if [ "$SIGNING_IDENTITY" = "-" ]; then
    if [ "$REQUIRE_PRODUCTION_SIGNING" = "1" ]; then
        fail "Production bundle builds require a Developer ID signing identity"
    fi
    echo -e "${YELLOW}⚠ Building with AD-HOC signing (development only)${NC}"
    echo -e "${YELLOW}  For production, run: ./build-app-bundle.sh \"Developer ID Application: Your Name\"${NC}"
    echo ""
else
    echo -e "${GREEN}✓ Building with Developer ID: $SIGNING_IDENTITY${NC}"
    if ! security find-identity -v -p codesigning | grep -Fq "$SIGNING_IDENTITY"; then
        fail "Developer ID signing identity not available in the current keychain: $SIGNING_IDENTITY"
    fi
    echo ""
fi

# Step 1: Build the executable
echo -e "${BLUE}Step 1: Building Swift package ($BUILD_CONFIGURATION mode)...${NC}"
swift build -c "$BUILD_CONFIGURATION"
BUILD_BIN_PATH="$(swift build -c "$BUILD_CONFIGURATION" --show-bin-path)"
echo -e "${GREEN}✓ Build complete${NC}"

# Step 2: Create app bundle structure
echo -e "${BLUE}Step 2: Creating app bundle structure...${NC}"
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"
mkdir -p "$FRAMEWORKS_DIR"
echo -e "${GREEN}✓ Directory structure created${NC}"

# Step 3: Copy executable
echo -e "${BLUE}Step 3: Copying executable...${NC}"
cp "$BUILD_BIN_PATH/$APP_NAME" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"
echo -e "${GREEN}✓ Executable copied${NC}"

# Step 3.1: Add rpath for embedded frameworks
echo -e "${BLUE}Step 3.1: Adding rpath for embedded frameworks...${NC}"
if ! otool -l "$MACOS_DIR/$APP_NAME" | grep -q "@executable_path/../Frameworks"; then
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACOS_DIR/$APP_NAME"
fi
echo -e "${GREEN}✓ Rpath added${NC}"

# Step 3.5: Copy Sparkle framework
echo -e "${BLUE}Step 3.5: Copying Sparkle framework...${NC}"
# Find Sparkle.framework in the build artifacts
SPARKLE_FRAMEWORK=$(find .build -name "Sparkle.framework" -type d 2>/dev/null | head -1)
if [ -n "$SPARKLE_FRAMEWORK" ] && [ -d "$SPARKLE_FRAMEWORK" ]; then
    cp -R "$SPARKLE_FRAMEWORK" "$FRAMEWORKS_DIR/"
    echo -e "${GREEN}✓ Sparkle framework copied from $SPARKLE_FRAMEWORK${NC}"
else
    # Try the artifacts directory (common in SPM builds)
    SPARKLE_ARTIFACT=$(find .build/artifacts -name "Sparkle.framework" -type d 2>/dev/null | head -1)
    if [ -n "$SPARKLE_ARTIFACT" ] && [ -d "$SPARKLE_ARTIFACT" ]; then
        cp -R "$SPARKLE_ARTIFACT" "$FRAMEWORKS_DIR/"
        echo -e "${GREEN}✓ Sparkle framework copied from $SPARKLE_ARTIFACT${NC}"
    else
        echo -e "${YELLOW}⚠ Sparkle.framework not found in .build directory${NC}"
        echo -e "${YELLOW}  Looking for alternative locations...${NC}"
        # List what we can find
        find .build -name "*.framework" -type d 2>/dev/null | head -5 || true
        warn_or_fail_for_production "Sparkle.framework not found; production app bundle cannot be validated"
    fi
fi

# Step 4: Copy Info.plist
echo -e "${BLUE}Step 4: Copying Info.plist...${NC}"
cp "Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
echo -e "${GREEN}✓ Info.plist copied${NC}"

# Step 5: Copy entitlements to Resources (for reference)
echo -e "${BLUE}Step 5: Copying entitlements...${NC}"
if [ -f "$ENTITLEMENTS_FILE" ]; then
    cp "$ENTITLEMENTS_FILE" "$RESOURCES_DIR/PathChanger.entitlements"
    echo -e "${GREEN}✓ Entitlements copied${NC}"
else
    warn_or_fail_for_production "Entitlements file not found at $ENTITLEMENTS_FILE"
fi

# Step 5.5: Copy app icon
echo -e "${BLUE}Step 5.5: Copying app icon...${NC}"
if [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
    echo -e "${GREEN}✓ App icon copied${NC}"
else
    warn_or_fail_for_production "AppIcon.icns not found in Resources"
fi

# Step 5.6: Copy persistent location bridge script (required for Multi-Spot/Joystick performance mode)
echo -e "${BLUE}Step 5.6: Copying persistent location bridge script...${NC}"
if [ -f "scripts/location_bridge.py" ]; then
    mkdir -p "$RESOURCES_DIR/scripts"
    cp "scripts/location_bridge.py" "$RESOURCES_DIR/scripts/location_bridge.py"
    chmod +x "$RESOURCES_DIR/scripts/location_bridge.py"
    echo -e "${GREEN}✓ Bridge script copied to Resources/scripts/${NC}"
else
    warn_or_fail_for_production "scripts/location_bridge.py not found - persistent-bridge performance mode will not work"
fi

# Step 5.7: Copy WiFi pairing helper (used by Settings > WiFi mode pairing flow)
echo -e "${BLUE}Step 5.7: Copying WiFi pairing helper...${NC}"
if [ -f "scripts/pair_wifi.py" ]; then
    mkdir -p "$RESOURCES_DIR/scripts"
    cp "scripts/pair_wifi.py" "$RESOURCES_DIR/scripts/pair_wifi.py"
    chmod +x "$RESOURCES_DIR/scripts/pair_wifi.py"
    echo -e "${GREEN}✓ WiFi pairing helper copied to Resources/scripts/${NC}"
else
    warn_or_fail_for_production "scripts/pair_wifi.py not found - WiFi mode users will need to pair manually via Terminal"
fi

# Step 6: Create PkgInfo
echo -e "${BLUE}Step 6: Creating PkgInfo...${NC}"
echo -n "APPL????" > "$CONTENTS_DIR/PkgInfo"
echo -e "${GREEN}✓ PkgInfo created${NC}"

# Step 7: Clean extended attributes and resource forks
echo -e "${BLUE}Step 7: Cleaning extended attributes and resource forks...${NC}"
sanitize_bundle_metadata "$APP_DIR"
echo -e "${GREEN}✓ Extended attributes and resource forks cleaned${NC}"

# Step 8: Code sign with entitlements
echo -e "${BLUE}Step 8: Code signing...${NC}"

# Sign frameworks from inside out - Sparkle contains nested code
if [ -d "$FRAMEWORKS_DIR/Sparkle.framework" ]; then
    echo -e "${BLUE}  Signing Sparkle framework components...${NC}"
    if [ "$SIGNING_IDENTITY" = "-" ]; then
        # Local ad-hoc builds must not use hardened runtime library validation.
        # Sign the full framework tree ad-hoc so it can be loaded from the app bundle.
        codesign --force --deep --sign - "$FRAMEWORKS_DIR/Sparkle.framework"
    else
        # Sign the Autoupdate executable
        if [ -f "$FRAMEWORKS_DIR/Sparkle.framework/Versions/B/Autoupdate" ]; then
            codesign --force --sign "$SIGNING_IDENTITY" "$FRAMEWORKS_DIR/Sparkle.framework/Versions/B/Autoupdate"
        fi
        # Sign Updater.app if it exists
        if [ -d "$FRAMEWORKS_DIR/Sparkle.framework/Versions/B/Updater.app" ]; then
            codesign --force --deep --sign "$SIGNING_IDENTITY" "$FRAMEWORKS_DIR/Sparkle.framework/Versions/B/Updater.app"
        fi
        # Sign the framework itself
        codesign --force --sign "$SIGNING_IDENTITY" "$FRAMEWORKS_DIR/Sparkle.framework"
    fi
fi

# codesign can rewrite framework bundle metadata; clean again before signing the app.
sanitize_bundle_metadata "$APP_DIR"

if [ -f "$ENTITLEMENTS_FILE" ]; then
    if [ "$SIGNING_IDENTITY" = "-" ]; then
        # Ad-hoc signing with entitlements
        codesign --force --sign - \
            --entitlements "$ENTITLEMENTS_FILE" \
            "$APP_DIR"
        echo -e "${GREEN}✓ Code signed (ad-hoc with entitlements)${NC}"
    else
        # Developer ID signing with entitlements and hardened runtime
        codesign --force --deep --sign "$SIGNING_IDENTITY" \
            --entitlements "$ENTITLEMENTS_FILE" \
            --options runtime \
            --timestamp \
            "$APP_DIR"
        echo -e "${GREEN}✓ Code signed with Developer ID and hardened runtime${NC}"
    fi
else
    if [ "$REQUIRE_PRODUCTION_SIGNING" = "1" ]; then
        fail "Production app bundle signing requires $ENTITLEMENTS_FILE"
    fi
    codesign --force --deep --sign "$SIGNING_IDENTITY" "$APP_DIR"
    echo -e "${GREEN}✓ Code signed (without entitlements)${NC}"
fi

# Step 8.5: Final metadata sanitation before signature verification
echo -e "${BLUE}Step 8.5: Final metadata sanitation before verification...${NC}"
sanitize_bundle_metadata "$APP_DIR"
verify_no_forbidden_xattrs "$APP_DIR"
echo -e "${GREEN}✓ Removable release artifact metadata is clean${NC}"

# Step 9: Verify signature
echo -e "${BLUE}Step 9: Verifying signature...${NC}"
codesign --verify --deep --strict --verbose=2 "$APP_DIR"
echo -e "${GREEN}✓ Signature verified${NC}"

# Step 10: Check entitlements
echo -e "${BLUE}Step 10: Checking entitlements...${NC}"
ENTITLEMENTS_OUTPUT="$(mktemp)"
if ! codesign -d --entitlements - "$APP_DIR" > "$ENTITLEMENTS_OUTPUT" 2>/dev/null; then
    rm -f "$ENTITLEMENTS_OUTPUT"
    fail "Could not read code-signing entitlements from $APP_DIR"
fi
head -20 "$ENTITLEMENTS_OUTPUT"
rm -f "$ENTITLEMENTS_OUTPUT"
if [ "$REQUIRE_PRODUCTION_SIGNING" = "1" ]; then
    codesign -dv "$APP_DIR" 2>&1 | grep -q "runtime" || fail "Production app bundle is missing hardened runtime"
fi
echo -e "${GREEN}✓ Entitlements check complete${NC}"

# Step 11: Summary
echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}✓ App bundle created successfully!${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
if [[ "$APP_DIR" = /* ]]; then
    DISPLAY_APP_DIR="$APP_DIR"
else
    DISPLAY_APP_DIR="$(pwd)/$APP_DIR"
fi
echo -e "Location: ${BLUE}$DISPLAY_APP_DIR${NC}"
echo -e "Size:     ${BLUE}$(du -sh "$APP_DIR" | cut -f1)${NC}"
echo -e "Signing:  ${BLUE}$SIGNING_IDENTITY${NC}"
echo ""

# Production instructions
if [ "$SIGNING_IDENTITY" = "-" ]; then
    echo -e "${YELLOW}FOR PRODUCTION DISTRIBUTION:${NC}"
    echo -e "1. Get an Apple Developer ID certificate"
    echo -e "2. Run: ./build-app-bundle.sh \"Developer ID Application: Your Name (TEAM_ID)\""
    echo -e "3. Notarize: xcrun notarytool submit $APP_DIR --apple-id YOUR_EMAIL --team-id TEAM_ID"
    echo -e "4. Staple: xcrun stapler staple $APP_DIR"
    echo ""
fi

echo -e "To install: ${BLUE}cp -R $APP_DIR /Applications/${NC}"
echo -e "To run:     ${BLUE}open $APP_DIR${NC}"
echo ""
