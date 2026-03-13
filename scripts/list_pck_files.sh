#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
source "$SCRIPT_DIR/common.sh"

GAME_EXE=$(resolve_game_exe)
GDRE_BIN=$(ensure_gdre)
STAMP=$(date +%Y%m%d-%H%M%S)
LOG_PATH="$ROOT_DIR/work/logs/list-files-$STAMP.txt"

mkdir -p "$ROOT_DIR/work/logs"

printf 'Listing embedded files from %s\n' "$GAME_EXE"
"$GDRE_BIN" --headless --list-files="$GAME_EXE" | tee "$LOG_PATH"

printf '\nSaved file list to %s\n' "$LOG_PATH"
