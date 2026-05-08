#!/bin/bash
# tools/cross-check-codegen.sh — verify the lazyc codegen agrees with
# the C codegen by comparing emitted .asm files. Also runs the fixed-point
# test: feed the bootstrap binary its own source and check it produces
# byte-identical asm to what the C compiler produces.
#
# Usage: tools/cross-check-codegen.sh

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

# Build the bootstrap binary.
echo "[build] lazyc bootstrap"
CONCAT=/tmp/lazyc.combined.ml
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
    lazyc/compiler/main.ml > $CONCAT
./lazyc-ref $CONCAT >/dev/null
nasm -f elf64 ${CONCAT}.asm -o /tmp/lazyc.o
ld /tmp/lazyc.o runtime/runtime.o -o /tmp/lazyc

# Phase 1: every accepted program must produce byte-identical asm.
echo "[run] codegen accept tests"
PASS=0; FAIL=0; SKIP=0
ACCEPT_FAILS=""
for f in tests/*.ml; do
    case "$f" in *_fail*.ml|*fail_*.ml) SKIP=$((SKIP+1)); continue;; esac
    /tmp/lazyc "$f" > /dev/null 2>&1; ml_rc=$?
    if [ $ml_rc -ne 0 ]; then
        FAIL=$((FAIL+1)); ACCEPT_FAILS="$ACCEPT_FAILS $f"; continue
    fi
    cp "$f.asm" /tmp/ml.asm
    ./lazyc-ref "$f" > /dev/null 2>&1
    if diff -q "$f.asm" /tmp/ml.asm > /dev/null; then
        PASS=$((PASS+1))
    else
        FAIL=$((FAIL+1)); ACCEPT_FAILS="$ACCEPT_FAILS $f"
    fi
done
echo "  accepted: $PASS pass, $FAIL fail (skip $SKIP rejection tests)"

# Phase 2: rejection tests must both fail.
echo "[run] codegen reject tests"
RJ_PASS=0; RJ_FAIL=0
RJ_FAILS=""
for f in tests/*fail*.ml; do
    /tmp/lazyc "$f" > /dev/null 2>&1; ml_rc=$?
    ./lazyc-ref "$f" > /dev/null 2>&1; c_rc=$?
    if [ $ml_rc -ne 0 ] && [ $c_rc -ne 0 ]; then
        RJ_PASS=$((RJ_PASS+1))
    else
        RJ_FAIL=$((RJ_FAIL+1)); RJ_FAILS="$RJ_FAILS $f"
    fi
done
echo "  rejected: $RJ_PASS pass, $RJ_FAIL fail"

# Phase 3: fixed-point self-hosting test.
echo "[run] fixed-point test (bootstrap on its own source)"
/tmp/lazyc $CONCAT >/dev/null
cp ${CONCAT}.asm /tmp/stage2.asm
./lazyc-ref $CONCAT >/dev/null
cp ${CONCAT}.asm /tmp/stage1.asm
if diff -q /tmp/stage1.asm /tmp/stage2.asm > /dev/null; then
    LINES=$(wc -l < /tmp/stage1.asm)
    echo "  stage1 == stage2: byte-identical ($LINES lines of asm)"
    FP_OK=1
else
    echo "  stage1 != stage2: DIVERGED"
    diff /tmp/stage1.asm /tmp/stage2.asm | head -10
    FP_OK=0
fi

# Phase 4: build stage-2 binary, run it on the bootstrap source, check
# stage-3 asm == stage-2 asm.
echo "[run] stage-3 fixed-point test"
nasm -f elf64 /tmp/stage2.asm -o /tmp/stage2.o
ld /tmp/stage2.o runtime/runtime.o -o /tmp/lazyc_stage2
/tmp/lazyc_stage2 $CONCAT >/dev/null
cp ${CONCAT}.asm /tmp/stage3.asm
if diff -q /tmp/stage2.asm /tmp/stage3.asm > /dev/null; then
    echo "  stage2 == stage3: SELF-HOSTED FIXED POINT"
else
    echo "  stage2 != stage3: DIVERGED"
    FP_OK=0
fi

if [ $FAIL -gt 0 ] || [ $RJ_FAIL -gt 0 ] || [ $FP_OK -eq 0 ]; then
    if [ $FAIL -gt 0 ]; then
        echo "Differing accepted files:"
        for f in $ACCEPT_FAILS; do echo "  $f"; done
    fi
    exit 1
fi
echo
echo "all good — bootstrap is self-hosting."
