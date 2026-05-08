// 14: alloc a buffer; reinterpret as Ptr<Long>; round-trip
// Expected exit: 45
Long main() {
    Ptr<Byte> buf = alloc(16);
    Ptr<Long> p = cast<Ptr<Long>>(buf);
    *p = 45;
    Long val = *p;
    free(buf);
    return val;
}
