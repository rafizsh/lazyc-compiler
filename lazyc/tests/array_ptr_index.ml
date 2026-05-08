// 17: indexing on a Ptr<T> works (mostly C-style sugar for *(p+i)).
// Expected exit: 111
Long main() {
    Ptr<Byte> raw = alloc(40);
    Ptr<Long> p = cast<Ptr<Long>>(raw);
    p[0] = 1;
    p[1] = 10;
    p[2] = 100;
    Long total = p[0] + p[1] + p[2];
    free(raw);
    return total;
}
