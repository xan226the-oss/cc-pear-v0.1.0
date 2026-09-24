#!/bin/zsh
set -e

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_SUPPORT="$HOME/Library/Application Support/ClipboardShelf"
mkdir -p "$APP_SUPPORT"
date +%s > "$APP_SUPPORT/show.request"
open "$ROOT_DIR/ClipboardShelf.app"
