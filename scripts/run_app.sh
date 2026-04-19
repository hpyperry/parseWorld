#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="$ROOT_DIR/.build/app/parseWorld.app"

if [[ ! -d "$APP_PATH" ]]; then
  "$ROOT_DIR/scripts/build_app.sh"
fi

open "$APP_PATH"
