#!/bin/zsh
set -e

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
"$ROOT_DIR/Scripts/build-app.command"
open "$ROOT_DIR/ClipboardShelf.app"
