// 13d: Ptr<Byte> + Long advances by 1 byte per increment.
// Expected exit: 5
Long main() {
    Ptr<Byte> raw = alloc(8);
    Ptr<Byte> p = raw;
    *p = cast<Byte>(5);
    p = p + 1;
    *p = cast<Byte>(99);
    Byte first = *raw;
    free(raw);
    return cast<Long>(first);
}
