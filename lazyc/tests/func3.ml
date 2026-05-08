Long fact(Long n) {
    if (n <= 1) { return 1; }
    return n * fact(n - 1);
}
Long main() { return fact(5); }
