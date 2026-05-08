# lazyc — Architecture Overview

This document describes the internals of the lazyc compiler and runtime
at the level needed by someone modifying the codebase. For language
syntax/semantics see [`../LANGUAGE.md`](../LANGUAGE.md).

---

## Two compilers

The repo contains two independent compilers that both compile lazyc
source to NASM assembly:

```
src/                         lazyc/
  main.c                       compiler/main.ml
  lexer.{c,h}                  compiler/lex.ml
  parser.{c,h}                 compiler/parse.ml + parse_struct.ml + parse_stmt.ml
  ast.h                        compiler/ast.ml + stmt.ml + types.ml + token.ml
  ast_print.c                  compiler/ast_print.ml + ast_print_stmt.ml
  symtab.{c,h}                 (inlined into codegen.ml)
  funcs.{c,h}                  (inlined into typecheck.ml)
  desugar.{c,h}                (very minimal; mostly inlined)
  typecheck.{c,h}              compiler/typecheck.ml
  codegen.{c,h}                compiler/codegen.ml
  types.{c,h}                  (inlined into types.ml)
```

The C compiler at `src/` is the **reference implementation** — written in
C, used to bootstrap the language in the first place. It is no longer
required for normal use; it stays in the tree as the absolute-scratch
bootstrap path.

The bootstrap compiler at `lazyc/` is **written in lazyc itself**,
self-hosting at three levels (compiler, runtime, build script). It
produces byte-identical assembly to the C reference for every program
in the test corpus.

The two implementations agree exactly. This is verified continuously:
`tools/full-check.sh` cross-compiles every test with both compilers
and diffs the output. Any divergence is a bug.

---

## Compilation pipeline

Both compilers follow the same five-phase pipeline:

```
source.ml
   │
   ▼
[lex]    → list of Tokens
   │
   ▼
[parse]  → AST (Program → FuncDecls → Stmts → Exprs, plus Structs)
   │
   ▼
[typecheck] → AST with `ety` (effective type) on every Expr,
              `field_resolved` on every EX_FIELD,
              and a validated set of FuncSigs
   │
   ▼
[codegen]   → NASM assembly text
   │
   ▼
output.asm
```

There is no IR — the codegen walks the typed AST directly.

### Phase 1: Lex

`lex.{c,ml}` consumes the source text and produces a flat list of
`Token`s. Each token has a kind (TOK_*), a slice of the source text,
and (for `TOK_NUMBER`) a parsed integer value.

The lexer is hand-written, single-pass, no backtracking. It recognizes:
- Whitespace and `//` comments (skipped)
- Numeric literals (decimal only)
- Character literals with `\` escapes
- String literals with `\` escapes (escapes are NOT decoded by the
  lexer; they're preserved in the token text and decoded later by the
  codegen)
- Identifiers, which are then matched against the keyword table to
  upgrade `TOK_IDENT` into a specific keyword token
- Punctuation and operators (longest-match: `<=` beats `<`)

### Phase 2: Parse

`parse.{c,ml}`, plus `parse_struct.ml` and `parse_stmt.ml` in the
bootstrap. Recursive-descent. Produces a `Program` AST.

The expression parser handles precedence with one function per level
(`parse_comparison` → `parse_additive` → `parse_term` → `parse_unary` →
`parse_primary`). Each level loops on left-associative operators.
Postfix `.` and `[]` are handled inside `parse_primary` after the atom.

The statement parser is more dispatch-heavy: peek the first token,
choose the right `parse_*_stmt` function. Statement boundaries are
explicit (`;` or `}`).

The struct parser handles field offset/alignment computation directly
during parsing, so by the time you have a `StructDef`, every field has
a final byte offset.

### Phase 3: Typecheck

`typecheck.{c,ml}`. Two passes:
1. **Collect signatures.** Walk all `FuncDecl`s and register them in a
   `FuncTab`. This is what lets functions call each other in any order.
2. **Check each body.** For each function, build a `TcCtx` (return type,
   funcs table, local variables), add parameters as locals, then
   `tc_stmt` the body.

`tc_stmt` and `tc_expr` recursively walk the AST. For each `Expr` they
set `e->ety` (the effective type) which the codegen later consults.

The trickiest piece is **untyped literal coercion**: integer literals
and `null` start with type `Long` / `Ptr<Byte>` but have an `is_untyped_int`
or `is_untyped_null` flag. Binary operators have a pre-pass that coerces
an untyped operand to its sibling's type if it fits. Assignment-like
contexts (`var = expr`, function arguments, return values) call
`implicitly_assignable` which performs the same kind of coercion.

The flag stays set after coercion (matching the C compiler's exact
behavior) — clearing it caused a fixed-point divergence and was fixed
in step 21i.

### Phase 4: Codegen

`codegen.{c,ml}`. Stack-machine evaluation: every expression pushes its
result on the runtime stack, every statement consumes pushed values.
This is wasteful but very simple — no register allocator, no
intermediate representation, no peephole optimization.

Per function, codegen does:
1. Compute parameter and local-variable offsets via `SymTab` (each
   variable gets a stack slot at `[rbp - offset]`).
2. Emit prologue: `push rbp; mov rbp, rsp; sub rsp, frame_size`.
3. Spill parameter registers into their stack slots.
4. Emit `gen_stmt(body)`.
5. Emit fall-through epilogue: `xor rax, rax; leave; ret`.

Control flow uses simple labels. `if`/`while`/`for` get a few `.L<N>:`
labels each, with `je` and `jmp` between them. Break/continue push the
target labels onto a `loop_stack` so nested loops work.

String literals are interned in two pools:
- `Lstr_<N>`: raw string literals (escape decoding deferred to
  emit-time)
- `Lcstr_<N>`: "cooked" fragments from format-string lowering, with
  escapes already decoded

Format-string lowering (`gen_format_call`) walks the format string at
compile time, splitting it into runs of literal text and `%X` specifiers.
For each literal run, intern as `Lcstr_<N>` and emit a
`call lazyc_write_bytes`. For each `%X`, evaluate the corresponding
arg, pop into `rdi`, and `call lazyc_print_<type>`.

### Phase 5: Output

The bootstrap buffers the entire asm in memory (`Ptr<Buf>`) and writes
it once via `writef`. The C compiler streams to a `FILE*`. Either way,
the output is `<source>.asm`.

---

## Runtime contract

The runtime (`build/runtime.o`) provides everything the compiler-emitted
asm references via `extern`:

```
_start                                   — ELF entry point
lazyc_argc, lazyc_argv                 — argv accessors

