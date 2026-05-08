// 13c: write through a pointer, then read it back.
// Expected exit: 50
Long main() {
    Long x = 0;
    Ptr<Long> p = &x;
    *p = 50;
    return x;
}
