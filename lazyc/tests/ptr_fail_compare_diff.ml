Long main() {
    Long x = 1;
    Char c = 'a';
    Ptr<Long> p = &x;
    Ptr<Char> q = &c;
    if (p < q) { return 1; }
    return 0;
}
