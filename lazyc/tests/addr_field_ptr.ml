// 16d: take address of a pointer-typed field. Ptr<Ptr<Long>>.
// Expected exit: 7
struct Holder { Ptr<Long> p; }
Long main() {
    Long x = 7;
    Holder h;
    h.p = &x;
    Ptr<Ptr<Long>> pp = &h.p;
    Ptr<Long> got = *pp;
    return *got;
}
