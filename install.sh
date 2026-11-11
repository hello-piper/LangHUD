#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="LangHUD"
LABEL="com.langhud.mac"
TARGET_DIR="$HOME/Applications"
TARGET_APP="$TARGET_DIR/$APP_NAME.app"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

./build.sh

echo "==> installing to $TARGET_APP"
mkdir -p "$TARGET_DIR"
pkill -x "$APP_NAME" >/dev/null 2>&1 || true
rm -rf "$TARGET_APP"
cp -R "build/$APP_NAME.app" "$TARGET_APP"

echo "==> writing LaunchAgent"
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<EOF
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
        <string>$TARGET_APP</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>LimitLoadToSessionType</key>
    <string>Aqua</string>
</dict>
</plist>
EOF

launchctl unload "$PLIST" >/dev/null 2>&1 || true
launchctl load "$PLIST"

echo "==> done"
echo "首次运行请在「系统设置 → 隐私与安全性 → 辅助功能」中勾选 LangHUD"
