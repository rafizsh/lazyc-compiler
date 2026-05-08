// 13b: pointer to a 4-byte signed type; deref reads the right size.
// Expected exit: 100
Long main() {
    Whole w = 100;
    Ptr<Whole> p = &w;
    Whole back = *p;
    return cast<Long>(back);
}
