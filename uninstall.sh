#!/bin/bash
set -euo pipefail

APP_NAME="LangHUD"
LABEL="com.langhud.mac"
TARGET_APP="$HOME/Applications/$APP_NAME.app"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

echo "==> stopping"
launchctl unload "$PLIST" >/dev/null 2>&1 || true
rm -f "$PLIST"
pkill -x "$APP_NAME" >/dev/null 2>&1 || true

echo "==> removing app"
rm -rf "$TARGET_APP"

echo "==> done"
