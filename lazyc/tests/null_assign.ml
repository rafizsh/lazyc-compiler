// 13c: reassign a typed pointer to null later.
// Expected exit: 1
Long main() {
    Long x = 5;
    Ptr<Long> p = &x;
    p = null;
    if (p == null) {
        return 1;
    }
    return 0;
}
