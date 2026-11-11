#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="LangHUD"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
MIN_MACOS="13.0"
STAGE="build/dmg-stage"
APP="$STAGE/$APP_NAME.app"
DIST="dist"
OUTPUT="$DIST/$APP_NAME-$VERSION.dmg"

rm -rf "$STAGE"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$DIST"

echo "==> compiling arm64"
swiftc -O -swift-version 5 -target "arm64-apple-macos$MIN_MACOS" \
  Sources/*.swift -o "$STAGE/bin-arm64"

echo "==> compiling x86_64"
swiftc -O -swift-version 5 -target "x86_64-apple-macos$MIN_MACOS" \
  Sources/*.swift -o "$STAGE/bin-x86_64"

echo "==> lipo universal"
lipo -create "$STAGE/bin-arm64" "$STAGE/bin-x86_64" -output "$APP/Contents/MacOS/$APP_NAME"
rm -f "$STAGE/bin-arm64" "$STAGE/bin-x86_64"
chmod +x "$APP/Contents/MacOS/$APP_NAME"

cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# 分发包用 ad-hoc 签名：同事机器不信任本机自签证书
echo "==> signing (ad-hoc)"
codesign --force --sign - "$APP" >/dev/null

# 拖拽安装布局：App + /Applications 软链
ln -s /Applications "$STAGE/Applications"

echo "==> building dmg"
rm -f "$OUTPUT"
hdiutil create -volname "$APP_NAME $VERSION" \
  -srcfolder "$STAGE" \
  -fs HFS+ \
  -format UDZO \
  -ov \
  "$OUTPUT" >/dev/null

echo "==> verifying"
lipo -info "$APP/Contents/MacOS/$APP_NAME"
codesign -dv "$APP" 2>&1 | grep -E "Identifier|Signature" || true

rm -rf "$STAGE"

echo "==> done: $OUTPUT"
ls -lh "$OUTPUT"
