// 16e: write field through pointer-to-struct.
// Expected exit: 99
struct Point { Long x; Long y; }
Long set_y(Ptr<Point> p, Long v) {
    (*p).y = v;
    return 0;
}
Long main() {
    Point pt;
    pt.x = 1;
    pt.y = 2;
    set_y(&pt, 99);
    return pt.y;
}
