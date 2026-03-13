#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
source "$SCRIPT_DIR/common.sh"

GDRE_VERSION="${GDRE_VERSION:-$DEFAULT_GDRE_VERSION}"
GDRE_URL="https://github.com/GDRETools/gdsdecomp/releases/download/${GDRE_VERSION}/GDRE_tools-${GDRE_VERSION}-linux.zip"
GDRE_DIR=$(resolve_gdre_dir)
GDRE_ZIP=$(resolve_gdre_zip)

mkdir -p "$ROOT_DIR/work/tools"

if [[ ! -f "$GDRE_ZIP" ]]; then
  printf 'Downloading GDRE %s...\n' "$GDRE_VERSION"
  curl -L --fail --output "$GDRE_ZIP" "$GDRE_URL"
fi

rm -rf "$GDRE_DIR"
mkdir -p "$GDRE_DIR"
unzip -oq "$GDRE_ZIP" -d "$GDRE_DIR"

GDRE_BIN=$(resolve_gdre_bin || true)
if [[ -z "$GDRE_BIN" ]]; then
  printf 'Unable to locate GDRE binary under %s\n' "$GDRE_DIR" >&2
  exit 1
fi

chmod +x "$GDRE_BIN"
printf 'GDRE ready: %s\n' "$GDRE_BIN"
