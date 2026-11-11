#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="LangHUD"
BUILD_DIR="build"
APP="$BUILD_DIR/$APP_NAME.app"
MIN_MACOS="13.0"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "==> compiling arm64"
swiftc -O -swift-version 5 \
  -target "arm64-apple-macos$MIN_MACOS" \
  Sources/*.swift \
  -o "$APP/Contents/MacOS/$APP_NAME"

cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

SIGN_IDENTITY="LangHUD Signing"
if [ "${ADHOC_SIGN:-0}" = "1" ]; then
  echo "==> signing (ad-hoc, for distribution)"
  codesign --force --sign - "$APP" >/dev/null
elif security find-identity -v -p codesigning 2>/dev/null | grep -q "$SIGN_IDENTITY"; then
  echo "==> signing ($SIGN_IDENTITY)"
  codesign --force --sign "$SIGN_IDENTITY" "$APP" >/dev/null
else
  echo "==> signing (ad-hoc)"
  codesign --force --sign - "$APP" >/dev/null
fi

echo "==> built: $APP"
lipo -info "$APP/Contents/MacOS/$APP_NAME"
