// 13b: pass a pointer into a function; the function dereferences.
// Expected exit: 50
Long load(Ptr<Long> p) {
    return *p;
}
Long main() {
    Long x = 50;
    return load(&x);
}
