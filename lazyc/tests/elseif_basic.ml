// 20: else if chain.
// Expected exit: 6
Long classify(Long x) {
    if (x < 0)         { return 0; }
    else if (x == 0)   { return 1; }
    else if (x < 10)   { return 2; }
    else               { return 3; }
}
Long main() {
    return classify(-5) + classify(0) + classify(7) + classify(100);
    // 0 + 1 + 2 + 3 = 6
}
