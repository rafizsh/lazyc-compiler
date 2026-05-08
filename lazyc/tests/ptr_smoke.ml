// 13a: declare pointer-typed variables; never use them.
// Expected exit: 99
Long never_called(Ptr<Long> p, Ptr<Char> q, Ptr<Ptr<Byte>> r) {
    return 0;
}
Long main() {
    Ptr<Long> p;
    Ptr<Whole> q;
    Ptr<Ptr<Long>> pp;
    return 99;
}
