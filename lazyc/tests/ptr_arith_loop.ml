// 13d: walk a buffer with pointer arithmetic.
// Expected exit: 45  (sum of 0..9 stored as Bytes)
Long main() {
    Ptr<Byte> buf = alloc(16);
    Ptr<Byte> p = buf;
    Long i = 0;
    while (i < 10) {
        *p = cast<Byte>(i);
        p = p + 1;
        i = i + 1;
    }
    Long total = 0;
    p = buf;
    Long j = 0;
    while (j < 10) {
        total = total + cast<Long>(*p);
        p = p + 1;
        j = j + 1;
    }
    free(buf);
    return total;
}
