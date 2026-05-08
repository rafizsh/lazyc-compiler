// 13c: 4-byte write through pointer.
// Expected exit: 123
Long main() {
    Whole w = 0;
    Ptr<Whole> p = &w;
    *p = 123;
    return cast<Long>(w);
}
