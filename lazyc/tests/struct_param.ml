// 16a: function can take a Ptr<Struct> parameter.
// Expected exit: 7
struct Box {
    Long value;
}
Long peek(Ptr<Box> b) {
    return 7;   // can't deref or access fields yet; placeholder
}
Long main() {
    Box b;
    Ptr<Box> p = &b;
    return peek(p);
}
