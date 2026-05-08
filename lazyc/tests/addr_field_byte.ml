// 16d: address of a 1-byte field, write through it.
// Expected exit: 200
struct Bag { Byte b; Long n; }
Long main() {
    Bag bag;
    Ptr<Byte> pb = &bag.b;
    *pb = cast<Byte>(200);
    return cast<Long>(bag.b);
}
