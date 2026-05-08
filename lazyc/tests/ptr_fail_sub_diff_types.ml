Long main() {
    Long x = 1;
    Char c = 'a';
    Ptr<Long> p = &x;
    Ptr<Char> q = &c;
    Long d = p - q;
    return 0;
}
