// 16e: 1-byte field read/write through pointer.
// Expected exit: 200
struct Bag { Byte b; Long n; }
Long set_b(Ptr<Bag> p, Byte v) {
    (*p).b = v;
    return 0;
}
Long main() {
    Bag bag;
    bag.b = cast<Byte>(0);
    bag.n = 0;
    set_b(&bag, cast<Byte>(200));
    return cast<Long>(bag.b);
}
