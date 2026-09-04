#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="余核"
EXEC_NAME="Yuhe"
BUILD_DIR="$ROOT/.build/release"
APP_BUNDLE="$ROOT/$APP_NAME.app"
VERSION="${VERSION:-1.8.0}"
BUILD_NUMBER="${BUILD_NUMBER:-12}"

cd "$ROOT"
echo "Building $APP_NAME..."
swift build -c release --product "$EXEC_NAME"

BIN="$(swift build -c release --product "$EXEC_NAME" --show-bin-path)/$EXEC_NAME"

echo "Creating app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BIN" "$APP_BUNDLE/Contents/MacOS/$EXEC_NAME"

mkdir -p "$APP_BUNDLE/Contents/Resources/Fonts"
FONT_SRC="$ROOT/Sources/Yuhe/Resources/Fonts"
cp "$FONT_SRC/"*.ttf "$APP_BUNDLE/Contents/Resources/Fonts/" 2>/dev/null || true

cat > "$APP_BUNDLE/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh-Hans</string>
    <key>CFBundleExecutable</key>
    <string>${EXEC_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>app.yuhe.quota</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

xattr -cr "$APP_BUNDLE" 2>/dev/null || true
codesign --force --deep --sign - "$APP_BUNDLE"
echo "Built $APP_BUNDLE"

if [[ "${1:-}" == "--install" || "${2:-}" == "--install" ]]; then
    echo "Installing to /Applications..."
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$APP_BUNDLE" "/Applications/$APP_NAME.app"
    xattr -cr "/Applications/$APP_NAME.app" 2>/dev/null || true
    codesign --force --deep --sign - "/Applications/$APP_NAME.app"
    echo "Installed /Applications/$APP_NAME.app"
fi

if [[ "${1:-}" == "--open" || "${2:-}" == "--open" ]]; then
    bash "$ROOT/scripts/launch.sh"
fi
