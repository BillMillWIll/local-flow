#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT_DIR/build/Local Flow.app"
APP_BINARY="$APP_DIR/Contents/MacOS/LocalFlow"
WHISPER_BINARY="$APP_DIR/Contents/Resources/whisper/bin/whisper-cli"
PARAKEET_BINARY="$APP_DIR/Contents/Resources/whisper/bin/parakeet-cli"
RUNTIME_LIB_DIR="$APP_DIR/Contents/Resources/whisper/lib"
RUNTIME_BIN_DIR="$APP_DIR/Contents/Resources/whisper/bin"
# Simuliert einen Mac ohne Homebrew: Der Homebrew-Ordner ist unsichtbar, die
# Tools müssen ihre Backends aus dem Bundle laden.
NO_HOMEBREW_PROFILE='(version 1)(allow default)(deny file-read* (subpath "/opt/homebrew"))'
without_homebrew() {
    sandbox-exec -p "$NO_HOMEBREW_PROFILE" "$@"
}
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/local-flow-portable.XXXXXX")"
# Große Modelle werden lokal zwischen Testläufen wiederverwendet.
MODEL_DIR="${LOCAL_FLOW_TEST_MODEL_DIRECTORY:-$HOME/Library/Caches/local-flow-test-models}"

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
    otool -L "$WHISPER_BINARY" "$PARAKEET_BINARY"
    find "$RUNTIME_LIB_DIR" -name '*.dylib' -exec otool -L {} \;
    find "$RUNTIME_BIN_DIR" -name '*.so' -exec otool -L {} \;
} | grep -Eq '/opt/homebrew|/usr/local'; then
    echo "Abbruch: Das App-Bundle enthält eine zwingende Homebrew-Abhängigkeit." >&2
    exit 1
fi

for required_file in \
    "$PARAKEET_BINARY" \
    "$RUNTIME_LIB_DIR/libparakeet.1.dylib" \
    "$RUNTIME_BIN_DIR/libggml-metal.so" \
    "$APP_DIR/Contents/Resources/LocalFlow.icns" \
    "$APP_DIR/Contents/Resources/licenses/libomp-LICENSE.txt" \
    "$APP_DIR/Contents/Resources/licenses/whisper.cpp-LICENSE.txt" \
    "$APP_DIR/Contents/Resources/licenses/ggml-LICENSE.txt" \
    "$APP_DIR/Contents/Resources/licenses/Local-Flow-LICENSE.txt"; do
    test -s "$required_file"
done
ls "$RUNTIME_BIN_DIR"/libggml-cpu-*.so >/dev/null

# Die Backends müssen aus dem Bundle geladen werden, nicht aus Homebrew.
for tool in "$WHISPER_BINARY" "$PARAKEET_BINARY"; do
    backend_log="$(without_homebrew "$tool" -h 2>&1 | grep -F 'load_backend: loaded' || true)"
    if ! print -r -- "$backend_log" | grep -Fq "loaded MTL backend from $RUNTIME_BIN_DIR"; then
        echo "Abbruch: $(basename "$tool") lädt das Metal-Backend nicht aus dem Bundle." >&2
        print -r -- "$backend_log" >&2
        exit 1
    fi
    if ! print -r -- "$backend_log" | grep -Fq "loaded CPU backend from $RUNTIME_BIN_DIR"; then
        echo "Abbruch: $(basename "$tool") lädt das CPU-Backend nicht aus dem Bundle." >&2
        exit 1
    fi
done

mkdir -p "$MODEL_DIR"
LOCAL_FLOW_MODEL_DIRECTORY="$MODEL_DIR" "$APP_BINARY" --download-model vad
VAD_PATH="$MODEL_DIR/ggml-silero-v5.1.2.bin"
test -s "$VAD_PATH"
echo "29940d98d42b91fbd05ce489f3ecf7c72f0a42f027e4875919a28fb4c04ea2cf  $VAD_PATH" \
    | shasum -a 256 -c -

if [[ "${LOCAL_FLOW_SKIP_INFERENCE:-0}" == "1" ]]; then
    codesign --verify --deep --strict "$APP_DIR"
    echo "Portable-Release-Test ohne VM-Inferenz bestanden."
    exit 0
fi

LOCAL_FLOW_MODEL_DIRECTORY="$MODEL_DIR" "$APP_BINARY" --download-model parakeet
LOCAL_FLOW_MODEL_DIRECTORY="$MODEL_DIR" "$APP_BINARY" --download-model whisperTurbo
PARAKEET_PATH="$MODEL_DIR/ggml-parakeet-tdt-0.6b-v3-q8_0.bin"
TURBO_PATH="$MODEL_DIR/ggml-large-v3-turbo-q5_0.bin"

say -v Anna -o "$TEST_DIR/test.aiff" "Guten Tag. Dies ist ein Test."
afconvert -f WAVE -d LEI16@16000 -c 1 \
    "$TEST_DIR/test.aiff" \
    "$TEST_DIR/test.wav"

without_homebrew "$PARAKEET_BINARY" \
    -m "$PARAKEET_PATH" \
    -f "$TEST_DIR/test.wav" \
    -otxt \
    -of "$TEST_DIR/parakeet" \
    -np >/dev/null 2>&1
grep -Eiq 'Guten Tag|Test' "$TEST_DIR/parakeet.txt"

without_homebrew "$WHISPER_BINARY" \
    -m "$TURBO_PATH" \
    -f "$TEST_DIR/test.wav" \
    -l de \
    --vad --vad-model "$VAD_PATH" \
    -otxt \
    -of "$TEST_DIR/whisper" \
    -np >/dev/null 2>&1
grep -Eiq 'Guten Tag|Test' "$TEST_DIR/whisper.txt"

codesign --verify --deep --strict "$APP_DIR"

echo "Portable-Release-Test bestanden."
