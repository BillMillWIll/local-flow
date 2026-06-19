#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$BUILD_DIR/Local Flow.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
WHISPER_DIR="$RESOURCES_DIR/whisper"
WHISPER_BIN_DIR="$WHISPER_DIR/bin"
WHISPER_LIB_DIR="$WHISPER_DIR/lib"
LICENSES_DIR="$RESOURCES_DIR/licenses"
ICONSET_DIR="$BUILD_DIR/LocalFlow.iconset"
VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"
BUILD_NUMBER="${BUILD_NUMBER:-1}"

WHISPER_PREFIX="$(brew --prefix whisper-cpp 2>/dev/null || true)"
GGML_PREFIX="$(brew --prefix ggml 2>/dev/null || true)"
LIBOMP_PREFIX="$(brew --prefix libomp 2>/dev/null || true)"

if [[ -z "$WHISPER_PREFIX" || -z "$GGML_PREFIX" || -z "$LIBOMP_PREFIX" ]]; then
    echo "Für den Release-Build werden whisper-cpp, ggml und libomp via Homebrew benötigt." >&2
    echo "Installation: brew install whisper-cpp libomp" >&2
    exit 1
fi

cd "$ROOT_DIR"
swift build -c release

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$WHISPER_BIN_DIR" "$WHISPER_LIB_DIR" "$LICENSES_DIR"
cp ".build/release/LocalFlow" "$MACOS_DIR/LocalFlow"
cp -L "$WHISPER_PREFIX/bin/whisper-cli" "$WHISPER_BIN_DIR/whisper-cli"
cp -L "$WHISPER_PREFIX/lib/libwhisper.1.dylib" "$WHISPER_LIB_DIR/libwhisper.1.dylib"
cp -L "$GGML_PREFIX/lib/libggml.0.dylib" "$WHISPER_LIB_DIR/libggml.0.dylib"
cp -L "$GGML_PREFIX/lib/libggml-base.0.dylib" "$WHISPER_LIB_DIR/libggml-base.0.dylib"
cp -L "$LIBOMP_PREFIX/lib/libomp.dylib" "$WHISPER_LIB_DIR/libomp.dylib"
cp "$WHISPER_PREFIX/LICENSE" "$LICENSES_DIR/whisper.cpp-LICENSE.txt"
cp "$GGML_PREFIX/LICENSE" "$LICENSES_DIR/ggml-LICENSE.txt"
cp "$ROOT_DIR/ThirdParty/libomp-LICENSE.txt" "$LICENSES_DIR/libomp-LICENSE.txt"
cp "$ROOT_DIR/THIRD-PARTY-NOTICES.md" "$LICENSES_DIR/THIRD-PARTY-NOTICES.md"
cp "$ROOT_DIR/LICENSE" "$LICENSES_DIR/Local-Flow-LICENSE.txt"

rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" \
        "$ROOT_DIR/Assets/LocalFlowIcon-1024.png" \
        --out "$ICONSET_DIR/icon_${size}x${size}.png" >/dev/null
    double_size=$((size * 2))
    sips -z "$double_size" "$double_size" \
        "$ROOT_DIR/Assets/LocalFlowIcon-1024.png" \
        --out "$ICONSET_DIR/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/LocalFlow.icns"
rm -rf "$ICONSET_DIR"

chmod 755 "$WHISPER_BIN_DIR/whisper-cli"

install_name_tool \
    -change "$GGML_PREFIX/lib/libggml.0.dylib" "@rpath/libggml.0.dylib" \
    -change "$GGML_PREFIX/lib/libggml-base.0.dylib" "@rpath/libggml-base.0.dylib" \
    "$WHISPER_BIN_DIR/whisper-cli"
install_name_tool \
    -id "@rpath/libwhisper.1.dylib" \
    -change "$GGML_PREFIX/lib/libggml.0.dylib" "@rpath/libggml.0.dylib" \
    -change "$GGML_PREFIX/lib/libggml-base.0.dylib" "@rpath/libggml-base.0.dylib" \
    "$WHISPER_LIB_DIR/libwhisper.1.dylib"
install_name_tool \
    -id "@rpath/libggml.0.dylib" \
    "$WHISPER_LIB_DIR/libggml.0.dylib"
install_name_tool \
    -id "@rpath/libggml-base.0.dylib" \
    -change "$LIBOMP_PREFIX/lib/libomp.dylib" "@rpath/libomp.dylib" \
    "$WHISPER_LIB_DIR/libggml-base.0.dylib"
install_name_tool \
    -id "@rpath/libomp.dylib" \
    "$WHISPER_LIB_DIR/libomp.dylib"

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>LocalFlow</string>
    <key>CFBundleIdentifier</key>
    <string>de.artmotion.localflow</string>
    <key>CFBundleName</key>
    <string>Local Flow</string>
    <key>CFBundleDisplayName</key>
    <string>Local Flow</string>
    <key>CFBundleIconFile</key>
    <string>LocalFlow</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>__VERSION__</string>
    <key>CFBundleVersion</key>
    <string>__BUILD_NUMBER__</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.productivity</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>Local Flow benötigt das Mikrofon für die lokale Spracheingabe.</string>
</dict>
</plist>
PLIST

sed -i '' \
    -e "s/__VERSION__/$VERSION/g" \
    -e "s/__BUILD_NUMBER__/$BUILD_NUMBER/g" \
    "$CONTENTS_DIR/Info.plist"

codesign --force --sign - "$WHISPER_LIB_DIR/libomp.dylib"
codesign --force --sign - "$WHISPER_LIB_DIR/libggml-base.0.dylib"
codesign --force --sign - "$WHISPER_LIB_DIR/libggml.0.dylib"
codesign --force --sign - "$WHISPER_LIB_DIR/libwhisper.1.dylib"
codesign --force --sign - "$WHISPER_BIN_DIR/whisper-cli"

codesign \
    --force \
    --deep \
    --sign - \
    --identifier de.artmotion.localflow \
    --requirements '=designated => identifier "de.artmotion.localflow"' \
    "$APP_DIR"

codesign --verify --deep --strict "$APP_DIR"
echo "$APP_DIR"
