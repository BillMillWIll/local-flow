#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_SCRIPT="$ROOT_DIR/scripts/build-dmg.sh"
BACKGROUND="$ROOT_DIR/Assets/dmg-background.svg"
BACKGROUND_RENDERER="$ROOT_DIR/scripts/render-dmg-background.swift"

test -f "$BACKGROUND"
test -f "$BACKGROUND_RENDERER"
grep -Fq 'Local Flow nach Programme ziehen' "$BACKGROUND"
grep -Fq 'Fehlermeldung beim Öffnen?' "$BACKGROUND"
grep -Fq '1. Systemeinstellungen öffnen' "$BACKGROUND"
grep -Fq '2. Datenschutz &amp; Sicherheit auswählen' "$BACKGROUND"
grep -Fq '3. Ganz nach unten zu Sicherheit scrollen' "$BACKGROUND"
grep -Fq '4. Bei Local Flow „Dennoch öffnen“ klicken' "$BACKGROUND"
grep -Fq 'viewBox="0 0 660 540"' "$BACKGROUND"
if grep -Eq '<rect x="(75|395)" y="132"' "$BACKGROUND"; then
    echo "DMG-Hintergrund darf keine Karten hinter den beiden Icons enthalten." >&2
    exit 1
fi
if grep -Fq '<filter' "$BACKGROUND"; then
    echo "DMG-Hintergrund darf keine von CoreSVG nicht unterstützten Filter nutzen." >&2
    exit 1
fi

grep -Fq 'DMG_WINDOW_WIDTH=660' "$BUILD_SCRIPT"
grep -Fq 'DMG_WINDOW_HEIGHT=540' "$BUILD_SCRIPT"
if grep -Eq 'Security\\.prefPane|Systemeinstellungen öffnen' "$BUILD_SCRIPT"; then
    echo "DMG darf keinen PREF-Link oder zusätzliches Hilfssymbol enthalten." >&2
    exit 1
fi
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
