#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# Any macOS host architecture; compile the actual font VFS linked into Husk.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT
clang -std=c11 -Wall -Wextra -Werror -O1 -g -fsanitize=address,undefined \
  -I"$ROOT/src/translation-layer-next" \
  "$ROOT/tests/translation-layer/font_discovery.c" "$ROOT/src/translation-layer-next/husk-tl-fonts.c" \
  -o "$OUT/font_discovery"
"$OUT/font_discovery"
