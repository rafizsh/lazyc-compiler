// 13a: Ptr<Ptr<...>> nesting parses.
// Expected exit: 0
Long main() {
    Ptr<Ptr<Long>> pp;
    Ptr<Ptr<Ptr<Char>>> ppp;
    return 0;
}
