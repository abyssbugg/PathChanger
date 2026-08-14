#!/bin/bash
# Script to build PathChanger.app bundle from Swift Package
# Supports both ad-hoc signing (development) and Developer ID signing (production)

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Configuration
APP_NAME="PathChanger"
APP_BUNDLE_NAME="$APP_NAME.app"
APP_DIR="build/$APP_BUNDLE_NAME"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"
ENTITLEMENTS_FILE="Resources/PathChanger.entitlements"
BUILD_CONFIGURATION="${BUILD_CONFIGURATION:-release}"

# Check for signing identity argument
SIGNING_IDENTITY="${1:--}"  # Default to ad-hoc if not specified

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  PathChanger macOS App Bundle Builder  ${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

# Display signing mode
if [ "$SIGNING_IDENTITY" = "-" ]; then
    echo -e "${YELLOW}⚠ Building with AD-HOC signing (development only)${NC}"
    echo -e "${YELLOW}  For production, run: ./build-app-bundle.sh \"Developer ID Application: Your Name\"${NC}"
    echo ""
else
    echo -e "${GREEN}✓ Building with Developer ID: $SIGNING_IDENTITY${NC}"
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
install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACOS_DIR/$APP_NAME" 2>/dev/null || true
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
    echo -e "${YELLOW}⚠ Entitlements file not found at $ENTITLEMENTS_FILE${NC}"
fi

# Step 5.5: Copy app icon
echo -e "${BLUE}Step 5.5: Copying app icon...${NC}"
if [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
    echo -e "${GREEN}✓ App icon copied${NC}"
else
    echo -e "${YELLOW}⚠ AppIcon.icns not found in Resources${NC}"
fi

# Step 5.6: Copy persistent location bridge (joystick / multi-spot updates)
echo -e "${BLUE}Step 5.6: Copying location bridge script...${NC}"
if [ -f "scripts/location_bridge.py" ]; then
    cp "scripts/location_bridge.py" "$RESOURCES_DIR/location_bridge.py"
    echo -e "${GREEN}✓ location_bridge.py copied${NC}"
else
    echo -e "${YELLOW}⚠ scripts/location_bridge.py not found${NC}"
fi

# Step 6: Create PkgInfo
echo -e "${BLUE}Step 6: Creating PkgInfo...${NC}"
echo -n "APPL????" > "$CONTENTS_DIR/PkgInfo"
echo -e "${GREEN}✓ PkgInfo created${NC}"

# Step 7: Clean extended attributes and resource forks
echo -e "${BLUE}Step 7: Cleaning extended attributes and resource forks...${NC}"
# Remove all extended attributes
xattr -cr "$APP_DIR"
# Remove any .DS_Store files
find "$APP_DIR" -name ".DS_Store" -delete 2>/dev/null || true
# Remove any ._* resource fork files
find "$APP_DIR" -name "._*" -delete 2>/dev/null || true
echo -e "${GREEN}✓ Extended attributes and resource forks cleaned${NC}"

# Step 8: Code sign with entitlements
echo -e "${BLUE}Step 8: Code signing...${NC}"

# Sign frameworks from inside out - Sparkle contains nested code
if [ -d "$FRAMEWORKS_DIR/Sparkle.framework" ]; then
    echo -e "${BLUE}  Signing Sparkle framework components...${NC}"
    if [ "$SIGNING_IDENTITY" = "-" ]; then
        # Local ad-hoc builds must not use hardened runtime library validation.
        # Sign the full framework tree ad-hoc so it can be loaded from the app bundle.
        codesign --force --deep --sign - "$FRAMEWORKS_DIR/Sparkle.framework" 2>&1 | grep -v "replacing" || true
    else
        # Sign the Autoupdate executable
        if [ -f "$FRAMEWORKS_DIR/Sparkle.framework/Versions/B/Autoupdate" ]; then
            codesign --force --sign "$SIGNING_IDENTITY" "$FRAMEWORKS_DIR/Sparkle.framework/Versions/B/Autoupdate" 2>&1 | grep -v "replacing" || true
        fi
        # Sign Updater.app if it exists
        if [ -d "$FRAMEWORKS_DIR/Sparkle.framework/Versions/B/Updater.app" ]; then
            codesign --force --deep --sign "$SIGNING_IDENTITY" "$FRAMEWORKS_DIR/Sparkle.framework/Versions/B/Updater.app" 2>&1 | grep -v "replacing" || true
        fi
        # Sign the framework itself
        codesign --force --sign "$SIGNING_IDENTITY" "$FRAMEWORKS_DIR/Sparkle.framework" 2>&1 | grep -v "replacing" || true
    fi
fi

if [ -f "$ENTITLEMENTS_FILE" ]; then
    if [ "$SIGNING_IDENTITY" = "-" ]; then
        # Ad-hoc signing with entitlements
        codesign --force --sign - \
            --entitlements "$ENTITLEMENTS_FILE" \
            "$APP_DIR" 2>&1 | grep -v "replacing existing signature" || true
        echo -e "${GREEN}✓ Code signed (ad-hoc with entitlements)${NC}"
    else
        # Developer ID signing with entitlements and hardened runtime
        codesign --force --deep --sign "$SIGNING_IDENTITY" \
            --entitlements "$ENTITLEMENTS_FILE" \
            --options runtime \
            --timestamp \
            "$APP_DIR" 2>&1 | grep -v "replacing existing signature" || true
        echo -e "${GREEN}✓ Code signed with Developer ID and hardened runtime${NC}"
    fi
else
    codesign --force --deep --sign "$SIGNING_IDENTITY" "$APP_DIR" 2>&1 | grep -v "replacing existing signature" || true
    echo -e "${GREEN}✓ Code signed (without entitlements)${NC}"
fi

# Step 9: Verify signature
echo -e "${BLUE}Step 9: Verifying signature...${NC}"
codesign --verify --verbose "$APP_DIR" && echo -e "${GREEN}✓ Signature verified${NC}" || echo -e "${RED}✗ Signature verification failed${NC}"

# Step 10: Check entitlements
echo -e "${BLUE}Step 10: Checking entitlements...${NC}"
codesign -d --entitlements - "$APP_DIR" 2>/dev/null | head -20 || true
echo -e "${GREEN}✓ Entitlements check complete${NC}"

# Step 11: Summary
echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}✓ App bundle created successfully!${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo -e "Location: ${BLUE}$(pwd)/$APP_DIR${NC}"
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

# Step 12: Install as the only launchable PathChanger.app
echo -e "${BLUE}Step 12: Installing the single PathChanger.app...${NC}"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
rm -rf /Applications/PathChanger.app
cp -R "$APP_DIR" /Applications/PathChanger.app
# Staging copy in build/ is removed so Spotlight/Dock only see one app.
rm -rf "$APP_DIR"
# Sweep leftover FlowDeck / tmp products so rebuilds cannot register extras.
find /Users/datamatics/Library/Developer/FlowDeck/DerivedData /private/tmp -name 'PathChanger.app' -prune -exec rm -rf {} + 2>/dev/null || true
if [ -x "$LSREGISTER" ]; then
    "$LSREGISTER" -f /Applications/PathChanger.app >/dev/null 2>&1 || true
fi
echo -e "${GREEN}✓ Installed /Applications/PathChanger.app (only launchable copy)${NC}"
echo ""
echo -e "To run:     ${BLUE}open /Applications/PathChanger.app${NC}"
echo ""
