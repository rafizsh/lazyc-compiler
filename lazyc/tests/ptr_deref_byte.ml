// 13b: pointer to a 1-byte unsigned type; deref zero-extends.
// Expected exit: 200
Long main() {
    Byte b = 200;
    Ptr<Byte> p = &b;
    Byte back = *p;
    return cast<Long>(back);
}
