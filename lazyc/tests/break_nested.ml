// 20: break only exits the innermost loop.
// Expected exit: 10
Long main() {
    Long total = 0;
    for (Long i = 0; i < 5; i = i + 1) {
        for (Long j = 0; j < 5; j = j + 1) {
            if (j == 2) { break; }
            total = total + 1;
        }
    }
    return total;
}
