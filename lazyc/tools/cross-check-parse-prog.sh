#!/bin/bash
# tools/cross-check-parse-prog.sh — verify the lazyc full-program parser
# agrees with the C parser on AST output.
#
# Skips explicit rejection tests (they're typechecker-rejected, not parser-
# rejected, and exit codes don't matter for this comparison).
#
# Usage: tools/cross-check-parse-prog.sh

set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [ ! -x ./lazyc-ref ]; then
    echo "[build] lazyc"
    make >/dev/null
fi
if [ ! -f runtime/runtime.o ]; then
    echo "[build] runtime"
    make runtime/runtime.o >/dev/null 2>&1 || true
fi

# Build the lazyc-side parse_prog test binary.
echo "[build] parse_prog_bin"
CONCAT=/tmp/parse_prog.combined.ml
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
    lazyc/tests/parse_prog.tail.ml > $CONCAT
./lazyc-ref $CONCAT >/dev/null
nasm -f elf64 ${CONCAT}.asm -o /tmp/parse_prog.o
ld /tmp/parse_prog.o runtime/runtime.o -o /tmp/parse_prog_bin

PASS=0
FAIL=0
SKIP=0
FAILS=""
for f in tests/*.ml; do
    case "$f" in *_fail*.ml|*fail_*.ml) SKIP=$((SKIP+1)); continue;; esac
    /tmp/parse_prog_bin "$f" > /tmp/ml.txt 2>/dev/null; ml_rc=$?
    ./lazyc-ref --ast-raw "$f" > /tmp/c.txt 2>/dev/null; c_rc=$?
    if [ $ml_rc -ne 0 ] && [ $c_rc -ne 0 ]; then PASS=$((PASS+1)); continue; fi
    if [ $ml_rc -ne 0 ] || [ $c_rc -ne 0 ]; then
        FAIL=$((FAIL+1)); FAILS="$FAILS $f"; continue
    fi
    if diff -q /tmp/ml.txt /tmp/c.txt > /dev/null; then
        PASS=$((PASS+1))
    else
        FAIL=$((FAIL+1)); FAILS="$FAILS $f"
    fi
done

echo
echo "parse-prog cross-check: $PASS pass, $FAIL fail, $SKIP skip (rejection tests)"
if [ $FAIL -gt 0 ]; then
    echo "differing files:"
    for f in $FAILS; do echo "  $f"; done
    exit 1
fi
