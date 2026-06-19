#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT_DIR/build/Local Flow.app"
APP_BINARY="$APP_DIR/Contents/MacOS/LocalFlow"
WHISPER_BINARY="$APP_DIR/Contents/Resources/whisper/bin/whisper-cli"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/local-flow-portable.XXXXXX")"

cleanup() {
    rm -rf "$TEST_DIR"
}
trap cleanup EXIT

"$ROOT_DIR/scripts/build-app.sh"

if [[ "$(file "$APP_BINARY")" != *"arm64"* ]]; then
    echo "Abbruch: Der Release-Build ist nicht arm64." >&2
    exit 1
fi

if {
    otool -L "$WHISPER_BINARY"
    find "$APP_DIR/Contents/Resources/whisper/lib" -name '*.dylib' \
        -exec otool -L {} \;
} | grep -Eq '/opt/homebrew|/usr/local'; then
    echo "Abbruch: Das App-Bundle enthält eine zwingende Homebrew-Abhängigkeit." >&2
    exit 1
fi

for required_file in \
    "$APP_DIR/Contents/Resources/LocalFlow.icns" \
    "$APP_DIR/Contents/Resources/licenses/libomp-LICENSE.txt" \
    "$APP_DIR/Contents/Resources/licenses/whisper.cpp-LICENSE.txt" \
    "$APP_DIR/Contents/Resources/licenses/ggml-LICENSE.txt" \
    "$APP_DIR/Contents/Resources/licenses/Local-Flow-LICENSE.txt"; do
    test -s "$required_file"
done

LOCAL_FLOW_MODEL_DIRECTORY="$TEST_DIR/models" \
    "$APP_BINARY" --download-model small

MODEL_PATH="$TEST_DIR/models/ggml-small-q5_1.bin"
test -s "$MODEL_PATH"
echo "ae85e4a935d7a567bd102fe55afc16bb595bdb618e11b2fc7591bc08120411bb  $MODEL_PATH" \
    | shasum -a 256 -c -

say -v Anna -o "$TEST_DIR/test.aiff" "Guten Tag. Dies ist ein Test."
afconvert -f WAVE -d LEI16@16000 -c 1 \
    "$TEST_DIR/test.aiff" \
    "$TEST_DIR/test.wav"

"$WHISPER_BINARY" \
    -m "$MODEL_PATH" \
    -f "$TEST_DIR/test.wav" \
    -l de \
    -ng \
    -otxt \
    -of "$TEST_DIR/transcript" \
    -np >/dev/null 2>&1

grep -Eiq 'Guten Tag|Test' "$TEST_DIR/transcript.txt"
codesign --verify --deep --strict "$APP_DIR"

echo "Portable-Release-Test bestanden."
