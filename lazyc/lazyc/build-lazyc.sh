#!/bin/bash
# build-lazyc.sh — build the bootstrap compiler binary using the C
# reference compiler. This is the path used to regenerate
# lazyc/prebuilt/lazyc.asm from source.
#
# For a normal build (no C compiler needed), use ../build.sh from the
# repo root instead. That uses the prebuilt asm.
#
# Concatenates the substrate library + compiler files in dependency
# order, runs the C reference compiler (./lazyc-ref) to produce
# assembly, then nasm + ld to produce the ELF binary at lazyc/lazyc.

set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LAZYC_DIR="$ROOT/lazyc"
COMPILER="$ROOT/lazyc-ref"
RUNTIME_O="$ROOT/build/runtime.o"
OUT="$LAZYC_DIR/lazyc"

if [ ! -x "$COMPILER" ]; then
    echo "C reference compiler not built: $COMPILER"
    echo "  run 'make' from the repo root first."
    exit 1
fi
if [ ! -f "$RUNTIME_O" ]; then
    echo "runtime not built: $RUNTIME_O"
    echo "  run '../build.sh' first."
    exit 1
fi

CONCAT="/tmp/lazyc.combined.ml"
ASM="/tmp/lazyc.combined.ml.asm"
OBJ="/tmp/lazyc.combined.o"

# Concatenation order matters because lazyc has no forward declarations:
#   1. Substrate library (strs, buf, ptrvec): no dependencies
#   2. compiler/types.ml: defines Type/Field/StructDef and helpers
#   3. compiler/token.ml: token kind constants
#   4. compiler/error.ml: error helpers
#   5. compiler/lex.ml: lexer
#   6. compiler/ast.ml + stmt.ml: AST data types
#   7. compiler/parse.ml + parse_struct.ml + parse_stmt.ml: parser
#   8. compiler/ast_print.ml + ast_print_stmt.ml: AST dumper
#   9. compiler/typecheck.ml: typechecker
#   10. compiler/codegen.ml: codegen
#   11. compiler/main.ml: ties it all together

echo "[1/4] concatenating sources -> $CONCAT"
cat "$LAZYC_DIR/lib/strs.ml" \
    "$LAZYC_DIR/lib/buf.ml" \
    "$LAZYC_DIR/lib/ptrvec.ml" \
    "$LAZYC_DIR/compiler/types.ml" \
    "$LAZYC_DIR/compiler/token.ml" \
    "$LAZYC_DIR/compiler/error.ml" \
    "$LAZYC_DIR/compiler/lex.ml" \
    "$LAZYC_DIR/compiler/ast.ml" \
    "$LAZYC_DIR/compiler/stmt.ml" \
    "$LAZYC_DIR/compiler/parse.ml" \
    "$LAZYC_DIR/compiler/parse_struct.ml" \
    "$LAZYC_DIR/compiler/parse_stmt.ml" \
    "$LAZYC_DIR/compiler/ast_print.ml" \
    "$LAZYC_DIR/compiler/ast_print_stmt.ml" \
    "$LAZYC_DIR/compiler/typecheck.ml" \
    "$LAZYC_DIR/compiler/codegen.ml" \
    "$LAZYC_DIR/compiler/main.ml" > "$CONCAT"
echo "  $(wc -l < "$CONCAT") lines total"

echo "[2/4] compiling with lazyc-ref -> $ASM"
"$COMPILER" "$CONCAT"

echo "[3/4] assembling with nasm -> $OBJ"
nasm -f elf64 "$ASM" -o "$OBJ"

echo "[4/4] linking -> $OUT"
ld "$OBJ" "$RUNTIME_O" -o "$OUT"

echo
echo "built $OUT"
echo "  try: $OUT some-source.ml"
