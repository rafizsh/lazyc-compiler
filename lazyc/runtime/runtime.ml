// runtime/runtime.ml — lazyc implementation of the runtime helpers.
//
// This file implements all the functions the codegen emits calls to,
// EXCEPT for the entry point, the argv-state accessors, and the raw
// syscall trampolines. Those live in runtime/syscall.asm.
//
// Provided by syscall.asm:
//   lazyc_argc, lazyc_argv,
//   lazyc_sys_read, lazyc_sys_write, lazyc_sys_open, lazyc_sys_close,
//   lazyc_sys_stat, lazyc_sys_mmap, lazyc_sys_munmap, lazyc_sys_exit.
//
// Implemented here:
//   lazyc_alloc, lazyc_free,
//   lazyc_exit,
//   lazyc_write_bytes, lazyc_print_newline, lazyc_print_char,
//   lazyc_print_string, lazyc_print_int16, lazyc_print_long,
//   lazyc_readf, lazyc_writef.
//
// Constraints:
//   * Cannot use the print/println/alloc/free/exit/readf/writef
//     built-ins, because they ARE this code. Only direct function calls
//     to the syscall trampolines and to other functions defined here.
//   * Cannot use String literals where println would be needed —
//     literals are fine, but we never do print("..."). Internal output
//     goes through lazyc_write_bytes and the formatter helpers.

// Forward declarations of the syscall trampolines, by signature only.
// lazyc has no `extern` keyword; we declare them as functions whose
// definitions are linked in from syscall.asm. The codegen emits a
// `call <name>` for each call, the linker does the rest.
//
// We can't actually write a body-less function in lazyc. So instead
// we don't declare them at all — calls to undefined names are resolved
// by the linker. That's what the bootstrap relies on for built-ins
// like `lazyc_alloc` already.

// ---- Extern syscall trampolines (defined in syscall.asm) ----
extern Long lazyc_sys_read(Long fd, Ptr<Byte> buf, Long n);
extern Long lazyc_sys_write(Long fd, Ptr<Byte> buf, Long n);
extern Long lazyc_sys_open(Ptr<Byte> path, Long flags, Long mode);
extern Long lazyc_sys_close(Long fd);
extern Long lazyc_sys_stat(Ptr<Byte> path, Ptr<Byte> statbuf);
extern Ptr<Byte> lazyc_sys_mmap(Ptr<Byte> addr, Long len, Long prot, Long flags, Long fd, Long off);
extern Long lazyc_sys_munmap(Ptr<Byte> addr, Long len);
extern Long lazyc_sys_exit(Long code);

// ---- lazyc_exit ----

Long lazyc_exit(Long code) {
    lazyc_sys_exit(code);
    return 0;     // unreachable
}

// ---- lazyc_alloc / lazyc_free ----
//
// mmap-based allocator. Each call mmaps a fresh page-aligned region
// rounded up to multiples of 4096 bytes. The size is stored in the
// first 8 bytes of the region; the returned pointer is region+8 so
// the caller doesn't see the header. Free reads the size and munmaps
// the whole region.

Ptr<Byte> lazyc_alloc(Long n) {
    // total = round_up(n + 8, 4096)
    Long total = n + 8 + 4095;
    total = total - (total - (total / 4096) * 4096);
    // sys_mmap(NULL, total, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0)
    Ptr<Byte> region = lazyc_sys_mmap(
        cast<Ptr<Byte>>(null),
        total,
        3,          // PROT_READ | PROT_WRITE
        34,         // MAP_PRIVATE | MAP_ANONYMOUS  (0x22 = 34)
        -1,
        0
    );
    // mmap returns a "negative-ish" errno on failure (last 4096 bytes of address space).
    // Treat any value with the high bit set near the top as failure.
    Long region_l = cast<Long>(region);
    if (region_l < 0) {
        if (region_l > -4096) {
            return cast<Ptr<Byte>>(null);
        }
    }
    // Write total at [region]; return region+8.
    Ptr<Long> hdr = cast<Ptr<Long>>(region);
    *hdr = total;
    return region + 8;
}

Boolean lazyc_free(Ptr<Byte> p) {
    if (p == null) { return false; }
    Ptr<Byte> region = p - 8;
    Ptr<Long> hdr = cast<Ptr<Long>>(region);
    Long total = *hdr;
    Long rc = lazyc_sys_munmap(region, total);
    if (rc != 0) { return false; }
    return true;
}

// ---- lazyc_write_bytes ----
//
// Writes the buffer at `buf` to fd 1 in a loop until all bytes are
// written or write returns an error. (Short writes can happen on
// pipes/terminals.) Returns void semantics — the codegen pushes 0
// after the call.

Long lazyc_write_bytes(Ptr<Byte> buf, Long n) {
    Long total = 0;
    while (total < n) {
        Long rc = lazyc_sys_write(1, buf + total, n - total);
        if (rc <= 0) { return 0; }
        total = total + rc;
    }
    return 0;
}

// ---- print helpers ----

Long lazyc_print_newline() {
    Byte nl[1];
    nl[0] = cast<Byte>(10);
    lazyc_write_bytes(cast<Ptr<Byte>>(&nl[0]), 1);
    return 0;
}

Long lazyc_print_char(Long c) {
    Byte b[1];
    b[0] = cast<Byte>(c);
    lazyc_write_bytes(cast<Ptr<Byte>>(&b[0]), 1);
    return 0;
}

// Print a null-terminated string.
Long lazyc_print_string(Ptr<Byte> s) {
    if (s == null) { return 0; }
    Long n = 0;
    while (cast<Long>(s[n]) != 0) {
        n = n + 1;
    }
    lazyc_write_bytes(s, n);
    return 0;
}

