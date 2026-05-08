// 16c: 4-byte signed-write, signed-read round-trip.
// Expected exit: 99
struct Mix { Whole w; Long n; }
Long main() {
    Mix m;
    m.w = 99;
    return cast<Long>(m.w);
}
