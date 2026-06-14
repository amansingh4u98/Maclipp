#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
OUTPUT_DIR="$ROOT_DIR/.build/checks"
MODULE_CACHE_DIR="$ROOT_DIR/.build/clang-module-cache"

mkdir -p "$OUTPUT_DIR" "$MODULE_CACHE_DIR"

CLANG_MODULE_CACHE_PATH="$MODULE_CACHE_DIR" swiftc \
    "$ROOT_DIR/Sources/Maclipp/Clipboard/ClipboardItem.swift" \
    "$ROOT_DIR/Sources/Maclipp/Clipboard/ClipboardImageReader.swift" \
    "$ROOT_DIR/Sources/Maclipp/Clipboard/ClipboardSecurityPolicy.swift" \
    "$ROOT_DIR/Sources/Maclipp/Hotkeys/GlobalHotKeyManager.swift" \
    "$ROOT_DIR/Sources/Maclipp/Storage/ClipboardRepository.swift" \
    "$ROOT_DIR/Checks/RepositoryChecks.swift" \
    -o "$OUTPUT_DIR/RepositoryChecks"

"$OUTPUT_DIR/RepositoryChecks"
