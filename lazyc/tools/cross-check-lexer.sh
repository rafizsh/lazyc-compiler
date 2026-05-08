#!/bin/bash
# tools/cross-check-lexer.sh — verify the lazyc-written lexer agrees with
# the C-written lexer on token output.
#
# This is a partial fixed-point test for 21d: it ensures the lexer's
# behavior is byte-identical between the two implementations on every
# test source we have. Later substeps (21e+) will add similar checks for
# parser, typechecker, and codegen.
#
# Usage: tools/cross-check-lexer.sh

set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# Build prerequisites if missing.
if [ ! -x ./lazyc-ref ]; then
    echo "[build] lazyc"
    make >/dev/null
fi
if [ ! -f runtime/runtime.o ]; then
    echo "[build] runtime"
    make runtime/runtime.o >/dev/null 2>&1 || true
fi

# Build the C-side lextest if missing.
if [ ! -x /tmp/lextest_c ]; then
    echo "[build] /tmp/lextest_c"
    gcc -o /tmp/lextest_c "$ROOT/lextest_c.c" "$ROOT/src/lexer.c"
fi

# Build the lazyc-side lextest by concatenating its tail with the
# substrate + lex files.
echo "[build] /tmp/lextest_ml"
CONCAT=/tmp/lextest_ml.combined.ml
cat lazyc/lib/strs.ml \
    lazyc/lib/buf.ml \
    lazyc/lib/ptrvec.ml \
    lazyc/compiler/types.ml \
    lazyc/compiler/token.ml \
    lazyc/compiler/error.ml \
    lazyc/compiler/lex.ml \
    lazyc/tests/lex.tail.ml > $CONCAT
./lazyc-ref $CONCAT >/dev/null
nasm -f elf64 ${CONCAT}.asm -o /tmp/lextest_ml.o
ld /tmp/lextest_ml.o runtime/runtime.o -o /tmp/lextest_ml

# Compare on every .ml file under tests/ and lazyc/.
PASS=0
FAIL=0
FAILURES=""
for f in tests/*.ml lazyc/lib/*.ml lazyc/compiler/*.ml lazyc/tests/*.ml; do
    /tmp/lextest_ml "$f" > /tmp/ml_out.txt 2>/dev/null
    /tmp/lextest_c  "$f" > /tmp/c_out.txt  2>/dev/null
    if diff -q /tmp/ml_out.txt /tmp/c_out.txt > /dev/null 2>&1; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        FAILURES="$FAILURES $f"
    fi
done

echo
echo "lexer cross-check: $PASS files match, $FAIL differ"
if [ $FAIL -ne 0 ]; then
    echo "differing files:"
    for f in $FAILURES; do echo "  $f"; done
    exit 1
fi
