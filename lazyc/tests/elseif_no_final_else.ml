// 20: else if works without a final else.
// Expected exit: 7
Long pick(Long x) {
    if (x == 1)       { return 100; }
    else if (x == 2)  { return 200; }
    else if (x == 3)  { return 7; }
    return 0;
}
Long main() {
    return pick(3);
}