lazyc_print_newline, lazyc_print_char,
lazyc_print_int16, lazyc_print_long,
lazyc_print_string                      — format-spec lowering targets
lazyc_write_bytes                       — raw byte output

lazyc_alloc, lazyc_free                — heap
lazyc_exit                              — process exit

lazyc_readf, lazyc_writef              — file I/O
```

The first three (`_start`, `lazyc_argc`, `lazyc_argv`) and the
syscall trampolines (`lazyc_sys_*`) are in `runtime/syscall.asm`.
Everything else is in `runtime/runtime.ml`, written in lazyc.

The `_start` routine reads argc/argv from the entry stack, saves them
in `.bss` globals, calls `main`, and uses main's return value as the
process exit code. lazyc user code accesses argc/argv via the
`argc()` and `argv(i)` built-ins, which the codegen lowers to direct
calls to the runtime accessors.

---

## Bootstrap relationship

The bootstrap is structured as concatenated lazyc source files. The
canonical concatenation order is in `lazyc/build-lazyc.sh` (and
implicitly in the prebuilt asm).

```
lib/strs.ml lib/buf.ml lib/ptrvec.ml      — substrate
compiler/types.ml compiler/token.ml
compiler/error.ml compiler/lex.ml
compiler/ast.ml compiler/stmt.ml
compiler/parse.ml compiler/parse_struct.ml
compiler/parse_stmt.ml
compiler/ast_print.ml compiler/ast_print_stmt.ml
compiler/typecheck.ml compiler/codegen.ml
compiler/main.ml
```

Concatenation order matters because lazyc has no module system.
`lib/` defines low-level data structures (`Buf`, `PtrVec`, string
helpers); `compiler/` builds on top of them.

The bootstrap is verified to be a fixed point: feeding it its own
source must produce byte-identical asm to what the prebuilt was built
from. `build.sh` checks this at every build.

---

## How to add a feature

To add a new language feature, the change typically touches four
places per compiler (so eight files when both are kept in sync):

1. **Lexer**: new token kind for any new keyword/operator.
2. **Parser**: how the new syntax is parsed; AST changes.
3. **Typechecker**: type rules for the new construct.
4. **Codegen**: how to lower it to assembly.

Plus often:

5. **AST printer**: so `--ast` and `--ast-raw` show the new construct
   correctly. (Important for cross-checking.)

Recipe for keeping both compilers in sync:
1. Make the change in the C compiler first.
2. Verify the C compiler still passes `tools/cross-check-codegen.sh`
   (every test still produces byte-identical asm with the bootstrap,
   because the new feature isn't used yet).
3. Mirror the change in the bootstrap.
4. Verify the bootstrap still produces byte-identical asm to the C
   compiler.
5. Verify the fixed-point property still holds (bootstrap compiling
   its own source produces byte-identical output).
6. Now write tests that exercise the new feature.
7. Verify the new tests work in both compilers.

This was the recipe for adding `extern` in step 22.

---

## Why no IR?

A real production compiler would have an SSA-like intermediate
representation between AST and codegen, with passes for inlining,
constant propagation, register allocation, etc. lazyc has none of
these.

The reason: educational simplicity. The pipeline is:
- AST → asm: walk the tree, emit asm. ~1600 lines of lazyc.

If we added an IR:
- AST → IR: build IR from AST. ~500 lines.
- IR passes: many. ~thousands.
- IR → asm: register allocator. ~hundreds.

That's appropriate for production but obscures the core compilation
machinery. lazyc trades performance for legibility.

The cost is real: the emitted code is roughly 5-10× slower than what
gcc -O0 produces, due to the stack-machine evaluation strategy. But
it's still fast enough that the bootstrap (~5,700 lines of lazyc)
self-compiles in under a second on commodity hardware.

---

## Testing strategy

Three cross-checks, all in `tools/`:

- `cross-check-codegen.sh`: every test program's `.asm` must be
  byte-identical between both compilers, and rejection tests must be
  rejected by both. This catches semantic divergence.
- `full-check.sh`: above, plus runtime equivalence (every test program
  must execute identically against both the new and old runtimes), plus
  the three-stage fixed-point check (A == B == C across recursive
  self-compilation).

The test corpus is in `tests/`. Files matching `*fail*.ml` are
expected-to-fail tests. The rest are expected-to-compile-and-run tests.

To run all of them, the C compiler runner is `tools/run_all.py`. It
uses the C compiler (`./lazyc-ref`) plus `nasm` plus `ld` to actually
compile, link, and run each test, then compares stdout and exit code
against expected values embedded in the test source as comments.
