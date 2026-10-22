#!/bin/bash
# Builds "build/Shift Happens.app" (and a .zip next to it) from the Swift package.
# Needs Xcode or the Command Line Tools (xcode-select --install).
#
# macOS ties the Input Monitoring and Accessibility permissions to the signature. An ad-hoc signature
# changes with every build, so the permissions would have to be granted again each time. The script
# therefore signs with a lasting certificate: SIGN_IDENTITY if set, otherwise "Apple Development: you@example.com" when that
# identity is in the keychain, and ad hoc only as a last resort.
# Example: SIGN_IDENTITY="Apple Development: you@example.com" ./scripts/build-app.sh
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

DEFAULT_IDENTITY="Apple Development: you@example.com"
if [ -z "${SIGN_IDENTITY:-}" ] && security find-identity -v -p codesigning | grep -q "\"$DEFAULT_IDENTITY\""; then
    SIGN_IDENTITY="$DEFAULT_IDENTITY"
fi
echo "Signing with: ${SIGN_IDENTITY:-ad hoc (permissions reset on every build)}"
codesign --force --options runtime --sign "${SIGN_IDENTITY:--}" "$APP"

(cd build && rm -f "$APP_NAME.zip" && ditto -c -k --keepParent "$APP_NAME.app" "$APP_NAME.zip")
echo "Done: $APP"
