# PathChanger Code Signing & Notarization Procedures

## Table of Contents
1. [Development Signing](#development-signing)
2. [Distribution Signing](#distribution-signing)
3. [Notarization Process](#notarization-process)
4. [Troubleshooting](#troubleshooting)

---

## Development Signing

### Step 1: Set Up Development Signing Identity

```bash
# List available signing identities
security find-identity -v -p codesigning

# Output should show: "iPhone Developer" or "Mac Developer" certificates
```

### Step 2: Configure Xcode for Development

1. Open `PathChanger.xcodeproj` in Xcode
2. Navigate to: **Build Settings** → **Code Signing**
3. Set the following:
   - **Code Signing Identity**: Automatic (Xcode will select)
   - **Provisioning Profile**: Automatic
   - **Team**: Your Apple Developer Team ID

### Step 3: Verify Development Build

```bash
# Build for development
swift build

# Should complete without code signing errors
```

---

## Distribution Signing

### Prerequisites
- **Developer ID Application Certificate** (not Mac Development)
- Must be obtained from: https://developer.apple.com/account/resources/certificates
- Import certificate into Keychain (double-click .cer file or use Keychain Access)

### Step 1: Obtain Developer ID Certificate

1. Visit Apple Developer Account
2. Go to **Certificates, Identifiers & Profiles** → **Certificates**
3. Click **+** to create new certificate
4. Select **Developer ID Application**
5. Follow CSR upload process
6. Download and import certificate

### Step 2: Configure Distribution Signing

```bash
# Verify Developer ID certificate is installed
security find-identity -v -p codesigning | grep "Developer ID Application"

# Output example:
# A1B2C3D4E5F6G7H8I9J0 "Developer ID Application: Your Name (XXXXXXXXXX)"
```

### Step 3: Update Entitlements for Distribution

Edit `Resources/PathChanger.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" 
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Hardened Runtime (REQUIRED for notarization) -->
    <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
    <false/>
    
    <!-- Allow JIT if using Python/runtime compilation -->
    <key>com.apple.security.cs.allow-jit</key>
    <true/>
    
    <!-- Disable library validation if loading third-party libraries -->
    <key>com.apple.security.cs.disable-library-validation</key>
    <false/>
    
    <!-- DO NOT include get-task-allow (breaks notarization) -->
    <!-- <key>com.apple.security.get-task-allow</key> -->
    
    <!-- Required for device communication -->
    <key>com.apple.security.device.usb</key>
    <true/>
</dict>
</plist>
```

### Step 4: Build for Distribution

```bash
# Create archive
xcode-select --install  # If needed

# Navigate to project
cd /Users/shigeo/Desktop/PathChanger

# Build release version
swift build -c release

# Create app bundle (if using Xcode project)
xcodebuild archive \
  -scheme PathChanger \
  -configuration Release \
  -archivePath ./PathChanger.xcarchive \
  -derivedDataPath ./build \
  -signingStyle automatic \
  -destination 'platform=macOS'
```

### Step 5: Code Sign the App

```bash
# Option A: Using codesign command (manual control)
codesign --deep \
  --force \
  --verify \
  --verbose \
  --sign "Developer ID Application: Your Name (TEAM_ID)" \
  --entitlements Resources/PathChanger.entitlements \
  ./build/PathChanger.app

# Option B: Using notarytool with code-sign option
notarytool submit \
  --apple-id your-apple-id@example.com \
  --team-id XXXXXXXXXX \
  --password app-specific-password \
  ./PathChanger.app
```

### Step 6: Verify Code Signature

```bash
# Verify signature
codesign --verify --verbose ./build/PathChanger.app

# Check entitlements
codesign --display --entitlements - ./build/PathChanger.app

# Detailed signature info
spctl -a -v ./build/PathChanger.app
```

---

## Notarization Process

### Prerequisites
1. Developer ID Application certificate (already obtained above)
2. Apple ID with Developer Team membership
3. App-specific password for CI/CD (or use interactive mode)

### Step 1: Generate App-Specific Password

1. Visit: https://appleid.apple.com/account/manage
2. Go to **Security** → **App-Specific Passwords**
3. Generate new password for "PathChanger Deployment"
4. Save password securely (will use for notarization)

### Step 2: Create Notarization-Ready App

```bash
# Create DMG or ZIP for distribution
# Option A: DMG (recommended for macOS apps)
hdiutil create -volname PathChanger \
  -srcfolder ./build/PathChanger.app \
  -ov -format UDZO \
  ./PathChanger.dmg

# Option B: ZIP
ditto -c -k --keepParent \
  ./build/PathChanger.app \
  PathChanger.zip
```

### Step 3: Submit for Notarization

```bash
# Using notarytool (newer, recommended - Xcode 13.1+)
notarytool submit PathChanger.dmg \
  --apple-id your-email@example.com \
  --team-id XXXXXXXXXX \
  --password app-specific-password \
  --wait

# Output example:
# Submitting file for notarization...
# Request ID: 12345678-1234-1234-1234-123456789012
# Notarizing...
# Notarization complete! Status: Accepted
```

### Step 4: Retrieve Notarization Log

```bash
# Get submission info
notarytool info 12345678-1234-1234-1234-123456789012 \
  --apple-id your-email@example.com \
  --team-id XXXXXXXXXX \
  --password app-specific-password

# Download detailed log
notarytool log 12345678-1234-1234-1234-123456789012 \
  --apple-id your-email@example.com \
  --team-id XXXXXXXXXX \
  --password app-specific-password \
  > notarization-log.json

# Review for any issues
cat notarization-log.json
```

### Step 5: Staple Ticket to App

```bash
# After successful notarization, staple the ticket
xcrun stapler staple PathChanger.dmg

# Verify ticket is attached
xcrun stapler validate PathChanger.dmg

# Output should show: "The file PathChanger.dmg is notarized."
```

### Step 6: Final Distribution

```bash
# Create final distributable version
# The DMG now includes the notarization ticket and is ready for distribution

# Verify before distribution
codesign --verify --deep --verbose PathChanger.dmg
xcrun stapler validate PathChanger.dmg
spctl -a -v PathChanger.dmg
```

---

## Automated Notarization Script

For CI/CD environments, use this script:

```bash
#!/bin/zsh
# notarize.sh - Automated notarization script

set -e

APP_PATH="${1:?Error: App path required}"
APPLE_ID="${2:?Error: Apple ID required}"
TEAM_ID="${3:?Error: Team ID required}"
PASSWORD="${4:?Error: App-specific password required}"

# Create DMG
echo "Creating DMG..."
hdiutil create -volname PathChanger \
  -srcfolder "$APP_PATH" \
  -ov -format UDZO \
  ./PathChanger.dmg

# Submit for notarization with --wait flag (blocks until complete)
echo "Submitting for notarization..."
SUBMISSION=$(notarytool submit PathChanger.dmg \
  --apple-id "$APPLE_ID" \
  --team-id "$TEAM_ID" \
  --password "$PASSWORD" \
  --wait 2>&1)

echo "$SUBMISSION"

# Extract Request ID
REQUEST_ID=$(echo "$SUBMISSION" | grep "Request ID:" | awk '{print $NF}')

if [ -z "$REQUEST_ID" ]; then
    echo "Error: Failed to extract Request ID"
    exit 1
fi

# Check status
STATUS=$(echo "$SUBMISSION" | grep "Status:" | awk '{print $NF}')

if [ "$STATUS" = "Accepted" ]; then
    echo "✓ Notarization accepted"
    
    # Get log
    echo "Downloading log..."
    notarytool log "$REQUEST_ID" \
      --apple-id "$APPLE_ID" \
      --team-id "$TEAM_ID" \
      --password "$PASSWORD" \
      > notarization-log.json
    
    # Staple ticket
    echo "Stapling ticket..."
    xcrun stapler staple PathChanger.dmg
    
    echo "✓ Notarization complete"
    exit 0
else
    echo "✗ Notarization rejected: $STATUS"
    exit 1
fi
```

Usage:
```bash
chmod +x notarize.sh
./notarize.sh ./build/PathChanger.app user@example.com XXXXXXXXXX "app-specific-password"
```

---

## Troubleshooting

### Issue: "Invalid signing identity"
**Solution:**
```bash
# List available identities
security find-identity -v -p codesigning

# Use exact certificate name from output
```

### Issue: "Code object is not signed at all"
**Solution:**
```bash
# Re-sign the app
codesign -s - --force PathChanger.app
```

### Issue: "Notarization request denied - Invalid code signature"
**Checklist:**
- [ ] Using Developer ID Application certificate (not Developer ID Installer)
- [ ] Removed get-task-allow entitlement
- [ ] Included secure timestamp (automatic with codesign)
- [ ] All frameworks are code signed
- [ ] No unsigned binaries embedded

### Issue: "Hardened Runtime required"
**Solution:**
Ensure entitlements include:
```xml
<key>com.apple.security.cs.allow-jit</key>
<true/>
```

### Issue: "Notarization takes too long"
**Status check:**
```bash
notarytool info REQUEST_ID \
  --apple-id your-email@example.com \
  --team-id XXXXXXXXXX \
  --password password
```

---

## Security Checklist

- [ ] Using Developer ID Application certificate
- [ ] Removed all debug entitlements (get-task-allow)
- [ ] Included Hardened Runtime entitlements
- [ ] Code signed with timestamp
- [ ] All embedded frameworks code signed
- [ ] No unsigned binaries in bundle
- [ ] Notarization ticket stapled to DMG
- [ ] Tested on clean macOS system
- [ ] Verified with spctl
- [ ] Git tag created for release

---

## References

- [Apple Notarization Documentation](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [Code Signing Guide](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/)
- [Hardened Runtime Capabilities](https://developer.apple.com/documentation/security/hardened-runtime)
