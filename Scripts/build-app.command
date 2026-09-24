#!/bin/zsh
set -e

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

swift build -c release --product cc-pear

APP_DIR="$ROOT_DIR/cc-pear.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$ROOT_DIR/.build/release/cc-pear" "$APP_DIR/Contents/MacOS/cc-pear"
cp "$ROOT_DIR/AppBundle/Contents/Info.plist" "$APP_DIR/Contents/Info.plist"
if [ -f "$ROOT_DIR/AppBundle/Contents/Resources/cc-pear.icns" ]; then
  cp "$ROOT_DIR/AppBundle/Contents/Resources/cc-pear.icns" "$APP_DIR/Contents/Resources/cc-pear.icns"
fi
chmod +x "$APP_DIR/Contents/MacOS/cc-pear"
codesign --force --deep --sign - "$APP_DIR"

echo "已生成：$APP_DIR"
