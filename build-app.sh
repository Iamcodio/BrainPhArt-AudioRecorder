#!/bin/bash

# Build script for BrainPhArt macOS app
# Creates a signed .app bundle in /Applications

set -e

APP_NAME="BrainPhArt"
BUNDLE_ID="com.brainphart.recorder"
BUILD_DIR=".build/release"
APP_DIR="/Applications/${APP_NAME}.app"

echo "🔨 Building ${APP_NAME} for release..."
swift build -c release

echo "📦 Creating app bundle..."

# Remove old app if exists
rm -rf "${APP_DIR}"

# Create app bundle structure
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

# Copy executable
cp "${BUILD_DIR}/${APP_NAME}" "${APP_DIR}/Contents/MacOS/"

# Copy Info.plist
cp "Sources/BrainPhArt/Info.plist" "${APP_DIR}/Contents/"

# Create PkgInfo
echo -n "APPL????" > "${APP_DIR}/Contents/PkgInfo"

# Create simple icon (placeholder)
# You can replace this with a proper .icns file later

echo "🔐 Attempting to sign app..."

# Try to sign with ad-hoc signature (no developer ID required)
if codesign --force --deep --sign - "${APP_DIR}" 2>/dev/null; then
    echo "✅ App signed with ad-hoc signature"
else
    echo "⚠️  Could not sign app (requires Xcode command line tools)"
fi

# Set permissions
chmod +x "${APP_DIR}/Contents/MacOS/${APP_NAME}"

echo ""
echo "✅ ${APP_NAME}.app created at: ${APP_DIR}"
echo ""
echo "📝 IMPORTANT: Grant permissions in System Settings:"
echo "   1. Privacy & Security → Microphone → Enable ${APP_NAME}"
echo "   2. Privacy & Security → Accessibility → Enable ${APP_NAME}"
echo ""
echo "🚀 To run: open '${APP_DIR}'"
