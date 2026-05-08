// 13c: declare a pointer as null and check.
// Expected exit: 1
Long main() {
    Ptr<Long> p = null;
    if (p == null) {
        return 1;
    }
    return 0;
}
