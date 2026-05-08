# lazyc

A small C-like programming language that compiles to x86-64 NASM assembly,
then through `nasm` and `ld` to a Linux ELF executable.

The canonical compiler `lazyc` is **self-hosted** — written in lazyc
itself, compiling its own source byte-identically. The runtime is also
written in lazyc, with about 50 lines of assembly providing the
`_start` entry point and raw syscall trampolines.

The repo also still contains the original C compiler (`src/*.c`) which
was used to bootstrap the language in the first place. It's not needed
for normal use, but it remains in the tree as the absolute-scratch
bootstrap path: anyone with just `gcc` + `nasm` + `ld` can rebuild the
entire toolchain from scratch and verify that `lazyc` produces
byte-identical output to the C reference compiler.

## Documentation

- **[`LANGUAGE.md`](LANGUAGE.md)** — complete language reference: every
  type, every operator, every built-in, every gotcha. The canonical
  document for writing lazyc code.
- **[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)** — compiler
  internals: pipeline phases, AST shape, codegen strategy, bootstrap
  relationship, how to add a feature.
- **[`docs/COOKBOOK.md`](docs/COOKBOOK.md)** — 15 worked examples
  covering common tasks (linked lists, dynamic buffers, file I/O,
  parsing, sorting, multi-dimensional data, etc.).
- **[`BUILD-AND-RUN.md`](BUILD-AND-RUN.md)** — build instructions and
  pipeline details.
- **[`runtime/README.md`](runtime/README.md)** — runtime structure
  (assembly stub vs lazyc code).
- **[`lazyc/README.md`](lazyc/README.md)** — bootstrap compiler
  development history (steps 21a–22).
- **[`bim/README.md`](bim/README.md)** — bim, a small vim-like text
  editor written in lazyc (~750 lines, demonstrates the language is
  capable of a real interactive program).

## Quick start

If you just want to use `lazyc`:
```sh
./build.sh
build/lazyc your_program.ml
nasm -f elf64 your_program.ml.asm -o your_program.o
ld your_program.o build/runtime.o -o your_program
./your_program
```

`build.sh` requires only `nasm` and `ld`. It bootstraps from the
prebuilt asm in `lazyc/prebuilt/` and `runtime/prebuilt/`, then
verifies the resulting binary is a fixed point of itself.

To rebuild from absolute scratch, including the C reference compiler:
```sh
make            # builds the C compiler (./lazyc-ref)
./build.sh      # builds lazyc using the prebuilts
tools/full-check.sh   # full equivalence + fixed-point verification
```

## Quick taste

```lazyc
struct Node {
    Long value;
    Ptr<Node> next;
}

Long sum_list(Ptr<Node> head) {
    Long total = 0;
    Ptr<Node> cur = head;
    while (cur != null) {
        total = total + (*cur).value;
        cur = (*cur).next;
    }
    return total;
}

Long main() {
    Node a;
    Node b;
    Node c;
    a.value = 1;   a.next = &b;
    b.value = 10;  b.next = &c;
    c.value = 100; c.next = null;

    Long total = sum_list(&a);
    println("sum = %l", total);
    return 0;
}
```

Every feature in that example — structs, self-referential pointer fields,
field-through-pointer access, format-string `println`, signed types,
`null` literals, `&`-of-variable, `while` loops — is built from the ground
up by the compiler.

## Pipeline

```
foo.ml --[lazyc]--> foo.ml.asm --[nasm]--> foo.o --[ld + runtime.o]--> foo
```

The compiler is a single-pass front end (lex → parse → typecheck → codegen)
producing NASM Intel-syntax x86-64 assembly. The assembler and linker are
standard system tools. A small NASM runtime (`runtime/runtime.asm`)
provides the entry point and a handful of helpers (system calls, integer
formatting, heap allocator).

# Language reference

## Types

The type system is the spine of the language. There are three categories:
primitive integer-shaped types, the `String` and `Ptr<T>` reference types,
and user-defined structs.

### Primitive types

