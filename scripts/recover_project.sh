#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
source "$SCRIPT_DIR/common.sh"

GAME_EXE=$(resolve_game_exe)
GDRE_BIN=$(ensure_gdre)
STAMP=$(date +%Y%m%d-%H%M%S)
OUT_DIR="${1:-$ROOT_DIR/work/recovered/lucid-blocks-$STAMP}"
LOG_PATH="$ROOT_DIR/work/logs/recover-$STAMP.log"

mkdir -p "$ROOT_DIR/work/logs"

printf 'Recovering project from %s\n' "$GAME_EXE"
printf 'Output directory: %s\n' "$OUT_DIR"

"$GDRE_BIN" --headless --recover="$GAME_EXE" --output="$OUT_DIR" 2>&1 | tee "$LOG_PATH"

printf '\nRecovered project written to %s\n' "$OUT_DIR"
printf 'Recovery log saved to %s\n' "$LOG_PATH"
