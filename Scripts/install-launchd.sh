#!/usr/bin/env bash
# Optional: install slapme-helper as a LaunchDaemon (still needs root sensor access)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
USER_NAME="$(id -un)"
HOME_DIR="$(eval echo ~"$USER_NAME")"
SUPPORT="$HOME_DIR/Library/Application Support/SlapMe"
SOCKET="$SUPPORT/slapme.sock"
HELPER="$ROOT/dist/slapme-helper"
PLIST="/Library/LaunchDaemons/game.sixthree.slapme-helper.plist"

if [ ! -x "$HELPER" ]; then
  echo "Build first: Scripts/build.sh"
  exit 1
fi

mkdir -p "$SUPPORT/Packs" "$SUPPORT/Icons"

sudo tee "$PLIST" >/dev/null <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>game.sixthree.slapme-helper</string>
  <key>ProgramArguments</key>
  <array>
    <string>$HELPER</string>
    <string>--socket</string>
    <string>$SOCKET</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>SLAPME_SOCKET</key>
    <string>$SOCKET</string>
  </dict>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>UserName</key>
  <string>root</string>
  <key>StandardOutPath</key>
  <string>/tmp/slapme-helper.log</string>
  <key>StandardErrorPath</key>
  <string>/tmp/slapme-helper.err</string>
</dict>
</plist>
EOF

sudo launchctl bootout system "$PLIST" 2>/dev/null || true
sudo launchctl bootstrap system "$PLIST"
sudo launchctl enable system/game.sixthree.slapme-helper
sudo launchctl kickstart -k system/game.sixthree.slapme-helper
echo "Installed LaunchDaemon: $PLIST"
echo "Socket: $SOCKET"
echo "Logs: /tmp/slapme-helper.log"
