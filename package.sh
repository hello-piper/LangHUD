#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="LangHUD"
LABEL="com.langhud.mac"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
DIST="dist"
ROOT="$DIST/root"
SCRIPTS="$DIST/scripts"
OUTPUT="$DIST/$APP_NAME-$VERSION.pkg"

# 分发包用 ad-hoc 签名：同事机器不信任本机自签证书，证书签名会被 Gatekeeper 判为损坏
ADHOC_SIGN=1 ./build.sh

rm -rf "$DIST"
mkdir -p "$ROOT/Applications" "$SCRIPTS"

echo "==> staging payload"
# 用 ditto 去掉扩展属性，避免 pkgbuild 生成 ._ AppleDouble 文件
ditto --norsrc --noextattr "build/$APP_NAME.app" "$ROOT/Applications/$APP_NAME.app"

echo "==> writing postinstall"
cat > "$SCRIPTS/postinstall" <<SCRIPT
#!/bin/bash
set -e

PLIST="/Library/LaunchAgents/$LABEL.plist"
mkdir -p "/Library/LaunchAgents"

cat > "\$PLIST" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/open</string>
        <string>-a</string>
        <string>/Applications/$APP_NAME.app</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>LimitLoadToSessionType</key>
    <string>Aqua</string>
</dict>
</plist>
EOF

chmod 644 "\$PLIST"
chown root:wheel "\$PLIST"

# 为当前登录用户立即加载，无需重启
CONSOLE_USER=\$(stat -f%Su /dev/console)
if [ -n "\$CONSOLE_USER" ] && [ "\$CONSOLE_USER" != "root" ]; then
    CONSOLE_UID=\$(id -u "\$CONSOLE_USER")
    launchctl asuser "\$CONSOLE_UID" launchctl load -w "\$PLIST" 2>/dev/null || true
fi

exit 0
SCRIPT
chmod +x "$SCRIPTS/postinstall"
xattr -c "$SCRIPTS/postinstall" 2>/dev/null || true

echo "==> pkgbuild"
pkgbuild --root "$ROOT" \
         --identifier "$LABEL" \
         --version "$VERSION" \
         --scripts "$SCRIPTS" \
         --install-location "/" \
         "$DIST/component.pkg"

echo "==> productbuild"
cat > "$DIST/Distribution" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="1">
    <pkg-ref id="$LABEL"/>
    <options customize="never" require-scripts="false" hostArchitectures="arm64"/>
    <choices-outline>
        <line choice="default">
            <line choice="$LABEL"/>
        </line>
    </choices-outline>
    <choice id="default"/>
    <choice id="$LABEL" visible="false">
        <pkg-ref id="$LABEL"/>
    </choice>
    <pkg-ref id="$LABEL" version="$VERSION" onConclusion="none">component.pkg</pkg-ref>
</installer-gui-script>
EOF

productbuild --distribution "$DIST/Distribution" \
             --package-path "$DIST" \
             "$OUTPUT"

rm -f "$DIST/component.pkg" "$DIST/Distribution"
rm -rf "$ROOT" "$SCRIPTS"

echo "==> done: $OUTPUT"
ls -lh "$OUTPUT"
