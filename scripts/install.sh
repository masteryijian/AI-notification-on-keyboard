#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="$HOME/Applications/Pixiu Agent LED.app"
LAUNCH_AGENT="$HOME/Library/LaunchAgents/com.yijian.pixiu-agent-led.plist"
SUPPORT_DIR="$HOME/Library/Application Support/PixiuAgentLED"

mkdir -p "$HOME/Applications" "$HOME/Library/LaunchAgents" "$SUPPORT_DIR"
APP_DESTINATION="$APP_PATH" "$PROJECT_ROOT/scripts/build-app.sh"

cat > "$LAUNCH_AGENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.yijian.pixiu-agent-led</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/open</string>
        <string>-n</string>
        <string>$APP_PATH</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$SUPPORT_DIR/daemon.log</string>
    <key>StandardErrorPath</key>
    <string>$SUPPORT_DIR/daemon-error.log</string>
</dict>
</plist>
PLIST

plutil -lint "$LAUNCH_AGENT"
launchctl bootout "gui/$UID/com.yijian.pixiu-agent-led" 2>/dev/null || true
launchctl bootstrap "gui/$UID" "$LAUNCH_AGENT"

echo "Installed: $APP_PATH"
echo "Now allow Input Monitoring in macOS System Settings."
