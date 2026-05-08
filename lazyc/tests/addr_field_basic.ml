// 16d: take address of a struct field, write through the pointer.
// Expected exit: 42
struct Point { Long x; Long y; }
Long set_to(Ptr<Long> p, Long v) {
    *p = v;
    return 0;
}
Long main() {
    Point p;
    set_to(&p.x, 42);
    return p.x;
}
