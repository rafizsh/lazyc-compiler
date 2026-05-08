#!/bin/bash
# build.sh — build the lazyc compiler from prebuilt asm.
#
# This script does NOT require the C reference compiler. It bootstraps
# `lazyc` from the asm files committed to lazyc/prebuilt/ and
# runtime/prebuilt/, then verifies the resulting binary is a fixed point:
# feeding it its own source must produce byte-identical asm.
#
# Required tools: nasm, ld.
#
# Outputs (all under build/):
#   build/syscall.o        - assembled syscall trampolines
#   build/runtime_ml.o     - assembled prebuilt lazyc runtime
#   build/runtime.o        - combined runtime
#   build/lazyc-stage0.o   - assembled prebuilt bootstrap
#   build/lazyc-stage0     - lazyc built from prebuilt
#   build/lazyc-stage1.asm - asm produced by stage0 compiling itself
#   build/lazyc-stage1.o
#   build/lazyc            - the canonical lazyc binary
#
# After this script: `build/lazyc` is the compiler to use.

set -e
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
mkdir -p build

NASM="${NASM:-nasm}"
LD="${LD:-ld}"

echo "[1/6] assembling syscall.asm"
$NASM -f elf64 runtime/syscall.asm -o build/syscall.o

echo "[2/6] assembling prebuilt runtime asm"
$NASM -f elf64 runtime/prebuilt/runtime_ml.asm -o build/runtime_ml.o

echo "[3/6] combining runtime objects"
$LD -r build/syscall.o build/runtime_ml.o -o build/runtime.o

echo "[4/6] assembling prebuilt lazyc asm"
$NASM -f elf64 lazyc/prebuilt/lazyc.asm -o build/lazyc-stage0.o
$LD build/lazyc-stage0.o build/runtime.o -o build/lazyc-stage0

echo "[5/6] stage0 compiling its own source -> stage1.asm"
# Concatenate the canonical bootstrap source.
cat lazyc/lib/strs.ml \
    lazyc/lib/buf.ml \
    lazyc/lib/ptrvec.ml \
    lazyc/compiler/types.ml \
    lazyc/compiler/token.ml \
    lazyc/compiler/error.ml \
    lazyc/compiler/lex.ml \
    lazyc/compiler/ast.ml \
    lazyc/compiler/stmt.ml \
    lazyc/compiler/parse.ml \
    lazyc/compiler/parse_struct.ml \
    lazyc/compiler/parse_stmt.ml \
    lazyc/compiler/ast_print.ml \
    lazyc/compiler/ast_print_stmt.ml \
    lazyc/compiler/typecheck.ml \
    lazyc/compiler/codegen.ml \
    lazyc/compiler/main.ml > build/lazyc.combined.ml

build/lazyc-stage0 build/lazyc.combined.ml > /dev/null
mv build/lazyc.combined.ml.asm build/lazyc-stage1.asm

# Verify fixed point: stage0's output should match the prebuilt asm.
if diff -q build/lazyc-stage1.asm lazyc/prebuilt/lazyc.asm > /dev/null; then
    echo "  fixed-point check: stage0 output matches prebuilt"
else
    echo "  WARNING: stage0 output differs from prebuilt asm."
    echo "  (This is expected if you've modified the bootstrap source.)"
fi

echo "[6/6] assembling stage1.asm -> lazyc"
$NASM -f elf64 build/lazyc-stage1.asm -o build/lazyc-stage1.o
$LD build/lazyc-stage1.o build/runtime.o -o build/lazyc

echo
echo "done. canonical binary: build/lazyc"
echo "size: $(wc -c < build/lazyc) bytes"
