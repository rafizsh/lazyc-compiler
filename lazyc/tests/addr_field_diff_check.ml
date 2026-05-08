// 16d: pointer arithmetic across fields. Distance should be 1 Long (sizeof Long).
// Expected exit: 1
struct Point { Long x; Long y; }
Long main() {
    Point p;
    Ptr<Long> px = &p.x;
    Ptr<Long> py = &p.y;
    Long diff = py - px;
    return diff;
}
