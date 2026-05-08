// 13d: Ptr<T> - Ptr<T> -> count of Ts.
// Expected exit: 5
Long main() {
    Ptr<Byte> raw = alloc(64);
    Ptr<Long> a = cast<Ptr<Long>>(raw);
    Ptr<Long> b = a + 5;
    Long diff = b - a;
    free(raw);
    return diff;
}
