// 13d: pointer ordering uses unsigned compare; b > a after b = a+5.
// Expected exit: 1
Long main() {
    Ptr<Byte> raw = alloc(64);
    Ptr<Long> a = cast<Ptr<Long>>(raw);
    Ptr<Long> b = a + 5;
    if (b > a) {
        if (a < b) {
            free(raw);
            return 1;
        }
    }
    free(raw);
    return 0;
}
