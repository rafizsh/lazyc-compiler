// 13d: Ptr<Long> + 1 advances by 8 bytes.
// Expected exit: 200
Long main() {
    Ptr<Byte> raw = alloc(32);
    Ptr<Long> p = cast<Ptr<Long>>(raw);
    *p = 100;
    Ptr<Long> q = p + 1;
    *q = 200;
    // Verify p is unchanged
    Long first  = *p;
    Long second = *q;
    free(raw);
    return second;
}
