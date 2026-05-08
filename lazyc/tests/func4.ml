Long fib(Long n) {
    if (n < 2) { return n; }
    return fib(n - 1) + fib(n - 2);
}
Long main() { return fib(11); }
