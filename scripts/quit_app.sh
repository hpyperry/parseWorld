#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="copyWorld"
APP_BINARY="$ROOT_DIR/.build/app/$APP_NAME.app/Contents/MacOS/$APP_NAME"

if pgrep -f "$APP_BINARY" >/dev/null; then
  pkill -f "$APP_BINARY"
  echo "copyWorld stopped."
else
  echo "copyWorld is not running."
fi
