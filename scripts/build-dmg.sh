#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"
DIST_DIR="$ROOT_DIR/dist"
STAGING_DIR="$ROOT_DIR/build/dmg"
DMG_PATH="$DIST_DIR/Local-Flow-$VERSION.dmg"

"$ROOT_DIR/scripts/check-release.sh"
"$ROOT_DIR/scripts/build-app.sh"

rm -rf "$STAGING_DIR" "$DMG_PATH"
mkdir -p "$STAGING_DIR" "$DIST_DIR"
cp -R "$ROOT_DIR/build/Local Flow.app" "$STAGING_DIR/Local Flow.app"
ln -s /Applications "$STAGING_DIR/Programme"

hdiutil create \
    -volname "Local Flow $VERSION" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

(
    cd "$DIST_DIR"
    shasum -a 256 "$(basename "$DMG_PATH")" > "$(basename "$DMG_PATH").sha256"
)
echo "$DMG_PATH"
