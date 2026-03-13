#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

DEFAULT_GAME_EXE="/data/SteamLibrary/steamapps/common/lucid-blocks/lucid-blocks/lucid-blocks.exe"
DEFAULT_GDRE_VERSION="v2.4.0"
DEFAULT_GODOT_EXPORT_BIN="$ROOT_DIR/work/tools/godot-4.6/editor/Godot_v4.6-stable_linux.x86_64"

resolve_game_exe() {
  local game_exe="${GAME_EXE:-$DEFAULT_GAME_EXE}"
  if [[ ! -f "$game_exe" ]]; then
    printf 'Lucid Blocks executable not found: %s\n' "$game_exe" >&2
    return 1
  fi
  printf '%s\n' "$game_exe"
}

resolve_gdre_dir() {
  local version="${GDRE_VERSION:-$DEFAULT_GDRE_VERSION}"
  printf '%s/work/tools/gdre-%s\n' "$ROOT_DIR" "$version"
}

resolve_gdre_zip() {
  local version="${GDRE_VERSION:-$DEFAULT_GDRE_VERSION}"
  printf '%s/work/tools/GDRE_tools-%s-linux.zip\n' "$ROOT_DIR" "$version"
}

resolve_gdre_bin() {
  local gdre_dir
  gdre_dir=$(resolve_gdre_dir)

  if [[ ! -d "$gdre_dir" ]]; then
    return 1
  fi

  local candidate
  shopt -s nullglob globstar
  for candidate in \
    "$gdre_dir"/**/gdre_tools*.x86_64 \
    "$gdre_dir"/**/gdre_tools \
    "$gdre_dir"/**/GDRE_tools*.x86_64 \
    "$gdre_dir"/**/GDRE_tools; do
    if [[ -f "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

ensure_gdre() {
  local gdre_bin
  if gdre_bin=$(resolve_gdre_bin); then
    printf '%s\n' "$gdre_bin"
    return 0
  fi

  "$SCRIPT_DIR/install_gdre.sh" >/dev/null
  resolve_gdre_bin
}

resolve_godot_export_bin() {
  local godot_bin="${GODOT_EXPORT_BIN:-$DEFAULT_GODOT_EXPORT_BIN}"
  if [[ ! -f "$godot_bin" ]]; then
    printf 'Godot 4.6 export binary not found: %s\n' "$godot_bin" >&2
    return 1
  fi
  printf '%s\n' "$godot_bin"
}
