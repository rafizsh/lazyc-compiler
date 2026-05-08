// 13c: comprehensive write-then-read with multiple updates.
// Expected exit: 30
Long main() {
    Long sum = 0;
    Ptr<Long> p = &sum;
    *p = 10;
    *p = *p + 5;
    *p = *p + 15;
    return sum;
}
