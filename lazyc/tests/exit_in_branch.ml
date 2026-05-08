// 14: exit inside a conditional
// Expected exit: 7
Long main() {
    Long x = 7;
    if (x > 0) {
        exit(x);
    }
    return 99;
}
