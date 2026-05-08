// 20: break exits a for loop early.
// Expected exit: 6
Long main() {
    Long total = 0;
    for (Long i = 0; i < 100; i = i + 1) {
        if (i == 4) { break; }
        total = total + i;
    }
    return total;   // 0+1+2+3 = 6
}
