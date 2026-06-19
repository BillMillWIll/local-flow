#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"
DIST_DIR="$ROOT_DIR/dist"
STAGING_DIR="$ROOT_DIR/build/dmg"
DMG_PATH="$DIST_DIR/Local-Flow-$VERSION.dmg"
BACKGROUND_SOURCE="$ROOT_DIR/Assets/dmg-background.svg"
BACKGROUND_PNG="$ROOT_DIR/build/dmg-background.png"
DMG_WINDOW_WIDTH=660
DMG_WINDOW_HEIGHT=540

"$ROOT_DIR/scripts/check-release.sh"
"$ROOT_DIR/scripts/build-app.sh"

if ! command -v create-dmg >/dev/null 2>&1; then
    echo "Abbruch: create-dmg fehlt. Installation: brew install create-dmg" >&2
    exit 1
fi

rm -rf "$STAGING_DIR" "$BACKGROUND_PNG" "$DMG_PATH"
mkdir -p "$STAGING_DIR" "$DIST_DIR"
cp -R "$ROOT_DIR/build/Local Flow.app" "$STAGING_DIR/Local Flow.app"
ln -s /Applications "$STAGING_DIR/Programme"
ln -s /System/Library/PreferencePanes/Security.prefPane \
    "$STAGING_DIR/Systemeinstellungen öffnen"

# Keep the editable SVG in the repository while Finder receives an exact-size
# PNG rendered by AppKit.
swift "$ROOT_DIR/scripts/render-dmg-background.swift" \
    "$BACKGROUND_SOURCE" \
    "$BACKGROUND_PNG"

create-dmg \
    --volname "Local Flow $VERSION" \
    --background "$BACKGROUND_PNG" \
    --window-pos 180 140 \
    --window-size "$DMG_WINDOW_WIDTH" "$DMG_WINDOW_HEIGHT" \
    --icon-size 96 \
    --text-size 13 \
    --icon "Local Flow.app" 170 220 \
    --icon "Programme" 490 220 \
    --icon "Systemeinstellungen öffnen" 150 405 \
    --hide-extension "Local Flow.app" \
    --format UDZO \
    --filesystem APFS \
    "$DMG_PATH" \
    "$STAGING_DIR"

rm -f "$BACKGROUND_PNG"

(
    cd "$DIST_DIR"
    shasum -a 256 "$(basename "$DMG_PATH")" > "$(basename "$DMG_PATH").sha256"
)
echo "$DMG_PATH"
