// 16c: write a field, read it back via field access.
// Expected exit: 42
struct Point { Long x; Long y; }
Long main() {
    Point p;
    p.x = 42;
    return p.x;
}
