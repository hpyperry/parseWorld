#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="copyWorld"
BUILD_DIR="$ROOT_DIR/.build/app"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
MACOS_DIR="$APP_DIR/Contents/MacOS"
RESOURCES_DIR="$APP_DIR/Contents/Resources"

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

swiftc \
  -module-name "$APP_NAME" \
  -o "$MACOS_DIR/$APP_NAME" \
  "$ROOT_DIR"/Sources/copyWorld/*.swift \
  -framework SwiftUI \
  -framework AppKit

cp "$ROOT_DIR/scripts/Info.plist" "$APP_DIR/Contents/Info.plist"

echo "Built app bundle at: $APP_DIR"
