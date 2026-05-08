# lazyc — Language Reference

A complete reference for the lazyc programming language. This document
describes the language as actually implemented; it is not aspirational.
Where features are deliberately absent (logical operators, nested field
assignment, etc.) those are noted as **Gotchas**.

For an end-to-end build/run walkthrough see [`BUILD-AND-RUN.md`](BUILD-AND-RUN.md).
For compiler architecture see [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).
For worked code examples see [`docs/COOKBOOK.md`](docs/COOKBOOK.md).

---

## Contents

1. [Overview](#overview)
2. [Lexical structure](#lexical-structure)
3. [Types](#types)
4. [Expressions](#expressions)
5. [Statements](#statements)
6. [Functions](#functions)
7. [Structs](#structs)
8. [Arrays](#arrays)
9. [Pointers](#pointers)
10. [Built-in functions](#built-in-functions)
11. [Programs and linkage](#programs-and-linkage)
12. [Gotchas summary](#gotchas-summary)

---

## Overview

lazyc is a small, statically-typed, C-family language that compiles to
x86-64 NASM assembly for Linux. It has:

- A C-like syntax, but no preprocessor, no `&&`/`||`, no header files,
  no forward declarations.
- Eight numeric types, plus `Boolean`, `Char`, `Byte`, `String`, `Ptr<T>`,
  structs, and fixed-size arrays.
- Untyped integer literals that take the type of their context (no
  suffix needed).
- Manual memory management: `alloc(n)` / `free(p)` (mmap-backed).
- A 5-specifier formatted print system: `%c %i %l %s %%`.
- Direct pointer access, but no arithmetic on `Ptr<Byte>` is special-cased
  away from the regular `Ptr<T>` arithmetic rules.
- No closures, no generics, no exceptions, no references-as-distinct-from-pointers.

A complete program looks like this:

```lazyc
Long main() {
    Long total = 0;
    Long i = 1;
    while (i <= 10) {
        total = total + i;
        i = i + 1;
    }
    println("sum 1..10 = %l", total);
    return total;
}
```

Compiled with `lazyc`, this produces an executable whose exit code
is `55` and that prints `sum 1..10 = 55` to stdout.

---

## Lexical structure

### Comments

```lazyc
// single-line comment, runs to end of line
```

There are no `/* ... */` block comments.

### Identifiers

`[A-Za-z_][A-Za-z0-9_]*`. Case-sensitive. Identifiers used as type names
have no special syntactic distinction from variable names; the compiler
disambiguates from context.

### Keywords

```
Boolean Char Byte
Integer uInteger Whole uWhole Long uLong
String Ptr
true false null
if else while for return cast struct break continue extern
```

These cannot be used as identifiers.

### Numeric literals

Decimal integers: `0`, `42`, `9223372036854775807`. There is no `0x` hex,
no `0b` binary, no underscores, no suffix. Negative literals are formed
by applying the unary `-` operator to a positive literal: `-42` parses
as `OP_NEG (42)` which constant-folds to a single `-42` value.

The largest negative value `LONG_MIN = -9223372036854775808` is special
because `9223372036854775808` overflows. Write it as
`-9223372036854775807 - 1`. The constant folder produces the right
value at typecheck time.

### Character literals

`'A'`, `'\n'`, `'\\'`, `'\''`, `'\"'`, `'\0'`, `'\t'`, `'\r'`. ASCII only;
each character literal has type `Char` and a value in `0..127`.

### String literals

`"hello"`, `"escape: \n\t\\\""`. Type is `String`. String literals are
interned by the codegen into a `.rodata` section.

Recognized backslash escapes inside strings:

| Sequence | Byte    | Meaning                     |
|----------|---------|-----------------------------|
| `\n`     | 10      | newline                     |
| `\t`     | 9       | tab                         |
| `\r`     | 13      | carriage return             |
| `\0`     | 0       | null byte                   |
| `\\`     | 92      | literal backslash           |
| `\'`     | 39      | literal single quote        |
| `\"`     | 34      | literal double quote        |
| `\xHH`   | 0xHH    | exactly two hex digits      |

The `\x` form lets you put any byte 0..255 into a string. Useful for
ANSI escape sequences (`"\x1b[2J"` clears the screen), control bytes,
or non-ASCII binary data. Unlike C, exactly two hex digits are required
— `\x1` would be parsed as the single character `x1`.

(Character literals in single quotes do NOT support `\x`. If you need
a non-printable Char value, use a numeric literal with `cast<Char>(N)`.)

A `String` is **not** the same as a `Ptr<Byte>`, even though both
typically point to UTF-8-ish byte sequences. You have to cast explicitly
between them: `cast<Ptr<Byte>>(s)` or `cast<String>(p)`.

### Operators and punctuation

```
+  -  *  /  %
=  ==  !=  <  >  <=  >=
!  &
(  )  {  }  [  ]
;  ,  .
```

Note: there is no `&&`, no `||`, no `++`, no `--`, no `+=`, no `-=`,
no `<<`, no `>>`, no `?:`, no `,` operator (only as a separator).

---

## Types

All sizes are exact and target-independent (Linux x86-64).

| Type      | Size | Signed?  | Range                    | Notes                    |
|-----------|------|----------|--------------------------|--------------------------|
| `Boolean` | 1B   | n/a      | `false`/`true`           | Stored as 0 or 1         |
| `Char`    | 1B   | n/a      | 0..127                   | ASCII character          |
| `Byte`    | 1B   | unsigned | 0..255                   | Raw byte                 |
| `Integer` | 2B   | signed   | -32768..32767            |                          |
| `uInteger`| 2B   | unsigned | 0..65535                 |                          |
| `Whole`   | 4B   | signed   | -2³¹..2³¹-1              |                          |
| `uWhole`  | 4B   | unsigned | 0..2³²-1                 |                          |
| `Long`    | 8B   | signed   | -2⁶³..2⁶³-1              | The default integer type |
| `uLong`   | 8B   | unsigned | 0..2⁶⁴-1                 |                          |
| `String`  | 8B   | n/a      | pointer to bytes         | Used by `%s`             |
| `Ptr<T>`  | 8B   | n/a      | pointer to T             | Generic over T           |
| `T[N]`    | N·sz | n/a      | inline array             | N is a literal integer   |
| struct    | size | n/a      | declared aggregate       | See [Structs](#structs)  |

### Numeric literal coercion

Integer literals are *untyped* until the context types them. The compiler
coerces them to the surrounding type if (a) the target type is numeric,
`Char`, or `Byte`, and (b) the literal value fits in the target's range.

```lazyc
Char c = 65;        // ok: 65 fits in Char (0..127)
Char d = 200;       // ERROR: 200 doesn't fit in Char
Byte b = 200;       // ok: Byte allows 0..255
Long x = 100;       // ok: Long allows everything
Boolean q = 0;      // ERROR: Boolean is NOT in the coercion set; use false
```

`Boolean` is intentionally excluded from this coercion. You must write
`true` or `false` for boolean values.

### Type compatibility

For values where neither operand is an untyped literal, lazyc requires
**exact type match** for arithmetic and assignments. There is no implicit
widening between `Whole` and `Long`, no implicit signed/unsigned
conversion. Use `cast<T>(x)` to convert.

```lazyc
Long  a = 5;
Whole b = 10;
Long  c = a + b;    // ERROR: type mismatch (Long vs Whole)
Long  c = a + cast<Long>(b);   // ok
```

When **one** operand is an untyped literal, it gets coerced to the other
operand's type:

```lazyc
Long a = 5;
Long b = a + 10;    // ok: 10 is untyped, becomes Long
```

### Casts

```lazyc
cast<T>(expr)
```

Allowed conversions:

- Numeric → numeric (any numeric type to any numeric type, sign-extended
  or zero-extended, truncated for narrower).
- `Char`/`Byte`/`Boolean` → numeric.
- Any non-`Void` type → `Boolean` (zero → false, non-zero → true).
- `Ptr<T>` → `Ptr<U>` (for any T, U). Pointer casts don't change bits.
- `String` ↔ `Ptr<Byte>`. These are the only string-related conversions.
- A cast TO `String` requires the source to be `Ptr<Byte>`.

```lazyc
Long n = 65;
Char c = cast<Char>(n);                  // ok
Byte b = cast<Byte>(c);                  // Char -> Byte, ok
Ptr<Long> p = alloc(8);                  // alloc returns Ptr<Byte>...
                                         // ERROR: type mismatch
Ptr<Long> p = cast<Ptr<Long>>(alloc(8)); // ok with explicit cast
```

You **cannot** cast to a struct or array type.

---

## Expressions

### Precedence (highest first)

| Level | Operators | Associativity |
|---|---|---|
| 1 | `()` `[]` `.` (postfix) | left |
| 2 | `&` `*` `-` `!` (unary prefix) | right |
| 3 | `*` `/` `%` | left |
| 4 | `+` `-` | left |
| 5 | `==` `!=` `<` `>` `<=` `>=` | left |

There is **no logical-AND or logical-OR**. To express compound conditions,
use nested `if` statements with boolean flag variables (see
[Gotchas](#gotchas-summary)).

### Operator semantics

- `+`, `-`, `*`, `/`, `%` on numeric types: produce a value of the
  promoted type. `/` and `%` are signed division for signed types
  (truncating toward zero) and unsigned division for unsigned types.
- `+`, `-` on `Ptr<T>`: pointer arithmetic, scaled by `sizeof(T)`.
  `Ptr<T> + Long` and `Long + Ptr<T>` both produce `Ptr<T>`. `Ptr<T> -
  Long` produces `Ptr<T>`. `Ptr<T> - Ptr<T>` produces `Long` (the
  number of T's between them).
- `==`, `!=`, `<`, `>`, `<=`, `>=`: produce `Boolean`. Comparison
  operands must have compatible types (or one is an untyped literal).
  Pointers compare unsigned.
- `!`: takes a `Boolean`, produces a `Boolean`.
- `-`: unary negate; requires a signed numeric type.
- `&x`: takes the address of a variable, struct field, or array element.
  Produces a `Ptr<T>` of the appropriate pointee type.
- `*p`: dereferences a `Ptr<T>`, producing a value of type T.
- `s.field`: field access on a struct value or via a pointer (`*p`).
- `arr[i]`: index into an array or pointer. For `Ptr<T>`, equivalent
  to `*(arr + i)`.

### Constant folding

The compiler folds integer arithmetic on untyped literals at type-check
time. So `2 + 3 * 4` becomes the literal `14` before codegen.

```lazyc
Long x = 2 + 3 * 4;       // x is initialized to 14 (literal)
```

Folding only applies when both operands are untyped. Once a value has
been typed, it isn't folded any further.

### Evaluation order

Subexpressions are evaluated left-to-right. The codegen uses a stack
machine: each expression pushes its result on the runtime stack, and
binary operators pop two and push one.

---

## Statements

A function body is a `block`, which is a brace-delimited sequence of
statements. There is no expression-level `let` — every variable is
introduced by a `var-decl statement`.

### Variable declaration

```lazyc
Type name;              // declared, initialized to all-zeros
Type name = expr;       // declared, initialized to expr
```

The type can be a primitive, `Ptr<T>`, a struct name, or `T[N]` array
suffix on the variable name:

```lazyc
Long       a;
Ptr<Long>  p;
Long       arr[10];      // 10 × Long, uninitialized then zeroed
struct_name s;           // struct, fields all zeroed
```

Uninitialized variables are zero-initialized at function entry (this is
not an undefined-value language). For aggregate types (struct, array)
the entire storage is zeroed.

### Assignment

```lazyc
name = expr;             // assign to variable
*ptr = expr;             // store through pointer
s.field = expr;          // store to struct field
arr[i] = expr;           // store to array/ptr element
```

The LHS must be one of these four lvalue forms. There is no compound
assignment (`+=`, `-=`, etc.). There is no chained assignment.

### Control flow

```lazyc
if (cond) { ... }
if (cond) { ... } else { ... }
if (cond) { ... } else if (cond) { ... } else { ... }

while (cond) { ... }

for (init; cond; update) { ... }

return;            // in a Long function: returns 0
return expr;       // returns expr

break;             // exit innermost while/for
continue;          // jump to step (for) or test (while) of innermost loop
```

`cond` must have type `Boolean`. There is no truthy/falsy coercion;
`if (n)` where `n` is an integer is a type error. Write `if (n != 0)`.

For `for`, `init` and `update` must be statements (not expressions).
The condition is optional; an empty condition means "always true" (use
`break` to exit).

### Block

```lazyc
{ stmt1; stmt2; ... }
```

`{}` are required around the body of every `if`, `else`, `while`, `for`.
Single-statement bodies without braces are not allowed.

Blocks do **not** introduce a new variable scope. See
[Per-function flat scoping](#per-function-flat-scoping).

### Expression statement

```lazyc
println("hi");           // function call as a statement
```

Only function-call expressions are valid expression statements. You
cannot write `1 + 2;` or `x;` as a statement.

---

## Functions

### Definition

```lazyc
ReturnType name(ParamType1 p1, ParamType2 p2, ...) {
    // body
}
```

- Up to 6 parameters (System V AMD64 ABI register limit).
- Return type can be any non-`Void` type. There is no `Void` keyword;
  for "void" semantics, return `Long` and `return 0;`.
- Parameters are passed by value. Use `Ptr<T>` for pass-by-reference.
- No default arguments, no overloading, no varargs (except for the
  built-in `print`/`println` family).

### Calls

```lazyc
result = name(arg1, arg2);
```

Arguments must match parameter types (with the usual untyped-literal
coercion).

### Forward references

There are **no forward declarations**. The compiler resolves all
function names globally after parsing the entire program, so functions
can call each other in any order.

### Extern declarations

```lazyc
extern ReturnType name(ParamType1 p1, ...);
```

Declares a function whose body is provided by the linker (typically
hand-written assembly or a function from another module). The compiler
emits `extern <name>` in the asm header and skips codegen for the
declaration.

```lazyc
extern Long lazyc_sys_write(Long fd, Ptr<Byte> buf, Long n);

Long main() {
    lazyc_sys_write(1, cast<Ptr<Byte>>("hi\n"), 3);
    return 0;
}
```

Used in the runtime to declare syscall trampolines (see
[`runtime/runtime.ml`](runtime/runtime.ml) for the canonical example).

### Per-function flat scoping

This is the most important gotcha. lazyc has **per-function** scoping,
not per-block. A name declared anywhere in a function body is visible
everywhere else in the same function, and **redeclaring it is an error**:

```lazyc
Long main() {
    if (cond) {
        Long x = 1;
    } else {
        Long x = 2;        // ERROR: redeclaration of 'x'
    }
    return 0;
}
```

The fix is to use distinct names:

```lazyc
Long main() {
    if (cond) {
        Long x_then = 1;
    } else {
        Long x_else = 2;
    }
    return 0;
}
```

Or hoist the declaration:

```lazyc
Long main() {
    Long x = 0;
    if (cond) { x = 1; }
    else      { x = 2; }
    return 0;
}
```

This rule applies to function bodies only — different functions may
reuse the same names freely.

---

## Structs

```lazyc
struct Point {
    Long x;
    Long y;
}
```

- Fields can be any type **except** `Void`/`Unknown`.
- Layout is field-order with natural alignment (each field aligned to
  its size; struct alignment is the maximum field alignment; struct
  size is rounded up to that alignment).
- Struct values are stored inline (not heap-allocated by default).
- No methods, no constructors, no inheritance.

### Use

```lazyc
Point p;            // declared, all fields zero
p.x = 3;
p.y = 4;
Long mag = p.x * p.x + p.y * p.y;
```

Pass struct pointers to functions:

```lazyc
Long magsq(Ptr<Point> p) {
    return (*p).x * (*p).x + (*p).y * (*p).y;
}

Long main() {
    Point p;
    p.x = 3; p.y = 4;
    return magsq(&p);
}
```

Field access through a pointer requires the explicit `(*p).field` form.
There is no `->` operator.

### Recursive structs

A struct can contain a `Ptr<` to itself:

```lazyc
struct Node {
    Long value;
    Ptr<Node> next;
}
```

But it **cannot** contain itself by value. Mutual recursion between
two struct types is also not supported directly — use opaque
`Ptr<Byte>` and cast at the use site.

### Gotcha: nested struct field assignment

```lazyc
struct A { Long x; }
struct B { A a; Long y; }
Long main() {
    B b;
    b.y = 1;          // ok
    b.a.x = 2;        // ERROR: not supported
    return 0;
}
```

Field-of-field assignment is not parseable as an lvalue. Workaround:

```lazyc
Ptr<A> ap = &b.a;
(*ap).x = 2;          // ok
```

---

## Arrays

Fixed-size, declared by suffix:

```lazyc
Long arr[10];           // 10 Longs, all zero
Char buf[256];          // 256 bytes
```

- Size must be a literal integer ≥ 1.
- Stored inline (not heap-allocated).
- Indexing is unchecked: `arr[100]` on a 10-element array is undefined.
- Arrays are **not first-class** — you can't pass an array by value
  or return one. Pass `Ptr<T>` instead, optionally with a length.

### Indexing

```lazyc
arr[i] = 42;            // store
Long x = arr[i];        // load
```

`i` must be an integer expression. The result type is the element type.

### Array of structs

```lazyc
Point pts[10];
pts[0].x = 1;           // ok: store to a field of an array element
pts[0].y = 2;
```

But not `pts[0].nested.x` (see nested-field gotcha above).

### Array address arithmetic

```lazyc
Long arr[10];
Ptr<Long> p = &arr[3];    // pointer to 4th element
Ptr<Long> q = &arr[0];    // pointer to first element
Long diff = p - q;         // 3
```

---

## Pointers

`Ptr<T>` is a typed pointer to T. A `Ptr<T>` holds an 8-byte address.
The pointee type matters for arithmetic and dereference but not for
storage size.

### Allocation

```lazyc
Ptr<Byte> raw = alloc(64);                 // 64 bytes, raw
Ptr<Long> longs = cast<Ptr<Long>>(raw);    // reinterpret as 8 Longs
```

`alloc(n)` returns `Ptr<Byte>` (8-byte aligned in practice). To use it
as a `Ptr<T>` you must cast.

### Dereference and address-of

```lazyc
*p                      // load value of type T
*p = expr               // store value of type T
&x                      // produce Ptr<T> from a variable of type T
&s.field                // pointer to a struct field
&arr[i]                 // pointer to an array element
```

### Pointer arithmetic

```lazyc
Ptr<Long> p = ...;
Ptr<Long> q = p + 3;    // 3 Longs forward (24 bytes)
Long diff = q - p;      // 3
```

Subtraction `Ptr<T> - Ptr<T>` is only valid when both pointers have the
same pointee type.

### Null

The literal `null` represents the null pointer. It has type "untyped
null" until it gets coerced to a specific `Ptr<T>` by context.

```lazyc
Ptr<Long> p = null;             // ok
if (p == null) { ... }          // ok
return null;                    // ok if the function returns Ptr<...>
```

Comparing pointers of mismatched pointee types (other than null) is an
error.

---

## Built-in functions

These names are **reserved** — you cannot define functions with these
names. They have special handling in the compiler.

### `print`, `println`

```lazyc
print(format_string, arg1, arg2, ...);
println(format_string, arg1, arg2, ...);
```

`println` adds a trailing newline. The format string is a `String`
literal; it is **not** an arbitrary runtime string. The compiler
parses the format string at typecheck time and validates each `%X`
specifier against the corresponding argument type.

| Specifier | Required type        | Notes                  |
|-----------|----------------------|------------------------|
| `%c`      | `Char`               | One ASCII byte         |
| `%i`      | `Integer`/`uInteger` | 16-bit integer         |
| `%l`      | `Long`/`uLong`/etc.  | 64-bit integer; also accepts smaller signed types via coercion |
| `%s`      | `String`             | Null-terminated string |
| `%%`      | (none)               | Literal `%`            |

The argument count must exactly match the number of specifiers.

```lazyc
println("hello %s, you are %l years old", "Sean", 30);
println("char='%c' code=%i", 'A', 65);
println("100%%");
```

### `alloc`, `free`

```lazyc
Ptr<Byte> alloc(Long n);     // returns null on failure
Boolean   free(Ptr<Byte> p); // returns true on success
```

`alloc(n)` returns a fresh n-byte region (mmap-backed, page-aligned).
`free(p)` releases a region previously returned by `alloc`. Passing a
non-`alloc`-returned pointer to `free` is undefined.

### `exit`

```lazyc
Long exit(Long code);    // never returns
```

Terminates the process with the given exit code.

### `readf`, `writef`

```lazyc
Ptr<Byte> readf(String path);             // returns null on failure
Boolean   writef(String path, Ptr<Byte> contents); // returns false on failure
```

`readf` reads the entire file at `path`, returns a freshly-allocated
null-terminated buffer. The caller is responsible for `free`-ing it.

`writef` writes the null-terminated `contents` to `path`, truncating
or creating the file (mode 0644).

### `argc`, `argv`

```lazyc
Long      argc();           // number of command-line arguments
Ptr<Byte> argv(Long i);     // i-th argument as a null-terminated string;
                            //   returns null if i < 0 or i >= argc().
```

`argv(0)` is the program path. `argv(1)` is the first user argument.

```lazyc
Long main() {
    if (argc() < 2) {
        println("usage: %s <name>", cast<String>(argv(0)));
        return 1;
    }
    Ptr<Byte> name = argv(1);
    println("hi %s", cast<String>(name));
    return 0;
}
```

---

## Programs and linkage

A lazyc **program** is a single source file containing zero or more
struct declarations and zero or more function declarations (in any
order). Top-level declarations are the only kind of declaration; lazyc
has no global variables.

A program with a `main` function is an executable. The runtime expects:
```
Long main()        — exit-code returning entry, or
Long main(Long argc, Ptr<...> argv)   — NOT a thing in lazyc;
                                       use the argc()/argv() built-ins.
```

### Linkage model

The compiler emits NASM-syntax assembly. Each user-defined function
becomes a `global` symbol with the same name (no name mangling).
External symbols come from one of:

- The runtime (`build/runtime.o`): `_start`, `lazyc_alloc`, `lazyc_free`,
  `lazyc_exit`, `lazyc_print_*`, `lazyc_write_bytes`, `lazyc_readf`,
  `lazyc_writef`, `lazyc_argc`, `lazyc_argv`, plus the syscall
  trampolines `lazyc_sys_*`.
- User-declared `extern` functions: declared in the source via the
  `extern` keyword and resolved at link time.

To link a program:
```sh
build/lazyc your.ml                    # produces your.ml.asm
nasm -f elf64 your.ml.asm -o your.o
ld your.o build/runtime.o -o your
```

The runtime defines `_start` (the actual ELF entry point), which calls
your `main` and then invokes `exit_group` with main's return value.

### Multi-file programs

lazyc has no module/import system. To split a program across files,
concatenate them at the build step. The bootstrap compiler itself does
this — see `lazyc/build.sh` and `lazyc/prebuilt/lazyc.combined.ml`.

If you want clean separation, use `extern` declarations across "module"
boundaries and link the resulting `.o` files together with `ld -r`.

---

## Gotchas summary

These are surprises that trip up most newcomers. They're listed here
together for quick reference.

1. **No `&&`/`||`**. Use nested `if` with a boolean flag:

   ```lazyc
   // not: if (a > 0 && b > 0)
   Boolean both_pos = false;
   if (a > 0) {
       if (b > 0) { both_pos = true; }
   }
   if (both_pos) { ... }
   ```

2. **Per-function flat scoping**. A name declared in any branch is
   visible everywhere; redeclaration in a sibling branch is an error.

3. **No truthy coercion**. `if (n)` is not allowed when `n` is
   non-Boolean. Write `if (n != 0)`.

4. **`Boolean = 0` is rejected**. Boolean is intentionally not in the
   integer-coercion set; use `false` and `true`.

5. **No nested field assignment**. `b.a.x = 1;` doesn't parse. Take
   the address: `Ptr<A> ap = &b.a; (*ap).x = 1;`.

6. **No `->` operator**. Use `(*p).field`.

7. **No forward declarations**. Functions can call each other in any
   order; the compiler resolves all names globally after parsing.

8. **No expression statements other than calls**. `1+2;` is invalid.

9. **No compound assignment**. Write `x = x + 1;`, not `x += 1;`.

10. **Mutually recursive struct types are not supported**. Use opaque
    `Ptr<Byte>` and cast at use sites.

11. **String and `Ptr<Byte>` are distinct types**. Cast explicitly.

12. **`LONG_MIN` cannot be written as a single literal**. The integer
    `9223372036854775808` overflows. Write `-9223372036854775807 - 1`.

13. **`free` returns `Boolean`, not void**. You can ignore it, but
    if you assign it, you need a `Boolean` variable.

14. **`alloc` may return null**. Always check before dereferencing.

15. **Indexing is unchecked**. `arr[i]` for out-of-range `i` produces
    undefined behavior (memory corruption).

16. **Array sizes must be literal**. `Long arr[n];` where `n` is a
    variable doesn't work. Use `alloc(n * 8)` and a `Ptr<Long>`.

17. **Format strings must be literals**. `print(my_string)` where
    `my_string` is not a string literal is rejected — the compiler
    needs to inspect the format at compile time.

18. **No varargs in user functions**. Only `print`/`println` have
    variadic behavior, and that's compiler-magic, not exposed.
