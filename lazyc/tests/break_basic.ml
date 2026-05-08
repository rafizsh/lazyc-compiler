// 20: break exits a while loop early.
// Expected exit: 10
Long main() {
    Long total = 0;
    Long i = 0;
    while (i < 100) {
        if (i == 5) { break; }
        total = total + i;
        i = i + 1;
    }
    return total;
}
