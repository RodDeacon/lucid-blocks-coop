#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
source "$SCRIPT_DIR/common.sh"

GODOT_BIN=$(resolve_godot_export_bin)
MOD_SOURCE_DIR="$ROOT_DIR/mod/overrides"
OUTPUT_PATH="${1:-$ROOT_DIR/dist/lucid-blocks-coop-test.pck}"

mkdir -p "$ROOT_DIR/dist"

printf 'Building exported mod pack from %s\n' "$MOD_SOURCE_DIR"
"$GODOT_BIN" --headless --path "$MOD_SOURCE_DIR" --export-pack "Linux/X11" "$OUTPUT_PATH"

printf '\nBuilt mod pack: %s\n' "$OUTPUT_PATH"
