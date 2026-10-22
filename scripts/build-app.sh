#!/bin/bash
# Builds "build/Shift Happens.app" (and a .zip next to it) from the Swift package.
# Needs Xcode or the Command Line Tools (xcode-select --install).
#
# macOS ties the Input Monitoring and Accessibility permissions to the signature. An ad-hoc signature
# changes with every build, so the permissions would have to be granted again each time. To keep them,
# sign with a lasting certificate from your keychain: set SIGN_IDENTITY, or put its name in a
# .signing-identity file next to this repository's README (it is git-ignored). Without either, the app
# is signed ad hoc.
# Example: SIGN_IDENTITY="Apple Development: you@example.com" ./scripts/build-app.sh
set -euo pipefail

cd "$(dirname "$0")/.."
EXECUTABLE="ShiftHappens"
APP_NAME="Shift Happens"
APP="build/$APP_NAME.app"

if swift build -c release --arch arm64 --arch x86_64 2>/dev/null; then
    BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
else
    echo "Universal build unavailable, building for this Mac only"
    swift build -c release
    BIN_DIR="$(swift build -c release --show-bin-path)"
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$EXECUTABLE" "$APP/Contents/MacOS/$EXECUTABLE"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# Releases pass the tag's version (VERSION=1.2.3), so the app and the release always agree.
if [ -n "${VERSION:-}" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

if [ -z "${SIGN_IDENTITY:-}" ] && [ -f .signing-identity ]; then
    SIGN_IDENTITY="$(head -n 1 .signing-identity)"
fi
echo "Signing with: ${SIGN_IDENTITY:-ad hoc (permissions reset on every build)}"
codesign --force --options runtime --sign "${SIGN_IDENTITY:--}" "$APP"

(cd build && rm -f "$APP_NAME.zip" && ditto -c -k --keepParent "$APP_NAME.app" "$APP_NAME.zip")
echo "Done: $APP"
