// 16b: byte-sized field access uses 1-byte load.
// Expected exit: 200
struct Bag { Byte b; Long n; }
Long main() {
    Bag bag;
    Ptr<Bag> pb = &bag;
    Ptr<Byte> raw = cast<Ptr<Byte>>(pb);
    *raw = cast<Byte>(200);
    return cast<Long>(bag.b);
}
