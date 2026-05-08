// 14: alloc returns non-null
// Expected exit: 1
Long main() {
    Ptr<Byte> p = alloc(100);
    if (p == null) {
        return 0;
    }
    return 1;
}