| Type      | Size | Signed?  | Range                                      | Notes                  |
|-----------|------|----------|--------------------------------------------|------------------------|
| `Boolean` | 1B   | n/a      | `false`/`true`                             | Stored as 0 or 1       |
| `Char`    | 1B   | n/a      | ASCII (0..127)                             | Character literals     |
| `Byte`    | 1B   | unsigned | 0..255                                     | Raw byte               |
| `Integer` | 2B   | signed   | -32768..32767                              |                        |
| `uInteger`| 2B   | unsigned | 0..65535                                   |                        |
| `Whole`   | 4B   | signed   | -2^31 .. 2^31-1                            |                        |
| `uWhole`  | 4B   | unsigned | 0 .. 2^32-1                                |                        |
| `Long`    | 8B   | signed   | -2^63 .. 2^63-1                            | The default integer    |
| `uLong`   | 8B   | unsigned | 0 .. 2^64-1                                |                        |
| `String`  | 8B   | n/a      | Pointer to Char array (read-only literals) | See **Strings** below  |

### Compound types

| Type        | Size    | Notes                                    |
|-------------|---------|------------------------------------------|
| `Ptr<T>`    | 8B      | Typed pointer; `T` may be any other type, including another `Ptr<T>` (recursive) or a struct |
| `struct Foo`| varies  | Named record with named fields, C-style layout |
| `T[N]`      | N*sizeof(T) | Fixed-size array; `N` is a compile-time integer literal |

`Ptr<T>` is fully recursive — `Ptr<Ptr<Long>>` is a valid type with all
the expected operations. Arrays are first-class types: `Long[10]` and
`Long[20]` are different (incompatible) types. Arrays don't decay to
pointers automatically — write `&arr[0]` to get a `Ptr<T>`.

### Implicit conversions

Strict by design. The implicit conversions are:

1. **Identical types**: always assignable.
2. **Untyped int literal → integer target**: a numeric literal like `42`
   is "untyped" until placed in context. It coerces to any integer-shaped
   target whose range fits. `Byte b = 200;` works (200 fits in 0..255).
   `Byte b = 300;` is rejected at compile time.
3. **Untyped null → any pointer**: `null` is untyped until it sees a
   pointer context. `Ptr<Node> p = null;` works.
4. **Same-signed numeric widening**: `Integer → Long` is implicit.
   `Whole → Long` is implicit. `Byte → uWhole` is implicit (both unsigned).
5. **Everything else needs `cast<T>(x)`**: signed↔unsigned, narrowing,
   pointer↔pointer of different pointee types, `String ↔ Ptr<Byte>`.

Casts are explicit and enforce a small whitelist:

- Numeric ↔ numeric: any combination, with truncation/sign-extension
  applied at runtime where appropriate.
- `Ptr<A> ↔ Ptr<B>`: always allowed (raw reinterpretation, like C void
  pointers).
- `String ↔ Ptr<Byte>`: allowed in both directions (no-op at the asm
  level — same size, same bit pattern).
- `String ↔ anything-else`: rejected. You must go through `Ptr<Byte>`.

### Type literals

| Literal        | Type             |
|----------------|------------------|
| `42`           | untyped int      |
| `'a'`          | `Char`           |
| `"hello"`      | `String`         |
| `true`/`false` | `Boolean`        |
| `null`         | untyped null     |

Untyped literals get their final type from context. `Byte b = 5;` makes
`5` a `Byte`; `Long n = 5;` makes the same `5` a `Long`. If there's no
context (e.g. `5;` as a statement), the literal defaults to `Long`.

## Operators

### Arithmetic (numeric only)

| Op  | Description       |
|-----|-------------------|
| `+` | Addition          |
| `-` | Subtraction       |
| `*` | Multiplication    |
| `/` | Division          |
| `%` | Modulo            |

Mixed-type arithmetic auto-promotes within the same signedness class and
is rejected across signedness — e.g. `Long + uLong` is a typecheck error;
use `cast<>` to disambiguate.

### Pointer arithmetic

