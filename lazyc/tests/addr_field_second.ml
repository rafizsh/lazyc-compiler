// 16d: address of the second field has correct offset.
// Expected exit: 99
struct Point { Long x; Long y; }
Long main() {
    Point p;
    p.x = 10;
    p.y = 20;
    Ptr<Long> py = &p.y;
    *py = 99;
    return p.y;
}
