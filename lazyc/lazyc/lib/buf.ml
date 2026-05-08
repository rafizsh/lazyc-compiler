// lazyc — substrate library
// Growable byte buffer "Buf". Used for accumulating assembly output
// before writing it to disk, since lazyc's writef takes a whole buffer.
//
// Doesn't currently use realloc (we don't have one) — instead grows by
// allocating a new buffer of doubled capacity, copying, freeing the old.

struct Buf {
    Ptr<Byte> data;     // heap-allocated, null-terminated; len bytes valid
    Long      len;      // bytes currently held (excluding null terminator)
    Long      cap;      // bytes allocated (always at least len + 1)
}

// Initialize a Buf with a small initial capacity.
Long buf_init(Ptr<Buf> b) {
    Long initial = 64;
    Ptr<Byte> data = alloc(initial);
    if (data == null) { exit(1); }
    data[0] = cast<Byte>(0);
    (*b).data = data;
    (*b).len = 0;
    (*b).cap = initial;
    return 0;
}

// Free a Buf's storage. Safe to call on already-freed bufs (data == null).
Long buf_free(Ptr<Buf> b) {
    if ((*b).data != null) {
        free((*b).data);
        (*b).data = null;
    }
    (*b).len = 0;
    (*b).cap = 0;
    return 0;
}

// Internal: ensure cap is at least `need` bytes (including null terminator).
// Grows by powers of 2.
Long buf_reserve(Ptr<Buf> b, Long need) {
    if ((*b).cap >= need) { return 0; }
    Long new_cap = (*b).cap;
    if (new_cap < 64) { new_cap = 64; }
    while (new_cap < need) {
        new_cap = new_cap * 2;
    }
    Ptr<Byte> new_data = alloc(new_cap);
    if (new_data == null) { exit(1); }
    // Copy existing bytes (len + 1 to include the null).
    Long i = 0;
    Long copy_n = (*b).len + 1;
    while (i < copy_n) {
        new_data[i] = (*b).data[i];
        i = i + 1;
    }
    free((*b).data);
    (*b).data = new_data;
    (*b).cap = new_cap;
    return 0;
}

// Append a single byte.
Long buf_push_byte(Ptr<Buf> b, Byte c) {
    buf_reserve(b, (*b).len + 2);    // need len+1 for byte + len+2 for null
    (*b).data[(*b).len] = c;
    (*b).len = (*b).len + 1;
    (*b).data[(*b).len] = cast<Byte>(0);
    return 0;
}

// Append n bytes from src.
Long buf_push_bytes(Ptr<Buf> b, Ptr<Byte> src, Long n) {
    if (n <= 0) { return 0; }
    buf_reserve(b, (*b).len + n + 1);
    Long i = 0;
    while (i < n) {
        (*b).data[(*b).len + i] = src[i];
        i = i + 1;
    }
    (*b).len = (*b).len + n;
    (*b).data[(*b).len] = cast<Byte>(0);
    return 0;
}

// Append a null-terminated string.
Long buf_push_str(Ptr<Buf> b, Ptr<Byte> s) {
    if (s == null) { return 0; }
    Long n = ml_strlen(s);
    return buf_push_bytes(b, s, n);
}

// Append the decimal representation of a Long.
Long buf_push_long(Ptr<Buf> b, Long n) {
    if (n == 0) {
        buf_push_byte(b, cast<Byte>(48));    // '0'
        return 0;
    }
    // Special-case LONG_MIN since negating it overflows.
    if (n == -9223372036854775807 - 1) {
        buf_push_str(b, cast<Ptr<Byte>>("-9223372036854775808"));
        return 0;
    }
    Boolean neg = false;
    Long v = n;
    if (v < 0) {
        neg = true;
        v = 0 - v;
    }
    // Build digits in reverse (max ~20 digits for a 64-bit Long).
    Byte digits[24];
    Long ndigits = 0;
    while (v > 0) {
        digits[ndigits] = cast<Byte>(48 + (v % 10));
        ndigits = ndigits + 1;
        v = v / 10;
    }
    if (neg) {
        buf_push_byte(b, cast<Byte>(45));    // '-'
    }
    // Emit in correct order.
    Long i = ndigits - 1;
    while (i >= 0) {
        buf_push_byte(b, digits[i]);
        i = i - 1;
    }
    return 0;
}
