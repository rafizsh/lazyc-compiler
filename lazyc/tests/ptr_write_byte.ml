// 13c: byte write goes through 1-byte store.
// Expected exit: 200
Long main() {
    Byte b = 0;
    Ptr<Byte> p = &b;
    *p = 200;
    return cast<Long>(b);
}
