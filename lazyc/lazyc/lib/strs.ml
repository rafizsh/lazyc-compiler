// lazyc — substrate library
// 21a: byte-level string and memory primitives
//
// Everything here is built only from lazyc primitives (alloc/free,
// pointer arithmetic, basic loops). No standard-library dependence.

// Length of a null-terminated byte buffer.
Long ml_strlen(Ptr<Byte> s) {
    if (s == null) { return 0; }
    Long n = 0;
    Ptr<Byte> p = s;
    while (*p != cast<Byte>(0)) {
        n = n + 1;
        p = p + 1;
    }
    return n;
}

// Equality of two null-terminated buffers.
Boolean ml_streq(Ptr<Byte> a, Ptr<Byte> b) {
    if (a == null) {
        if (b == null) { return true; }
        return false;
    }
    if (b == null) { return false; }
    Ptr<Byte> pa = a;
    Ptr<Byte> pb = b;
    while (true) {
        Byte ca = *pa;
        Byte cb = *pb;
        if (ca != cb) { return false; }
        if (ca == cast<Byte>(0)) { return true; }
        pa = pa + 1;
        pb = pb + 1;
    }
    return false;   // unreachable; lazyc requires return on all paths
}

// strncmp-style: -1 / 0 / 1.
Long ml_strcmp(Ptr<Byte> a, Ptr<Byte> b) {
    if (a == null) {
        if (b == null) { return 0; }
        return -1;
    }
    if (b == null) { return 1; }
    Ptr<Byte> pa = a;
    Ptr<Byte> pb = b;
    while (true) {
        Long ca = cast<Long>(*pa);
        Long cb = cast<Long>(*pb);
        if (ca < cb) { return -1; }
        if (ca > cb) { return 1; }
        if (ca == 0) { return 0; }
        pa = pa + 1;
        pb = pb + 1;
    }
    return 0;       // unreachable
}

// Memcpy: copy n bytes from src to dst. Caller ensures non-overlap.
Long ml_memcpy(Ptr<Byte> dst, Ptr<Byte> src, Long n) {
    Long i = 0;
    while (i < n) {
        dst[i] = src[i];
        i = i + 1;
    }
    return 0;
}

// Allocate a fresh null-terminated copy of [src .. src+n).
Ptr<Byte> ml_memdup(Ptr<Byte> src, Long n) {
    Ptr<Byte> buf = alloc(n + 1);
    if (buf == null) { return null; }
    Long i = 0;
    while (i < n) {
        buf[i] = src[i];
        i = i + 1;
    }
    buf[n] = cast<Byte>(0);
    return buf;
}

// Allocate a fresh null-terminated copy of an existing null-terminated string.
Ptr<Byte> ml_strdup(Ptr<Byte> s) {
    if (s == null) { return null; }
    Long n = ml_strlen(s);
    return ml_memdup(s, n);
}

// True if the byte is an ASCII digit '0'..'9'.
Boolean ml_is_digit(Byte b) {
    Long c = cast<Long>(b);
    if (c < 48) { return false; }   // '0'
    if (c > 57) { return false; }   // '9'
    return true;
}

// True if the byte is an ASCII letter or underscore.
Boolean ml_is_ident_start(Byte b) {
    Long c = cast<Long>(b);
    if (c == 95) { return true; }                  // '_'
    if (c >= 65) { if (c <= 90)  { return true; } } // 'A'..'Z'
    if (c >= 97) { if (c <= 122) { return true; } } // 'a'..'z'
    return false;
}

// True if the byte is letter, digit, or underscore.
Boolean ml_is_ident_cont(Byte b) {
    if (ml_is_ident_start(b)) { return true; }
    return ml_is_digit(b);
}

// True if whitespace: space, tab, newline, carriage return.
Boolean ml_is_space(Byte b) {
    Long c = cast<Long>(b);
    if (c == 32) { return true; }    // ' '
    if (c == 9)  { return true; }    // '\t'
    if (c == 10) { return true; }    // '\n'
    if (c == 13) { return true; }    // '\r'
    return false;
}

// Parse a decimal Long from a null-terminated buffer. Returns 0 on no digits.
// Stops at the first non-digit. Does not handle overflow gracefully.
Long ml_atol(Ptr<Byte> s) {
    if (s == null) { return 0; }
    Long n = 0;
    Long sign = 1;
    Ptr<Byte> p = s;
    if (cast<Long>(*p) == 45) { sign = -1; p = p + 1; }   // '-'
    while (true) {
        Byte b = *p;
        if (!ml_is_digit(b)) { break; }
        n = n * 10 + (cast<Long>(b) - 48);
        p = p + 1;
    }
    return n * sign;
}
