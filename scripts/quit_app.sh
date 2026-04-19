#!/bin/zsh

set -euo pipefail

APP_BINARY="/Users/hpy/Workspace/parseWorld/.build/app/parseWorld.app/Contents/MacOS/parseWorld"

if pgrep -f "$APP_BINARY" >/dev/null; then
  pkill -f "$APP_BINARY"
  echo "parseWorld stopped."
else
  echo "parseWorld is not running."
fi
