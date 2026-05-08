# lazyc — the bootstrap port

This directory holds the in-progress port of the lazyc compiler from C
into lazyc itself. The end goal is a self-hosting compiler: a lazyc
program that compiles its own source and produces byte-identical
assembly to what the C compiler produces from the same source.

## Status

**21a — substrate library (DONE).** A small library of helpers that
lazyc doesn't have built-in: string operations, a growable byte buffer
(`Buf`) for accumulating output, and a growable pointer-array (`PtrVec`)
for collections that would use `realloc` in C.

**21b — command-line arguments (DONE).** Added `argc()` and `argv(i)`
built-ins to the language so the bootstrap compiler can read its source
file path from the command line. Implemented as runtime helpers
(`lazyc_argc` / `lazyc_argv`) that capture argc/argv at `_start` entry,
plus typechecker + codegen entries that recognize the new built-in names.

**21c — skeleton main.ml (DONE).** A working `lazyc` binary built from
lazyc sources. It reads a source path from argv, calls a stubbed pipeline
(lex → parse → typecheck → codegen, each a no-op), and writes a placeholder
`.asm` file. The wiring is complete; subsequent substeps replace stubs
with real implementations one at a time.

**21d — lexer (DONE).** Real lexer in lazyc. Tokenizes the entire source
into a `TokenList` (a `PtrVec` of `Ptr<Token>`). Token kinds match the C
lexer exactly. Cross-checked against the C lexer on every test source in
the repo (235 files, 0 mismatches), including the bootstrap's own ~21KB
of source. The script `tools/cross-check-lexer.sh` runs the comparison.

**21e — expression parser (DONE).** Real parser for expressions only.
Operator precedence ladder (comparison → additive → term → unary →
primary + postfix), call/index/field postfix chains, `cast<T>(...)`.
Verified by extracting 100+ unique `return E;` expressions from the
real test corpus, then dumping the resulting AST in the same format as
the C compiler's `--ast-raw` output and diffing. **0 mismatches across
130+ distinct expression shapes.** Test driver in
`lazyc/tests/parse_expr.tail.ml`; cross-check in
`tools/cross-check-parse-expr.sh`.

**21f — statement and function parser (DONE).** Real `parse_program` that
takes a TokenList and returns a `Ptr<Program>` containing `Ptr<FuncDecl>`s.
Handles all statement kinds: var declarations, assignments, pointer/field/
index stores, if/else if/else, while, for, return, break, continue, blocks,
expression statements. Functions with parameters and bodies. Wired into
`main.ml` replacing `stub_parse`. Cross-checked against the C parser on
**107 mainline test files (0 mismatches)**, restricted to programs that
don't use structs or arrays (those land in 21g).

**21g — struct and array parser (DONE).** Adds `parse_struct_decl` with
field offset/alignment computation, the parser-side struct registry that
`parse_type` consults so identifiers resolve to known struct types, and
`wrap_with_array_suffix` so var decls and struct fields can use the
`Type name[N]` array form. `parse_program` now dispatches on `struct` vs
function decls at top level. Cross-checked against the C parser on the
**full mainline test corpus (157 pass, 0 fail)** — every non-rejection
test now produces byte-identical AST. As a stronger check, the bootstrap's
own ~2700-line source parses to an 8632-line AST that is also byte-
identical to the C parser's output. **The lazyc parser can now parse
its own source.**

**21h — typechecker (DONE).** Full typechecker for both expressions and
statements. Handles all expression kinds with their type rules: numeric
promotion, untyped-int and untyped-null coercion, pointer arithmetic,
struct field resolution, format-string validation for print/println,
and all built-ins (alloc/free/exit/readf/writef/argc/argv). Statement-
level checks include assignment compatibility, return-type matching,
condition-must-be-Boolean, break/continue inside loops, redeclaration,
duplicate field names, etc. Wired into `main.ml` replacing
`stub_typecheck`. **Cross-checked exhaustively against the C
typechecker:**

  * 157/157 accepted programs produce byte-identical post-typecheck
    AST output (i.e., same `ety` set on every Expr; same field
    resolutions; same constant-folding outcomes).
  * 67/67 rejection tests are correctly rejected (both compilers exit
    nonzero on the same set of programs).
  * Bootstrap's own ~4000-line source typechecks to a 13493-line AST
    that is byte-identical to the C compiler's. **The lazyc
    typechecker can now typecheck its own source.**

  Cross-check script: `tools/cross-check-typecheck.sh`. New file
  `lazyc/compiler/typecheck.ml` (~1100 lines) plus tail driver
  `lazyc/tests/tc_prog.tail.ml`. Also added `is_untyped_null` field
  to Expr and `types_equal` helper to types.ml.

