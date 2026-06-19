#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_SCRIPT="$ROOT_DIR/scripts/build-dmg.sh"
BACKGROUND="$ROOT_DIR/Assets/dmg-background.svg"
BACKGROUND_RENDERER="$ROOT_DIR/scripts/render-dmg-background.swift"

test -f "$BACKGROUND"
test -f "$BACKGROUND_RENDERER"
grep -Fq 'Local Flow nach Programme ziehen' "$BACKGROUND"
grep -Fq 'viewBox="0 0 660 400"' "$BACKGROUND"
grep -Fq 'fill="#f4f7fb" opacity="0.9"' "$BACKGROUND"
if grep -Fq '<filter' "$BACKGROUND"; then
    echo "DMG-Hintergrund darf keine von CoreSVG nicht unterstützten Filter nutzen." >&2
    exit 1
fi

grep -Fq 'DMG_WINDOW_WIDTH=660' "$BUILD_SCRIPT"
grep -Fq 'DMG_WINDOW_HEIGHT=400' "$BUILD_SCRIPT"
grep -Fq 'create-dmg' "$BUILD_SCRIPT"
grep -Fq -- '--window-size "$DMG_WINDOW_WIDTH" "$DMG_WINDOW_HEIGHT"' "$BUILD_SCRIPT"
grep -Fq -- '--icon "Local Flow.app" 170 220' "$BUILD_SCRIPT"
grep -Fq -- '--icon "Programme" 490 220' "$BUILD_SCRIPT"
grep -Fq -- '--background "$BACKGROUND_PNG"' "$BUILD_SCRIPT"
grep -Fq 'render-dmg-background.swift' "$BUILD_SCRIPT"
if grep -Eq 'osascript|hdiutil attach' "$BUILD_SCRIPT"; then
    echo "DMG-Layout soll nicht über eigene Finder-Automation gebaut werden." >&2
    exit 1
fi

echo "DMG-Layout-Test bestanden."
