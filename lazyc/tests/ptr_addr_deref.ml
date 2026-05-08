// 13b: round-trip Long via &/*. Expected exit: 99
Long main() {
    Long x = 99;
    Ptr<Long> p = &x;
    Long y = *p;
    return y;
}