**21i — typechecker polish (DONE).** A targeted hardening pass on top of
21h. The cross-check on the corpus + bootstrap source already showed
byte-identical AST output, but that test only catches divergences that
manifest in the AST. A careful read of the C compiler against the lazyc
port surfaced one semantic divergence that was AST-invisible:
`implicitly_assignable` in the C version updates `e->type` when coercing
an untyped integer literal but does NOT clear `is_untyped_int`; my port
was clearing the flag. The flag isn't read by the AST printer or codegen,
so the corpus cross-check missed it — but it would have caused stage-1
and stage-2 to diverge at the 21m fixed-point test. Fixed.

Beyond the fix, ~50 hand-crafted edge-case programs (literal boundaries
near each numeric type's range, pointer arithmetic, nested struct field
access, division by zero, `Boolean = 0`, mixed-sign arithmetic, etc.)
were all run through both compilers; every program agreed on accept/
reject, and all accepted programs produced byte-identical AST.

**21j+k+l — codegen (DONE).** The full codegen, ported from
`src/codegen.c` (1200 lines C → ~1600 lines lazyc) into one file
`lazyc/compiler/codegen.ml`. Three substeps landed together because
they're tightly coupled — the C codegen is one module that handles
expressions, statements, functions, and string-pool management as a
single unit. Splitting at file boundaries would have just added
ceremonial declarations.

The implementation mirrors the C version's emission order, label
numbering, and string interning protocol exactly — required because
the fixed-point test demands byte-identical output. Stack-machine
evaluation: every expression pushes its result; statements pop and
consume. Locals live in stack slots negative-indexed from rbp. String
literals are interned into two pools (raw `Lstr_*` for general use,
"cooked" `Lcstr_*` with escapes pre-decoded for `print`/`println`
fragments).

**Results:**
  * **157/157 accepted programs produce byte-identical .asm** — every
    single test in the mainline corpus codegen-matches the C compiler.
  * **67/67 rejection tests are correctly rejected** by both compilers.
  * **Bootstrap-on-itself: byte-identical 45,555-line .asm** — when the
    bootstrap binary (built via the C compiler) compiles its own
    source, the resulting assembly is identical to what the C compiler
    produces for the same input.
  * **Fixed point reached.** Building a stage-2 binary from that asm
    and running it against the bootstrap source produces stage-3 asm
    that is byte-identical to stage-2 asm.

  Required one fix to `lib/buf.ml`: the `buf_push_long` helper had a
  LONG_MIN bug — negating LONG_MIN overflows. Added a special case
  for the value to print it as a hardcoded string.

  Cross-check script: `tools/cross-check-codegen.sh`.

The bootstrap is structured as:
```
lazyc/lib/         strs.ml, buf.ml, ptrvec.ml      — substrate (21a)
lazyc/compiler/    types.ml                         — Type/Field/StructDef + helpers + types_equal (21h)
                     token.ml                         — Token struct + TOK_* constants (21d)
                     error.ml                         — die(), die_named(), etc.
                     lex.ml                           — lexer (21d)
                     ast.ml                           — Expr struct + EX_/OP_ constants (21e/21h)
                     stmt.ml                          — Stmt + Param + FuncDecl + Program (21f)
                     parse.ml                         — Parser state + expression parser (21e/21g)
                     parse_struct.ml                  — struct decl parser + type_align (21g)
                     parse_stmt.ml                    — statement + function parser (21f/21g)
                     ast_print.ml                     — expression AST printer (21e)
                     ast_print_stmt.ml                — statement + program AST printer (21f)
                     typecheck.ml                     — full typechecker (21h/21i)
                     codegen.ml                       — full codegen (21j+k+l)
                     main.ml                          — entry point
```

