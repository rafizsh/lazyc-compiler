// 16c: write a Long field, then format-print it.
// Expected exit: 0
// Expected stdout: "x=42\n"
struct Bag { Long x; }
Long main() {
    Bag b;
    b.x = 42;
    println("x=%l", b.x);
    return 0;
}
