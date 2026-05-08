struct Foo { Long x; }
Long main() {
    Foo f;
    Ptr<Long> p = &f.bogus;
    return 0;
}
