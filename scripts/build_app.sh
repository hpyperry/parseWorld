#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="copyWorld"
BUILD_DIR="$ROOT_DIR/dist"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
DERIVED_DATA_DIR="$ROOT_DIR/.build/DerivedData"

rm -rf "$APP_DIR"
mkdir -p "$BUILD_DIR" "$DERIVED_DATA_DIR"

xcodebuild \
  -project "$ROOT_DIR/copyWorld.xcodeproj" \
  -scheme "$APP_NAME" \
  -configuration Release \
  -destination "platform=macOS,arch=arm64" \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  CONFIGURATION_BUILD_DIR="$BUILD_DIR" \
  build > /dev/null

echo "Built app bundle at: $APP_DIR"
