#!/bin/bash
# build-substrate.sh — concatenate the lazyc substrate library + a test
# (or eventually + main.ml) into a single .ml file, then compile it.
#
# Usage: ./build-substrate.sh <tail.ml> [output-binary]
#   tail.ml     — the file containing main(), to be appended to lib/*.ml
#   output      — final ELF binary path; default: based on tail.ml name
#
# The lazyc language doesn't have an import directive (and we don't plan
# to add one — the bootstrap is one program). We just concatenate.

set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MYLANGC="$ROOT/lazyc"
COMPILER="$ROOT/lazyc"
RUNTIME_O="$ROOT/runtime/runtime.o"

if [ $# -lt 1 ]; then
    echo "usage: $0 <tail.ml> [output-binary]"
    exit 1
fi

TAIL="$1"
NAME="$(basename "$TAIL" .ml)"
OUT="${2:-$ROOT/lazyc/$NAME}"

if [ ! -x "$COMPILER" ]; then
    echo "compiler not built: $COMPILER"
    echo "  run 'make' from the repo root first."
    exit 1
fi
if [ ! -f "$RUNTIME_O" ]; then
    echo "runtime not built: $RUNTIME_O"
    echo "  run 'make runtime/runtime.o' first."
    exit 1
fi

CONCAT="/tmp/${NAME}.combined.ml"
ASM="/tmp/${NAME}.combined.ml.asm"
OBJ="/tmp/${NAME}.combined.o"

echo "[1/4] concatenating substrate + tail -> $CONCAT"
cat "$MYLANGC/lib/strs.ml" \
    "$MYLANGC/lib/buf.ml" \
    "$MYLANGC/lib/ptrvec.ml" \
    "$TAIL" > "$CONCAT"
echo "  $(wc -l < "$CONCAT") lines total"

echo "[2/4] compiling with lazyc -> $ASM"
"$COMPILER" "$CONCAT"

echo "[3/4] assembling with nasm -> $OBJ"
nasm -f elf64 "$ASM" -o "$OBJ"

echo "[4/4] linking -> $OUT"
ld "$OBJ" "$RUNTIME_O" -o "$OUT"

echo
echo "built $OUT"
echo "  run: $OUT"
