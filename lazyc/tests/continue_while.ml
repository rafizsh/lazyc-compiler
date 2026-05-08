// 20: continue in a while loop jumps to top.
// Sum of 1..10 (= 55) minus 4 minus 6 = 45.
// Expected exit: 45
Long main() {
    Long total = 0;
    Long i = 0;
    while (i < 10) {
        i = i + 1;            // increment first to avoid infinite loop on continue
        if (i == 4) { continue; }
        if (i == 6) { continue; }
        total = total + i;
    }
    return total;
}
