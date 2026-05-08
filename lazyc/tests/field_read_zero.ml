// 16b: declared struct fields are zero by default.
// Expected exit: 0
struct Point { Long x; Long y; }
Long main() {
    Point p;
    return p.x + p.y;
}
