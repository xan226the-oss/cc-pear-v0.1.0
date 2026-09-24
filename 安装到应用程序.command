#!/bin/zsh
set -e

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_APP="$ROOT_DIR/剪贴板小窗.app"
TARGET_APP="/Applications/剪贴板小窗.app"

if [ ! -d "$SOURCE_APP" ]; then
  echo "找不到 $SOURCE_APP"
  exit 1
fi

osascript -e 'try' -e 'tell application "剪贴板小窗" to quit' -e 'end try' >/dev/null 2>&1 || true
rm -rf "$TARGET_APP"
ditto "$SOURCE_APP" "$TARGET_APP"
open "$TARGET_APP"

echo "已安装到：$TARGET_APP"
echo "以后可以在 启动台 / 应用程序 / Spotlight 里搜索：剪贴板小窗"