| Op                | Result            | Effect                                        |
|-------------------|-------------------|-----------------------------------------------|
| `Ptr<T> + Long`   | `Ptr<T>`          | Advance by `n * sizeof(T)`                    |
| `Long + Ptr<T>`   | `Ptr<T>`          | Same (commutative)                            |
| `Ptr<T> - Long`   | `Ptr<T>`          | Retreat                                       |
| `Ptr<T> - Ptr<T>` | `Long`            | Number of `T`s between two same-typed pointers |

Multiplication, division, and modulo on pointers are typecheck errors.

### Comparison

| Op  | Description |
|-----|-------------|
| `==`, `!=` | Equality |
| `<`, `>`, `<=`, `>=` | Ordering |

For pointers, ordering is **unsigned** (so that comparing addresses
behaves sensibly). For numeric types, signedness is determined by the
operand types and the correct `setl`/`setb`/etc. variant is emitted.

Pointer equality requires same pointee type. Pointer ordering requires
same pointee type.

### Logical

| Op  | Operand types     | Notes                       |
|-----|-------------------|-----------------------------|
| `!` | `Boolean`         | Logical negation            |

`&&` and `||` are **not implemented**. Use nested `if` statements with
`Boolean` flags instead:

```lazyc
Boolean both = false;
if (cond_a) { if (cond_b) { both = true; } }   // a && b
if (cond_a) { both = true; }
if (cond_b) { both = true; }                    // a || b
```

The arithmetic short-circuit form is a nice-to-have that hasn't been
needed yet.

### Pointer operations

| Syntax    | Meaning                        | Result type           |
|-----------|--------------------------------|-----------------------|
| `&x`      | Address of variable            | `Ptr<TypeOf(x)>`      |
| `&s.f`    | Address of field               | `Ptr<TypeOf(f)>`      |
| `&(*p).f` | Address of field via pointer   | `Ptr<TypeOf(f)>`      |
| `*p`      | Dereference pointer            | `TypeOf(*p)`          |
| `*p = e`  | Write through pointer          | (statement)           |

Note: `&` requires an lvalue — variables, struct fields, and field-through-pointer
expressions are lvalues. Function call results, literals, and arithmetic
expressions are not.

### Cast

```lazyc
cast<TargetType>(expr)
```

See **Implicit conversions** above for the rules.

## Statements

### Variable declarations

```lazyc
Long x;             // zero-initialized
Long y = 42;        // with initializer
Ptr<Node> head = null;
struct Foo f;       // struct local, all fields zero
```

Scoping is **flat per function** — no shadowing, no nested scopes. A name
declared anywhere in a function is in scope from that point until the end
of the function. Re-declaring an existing name is a compile error.

### Assignment

```lazyc
x = expr;            // simple variable
*p = expr;           // through pointer
s.field = expr;      // struct field
(*p).field = expr;   // field through pointer-to-struct
```

### Control flow

```lazyc
if (cond) { ... }
if (cond) { ... } else { ... }
if (cond) { ... } else if (cond2) { ... } else { ... }

while (cond) { ... }

for (init; cond; step) { ... }
```

The `init` clause of a `for` may be a variable declaration *or* an
assignment, both syntactically inside the parentheses.

**`else if` chains** are sugar for nested if-else: after `else`, the
parser accepts either a brace-block or another `if` statement. There's
no limit to chain length.

**`break`** exits the innermost enclosing loop (`while` or `for`).
**`continue`** skips to the next iteration. For a `while`, that means
re-evaluating the condition; for a `for`, that means running the
step expression and then re-evaluating the condition (so the step is
*not* skipped on continue, matching C semantics).

```lazyc
for (Long i = 0; i < 10; i = i + 1) {
    if (i == 3) { continue; }   // skip 3, but still run i = i + 1
    if (i == 7) { break; }      // exit loop entirely
    println("i = %l", i);
}
```

Both `break` and `continue` outside any loop are typecheck errors. They
only target the innermost enclosing loop — there's no labeled-break.

### Return

```lazyc
return expr;       // exit the function with a value of the declared return type
```

