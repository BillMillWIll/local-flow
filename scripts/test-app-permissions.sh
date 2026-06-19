#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT_DIR/build/Local Flow.app"

"$ROOT_DIR/scripts/build-app.sh" >/dev/null

for dylib in "$APP_DIR/Contents/Resources/whisper/lib/"*.dylib; do
    if [[ ! -w "$dylib" ]]; then
        echo "Eingebettete Bibliothek ist für den Besitzer nicht schreibbar: $dylib" >&2
        exit 1
    fi
done

echo "App-Dateirechte-Test bestanden."
