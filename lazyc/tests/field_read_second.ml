// 16b: second field has correct offset.
// Expected exit: 200
struct Point { Long x; Long y; }
Long main() {
    Point p;
    Ptr<Point> pp = &p;
    Ptr<Long> px = cast<Ptr<Long>>(pp);
    *px = 100;
    Ptr<Long> py = px + 1;
    *py = 200;
    return p.y;
}
