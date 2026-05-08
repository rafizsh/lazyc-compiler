// 16a: struct with mixed alignment requires padding.
// { Char c; Long x; } -> c at 0, padding 1..7, x at 8, total 16.
// Expected exit: 0
struct Padded {
    Char c;
    Long x;
}
Long main() {
    Padded p;
    return 0;
}