// Print a signed 64-bit integer. Handles LONG_MIN as a special case
// because negating LONG_MIN overflows.
Long lazyc_print_long(Long n) {
    if (n == 0) {
        Byte z[1];
        z[0] = cast<Byte>(48);
        lazyc_write_bytes(cast<Ptr<Byte>>(&z[0]), 1);
        return 0;
    }
    if (n == -9223372036854775807 - 1) {
        Byte lm[20];
        lm[0]  = cast<Byte>(45);  // -
        lm[1]  = cast<Byte>(57);  // 9
        lm[2]  = cast<Byte>(50);  // 2
        lm[3]  = cast<Byte>(50);  // 2
        lm[4]  = cast<Byte>(51);  // 3
        lm[5]  = cast<Byte>(51);  // 3
        lm[6]  = cast<Byte>(55);  // 7
        lm[7]  = cast<Byte>(50);  // 2
        lm[8]  = cast<Byte>(48);  // 0
        lm[9]  = cast<Byte>(51);  // 3
        lm[10] = cast<Byte>(54);  // 6
        lm[11] = cast<Byte>(56);  // 8
        lm[12] = cast<Byte>(53);  // 5
        lm[13] = cast<Byte>(52);  // 4
        lm[14] = cast<Byte>(55);  // 7
        lm[15] = cast<Byte>(55);  // 7
        lm[16] = cast<Byte>(53);  // 5
        lm[17] = cast<Byte>(56);  // 8
        lm[18] = cast<Byte>(48);  // 0
        lm[19] = cast<Byte>(56);  // 8
        lazyc_write_bytes(cast<Ptr<Byte>>(&lm[0]), 20);
        return 0;
    }
    Byte digits[24];
    Long ndigits = 0;
    Boolean neg = false;
    Long v = n;
    if (v < 0) {
        neg = true;
        v = 0 - v;
    }
    while (v > 0) {
        digits[ndigits] = cast<Byte>(48 + (v % 10));
        ndigits = ndigits + 1;
        v = v / 10;
    }
    Byte out[32];
    Long pos = 0;
    if (neg) {
        out[pos] = cast<Byte>(45);
        pos = pos + 1;
    }
    Long i = ndigits - 1;
    while (i >= 0) {
        out[pos] = digits[i];
        pos = pos + 1;
        i = i - 1;
    }
    lazyc_write_bytes(cast<Ptr<Byte>>(&out[0]), pos);
    return 0;
}

// print_int16 is the same as print_long (the codegen passes the value
// already sign-extended in a 64-bit register; range matters only for
// whether it fits in 16 bits, which is the typechecker's concern).
Long lazyc_print_int16(Long n) {
    return lazyc_print_long(n);
}

// ---- readf / writef ----
//
// readf(path) reads the whole file at `path` and returns a freshly
// allocated null-terminated buffer. Returns null on any failure.
//
// The implementation:
//   1. stat(path, &statbuf) to learn the size (st_size at offset 48).
//   2. alloc(size + 1) for the buffer.
//   3. open(path, O_RDONLY).
//   4. Loop reading until size bytes have been read or read returns 0/error.
//   5. close(fd).
//   6. Null-terminate at buf[size].

Ptr<Byte> lazyc_readf(Ptr<Byte> path) {
    if (path == null) { return cast<Ptr<Byte>>(null); }

    Ptr<Byte> statbuf = lazyc_alloc(144);
    if (statbuf == null) { return cast<Ptr<Byte>>(null); }
    Long sr = lazyc_sys_stat(path, statbuf);
    if (sr < 0) {
        lazyc_free(statbuf);
        return cast<Ptr<Byte>>(null);
    }
    // st_size lives at offset 48 within Linux's stat struct.
    Ptr<Long> size_p = cast<Ptr<Long>>(statbuf + 48);
    Long size = *size_p;
    lazyc_free(statbuf);

    Ptr<Byte> buf = lazyc_alloc(size + 1);
    if (buf == null) { return cast<Ptr<Byte>>(null); }

    Long fd = lazyc_sys_open(path, 0, 0);     // O_RDONLY
    if (fd < 0) {
        lazyc_free(buf);
        return cast<Ptr<Byte>>(null);
    }

    Long total = 0;
    while (total < size) {
        Long rc = lazyc_sys_read(fd, buf + total, size - total);
        if (rc < 0) {
            lazyc_sys_close(fd);
            lazyc_free(buf);
            return cast<Ptr<Byte>>(null);
        }
        if (rc == 0) { break; }              // EOF
        total = total + rc;
    }
    lazyc_sys_close(fd);

    buf[total] = cast<Byte>(0);
    return buf;
}

// writef(path, contents) writes `contents` (null-terminated) to `path`.
// Truncates if the file exists. Creates it with mode 0644 otherwise.
// Returns true on success, false on any failure.

Boolean lazyc_writef(Ptr<Byte> path, Ptr<Byte> contents) {
    if (path == null) { return false; }
    if (contents == null) { return false; }

    // O_WRONLY | O_CREAT | O_TRUNC = 0x241 = 577
    Long fd = lazyc_sys_open(path, 577, 420);  // 0644 = 420
    if (fd < 0) { return false; }

    // Length of contents (null-terminated).
    Long n = 0;
    while (cast<Long>(contents[n]) != 0) {
        n = n + 1;
    }

    Long total = 0;
    while (total < n) {
        Long rc = lazyc_sys_write(fd, contents + total, n - total);
        if (rc <= 0) {
            lazyc_sys_close(fd);
            return false;
        }
        total = total + rc;
    }
    lazyc_sys_close(fd);
    return true;
}
