// 13b: Ptr<Long> cannot accept &c where c is Char.
Long main() {
    Char c = 'A';
    Ptr<Long> p = &c;
    return 0;
}
