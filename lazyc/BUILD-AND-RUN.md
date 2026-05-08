# Build and run

This shows you how to build the lazyc compiler and use it to compile +
run the showcase program `tests/text_stats.ml`.

## Prerequisites (Linux x86-64)

```sh
# Debian / Ubuntu
sudo apt install nasm binutils
# Optional: gcc, only needed if you want to rebuild the C reference compiler.
sudo apt install gcc
```

`nasm` to assemble, `ld` (from `binutils`) to link. `gcc` is only
needed for the absolute-scratch path.

## Build the compiler (canonical path)

From the repo root:

```sh
./build.sh
```

That bootstraps `build/lazyc` from prebuilt asm + nasm + ld. No C
compiler involved. Output:

```
build/lazyc          - the canonical compiler
build/runtime.o        - linked runtime (syscall stub + lazyc code)
```

The build script also verifies a fixed-point property: it builds
`lazyc` from the prebuilt asm, runs that binary against its own
source, and confirms the result byte-matches the prebuilt asm.

## Compile + run the showcase

```sh
build/lazyc tests/text_stats.ml
nasm -f elf64 tests/text_stats.ml.asm -o tests/text_stats.o
ld tests/text_stats.o build/runtime.o -o tests/text_stats
./tests/text_stats; echo "exit=$?"
```

## Absolute-scratch path

If you want to build everything from source without trusting the
prebuilt asm, the C reference compiler is still in the tree:

```sh
make                   # builds the C compiler at ./lazyc-ref
./build.sh             # builds lazyc using the prebuilt asm
tools/full-check.sh    # full corpus + fixed-point + runtime-equivalence check
```

`tools/full-check.sh` confirms that `build/lazyc` and `./lazyc-ref`
produce byte-identical asm for every program in the test corpus, and
that the new runtime is functionally identical to the old hand-written
assembly runtime.
./tests/text_stats; echo "exit=$?"
```

## Expected output

The program writes a small text document to `/tmp/text-stats-input.txt`,
reads it back, splits it into a heap-allocated linked list of `Line`
nodes, then prints stats. Final `exit=0`. The stdout looks like:

```
=== read 131 bytes from disk ===

=== lines ===
  line 1 (len=19, first=84): The quick brown fox
  line 2 (len=24, first=106): jumps over the lazy dog.
  line 3 (len=0, first=0): 
  line 4 (len=33, first=77): Mylang is now self-hosting-ready.
  line 5 (len=20, first=105):   indented line here
  line 6 (len=30, first=76): Last line, no trailing newline

--- stats ---
  lines:        6
  total bytes:  126
  blank lines:  1
  longest line: 33 bytes
  letter counts (a..z, only nonzero):
    a = 5
    b = 1
    c = 1
    d = 4
    e = 13
    f = 2
    g = 4
    h = 4
    i = 9
    j = 1
    k = 1
    l = 8
    m = 2
    n = 12
    o = 7
    p = 1
    q = 1
    r = 5
    s = 5
    t = 6
    u = 2
    v = 1
    w = 3
    x = 1
    y = 3
    z = 1
  total letters: 103

=== sanity ===
  fib(10)    = 55   (expected 55)
  fib(15)    = 610   (expected 610)
  ipow(2,10) = 1024   (expected 1024)
  ipow(3, 5) = 243   (expected 243)
  even-sum 0..14 step 2 (skip odds, break at 14) = 42 (expected 0+2+4+6+8+10+12 = 42)
  bailed at = 14
  cast Long->Whole->Long round-trip: 1000 -> 1000 (expected 1000 -> 1000)
  cast Long->Byte->Long: 1000 -> 232 (expected 1000 -> 232)

OK
exit=0
```

## What this exercises

`tests/text_stats.ml` is a single 300-line lazyc program that uses
basically every feature of the language:

- **Structs**: `Line` (self-referential via `Ptr<Line> next`), `Stats`
  (with an array field `Long histogram[26]`).
- **Heap**: `alloc`/`free` for line nodes and their text buffers.
- **File I/O**: `writef` + `readf` round-trip through `/tmp`.
- **Pointers**: byte-level walking with `*p`, `p + 1`; `Ptr<Byte>` ↔
  `String` casting.
- **Field access through pointer**: `(*cur).next`, `(*cur).text`,
  `(*out).histogram[i]`.
- **Arrays**: `Char buf[N]` style declarations, indexing, an array as
  a struct field with element-write through a struct pointer.
- **Control flow**: `if`/`else if`/`else`, `while`, `for`, `break`,
  `continue`, recursion (`fib`, `ipow`).
- **Casts**: `Long → Whole`, `Long → Byte`, `Ptr<Byte> → String`,
  `Ptr<Line> → Ptr<Byte>` (for `free`).
- **Format printing**: `%l`, `%s`, `%c` with multiple args.

If this builds and runs to `exit=0` with the output above, the compiler
is working end-to-end and the language is feature-complete enough for
the bootstrap.

## Run the test suite

```sh
python3 tools/run_all.py
```

That builds and runs all 216 tests in `tests/` and checks each one's
exit code + stdout against the manifest. Expected output ends with
`TOTAL: 216 ok, 0 fail`.

If you don't want to run the full suite, here are a few representative
single tests:

```sh
make test PROG=tests/showcase
make test PROG=tests/ptr_field_self
make test PROG=tests/array_loop
make test PROG=tests/break_array_search
```

Each builds a binary under `tests/<name>` that you can run directly.
