#!/usr/bin/env bash
# Start privileged helper + menu bar app
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SUPPORT="$HOME/Library/Application Support/SlapMe"
SOCKET="$SUPPORT/slapme.sock"
LOG="/tmp/slapme-helper.log"
mkdir -p "$SUPPORT/Packs" "$SUPPORT/Icons"

if [ ! -x "$ROOT/dist/SlapMe.app/Contents/MacOS/SlapMe" ] || [ ! -x "$ROOT/dist/slapme-helper" ]; then
  echo "Binaries missing — building first…"
  bash "$ROOT/Scripts/build.sh" release
fi

# Must authenticate on an interactive TTY BEFORE backgrounding.
# `sudo … &` cannot read a password (Input/output error / Illegal seek).
if [[ ! -t 0 ]]; then
  echo "Error: start.sh needs an interactive terminal for the password prompt."
  echo "Run it in Terminal, or open SlapMe.app and use “Grant access & start helper…”."
  exit 1
fi

echo "SlapMe needs admin once to read the MacBook accelerometer (IOKit HID)."
echo "Enter your Mac login password when prompted."
if ! sudo -v; then
  echo "Admin authentication failed or cancelled."
  exit 1
fi

# Keep sudo ticket alive while we start things
sudo -v

if pgrep -qx slapme-helper; then
  echo "Stopping existing slapme-helper…"
  sudo pkill -x slapme-helper || true
  sleep 0.3
fi

export SLAPME_SOCKET="$SOCKET"
echo "Socket: $SOCKET"
echo "Starting slapme-helper…"
: >"$LOG"

# Cached credentials → non-interactive; safe to background
sudo -n env SLAPME_SOCKET="$SOCKET" "$ROOT/dist/slapme-helper" \
  --socket "$SOCKET" --verbose >>"$LOG" 2>&1 &

# Wait for the real helper process (not the shell's sudo wrapper)
HELPER_OK=0
for _ in 1 2 3 4 5 6 7 8; do
  if pgrep -qx slapme-helper; then
    HELPER_OK=1
    break
  fi
  sleep 0.25
done

if [[ "$HELPER_OK" -ne 1 ]]; then
  echo "Helper failed to start."
  echo "Log: $LOG"
  [[ -f "$LOG" ]] && tail -n 40 "$LOG" || true
  echo
  echo "Check sensor with: ioreg -l -w0 | grep AppleSPUHIDDevice"
  echo "Or open SlapMe.app and use “Grant access & start helper…”."
  exit 1
fi

HELPER_PID="$(pgrep -x slapme-helper | head -n1)"
echo "Helper running (PID $HELPER_PID)."

APP_BIN="$ROOT/dist/SlapMe.app/Contents/MacOS/SlapMe"
APP_LOG="/tmp/slapme-app.log"

# Menu-bar agent apps (LSUIElement) often make `open` time out with -1712.
# Launch the executable directly instead.
if pgrep -qx SlapMe; then
  echo "Restarting existing SlapMe menu bar app…"
  pkill -x SlapMe || true
  sleep 0.4
fi

echo "Launching SlapMe menu bar app…"
: >"$APP_LOG"

# Prefer Launch Services so MenuBarExtra registers correctly.
# Direct exec of the binary can leave the status item missing.
if ! open -g -a "$ROOT/dist/SlapMe.app" >>"$APP_LOG" 2>&1; then
  echo "open failed — launching binary directly…"
  nohup "$APP_BIN" >>"$APP_LOG" 2>&1 &
  disown || true
fi

APP_OK=0
for _ in 1 2 3 4 5 6; do
  if pgrep -qx SlapMe; then
    APP_OK=1
    break
  fi
  sleep 0.25
done

if [[ "$APP_OK" -ne 1 ]]; then
  echo "Menu bar app failed to start. Log: $APP_LOG"
  [[ -f "$APP_LOG" ]] && tail -n 40 "$APP_LOG" || true
  exit 1
fi

echo "SlapMe is running (look for the hand icon in the menu bar)."
echo "Slap your MacBook. Quit from the menu bar popover."
echo "Helper log: $LOG"
echo "App log:    $APP_LOG"
