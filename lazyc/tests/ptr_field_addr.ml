// 16e: take address of a field through a pointer.
// &(*p).y should equal &pt.y when p == &pt.
// Expected exit: 1
struct Point { Long x; Long y; }
Long main() {
    Point pt;
    Ptr<Point> p = &pt;
    Ptr<Long> a = &(*p).y;
    Ptr<Long> b = &pt.y;
    if (a == b) { return 1; }
    return 0;
}