Every function declares a return type and must return a value of that type.
A bare `return;` is not valid — there's no `Void` return type yet. For
helpers that don't have a meaningful result, declare `Long` and `return 0;`.

### Block

`{ stmt; stmt; ... }` groups statements. Unlike C, blocks don't introduce
a scope (because lazyc has flat per-function scoping).

### Expression statement

Any expression followed by `;` becomes a statement, primarily for
function calls used for their side effects.

## Functions

```lazyc
ReturnType functionName(ParamType1 p1, ParamType2 p2, ...) {
    body
}
```

Constraints:
- Up to **6 parameters** (no stack-passed args yet)
- Return type can be any type, *except* struct-by-value (use `Ptr<Struct>`)
- Parameters are passed in `rdi, rsi, rdx, rcx, r8, r9` per the System V
  AMD64 ABI
- No `Void` return type — for side-effect-only functions, return `Long` and
  `return 0;`

Functions are visible from anywhere in the compilation unit (no forward
declarations needed). The compiler does a Pass A over all declarations to
build a function signature table before typechecking bodies.

## Structs

```lazyc
struct Token {
    Long kind;
    Ptr<Byte> text;
    Long length;
    Long line;
}
```

Layout is **C-style natural alignment**:
- Fields appear in declaration order
- Each field is placed at the next offset divisible by its alignment
- Struct alignment is the maximum of its fields' alignments
- Total size is rounded up to that alignment

Example: `struct { Char c; Long x; }` occupies 16 bytes — `c` at offset 0,
7 bytes of padding, `x` at offset 8.

### Struct features by substep

The struct system was built in five substeps. All five are complete:

- **16a — Type plumbing.** `struct Foo { ... }` parses, `Foo` is usable
  as a type in declarations, struct locals get correctly-sized stack
  slots, zero-initialized at declaration. `&struct_var` produces
  `Ptr<Struct>`. Direct self-reference forbidden; `Ptr<Self>` works (for
  linked structures, ASTs).

- **16b — Field reads.** `s.field` reads a field's value with proper
  sized/signed loads (1B, 2B, 4B, 8B). Restricted to `EX_IDENT.field`.

- **16c — Field writes.** `s.field = expr;` writes a value to a field
  with matching-width stores.

- **16d — Address-of-field.** `&s.field` produces `Ptr<FieldType>`. Plays
  nicely with pointer arithmetic: `&p.y - &p.x` returns 1 (count of
  `Long`s), not 8 (raw bytes).

- **16e — Through-pointer access.** `(*p).field` reads, `(*p).field = e`
  writes, `&(*p).field` takes the address. Together with prior substeps,
  this enables linked-list traversal, heap-allocated record building, and
  pulling a `Ptr<Node>` out of a field then dereferencing it
  (`(*node.next).value`).

What's still **not** supported in structs (deferred indefinitely; not
needed for bootstrap):

- Chained access through nested **struct-valued** fields like
  `outer.inner.x` where `inner` is itself a struct (not a pointer).
  Workaround: `(*&outer.inner).x` — explicit address-then-deref.

## Arrays

```lazyc
Long buf[10];          // local array of 10 Longs, zero-initialized
Char text[256];        // 256-byte char buffer
```

Arrays are fixed-size in their type: `Long[10]` and `Long[20]` are
different types and not assignment-compatible. The size `N` must be a
positive compile-time integer literal.

**Indexing.** `arr[i]` is a postfix operator producing an lvalue (you can
read it, write it, or take its address). The address calculation is
`base + i * sizeof(T)`. No bounds checking — out-of-bounds is undefined.

`arr[i]` works on both `T[N]` and `Ptr<T>`. For pointers, this is
equivalent to `*(p + i)`. So you can write:

```lazyc
Long buf[10];
buf[3] = 42;          // array indexing

Ptr<Long> p = &buf[0];
p[3] = 99;            // pointer indexing — same memory location
```

**Address-of-element.** `&arr[i]` produces `Ptr<T>` pointing at the
element. This is the canonical way to "decay" an array to a pointer —
explicit, not implicit.

