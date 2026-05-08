Long main() {
    Long fact = 1;
    for (Long n = 5; n > 0; n = n - 1) {
        fact = fact * n;
    }
    return fact;
}
