#!/bin/bash
set -e

# Usage: ./build.sh [developer-id]
# Example: ./build.sh "Developer ID Application: John Doe (XXXXXXXXXX)"
# Without argument: ad-hoc sign (won't register as service system-wide)

DEVELOPER_ID="${1:-}"
APP_NAME="md2pdf Helper"
BUNDLE_ID="com.dzarlax.md2pdf-helper"
BUILD_DIR="$(pwd)/.build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

echo "==> Compiling Swift sources..."
mkdir -p "$BUILD_DIR"

swiftc \
    Sources/md2pdf-helper/main.swift \
    Sources/md2pdf-helper/AppDelegate.swift \
    Sources/md2pdf-helper/ServiceHandler.swift \
    -o "$BUILD_DIR/md2pdf-helper" \
    -target arm64-apple-macos13.0 \
    -framework AppKit \
    -framework UserNotifications

echo "==> Assembling .app bundle..."
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BUILD_DIR/md2pdf-helper" "$APP_BUNDLE/Contents/MacOS/md2pdf-helper"
cp Info.plist "$APP_BUNDLE/Contents/Info.plist"

echo "==> Signing..."
if [[ -n "$DEVELOPER_ID" ]]; then
    # Sign inner binary first, then the bundle (no --deep, which is deprecated)
    codesign --force --options runtime --timestamp \
        --entitlements entitlements.plist \
        --sign "$DEVELOPER_ID" \
        "$APP_BUNDLE/Contents/MacOS/md2pdf-helper"
    codesign --force --options runtime --timestamp \
        --entitlements entitlements.plist \
        --sign "$DEVELOPER_ID" \
        "$APP_BUNDLE"
    echo "    Signed with: $DEVELOPER_ID"
else
    codesign --force --sign - "$APP_BUNDLE/Contents/MacOS/md2pdf-helper"
    codesign --force --sign - "$APP_BUNDLE"
    echo "    Ad-hoc signed (no Developer ID)"
fi

echo "==> Installing to /Applications..."
rm -rf "/Applications/$APP_NAME.app"
cp -R "$APP_BUNDLE" "/Applications/$APP_NAME.app"
xattr -dr com.apple.quarantine "/Applications/$APP_NAME.app" 2>/dev/null || true

echo "==> Registering service..."
open "/Applications/$APP_NAME.app"
sleep 2
/System/Library/CoreServices/pbs -update

echo ""
echo "Done! Right-click any .md file → Quick Actions → Convert to PDF"
echo "If it doesn't appear immediately, log out and back in once."
