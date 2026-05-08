// 16c: write both fields and read them back.
// Expected exit: 142
struct Point { Long x; Long y; }
Long main() {
    Point p;
    p.x = 42;
    p.y = 100;
    return p.x + p.y;
}
