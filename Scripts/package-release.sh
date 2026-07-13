#!/usr/bin/env bash
# Build + zip SlapMe.app for GitHub Releases
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="${1:-1.1.0}"
bash "$ROOT/Scripts/build.sh" release

DIST="$ROOT/dist"
APP="$DIST/SlapMe.app"
ZIP="$DIST/SlapMe-${VERSION}-macOS.zip"

rm -f "$ZIP"
# ditto preserves .app bundle / resource forks better than zip for macOS apps
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

echo "Release package:"
echo "  $ZIP"
ls -lh "$ZIP"
