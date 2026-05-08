#!/bin/bash
# tools/full-check.sh — exhaustive end-to-end verification.
#
# Runs every check we have: corpus asm-equivalence, corpus exec-equivalence,
# self-hosting fixed point, three-stage fixed point with the new runtime.
#
# Requires nasm, ld. The C compiler (./lazyc-ref) must be built; we use it
# for cross-checking.
#
# Usage: tools/full-check.sh

set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [ ! -x ./lazyc-ref ]; then
    echo "[build] C compiler"
    make >/dev/null
fi
if [ ! -x build/lazyc ]; then
    echo "[build] lazyc"
    ./build.sh >/dev/null
fi

echo "[1/4] codegen accept-tests: byte-identical asm"
PASS=0; FAIL=0; FAILS=""
for f in tests/*.ml; do
    case "$f" in *_fail*.ml|*fail_*.ml) continue;; esac
    build/lazyc "$f" > /dev/null 2>&1 || { FAIL=$((FAIL+1)); FAILS="$FAILS $f"; continue; }
    cp "$f.asm" /tmp/m.asm
    ./lazyc-ref "$f" > /dev/null 2>&1
    if diff -q "$f.asm" /tmp/m.asm > /dev/null; then
        PASS=$((PASS+1))
    else
        FAIL=$((FAIL+1)); FAILS="$FAILS $f"
    fi
done
echo "  $PASS pass, $FAIL fail"

echo "[2/4] reject-tests: both compilers reject"
RJ_PASS=0; RJ_FAIL=0
for f in tests/*fail*.ml; do
    build/lazyc "$f" > /dev/null 2>&1; ml=$?
    ./lazyc-ref "$f" > /dev/null 2>&1; c=$?
    if [ $ml -ne 0 ] && [ $c -ne 0 ]; then
        RJ_PASS=$((RJ_PASS+1))
    else
        RJ_FAIL=$((RJ_FAIL+1))
    fi
done
echo "  $RJ_PASS pass, $RJ_FAIL fail"

echo "[3/4] runtime equivalence: every program executes the same"
EQ_PASS=0; EQ_FAIL=0
for f in tests/*.ml; do
    case "$f" in *_fail*.ml|*fail_*.ml) continue;; esac
    ./lazyc-ref "$f" > /dev/null 2>&1
    nasm -f elf64 "$f.asm" -o /tmp/t.o 2>/dev/null || continue
    ld /tmp/t.o build/runtime.o -o /tmp/t_new 2>/dev/null
    ld /tmp/t.o runtime/runtime.o -o /tmp/t_old 2>/dev/null
    out_new=$(timeout 5 /tmp/t_new 2>&1); rc_new=$?
    out_old=$(timeout 5 /tmp/t_old 2>&1); rc_old=$?
    # Normalize the binary path that may appear in argv[0].
    out_new_n=$(echo "$out_new" | sed "s|/tmp/t_new|BIN|g")
    out_old_n=$(echo "$out_old" | sed "s|/tmp/t_old|BIN|g")
    if [ "$out_new_n" = "$out_old_n" ] && [ "$rc_new" = "$rc_old" ]; then
        EQ_PASS=$((EQ_PASS+1))
    else
        EQ_FAIL=$((EQ_FAIL+1))
    fi
done
echo "  $EQ_PASS pass, $EQ_FAIL fail"

echo "[4/4] three-stage fixed point with new runtime"
cat lazyc/lib/strs.ml lazyc/lib/buf.ml lazyc/lib/ptrvec.ml \
    lazyc/compiler/types.ml lazyc/compiler/token.ml lazyc/compiler/error.ml \
    lazyc/compiler/lex.ml lazyc/compiler/ast.ml lazyc/compiler/stmt.ml \
    lazyc/compiler/parse.ml lazyc/compiler/parse_struct.ml lazyc/compiler/parse_stmt.ml \
    lazyc/compiler/ast_print.ml lazyc/compiler/ast_print_stmt.ml \
    lazyc/compiler/typecheck.ml lazyc/compiler/codegen.ml \
    lazyc/compiler/main.ml > /tmp/canon.ml
build/lazyc /tmp/canon.ml > /dev/null
cp /tmp/canon.ml.asm /tmp/A.asm
nasm -f elf64 /tmp/A.asm -o /tmp/A.o
ld /tmp/A.o build/runtime.o -o /tmp/A.bin
/tmp/A.bin /tmp/canon.ml > /dev/null
cp /tmp/canon.ml.asm /tmp/B.asm
nasm -f elf64 /tmp/B.asm -o /tmp/B.o
ld /tmp/B.o build/runtime.o -o /tmp/B.bin
/tmp/B.bin /tmp/canon.ml > /dev/null
cp /tmp/canon.ml.asm /tmp/C.asm
diff -q /tmp/A.asm /tmp/B.asm > /dev/null && AB=1 || AB=0
diff -q /tmp/B.asm /tmp/C.asm > /dev/null && BC=1 || BC=0
LINES=$(wc -l < /tmp/A.asm)
if [ $AB -eq 1 ] && [ $BC -eq 1 ]; then
    echo "  A==B==C ($LINES lines): SELF-HOSTED"
else
    echo "  diverged"
fi

echo
if [ $FAIL -eq 0 ] && [ $RJ_FAIL -eq 0 ] && [ $EQ_FAIL -eq 0 ] && [ $AB -eq 1 ] && [ $BC -eq 1 ]; then
    echo "all good. lazyc is fully self-hosting with the new runtime."
    exit 0
else
    echo "FAILURES detected"
    if [ -n "$FAILS" ]; then
        for f in $FAILS; do echo "  asm-mismatch: $f"; done
    fi
    exit 1
fi
