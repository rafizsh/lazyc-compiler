// 13c: assign and compare.
// Expected exit: 0
Long main() {
    Long x = 7;
    Ptr<Long> p = &x;
    if (p == null) {
        return 1;
    }
    if (p != null) {
        return 0;
    }
    return 2;
}
