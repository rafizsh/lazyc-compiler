// 16e: read field through pointer-to-struct.
// Expected exit: 42
struct Point { Long x; Long y; }
Long get_x(Ptr<Point> p) {
    return (*p).x;
}
Long main() {
    Point pt;
    pt.x = 42;
    pt.y = 100;
    return get_x(&pt);
}
