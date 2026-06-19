#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_SOURCE="$ROOT_DIR/build/Local Flow.app"
APP_TARGET="/Applications/Local Flow.app"

"$ROOT_DIR/scripts/build-app.sh"
pkill -x LocalFlow 2>/dev/null || true
ditto "$APP_SOURCE" "$APP_TARGET"
open "$APP_TARGET" || true

echo "Installiert: $APP_TARGET"
