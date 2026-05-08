#!/bin/bash
# tools/cross-check-typecheck.sh — verify the lazyc typechecker agrees
# with the C typechecker by comparing post-typecheck AST output.
#
# Two metrics:
#   1. Accepted programs: AST output must be byte-identical
#   2. Rejection tests: both compilers must reject (nonzero exit)
#
# Usage: tools/cross-check-typecheck.sh

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

# Build the lazyc-side tc_prog test binary.
echo "[build] tc_prog_bin"
CONCAT=/tmp/tc_prog.combined.ml
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
    lazyc/tests/tc_prog.tail.ml > $CONCAT
./lazyc-ref $CONCAT >/dev/null
nasm -f elf64 ${CONCAT}.asm -o /tmp/tc_prog.o
ld /tmp/tc_prog.o runtime/runtime.o -o /tmp/tc_prog_bin

# Phase 1: accepted programs must produce byte-identical AST.
echo "[run] accept tests"
PASS=0; FAIL=0; SKIP=0
ACCEPT_FAILS=""
for f in tests/*.ml; do
    case "$f" in *_fail*.ml|*fail_*.ml) SKIP=$((SKIP+1)); continue;; esac
    /tmp/tc_prog_bin "$f" > /tmp/ml.txt 2>/dev/null
    ./lazyc-ref --ast "$f" > /tmp/c.txt 2>/dev/null
    if diff -q /tmp/ml.txt /tmp/c.txt > /dev/null; then
        PASS=$((PASS+1))
    else
        FAIL=$((FAIL+1)); ACCEPT_FAILS="$ACCEPT_FAILS $f"
    fi
done
echo "  accepted: $PASS pass, $FAIL fail (out of $((PASS+FAIL)))"

# Phase 2: rejection tests must both fail.
echo "[run] reject tests"
RJ_PASS=0; RJ_FAIL=0
RJ_FAILS=""
for f in tests/*fail*.ml; do
    /tmp/tc_prog_bin "$f" > /dev/null 2>&1; ml_rc=$?
    ./lazyc-ref --ast "$f" > /dev/null 2>&1; c_rc=$?
    if [ $ml_rc -ne 0 ] && [ $c_rc -ne 0 ]; then
        RJ_PASS=$((RJ_PASS+1))
    else
        RJ_FAIL=$((RJ_FAIL+1)); RJ_FAILS="$RJ_FAILS $f"
    fi
done
echo "  rejected: $RJ_PASS pass, $RJ_FAIL fail (out of $((RJ_PASS+RJ_FAIL)))"

if [ $FAIL -gt 0 ] || [ $RJ_FAIL -gt 0 ]; then
    if [ $FAIL -gt 0 ]; then
        echo "Differing accepted files:"
        for f in $ACCEPT_FAILS; do echo "  $f"; done
    fi
    if [ $RJ_FAIL -gt 0 ]; then
        echo "Disagreeing reject files:"
        for f in $RJ_FAILS; do echo "  $f"; done
    fi
    exit 1
fi
echo "all good."
