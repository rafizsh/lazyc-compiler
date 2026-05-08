// 14: alloc more than one page
// Expected exit: 1
Long main() {
    Ptr<Byte> p = alloc(8192);
    if (p == null) { return 0; }
    free(p);
    return 1;
}
