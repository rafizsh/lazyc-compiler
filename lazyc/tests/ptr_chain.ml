// 13b: Ptr<Ptr<Long>> double dereference.
// Expected exit: 7
Long main() {
    Long x = 7;
    Ptr<Long> p = &x;
    Ptr<Ptr<Long>> pp = &p;
    return **pp;
}
