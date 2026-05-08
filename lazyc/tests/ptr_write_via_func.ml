// 13c: pass a pointer into a function; the function writes through it.
// Expected exit: 77
Long set(Ptr<Long> p, Long v) {
    *p = v;
    return 0;
}
Long main() {
    Long x = 0;
    set(&x, 77);
    return x;
}
