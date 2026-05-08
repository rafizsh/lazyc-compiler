// 16c: 1-byte field write.
// Expected exit: 200
struct Bag { Byte b; Long n; }
Long main() {
    Bag bag;
    bag.b = cast<Byte>(200);
    bag.n = 0;
    return cast<Long>(bag.b);
}
