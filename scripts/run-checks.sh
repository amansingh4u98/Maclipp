#!/bin/zsh
set -euo pipefail
unsetopt bg_nice 2>/dev/null || true

ROOT_DIR="${0:A:h:h}"
OUTPUT_DIR="$ROOT_DIR/.build/checks"
MODULE_CACHE_DIR="$ROOT_DIR/.build/clang-module-cache"

mkdir -p "$OUTPUT_DIR" "$MODULE_CACHE_DIR"

LOADER_PID=""

start_loader() {
    local message="$1"
    local frames='|/-\'
    local i=1

    (
        while true; do
            printf "\r%s %s" "$message" "${frames[i]}"
            i=$(( i % ${#frames} + 1 ))
            sleep 0.1
        done
    ) &

    LOADER_PID=$!
}

stop_loader() {
    local exit_code="$1"
    local message="$2"

    if [[ -n "$LOADER_PID" ]]; then
        kill "$LOADER_PID" 2>/dev/null || true
        wait "$LOADER_PID" 2>/dev/null || true
        LOADER_PID=""
    fi

    printf "\r%s\n" "$message"
    return "$exit_code"
}

run_with_loader() {
    local message="$1"
    shift

    start_loader "$message"

    if "$@"; then
        stop_loader 0 "$message done"
    else
        local exit_code=$?
        stop_loader "$exit_code" "$message failed"
        return "$exit_code"
    fi
}

run_with_loader "Compiling repository checks..." env CLANG_MODULE_CACHE_PATH="$MODULE_CACHE_DIR" swiftc \
    "$ROOT_DIR/Sources/Maclipp/Clipboard/ClipboardItem.swift" \
    "$ROOT_DIR/Sources/Maclipp/Clipboard/ClipboardImageReader.swift" \
    "$ROOT_DIR/Sources/Maclipp/Clipboard/ClipboardSecurityPolicy.swift" \
    "$ROOT_DIR/Sources/Maclipp/Hotkeys/GlobalHotKeyManager.swift" \
    "$ROOT_DIR/Sources/Maclipp/Storage/ClipboardRepository.swift" \
    "$ROOT_DIR/Checks/RepositoryChecks.swift" \
    -o "$OUTPUT_DIR/RepositoryChecks"

"$OUTPUT_DIR/RepositoryChecks"
