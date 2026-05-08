// 14: write a Long through allocated memory, read it back
// Expected exit: 42
Long main() {
    Ptr<Byte> raw = alloc(8);
    Ptr<Long> p = cast<Ptr<Long>>(raw);
    *p = 42;
    Long val = *p;
    free(raw);
    return val;
}
