#!/bin/bash
# tools/cross-check-parse-expr.sh — verify the lazyc expression parser
# agrees with the C parser. Builds the parse_expr test binary, then
# extracts every "return E;" expression from the test corpus and compares
# the resulting AST dumps.
#
# Usage: tools/cross-check-parse-expr.sh

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

# Build the lazyc-side parse_expr test binary.
echo "[build] parse_expr_bin"
CONCAT=/tmp/parse_expr.combined.ml
cat lazyc/lib/strs.ml \
    lazyc/lib/buf.ml \
    lazyc/lib/ptrvec.ml \
    lazyc/compiler/types.ml \
    lazyc/compiler/token.ml \
    lazyc/compiler/error.ml \
    lazyc/compiler/lex.ml \
    lazyc/compiler/ast.ml \
    lazyc/compiler/parse.ml \
    lazyc/compiler/ast_print.ml \
    lazyc/tests/parse_expr.tail.ml > $CONCAT
./lazyc-ref $CONCAT >/dev/null
nasm -f elf64 ${CONCAT}.asm -o /tmp/parse_expr.o
ld /tmp/parse_expr.o runtime/runtime.o -o /tmp/parse_expr_bin

python3 << 'PYEOF'
import re, pathlib, subprocess, sys

cases = set()
for p in list(pathlib.Path("tests").glob("*.ml")) + \
         list(pathlib.Path("lazyc/lib").glob("*.ml")) + \
         list(pathlib.Path("lazyc/compiler").glob("*.ml")) + \
         list(pathlib.Path("lazyc/tests").glob("*.ml")):
    src = p.read_text()
    i = 0
    while i < len(src):
        m = re.search(r'\breturn\b\s+', src[i:])
        if not m: break
        start = i + m.end()
        depth = 0
        j = start
        while j < len(src):
            c = src[j]
            if c in '([{': depth += 1
            elif c in ')]}': depth -= 1
            elif c == ';' and depth == 0: break
            j += 1
        if j >= len(src): break
        expr = src[start:j].strip()
        if expr and '\n' not in expr and len(expr) < 200:
            cases.add(expr)
        i = j + 1

# Add hand-written cases too.
HAND = [
    "1", "1+2", "1+2*3", "(1+2)*3", "a==b", "a!=b", "-x", "!x", "&y", "*p",
    "foo()", "foo(1)", "foo(1,2,3)", "arr[0]", "arr[i+1]", "s.field",
    "(*p).field", "cast<Long>(x)", "cast<Ptr<Byte>>(p)", "cast<Ptr<Ptr<Long>>>(q)",
    "true", "false", "null", "'a'", "'\\n'", "\"hello\"", "matrix[i][j]",
    "&arr[0]", "*p+1", "-x*y", "foo(1+2,x*3)", "((((42))))",
]
cases.update(HAND)

cases = sorted(cases)
print(f"[run] {len(cases)} expressions to check")

pass_n = fail_n = 0
mismatches = []
for expr in cases:
    src = f"Long _expr_test() {{ return {expr}; }}\n"
    pathlib.Path("/tmp/cur.ml").write_text(src)
    r1 = subprocess.run(["/tmp/parse_expr_bin", "/tmp/cur.ml"],
                        capture_output=True, text=True)
    r2 = subprocess.run(["./lazyc-ref", "--ast-raw", "/tmp/cur.ml"],
                        capture_output=True, text=True)
    c_out = "\n".join(line[6:] for line in r2.stdout.splitlines()[3:]) + "\n"
    if r1.returncode != 0 and r2.returncode != 0:
        pass_n += 1
        continue
    if r1.returncode != r2.returncode:
        fail_n += 1
        mismatches.append((expr, f"rc disagree (ml={r1.returncode} c={r2.returncode})"))
        continue
    if r1.stdout == c_out:
        pass_n += 1
    else:
        fail_n += 1
        mismatches.append((expr, "ast differs"))

print(f"PASS: {pass_n}  FAIL: {fail_n}")
if fail_n:
    for expr, why in mismatches:
        print(f"  [{expr}]: {why}")
    sys.exit(1)
PYEOF
