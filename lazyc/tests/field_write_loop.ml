// 16c: write fields inside a loop (mutate in-place).
// Expected exit: 55
struct Counter { Long n; }
Long main() {
    Counter c;
    c.n = 0;
    Long i = 1;
    while (i <= 10) {
        c.n = c.n + i;
        i = i + 1;
    }
    return c.n;
}
