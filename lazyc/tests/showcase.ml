Long fact(Long n) {
    if (n <= 1) { return 1; }
    return n * fact(n - 1);
}

Long main() {
    println("Factorials:");
    for (Long i = 1; i <= 6; i = i + 1) {
        println("  %l! = %l", i, fact(i));
    }
    println("done!");
    return 0;
}
