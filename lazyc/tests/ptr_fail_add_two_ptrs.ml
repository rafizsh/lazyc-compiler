Long main() {
    Long x = 1;
    Ptr<Long> p = &x;
    Ptr<Long> q = &x;
    Ptr<Long> r = p + q;
    return 0;
}
