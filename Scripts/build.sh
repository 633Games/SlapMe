#!/usr/bin/env bash
# Build SlapMe.app + slapme-helper into ./dist
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIG="${1:-release}"
BUILD_DIR="$ROOT/.build/$CONFIG"
DIST="$ROOT/dist"
APP="$DIST/SlapMe.app"

echo "==> Building ($CONFIG)"
swift build -c "$CONFIG"

echo "==> Assembling app bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BUILD_DIR/SlapMe" "$APP/Contents/MacOS/SlapMe"
cp "$BUILD_DIR/slapme-helper" "$DIST/slapme-helper"
# Bundle helper inside the app so the UI can launch it with an admin prompt
cp "$BUILD_DIR/slapme-helper" "$APP/Contents/MacOS/slapme-helper"
chmod +x "$APP/Contents/MacOS/SlapMe" "$DIST/slapme-helper" "$APP/Contents/MacOS/slapme-helper"

# SPM Bundle.module looks for SlapMe_SlapMe.bundle inside Bundle.main.bundleURL (.app root)
if [ -d "$BUILD_DIR/SlapMe_SlapMe.bundle" ]; then
  rm -rf "$APP/SlapMe_SlapMe.bundle"
  cp -R "$BUILD_DIR/SlapMe_SlapMe.bundle" "$APP/SlapMe_SlapMe.bundle"
  # Also keep a copy under Resources for Finder-friendliness / Bundle.main fallbacks
  cp -R "$BUILD_DIR/SlapMe_SlapMe.bundle" "$APP/Contents/Resources/"
fi

# Flatten Packs/Icons into Contents/Resources for Bundle.main fallback paths
if [ -d "$ROOT/Sources/SlapMe/Resources/Packs" ]; then
  cp -R "$ROOT/Sources/SlapMe/Resources/Packs" "$APP/Contents/Resources/"
fi
if [ -d "$ROOT/Sources/SlapMe/Resources/Icons" ]; then
  cp -R "$ROOT/Sources/SlapMe/Resources/Icons" "$APP/Contents/Resources/"
fi

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>SlapMe</string>
  <key>CFBundleIdentifier</key>
  <string>games.sixthree.SlapMe</string>
  <key>CFBundleName</key>
  <string>SlapMe</string>
  <key>CFBundleDisplayName</key>
  <string>SlapMe</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.1.0</string>
  <key>CFBundleVersion</key>
  <string>2</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

# ad-hoc codesign so Gatekeeper is less angry locally
codesign --force --deep --sign - "$APP" 2>/dev/null || true
codesign --force --sign - "$DIST/slapme-helper" 2>/dev/null || true
codesign --force --sign - "$APP/Contents/MacOS/slapme-helper" 2>/dev/null || true

echo "Built:"
echo "  $APP"
echo "  $DIST/slapme-helper"
echo "  (helper also at $APP/Contents/MacOS/slapme-helper)"