**Arrays in structs.** Allowed:

```lazyc
struct Vec {
    Long data[100];
    Long len;
}
```

**No arrays in function signatures.** Arrays cannot be passed by value or
returned. Use `Ptr<T>` instead, with explicit `&arr[0]` at the call site.

**No initializers yet.** `Long buf[3] = ...` is rejected. Write each
element with `buf[i] = ...` after the declaration.

**Arrays of structs / nested arrays as value.** `arr[i]` where the
element type is a struct or another array is rejected as a value
expression (would require copying an aggregate). Take `&arr[i]` to get a
pointer and access fields through it.

`String` is a typed pointer to a read-only Char buffer. String literals
end up in the `.rodata` section and are zero-terminated. The runtime's
print helpers walk until the null byte.

`String` and `Ptr<Byte>` are bidirectionally castable (as no-ops, since
they have the same representation), so reading file contents with
`readf()` (which returns `Ptr<Byte>`) and printing them with
`print("%s", ...)` just needs `cast<String>(buf)` at the boundary.

There are **no string operations in the language proper** — no
concatenation, no length, no substring. These are deferred to step 19,
where they'll be written *in lazyc* using the heap and arrays.

# Built-in functions

Every built-in is special-cased by name in the typechecker and codegen.
The runtime (`runtime/runtime.asm`) provides the actual implementations
as small assembly routines.

## Formatted output

| Name | Signature | Description |
|---|---|---|
| `print(fmt, args...)` | format string + values | No trailing newline |
| `println(fmt, args...)` | format string + values | Appends `\n` |

Format specifiers: `%c` Char, `%i` Integer, `%l` Long, `%s` String,
`%%` literal `%`.

Format strings must be **string literals** (validated at compile time —
type, count, and order of arguments must match). The compiler slices the
format string at compile time and emits one runtime call per segment, so
there's no runtime varargs machinery.

## Heap and process control

| Name         | Signature             | Description |
|--------------|-----------------------|-------------|
| `alloc(n)`   | `Long → Ptr<Byte>`    | Allocates `n` bytes; returns `null` on failure |
| `free(p)`    | `Ptr<Byte> → Boolean` | Frees an alloc'd block; returns `true` on success |
| `exit(code)` | `Long → (never)`      | Terminates the program with the given exit code |

The heap is mmap-backed, page-granular. Each block has an 8-byte size
header before the user pointer (so `free` can reverse the mapping).
`alloc` always returns `Ptr<Byte>`; use `cast<Ptr<T>>(p)` to view the
buffer as something else.

## File I/O

| Name | Signature | Description |
|---|---|---|
| `readf(path)`            | `String → Ptr<Byte>`              | Reads whole file; null on failure. Caller must `free`. |
| `writef(path, contents)` | `String, Ptr<Byte> → Boolean`     | Writes null-terminated bytes; returns `true` on success |

`readf` opens the file, stats it for size, allocates `size+1` bytes,
reads, null-terminates, and returns the heap pointer. `writef` uses
`strlen` on its `Ptr<Byte>` argument to find the byte count, then opens
with `O_WRONLY|O_CREAT|O_TRUNC` and writes in a loop.

## Command-line arguments

| Name | Signature | Description |
|---|---|---|
| `argc()`  | `() → Long`            | Number of command-line arguments. Always at least 1 (`argv(0)` is the program path). |
| `argv(i)` | `Long → Ptr<Byte>`     | Returns argv[i] as a null-terminated byte buffer. Returns `null` if `i` is negative or `>= argc()`. |

The runtime captures argc and argv at `_start` entry from the kernel-provided
stack layout, so these are available without any setup in `main`. The pointers
returned by `argv(i)` point into the kernel's argument area — they're stable
for the lifetime of the program but should not be freed.

# Examples

## Pointer arithmetic over a buffer

