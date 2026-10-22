#!/bin/bash
# Builds "build/Shift Happens.app" (and a .zip next to it) from the Swift package.
# Needs Xcode or the Command Line Tools (xcode-select --install).
#
# By default the app is signed ad hoc. macOS ties the Input Monitoring and Accessibility
# permissions to the signature, so after every ad-hoc rebuild they must be granted again.
# To keep them, sign with your own certificate: SIGN_IDENTITY="Apple Development: you@example.com" ./scripts/build-app.sh
set -euo pipefail

cd "$(dirname "$0")/.."
# The executable keeps the package name; only the bundle carries the display name.
EXECUTABLE="KeyBindingApp"
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
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

codesign --force --options runtime --sign "${SIGN_IDENTITY:--}" "$APP"

(cd build && rm -f "$APP_NAME.zip" && ditto -c -k --keepParent "$APP_NAME.app" "$APP_NAME.zip")
echo "Done: $APP"
