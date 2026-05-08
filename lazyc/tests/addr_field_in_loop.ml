// 16d: addresses are stable across iterations.
// Expected exit: 55
struct Counter { Long n; }
Long inc(Ptr<Long> p) {
    *p = *p + 1;
    return 0;
}
Long main() {
    Counter c;
    c.n = 0;
    Ptr<Long> pn = &c.n;
    Long i = 1;
    while (i <= 10) {
        *pn = *pn + i;
        i = i + 1;
    }
    return c.n;
}