```lazyc
Long count_l(String text) {
    Ptr<Byte> p = cast<Ptr<Byte>>(text);
    Long count = 0;
    while (*p != cast<Byte>(0)) {
        if (*p == cast<Byte>('l')) {
            count = count + 1;
        }
        p = p + 1;       // 13d: pointer advances by 1 (sizeof Byte)
    }
    return count;
}

Long main() {
    return count_l("hello world");    // returns 3
}
```

## Linked list with heap allocation

```lazyc
struct Node { Long value; Ptr<Node> next; }

Ptr<Node> make_node(Long v) {
    Ptr<Byte> raw = alloc(16);             // sizeof(Node) = 16
    Ptr<Node> n = cast<Ptr<Node>>(raw);
    (*n).value = v;
    (*n).next = null;
    return n;
}

Long sum(Ptr<Node> head) {
    Long total = 0;
    Ptr<Node> cur = head;
    while (cur != null) {
        total = total + (*cur).value;
        cur = (*cur).next;
    }
    return total;
}

Long main() {
    Ptr<Node> a = make_node(1);
    Ptr<Node> b = make_node(10);
    Ptr<Node> c = make_node(100);
    (*a).next = b;
    (*b).next = c;
    println("sum = %l", sum(a));
    free(cast<Ptr<Byte>>(a));
    free(cast<Ptr<Byte>>(b));
    free(cast<Ptr<Byte>>(c));
    return 0;
}
```

## File round-trip

```lazyc
Long main() {
    writef("/tmp/note.txt", cast<Ptr<Byte>>("hello, file"));
    Ptr<Byte> got = readf("/tmp/note.txt");
    if (got == null) { exit(1); }
    println("read back: %s", cast<String>(got));
    free(got);
    return 0;
}
```

# Build & test

```sh
make                            # builds bin/lazyc
make test PROG=tests/showcase   # compile, assemble, link, run
```

The full test suite uses `tests/expected.txt` as a manifest. Each entry
is either:

- `PASS name exit_code stdout-repr` — the test compiles, assembles,
  links, runs, and produces the expected exit code and stdout
- `FAIL name` — the compiler is expected to **reject** the program
  (parser or typechecker error), so the test passes if lazyc exits
  non-zero

189 tests, all passing.

# Implementation

## File layout

```
src/
  lexer.{c,h}       source bytes -> token stream
  parser.{c,h}      tokens -> AST (recursive descent + struct registry)
  ast.h             AST node types (tagged unions for Type, Expr, Stmt, etc.)
  ast_print.c       AST debug pretty-printer
  desugar.{c,h}     placeholder pass — currently a no-op walker reserved
                    for future lowerings (was previously for→while; that
                    desugaring was reverted in step 20 because continue
                    needs to target the for's step expression specifically)
  symtab.{c,h}      sized stack allocation per variable, struct-aware
  funcs.{c,h}       function signature table (Pass A)
  types.{c,h}       Type constructors (type_simple, type_ptr, type_struct,
                    types_equal — recursive on Ptr, nominal on struct)
  typecheck.{c,h}   AST annotation, format-string validation, const folding
  codegen.{c,h}     AST -> NASM (sized loads/stores, format-string lowering)
  main.c            CLI driver
runtime/
  runtime.asm       _start, write_bytes, print_char/string/int/long,
                    alloc/free/exit, readf/writef
tests/
  *.ml              test programs
  expected.txt      PASS/FAIL manifest with expected exit codes + stdout
```

## Compilation pipeline (in order)

1. **Lexer** (`src/lexer.c`): byte stream → tokens. Handles keywords
   (including `Ptr`, `cast`, `struct`), single-char punctuation
   (including `.` for field access), multi-char operators, integer
   literals, char literals (`'a'`, with escape handling), string literals
   (with escape handling deferred to emit-time for plain literals,
   intern-time for format-string slices).

2. **Parser** (`src/parser.c`): tokens → AST. Recursive descent with one
   token of lookahead. Maintains a struct registry so type names
   (including IDENTs that resolve to structs) can be parsed in type
   position.

