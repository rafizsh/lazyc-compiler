#!/bin/bash
# bim/build-bim.sh — build the bim editor.
#
# Requires: nasm, ld, and a built lazyc compiler at ../build/lazyc
# (run ../build.sh from the repo root first).
#
# Output: bim/bim — the editor binary.

set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LAZYC="$ROOT/build/lazyc"
RUNTIME_O="$ROOT/build/runtime.o"
BIM_DIR="$ROOT/bim"
OUT="$BIM_DIR/bim"

if [ ! -x "$LAZYC" ]; then
    echo "lazyc not built: $LAZYC"
    echo "  run '../build.sh' from the repo root first."
    exit 1
fi
if [ ! -f "$RUNTIME_O" ]; then
    echo "runtime not built: $RUNTIME_O"
    echo "  run '../build.sh' from the repo root first."
    exit 1
fi

NASM="${NASM:-nasm}"
LD="${LD:-ld}"

echo "[1/3] compiling bim.ml -> bim.ml.asm"
"$LAZYC" "$BIM_DIR/bim.ml"

echo "[2/3] assembling -> bim.o"
"$NASM" -f elf64 "$BIM_DIR/bim.ml.asm" -o "$BIM_DIR/bim.o"

echo "[3/3] linking -> bim"
"$LD" "$BIM_DIR/bim.o" "$RUNTIME_O" -o "$OUT"

echo
echo "built $OUT"
echo "  try: $OUT some-file.txt"
