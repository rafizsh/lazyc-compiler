// 21b: argv(i) where i is out of range returns null.
// Expected exit: 0
Long main() {
    Ptr<Byte> too_big = argv(99);
    if (too_big != null) { return 1; }
    Ptr<Byte> negative = argv(-1);
    if (negative != null) { return 2; }
    return 0;
}
