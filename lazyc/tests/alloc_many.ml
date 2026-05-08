// 14: multiple independent allocations
// Expected exit: 60
Long main() {
    Ptr<Byte> a = alloc(64);
    Ptr<Byte> b = alloc(64);
    Ptr<Long> pa = cast<Ptr<Long>>(a);
    Ptr<Long> pb = cast<Ptr<Long>>(b);
    *pa = 10;
    *pb = 50;
    Long sum = *pa + *pb;
    free(a);
    free(b);
    return sum;
}
