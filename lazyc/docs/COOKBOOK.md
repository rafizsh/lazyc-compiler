# lazyc — Cookbook

A collection of small, complete, runnable lazyc programs for common
tasks. Each recipe has been verified to compile and run correctly.

For language reference see [`../LANGUAGE.md`](../LANGUAGE.md).

To run any recipe, save it as `recipe.ml`, then:

```sh
build/lazyc recipe.ml
nasm -f elf64 recipe.ml.asm -o recipe.o
ld recipe.o build/runtime.o -o recipe
./recipe
```

---

## Contents

1. [Hello, world](#hello-world)
2. [Command-line arguments](#command-line-arguments)
3. [Linked list with manual memory management](#linked-list)
4. [Dynamic byte buffer](#dynamic-byte-buffer)
5. [Reading and processing a file](#reading-and-processing-a-file)
6. [Parsing integers from strings](#parsing-integers-from-strings)
7. [Array of structs](#array-of-structs)
8. [String comparison](#string-comparison)
9. [Bubble sort](#bubble-sort)
10. [Compound conditions without `&&`](#compound-conditions-without-)
11. [Simple state machine](#simple-state-machine)
12. [Word count](#word-count)
13. [Reading a number from argv](#reading-a-number-from-argv)
14. [Hex digit lookup](#hex-digit-lookup)
15. [Working with multi-dimensional data](#working-with-multi-dimensional-data)

---

## Hello, world

```lazyc
Long main() {
    println("Hello, world!");
    return 0;
}
```

`main` returns the process exit code. Use `println` for line-terminated
output, `print` for output without a trailing newline.

---

## Command-line arguments

```lazyc
Long main() {
    Long n = argc();
    println("got %l args:", n);
    Long i = 0;
    while (i < n) {
        Ptr<Byte> a = argv(i);
        println("  argv[%l] = %s", i, cast<String>(a));
        i = i + 1;
    }
    return 0;
}
```

`argv(i)` returns `Ptr<Byte>`; cast to `String` for `%s`. `argv(0)` is
the program path; user arguments start at `argv(1)`. Out-of-range
indices return `null`.

---

## Linked list

A singly-linked list with manual memory management.

```lazyc
struct Node {
    Long value;
    Ptr<Node> next;
}

// Insert v at the head of list, returns new head.
Ptr<Node> push(Ptr<Node> head, Long v) {
    Ptr<Byte> raw = alloc(16);
    Ptr<Node> n = cast<Ptr<Node>>(raw);
    (*n).value = v;
    (*n).next = head;
    return n;
}

// Sum all values in the list.
Long sum_list(Ptr<Node> head) {
    Long total = 0;
    Ptr<Node> cur = head;
    while (cur != null) {
        total = total + (*cur).value;
        cur = (*cur).next;
    }
    return total;
}

// Free all nodes in the list.
Long free_list(Ptr<Node> head) {
    Ptr<Node> cur = head;
    while (cur != null) {
        Ptr<Node> next_node = (*cur).next;
        free(cast<Ptr<Byte>>(cur));
        cur = next_node;
    }
    return 0;
}

Long main() {
    Ptr<Node> head = null;
    head = push(head, 1);
    head = push(head, 2);
    head = push(head, 3);
    head = push(head, 4);
    println("sum = %l", sum_list(head));
    free_list(head);
    return 0;
}
```

Output: `sum = 10`.

Notes:
- `alloc(16)` allocates exactly 16 bytes — enough for one Node
  (8-byte Long + 8-byte pointer).
- `cast<Ptr<Byte>>(cur)` is needed because `free` takes `Ptr<Byte>`.
- Fields are accessed via `(*p).field`. There's no `->` operator.
- Use `next_node` not `next` to avoid colliding with the field name.

---

## Dynamic byte buffer

A growable byte buffer (analog of C++ `std::vector<char>`):

```lazyc
struct Buf {
    Ptr<Byte> data;
    Long len;
    Long cap;
}

Long buf_init(Ptr<Buf> b) {
    (*b).data = alloc(16);
    (*b).len = 0;
    (*b).cap = 16;
    return 0;
}

Long buf_grow(Ptr<Buf> b, Long need) {
    if ((*b).len + need <= (*b).cap) { return 0; }
    Long new_cap = (*b).cap * 2;
    while (new_cap < (*b).len + need) {
        new_cap = new_cap * 2;
    }
    Ptr<Byte> new_data = alloc(new_cap);
    Long i = 0;
    while (i < (*b).len) {
        new_data[i] = (*b).data[i];
        i = i + 1;
    }
    free((*b).data);
    (*b).data = new_data;
    (*b).cap = new_cap;
    return 0;
}

Long buf_push(Ptr<Buf> b, Byte c) {
    buf_grow(b, 1);
    (*b).data[(*b).len] = c;
    (*b).len = (*b).len + 1;
    return 0;
}

Long buf_free(Ptr<Buf> b) {
    free((*b).data);
    (*b).data = cast<Ptr<Byte>>(null);
    (*b).len = 0;
    (*b).cap = 0;
    return 0;
}

Long main() {
    Buf b;
    buf_init(&b);
    buf_push(&b, cast<Byte>(72));   // 'H'
    buf_push(&b, cast<Byte>(105));  // 'i'
    buf_push(&b, cast<Byte>(10));   // '\n'
    buf_push(&b, cast<Byte>(0));    // null terminator
    print("%s", cast<String>(b.data));
    println("length: %l", b.len);
    buf_free(&b);
    return 0;
}
```

Output:
```
Hi
length: 4
```

This is exactly the pattern used in the bootstrap's substrate
(`lazyc/lib/buf.ml`), generalized.

---

## Reading and processing a file

```lazyc
Long main() {
    if (argc() < 2) {
        println("usage: %s <path>", cast<String>(argv(0)));
        return 1;
    }
    Ptr<Byte> path = argv(1);
    Ptr<Byte> data = readf(cast<String>(path));
    if (data == null) {
        println("error: could not read '%s'", cast<String>(path));
        return 1;
    }
    // Compute length by scanning to null terminator.
    Long n = 0;
    while (cast<Long>(data[n]) != 0) {
        n = n + 1;
    }
    // Count newlines.
    Long lines = 0;
    Long i = 0;
    while (i < n) {
        if (cast<Long>(data[i]) == 10) {
            lines = lines + 1;
        }
        i = i + 1;
    }
    println("%l bytes, %l lines", n, lines);
    free(data);
    return 0;
}
```

`readf` returns a freshly-allocated, null-terminated buffer. It's your
responsibility to `free` it when done.

---

## Parsing integers from strings

```lazyc
// Parse a leading optional sign + decimal digits. Returns 0 on failure
// or empty input. Stops at the first non-digit.
Long parse_int(Ptr<Byte> s) {
    if (s == null) { return 0; }
    Long sign = 1;
    Long i = 0;
    if (cast<Long>(s[0]) == 45) {   // '-'
        sign = -1;
        i = 1;
    }
    Long n = 0;
    Boolean any = false;
    while (true) {
        Long c = cast<Long>(s[i]);
        if (c < 48) { break; }      // '0'
        if (c > 57) { break; }      // '9'
        n = n * 10 + (c - 48);
        any = true;
        i = i + 1;
    }
    if (!any) { return 0; }
    return n * sign;
}

Long main() {
    if (argc() < 3) {
        println("usage: %s <a> <b>", cast<String>(argv(0)));
        return 1;
    }
    Long a = parse_int(argv(1));
    Long b = parse_int(argv(2));
    println("%l + %l = %l", a, b, a + b);
    println("%l * %l = %l", a, b, a * b);
    return 0;
}
```

Run with `./prog -3 12`:
```
-3 + 12 = 9
-3 * 12 = -36
```

Notes:
- Each character compared as a `Long` (its ASCII code).
- `45` is `-`, `48` is `0`, `57` is `9`.
- The boolean `any` flag prevents an empty digit string from being
  treated as 0 (and lets you distinguish "user typed 0" from "user
  typed garbage" if you want — extend the function to return a status
  alongside the value).

---

## Array of structs

Two ways to allocate an array of structs.

### Inline (fixed size at compile time)

The straightforward `Point pts[5]; pts[i].x = ...` doesn't quite work
— field access on an array element isn't a supported lvalue form (see
the [nested field assignment gotcha](../LANGUAGE.md#gotcha-nested-struct-field-assignment)).
Use `&pts[i]` and write through a `Ptr<Point>`:

```lazyc
struct Point {
    Long x;
    Long y;
}

Long main() {
    Point pts[5];
    Long i = 0;
    while (i < 5) {
        Ptr<Point> pi = &pts[i];
        (*pi).x = i;
        (*pi).y = i * i;
        i = i + 1;
    }
    i = 0;
    while (i < 5) {
        Ptr<Point> pj = &pts[i];
        println("pt[%l] = (%l, %l)", i, (*pj).x, (*pj).y);
        i = i + 1;
    }
    return 0;
}
```

For element reads, the typechecker is more permissive — `pts[i].x` is
an rvalue and works in expressions. It's only **assignment to** an
array-element field that needs the pointer indirection.

### Dynamic (size known at runtime)

```lazyc
struct Point {
    Long x;
    Long y;
}

Long main() {
    Long n = 5;
    Ptr<Byte> raw = alloc(n * 16);          // 16 = sizeof(Point)
    Ptr<Point> pts = cast<Ptr<Point>>(raw);

    Long i = 0;
    while (i < n) {
        Ptr<Point> pi = pts + i;            // pointer arithmetic
        (*pi).x = i;
        (*pi).y = i * i;
        i = i + 1;
    }
    i = 0;
    while (i < n) {
        Ptr<Point> pj = pts + i;
        println("pt[%l] = (%l, %l)", i, (*pj).x, (*pj).y);
        i = i + 1;
    }
    free(raw);
    return 0;
}
```

Pointer arithmetic on `Ptr<struct>` scales by the full struct size,
so `pts + 1` advances 16 bytes, not 8.

Notice the use of `pi` and `pj` rather than reusing the name `p` — see
the [per-function flat scoping gotcha](../LANGUAGE.md#per-function-flat-scoping).

---

## String comparison

lazyc has no built-in string comparison. Write your own:

```lazyc
// Returns true if s1 and s2 contain the same null-terminated bytes.
Boolean str_eq(Ptr<Byte> s1, Ptr<Byte> s2) {
    if (s1 == null) {
        if (s2 == null) { return true; }
        return false;
    }
    if (s2 == null) { return false; }
    Long i = 0;
    while (true) {
        Long a = cast<Long>(s1[i]);
        Long b = cast<Long>(s2[i]);
        if (a != b) { return false; }
        if (a == 0) { return true; }
        i = i + 1;
    }
    return true;   // unreachable
}

Long main() {
    if (argc() < 3) {
        println("usage: %s <a> <b>", cast<String>(argv(0)));
        return 1;
    }
    if (str_eq(argv(1), argv(2))) {
        println("equal");
    } else {
        println("different");
    }
    return 0;
}
```

A `Long`-based comparison loop (one byte at a time as a 64-bit value)
keeps the body simple. For longer strings you could compare 8 bytes at
a time using `Ptr<uLong>`, but the simple version is plenty fast.

---

## Bubble sort

```lazyc
Long bubble_sort(Ptr<Long> arr, Long n) {
    Long i = 0;
    while (i < n - 1) {
        Long j = 0;
        while (j < n - 1 - i) {
            if (arr[j] > arr[j + 1]) {
                Long tmp = arr[j];
                arr[j] = arr[j + 1];
                arr[j + 1] = tmp;
            }
            j = j + 1;
        }
        i = i + 1;
    }
    return 0;
}

Long main() {
    Long arr[8];
    arr[0] = 5;
    arr[1] = 2;
    arr[2] = 9;
    arr[3] = 1;
    arr[4] = 7;
    arr[5] = 3;
    arr[6] = 8;
    arr[7] = 4;

    bubble_sort(cast<Ptr<Long>>(&arr[0]), 8);

    Long i = 0;
    while (i < 8) {
        println("arr[%l] = %l", i, arr[i]);
        i = i + 1;
    }
    return 0;
}
```

Output: arr is sorted as 1,2,3,4,5,7,8,9.

`&arr[0]` gives a pointer to the array's first element, which is then
passed to the sort function. The sort function modifies the array in
place through the pointer.

---

## Compound conditions without `&&`

Since lazyc has no `&&`/`||`, compound conditions must be expressed via
nested `if` statements with boolean flags.

### `&&` equivalent

```lazyc
// Want: if (a > 0 && b > 0) { ... }
Boolean both_pos = false;
if (a > 0) {
    if (b > 0) { both_pos = true; }
}
if (both_pos) {
    // ...
}
```

For non-side-effecting operands, you can also nest directly:

```lazyc
if (a > 0) {
    if (b > 0) {
        // a > 0 AND b > 0
    }
}
```

### `||` equivalent

```lazyc
// Want: if (a == 0 || b == 0) { ... }
Boolean either_zero = false;
if (a == 0) { either_zero = true; }
if (b == 0) { either_zero = true; }
if (either_zero) {
    // ...
}
```

This is the pattern used throughout the bootstrap's source — search
`lazyc/compiler/typecheck.ml` for any of these idioms, and you'll
see hundreds.

### Idiom: early exit

For "one of these conditions stops us", multiple `if`s with `return`:

```lazyc
Long checked_divide(Long a, Long b) {
    if (b == 0) {
        return -1;       // sentinel for failure
    }
    if (a < 0) {
        return -1;
    }
    return a / b;
}
```

---

## Simple state machine

A minimal lexer for a "key=value" line:

```lazyc
Long ST_KEY()    { return 0; }
Long ST_EQ()     { return 1; }
Long ST_VALUE()  { return 2; }

Long main() {
    Ptr<Byte> input = cast<Ptr<Byte>>("name=Sean");
    Long state = ST_KEY();
    Long i = 0;
    println("input: %s", cast<String>(input));

    while (true) {
        Long c = cast<Long>(input[i]);
        if (c == 0) { break; }
        Char ch = cast<Char>(c);   // for %c we need Char, not Long

        if (state == ST_KEY()) {
            if (c == 61) {           // '='
                state = ST_EQ();
            } else {
                println("key+= %c", ch);
            }
        } else {
            if (state == ST_EQ()) {
                state = ST_VALUE();
                println("value+= %c", ch);
            } else {
                if (state == ST_VALUE()) {
                    println("value+= %c", ch);
                }
            }
        }
        i = i + 1;
    }
    return 0;
}
```

State constants are defined as zero-arg functions (the same trick used
throughout the bootstrap to fake `enum` values). Each call returns a
small integer. Note the `cast<Char>(c)` — `%c` strictly requires a
`Char`, not a `Long`, even when the value is in range.

---

## Word count

A simple word counter:

```lazyc
Long main() {
    if (argc() < 2) {
        println("usage: %s <path>", cast<String>(argv(0)));
        return 1;
    }
    Ptr<Byte> data = readf(cast<String>(argv(1)));
    if (data == null) {
        println("read failed");
        return 1;
    }

    Long bytes = 0;
    Long lines = 0;
    Long words = 0;
    Boolean in_word = false;
    Long i = 0;

    while (true) {
        Long c = cast<Long>(data[i]);
        if (c == 0) { break; }
        bytes = bytes + 1;

        if (c == 10) {                // '\n'
            lines = lines + 1;
        }
        // word boundary: whitespace = 32 (space), 9 (tab), 10 (\n)
        Boolean is_ws = false;
        if (c == 32) { is_ws = true; }
        if (c == 9)  { is_ws = true; }
        if (c == 10) { is_ws = true; }

        if (is_ws) {
            in_word = false;
        } else {
            if (!in_word) {
                words = words + 1;
                in_word = true;
            }
        }
        i = i + 1;
    }

    println("%l %l %l %s", lines, words, bytes, cast<String>(argv(1)));
    free(data);
    return 0;
}
```

Output mimics `wc`: `<lines> <words> <bytes> <filename>`.

Note the `is_ws` boolean — that's the no-`||` workaround for "is this
character any of: space, tab, newline".

---

## Reading a number from argv

Combining `argv`, `parse_int`, and arithmetic:

```lazyc
Long parse_int(Ptr<Byte> s) {
    if (s == null) { return 0; }
    Long sign = 1;
    Long i = 0;
    if (cast<Long>(s[0]) == 45) { sign = -1; i = 1; }
    Long n = 0;
    while (true) {
        Long c = cast<Long>(s[i]);
        if (c < 48) { break; }
        if (c > 57) { break; }
        n = n * 10 + (c - 48);
        i = i + 1;
    }
    return n * sign;
}

// Compute n! (factorial); handles overflow silently.
Long factorial(Long n) {
    Long result = 1;
    Long i = 2;
    while (i <= n) {
        result = result * i;
        i = i + 1;
    }
    return result;
}

Long main() {
    if (argc() < 2) {
        println("usage: %s <n>", cast<String>(argv(0)));
        return 1;
    }
    Long n = parse_int(argv(1));
    println("%l! = %l", n, factorial(n));
    return 0;
}
```

`./prog 10` prints `10! = 3628800`.

---

## Hex digit lookup

Using a fixed-size byte array as a lookup table:

```lazyc
Long main() {
    // Map 0..15 to ASCII hex digits.
    Char hex[16];
    hex[0]  = '0'; hex[1]  = '1'; hex[2]  = '2'; hex[3]  = '3';
    hex[4]  = '4'; hex[5]  = '5'; hex[6]  = '6'; hex[7]  = '7';
    hex[8]  = '8'; hex[9]  = '9'; hex[10] = 'a'; hex[11] = 'b';
    hex[12] = 'c'; hex[13] = 'd'; hex[14] = 'e'; hex[15] = 'f';

    // Print the byte 0xC0FFEE in hex.
    Long val = 12648430;       // 0xC0FFEE
    Long i = 5;
    print("0x");
    while (i >= 0) {
        Long shift = i * 4;
        // Manual right-shift via repeated division (lazyc has no >>).
        Long shifted = val;
        Long k = 0;
        while (k < shift) {
            shifted = shifted / 2;
            k = k + 1;
        }
        Long nibble = shifted - (shifted / 16) * 16;
        print("%c", hex[nibble]);
        i = i - 1;
    }
    println("");
    return 0;
}
```

Output: `0xc0ffee`.

lazyc has no shift operators, so `val >> shift` becomes a division
loop. For tight loops, you'd hardcode the unrolled extraction.

---

## Working with multi-dimensional data

lazyc has no native multi-dimensional arrays. You can simulate them
with row-major flat arrays:

```lazyc
Long ROWS() { return 4; }
Long COLS() { return 5; }

// Get value at (r, c) in a row-major Long array.
Long get(Ptr<Long> grid, Long r, Long c) {
    return grid[r * COLS() + c];
}

// Set value at (r, c) in a row-major Long array.
Long set(Ptr<Long> grid, Long r, Long c, Long v) {
    grid[r * COLS() + c] = v;
    return 0;
}

Long main() {
    Long total = ROWS() * COLS();
    Ptr<Byte> raw = alloc(total * 8);
    Ptr<Long> grid = cast<Ptr<Long>>(raw);

    // Initialize with row*10 + col.
    // Each loop nest declares its own row/col counters because lazyc's
    // per-function flat scoping won't let us reuse names between nests.
    Long r1 = 0;
    while (r1 < ROWS()) {
        Long c1 = 0;
        while (c1 < COLS()) {
            set(grid, r1, c1, r1 * 10 + c1);
            c1 = c1 + 1;
        }
        r1 = r1 + 1;
    }

    // Print as a grid.
    Long r2 = 0;
    while (r2 < ROWS()) {
        Long c2 = 0;
        while (c2 < COLS()) {
            print("%l\t", get(grid, r2, c2));
            c2 = c2 + 1;
        }
        println("");
        r2 = r2 + 1;
    }

    free(raw);
    return 0;
}
```

Output:
```
0       1       2       3       4
10      11      12      13      14
20      21      22      23      24
30      31      32      33      34
```

Why not just declare `Long grid[20];` directly and index it as a flat
array? You can — that works too. The advantage of `alloc` here is the
size can be a runtime value.

---

## What's missing

If you find yourself reaching for these and they don't exist, that's
because lazyc doesn't have them:

- **Hashtables / dictionaries.** Build one with arrays + hash function.
- **Strings as a first-class type with operations.** lazyc `String`
  is just a typed pointer to bytes. Use `parse_int`, `str_eq`, etc.
  patterns above.
- **Floating-point.** Not supported. Integer-only.
- **Closures or function pointers.** Functions are first-class only as
  `extern` declarations and direct calls.
- **Iterators / for-each.** Use indexed `while` loops.
- **Generic types beyond `Ptr<T>`.** No user-defined generics.
- **Modules / imports.** Concatenate source files at the build step.