All files concatenated at build time by `build-lazyc.sh`. Order matters
because lazyc processes struct definitions in source order; types must
precede the code that uses them.

## Building and running

From the repo root:

```sh
make                                                 # builds the C compiler
make runtime/runtime.o                               # builds the runtime
./lazyc/build-lazyc.sh                           # builds the bootstrap binary
./lazyc/lazyc some-source.ml                     # compiles a source file
```

The bootstrap currently runs all stubs. The output asm at `<source>.ml.asm`
is a placeholder that exits 0 — once the lexer (21d) and beyond come
online, it'll be the real generated assembly.

### Substrate smoke test

```sh
./lazyc/build-substrate.sh lazyc/tests/substrate.tail.ml
./lazyc/substrate
```

Expected output ends with `ALL TESTS PASS` and exit code 0. The smoke
test exercises every helper in the substrate (66 individual checks).

## Why no `import`?

lazyc doesn't have multi-file support and we're deliberately not adding
it — the bootstrap is one program. The `build-substrate.sh` script just
concatenates `lib/strs.ml`, `lib/buf.ml`, `lib/ptrvec.ml`, and a tail
file (containing `main()`) into a single `.ml` file before compiling.

## What's next

**The bootstrap is self-hosting and is now the canonical compiler.**
All planned milestones (21a–21l) have landed, the implicit 21m
fixed-point test passes, and step 22 retired the C compiler from the
required-build path: `lazyc` builds itself from prebuilt asm via
`build.sh`, and the runtime is also written in lazyc (with a small
syscall trampoline asm stub).

The C compiler in `src/` remains in the tree as the absolute-scratch
bootstrap — anyone with `gcc + nasm + ld` can rebuild everything from
source — but it is no longer required for normal development.

**Step 22 — `extern` keyword + lazyc runtime (DONE).**

Added an `extern` keyword to lazyc in both compilers (C reference
and bootstrap). Syntax: `extern <return-type> <name>(<params>);`,
declares a function whose body is provided by the linker. The
compilers emit `extern <name>` in the asm header and skip codegen for
the declaration. Both compilers gained the same support; verified
the bootstrap still produces byte-identical asm on its own source
(45,888 lines).

With `extern` available, the runtime was rewritten. The new
`runtime/syscall.asm` is a ~50-line stub providing only:
  * `_start`: read argc/argv from the entry stack, call main, exit
  * `lazyc_argc`, `lazyc_argv`: read the argv state captured at entry
  * `lazyc_sys_*`: thin syscall trampolines (read, write, open, close,
    stat, mmap, munmap, exit)

Everything else — `lazyc_alloc`/`lazyc_free` (mmap-based allocator),
`lazyc_print_long`/`lazyc_print_int16`/`lazyc_print_char`/
`lazyc_print_string`/`lazyc_print_newline`, `lazyc_write_bytes`,
`lazyc_readf`/`lazyc_writef`, `lazyc_exit` — lives in
`runtime/runtime.ml` as plain lazyc code.

Verified:
  * Bootstrap (compiled with the C compiler) produces a binary that,
    when linked with the new runtime, is a fixed point: A == B == C
    across three stages, 45,888 lines of asm each.
  * All 157 mainline accept-tests execute identically with the new
    runtime as with the original hand-written assembly runtime.

Build entry point: top-level `build.sh`. Cross-check: `tools/full-check.sh`.

Possible follow-ups not currently scheduled:
- Polish the bootstrap's error messages to match the C compiler's
  varargs-rich format (cosmetic).
- Switch `lazyc` to write output via `writef` instead of buffering
  the whole asm in memory.
- Generalize `extern` to allow it for variable declarations too (would
  let the runtime expose the saved-argv globals as lazyc `extern`s
  instead of needing argc/argv to stay in assembly).