3. **Typecheck** (`src/typecheck.c`): annotates the AST with type
   information, validates format strings, does const folding for
   integer-literal arithmetic, enforces the implicit conversion rules,
   resolves field names against struct definitions (setting `resolved`
   pointers in `EX_FIELD` nodes for codegen to use).

4. **Codegen** (`src/codegen.c`): AST → NASM Intel-syntax x86-64. Stack
   machine: every expression pushes its value. Every binary op pops two,
   pushes one. Locals live in the stack frame at offsets computed by
   `symtab`. Struct accesses produce `[rbp - struct_offset + field_offset]`
   addresses; pointer-through accesses evaluate the pointer and add the
   offset at runtime.

The `main.c` driver is just glue — open the source file, run each phase,
write the asm to `<input>.asm`.

## Key implementation decisions

**Single-pass codegen with stack machine.** Every expression pushes its
value onto the asm stack. Binary ops pop two, push one. This is wasteful
in the generated code (lots of `push rax / pop rax` pairs) but trivially
correct and easy to debug. Optimization is deferred indefinitely — the
goal is correctness for self-hosting, not speed.

**Stack frame layout.** Each function does
`push rbp; mov rbp, rsp; sub rsp, N` on entry where `N` is the total
local-variable bytes (rounded up to 16 for ABI alignment). A variable at
"offset N" lives at `[rbp - N .. rbp - N + sz - 1]`, with the *low*
address being `[rbp - N]`. For structs, the same convention holds: a
32-byte struct at offset 32 spans `[rbp-32 .. rbp-1]`. Field at
struct-internal offset `f->offset` lives at
`[rbp - (sy->offset - f->offset)]`.

**Type representation.** `Type` is a tagged struct with a `kind` enum, an
optional `pointee` pointer (for `Ptr<T>`), and an optional `sdef` pointer
(for structs). It's recursive — `Ptr<Ptr<Long>>` allocates two nested
heap-stored `Type` structs. `types_equal` recurses on the pointee chain
and uses pointer-identity on `StructDef` for nominal struct equality.

**Format-string lowering.** A `println("a=%l b=%l", x, y)` call becomes
five runtime calls: `write_bytes("a=", 2)`, `print_long(x)`,
`write_bytes(" b=", 3)`, `print_long(y)`, `print_newline()`. The compiler
slices the format string at codegen time and emits one helper call per
segment. No varargs anywhere.

**Cooked vs raw string tables.** Plain string literals (`"hello"`) go in
`.LstrN` and have escapes processed at *emission* time. Format-string
slices go in `.LcstrN` and have escapes processed at *intern* time. Two
tables, two label namespaces, no coordination needed.

**Cast narrowing fix.** Narrowing to a *signed* target uses
`movsx`/`movsxd` to re-sign-extend after truncation, not `movzx`. Without
this, `cast<Whole>(some_long_with_value_-1)` used immediately would print
as 4294967295 instead of -1.

**Stack-machine returns dummy zero for void calls.** `print`/`println`
return void, but our codegen pushes a value for every expression. After
emitting the format-call sequence we push a dummy `0` so the surrounding
`ST_EXPR` handler's `add rsp, 8` balances correctly.

**Globally unique labels.** Labels (`.L_if_end_42`, etc.) are unique
within the whole compilation unit, not per-function. Resetting per-function
broke multi-function programs in an early version; lesson learned.

**Pass A function table.** Function signatures are collected before any
typechecking, so calls forward-reference is implicit. There's a similar
table for structs maintained in the parser (since type names may appear
before the struct block ends — needed for `Ptr<Self>`).

**No struct-by-value.** Function parameters and return types of struct
type are explicitly disallowed. Use `Ptr<Struct>` instead. This sidesteps
the System V AMD64 struct-passing rules (which are messy: small structs
go in registers split by 8-byte chunks, large ones via implicit
caller-allocated buffer pointer). Adding it would only matter if we want
to call C from lazyc, which we don't.

# Step-by-step history

The compiler was built feature-by-feature, with a working binary and
passing test suite at every step. This is the order things landed in:

