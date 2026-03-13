#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
source "$SCRIPT_DIR/common.sh"

MOD_PACK_PATH="${1:-$ROOT_DIR/dist/lucid-blocks-coop-test.pck}"
GAME_EXE=$(resolve_game_exe)
GAME_DIR=$(dirname "$GAME_EXE")
MODS_DIR="$GAME_DIR/mods"
TARGET_PATH="$MODS_DIR/$(basename "$MOD_PACK_PATH")"

if [[ ! -f "$MOD_PACK_PATH" ]]; then
  printf 'Mod pack not found: %s\n' "$MOD_PACK_PATH" >&2
  exit 1
fi

mkdir -p "$MODS_DIR"
rm -f "$TARGET_PATH"
cp "$MOD_PACK_PATH" "$TARGET_PATH"

printf 'Installed mod pack to %s\n' "$TARGET_PATH"
