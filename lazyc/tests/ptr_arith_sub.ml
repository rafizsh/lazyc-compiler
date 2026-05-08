// 13d: ptr - Long subtracts.
// Expected exit: 100
Long main() {
    Ptr<Byte> raw = alloc(64);
    Ptr<Long> p = cast<Ptr<Long>>(raw);
    *p = 100;
    Ptr<Long> q = p + 3;
    Ptr<Long> back = q - 3;
    Long val = *back;
    free(raw);
    return val;
}
