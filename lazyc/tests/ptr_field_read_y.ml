// 16e: read second field through pointer.
// Expected exit: 99
struct Point { Long x; Long y; }
Long get_y(Ptr<Point> p) {
    return (*p).y;
}
Long main() {
    Point pt;
    pt.x = 10;
    pt.y = 99;
    return get_y(&pt);
}
