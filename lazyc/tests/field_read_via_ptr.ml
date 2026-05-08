// 16b: write a value through a reinterpreted pointer, read it via field access.
// Expected exit: 42
struct Point { Long x; Long y; }
Long main() {
    Point p;
    Ptr<Point> pp = &p;
    Ptr<Long> px = cast<Ptr<Long>>(pp);
    *px = 42;
    return p.x;
}
