// 20: continue in a for loop skips to the step.
// Expected exit: 35
Long main() {
    Long total = 0;
    for (Long i = 0; i < 10; i = i + 1) {
        if (i == 3) { continue; }
        if (i == 7) { continue; }
        total = total + i;
    }
    return total;   // 0+1+2+4+5+6+8+9 = 35
}
