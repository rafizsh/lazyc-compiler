// 16b: field read participates in expressions.
// Expected exit: 30
struct Both { Long a; Long b; }
Long main() {
    Both v;
    Ptr<Both> pv = &v;
    Ptr<Long> pa = cast<Ptr<Long>>(pv);
    *pa = 10;
    Ptr<Long> pb = pa + 1;
    *pb = 20;
    return v.a + v.b;
}