| Step  | What landed                                                                |
|-------|----------------------------------------------------------------------------|
| 1-3   | Lexer, parser skeleton, simplest expressions                               |
| 4     | Variable declarations, the `Long` type                                     |
| 5     | More numeric types: Integer, Whole, Byte, Char, Boolean, all sized correctly |
| 6     | Sign-aware comparisons (`setl` vs `setb`)                                  |
| 7     | If / else                                                                  |
| 8     | While loops                                                                |
| 9     | For loops (`for (init; cond; step) body` — handled directly in codegen)   |
| 10    | Function declarations, calls, parameters in registers                      |
| 11    | String literals, basic print                                               |
| 12    | Format-string `print`/`println` with compile-time validation               |
| 13a   | `Ptr<T>` type system (recursive)                                           |
| 13b   | `&x` and `*p` (reads)                                                      |
| 13c   | `*p = e` (writes), `null` literal                                          |
| 13d   | Pointer arithmetic and unsigned-pointer ordering                           |
| 14    | Heap (`alloc` / `free` / `exit`), mmap-backed                              |
| 15    | File I/O (`readf` / `writef`), `String ↔ Ptr<Byte>` casts                  |
| 16a   | `struct` declarations, type plumbing, sized stack slots                    |
| 16b   | Field reads (`s.f`)                                                        |
| 16c   | Field writes (`s.f = e`)                                                   |
| 16d   | Address-of-field (`&s.f`)                                                  |
| 16e   | Field access through pointer (`(*p).f`, `(*p).f = e`, `&(*p).f`)           |
| 17    | Arrays (`T[N]` types, `arr[i]` indexing, `&arr[i]`, indexing on `Ptr<T>`) |
| 20    | Control-flow polish: `break`, `continue`, `else if` chains             |
| 21a   | Bootstrap substrate library (string/buf/ptrvec helpers in lazyc)        |
| 21b   | Command-line argument support (`argc()`, `argv(i)` built-ins)            |
| 21c   | Bootstrap skeleton: stubbed pipeline + working ELF binary in lazyc/    |
| 21d   | Bootstrap lexer in lazyc; cross-check against C lexer (235 files match) |
| 21e   | Bootstrap expression parser in lazyc; cross-check against C (130+ exprs)|
| 21f   | Bootstrap statement+function parser; full-program AST cross-check (107)  |
| 21g   | Bootstrap struct+array parser; full-corpus AST cross-check (157 pass)    |
| 21h   | Bootstrap typechecker; full corpus + reject tests (157+67); self-typecheck |
| 21i   | Typechecker polish; fixed AST-invisible divergence to prep for fixed-point |
| 21j-l | Bootstrap codegen; 157/157 byte-identical asm; **fixed point reached**     |
| 22    | `extern` keyword in both compilers; runtime rewritten in lazyc            |

# What this compiler is for

This is a teaching project: build a real compiler from lexer to ELF
output, then use it to bootstrap itself.

The next phases on the roadmap:

- **21+**: the self-hosting port — rewrite the C compiler in lazyc piece
  by piece (lexer first, then parser, then typecheck, then codegen, then a
  fixed-point test where the lazyc-written compiler compiles itself and
  produces a byte-identical output).

**Deferred for now** (the language as it stands is enough to write the
bootstrap; these are nice-to-haves):

- Raw unions inside structs. Originally planned as step 18, deferred until
  the bootstrap actually needs them. The current approach for tagged nodes
  is "kind field + payload-pointer field": e.g. `struct AstNode { Long kind; Ptr<Byte> payload; }`,
  with the payload reinterpreted via `cast<Ptr<T>>` based on `kind`.
- String operations as a lazyc-level library (concat, length, compare,
  etc.) — these can be written once we start porting the C code, since
  they're just functions over `Ptr<Byte>` and the heap.

The project has Phase A (pointers, 13a-d), Phase B (heap + file I/O,
14-15), Phase C (structs, 16a-e), arrays (17), and control-flow polish
(20) complete. Everything needed to write a real lexer/parser in lazyc
is in place.
