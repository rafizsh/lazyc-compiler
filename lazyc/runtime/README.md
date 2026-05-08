# runtime

The lazyc runtime: the small set of low-level helpers every lazyc
program links against. Supplies the entry point, the format-string
print helpers, the heap allocator, and file I/O.

## Structure

```
runtime/
  syscall.asm           — assembly stub: _start, argc/argv, syscall trampolines
  runtime.ml            — lazyc implementation of everything else
  runtime.asm           — original hand-written assembly runtime (kept for
                          comparison; pre-step-22 build path used this directly)
  prebuilt/
    runtime_ml.asm      — runtime.ml compiled to asm; lets you rebuild
                          everything with just nasm+ld
```

## Layering

There are two layers:

1. **Assembly stub (`syscall.asm`)**. Hand-written asm that cannot be
   expressed in lazyc because it touches the entry-point stack frame
   directly or invokes raw syscalls. About 50 lines total. Provides:

   ```
   _start                                     — entry point
   lazyc_argc                                — read saved argc
   lazyc_argv (Long i)                       — read saved argv[i] (with bounds check)
   lazyc_sys_read   (fd, buf, n)             — syscall 0
   lazyc_sys_write  (fd, buf, n)             — syscall 1
   lazyc_sys_open   (path, flags, mode)      — syscall 2
   lazyc_sys_close  (fd)                     — syscall 3
   lazyc_sys_stat   (path, statbuf)          — syscall 4
   lazyc_sys_mmap   (addr, len, prot, flags, fd, off)  — syscall 9
   lazyc_sys_munmap (addr, len)              — syscall 11
   lazyc_sys_exit   (code)                   — syscall 60
   ```

2. **lazyc code (`runtime.ml`)**. Everything else. Declares the
   `lazyc_sys_*` trampolines via `extern`, then implements:

   ```
   lazyc_alloc, lazyc_free                  — mmap-based allocator
   lazyc_exit                                — calls sys_exit
   lazyc_write_bytes                         — write loop until done
   lazyc_print_newline, lazyc_print_char,
   lazyc_print_string, lazyc_print_int16,
   lazyc_print_long                          — format-string output helpers
   lazyc_readf                               — stat + open + read-loop + close
   lazyc_writef                              — open + write-loop + close
   ```

## Building

The runtime is built as part of `./build.sh` at the project root. The
output is `build/runtime.o`, which user programs link against.

To inspect what `runtime.ml` compiles to:
```sh
build/lazyc runtime/runtime.ml      # writes runtime/runtime.ml.asm
```

## Verifying equivalence with the old runtime

`runtime/runtime.asm` is the original hand-written runtime. It's still
in the tree for comparison. `tools/full-check.sh` runs every test in
the corpus against both runtimes and confirms they produce identical
output and exit codes — proves the new runtime is functionally
equivalent to the old.
