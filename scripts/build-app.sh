#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
APP_DIR="$ROOT_DIR/dist/Maclipp.app"
CONTENTS_DIR="$APP_DIR/Contents"
MODULE_CACHE_DIR="$ROOT_DIR/.build/clang-module-cache"
SWIFTPM_BUILD_DIR="$ROOT_DIR/.build/swiftpm"

cd "$ROOT_DIR"
mkdir -p "$MODULE_CACHE_DIR"
CLANG_MODULE_CACHE_PATH="$MODULE_CACHE_DIR" swift build \
    -c release \
    --scratch-path "$SWIFTPM_BUILD_DIR"
BIN_DIR="$(CLANG_MODULE_CACHE_PATH="$MODULE_CACHE_DIR" swift build \
    -c release \
    --scratch-path "$SWIFTPM_BUILD_DIR" \
    --show-bin-path)"

mkdir -p "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Resources"
cp "$BIN_DIR/Maclipp" "$CONTENTS_DIR/MacOS/Maclipp"
cp "$ROOT_DIR/support/Info.plist" "$CONTENTS_DIR/Info.plist"
CLANG_MODULE_CACHE_PATH="$MODULE_CACHE_DIR" swift \
    "$ROOT_DIR/support/generate-app-icon.swift" \
    "$ROOT_DIR/support/AppIcon.svg" \
    "$CONTENTS_DIR/Resources/Maclipp.icns"
codesign --force --deep --sign - "$APP_DIR"

echo "Built $APP_DIR"
