#!/bin/zsh
set -e

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT_DIR/cc-pear.app"
DIST_DIR="$ROOT_DIR/github-release"
STAGE_DIR="$ROOT_DIR/build-assets/dmg-stage"
DMG_PATH="$DIST_DIR/cc-pear-v0.1.0.dmg"

if [ ! -d "$APP_DIR" ]; then
  "$ROOT_DIR/Scripts/build-app.command"
fi

rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR" "$DIST_DIR"

ditto "$APP_DIR" "$STAGE_DIR/cc-pear.app"
ln -s /Applications "$STAGE_DIR/Applications"
cp "$ROOT_DIR/新手指引.md" "$STAGE_DIR/新手指引.md"

hdiutil create \
  -volname "cc-pear" \
  -srcfolder "$STAGE_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

cp "$ROOT_DIR/README.md" "$DIST_DIR/README.md"
cp "$ROOT_DIR/新手指引.md" "$DIST_DIR/新手指引.md"

echo "已生成：$DMG_PATH"
