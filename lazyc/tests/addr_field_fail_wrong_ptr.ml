// &p.x is Ptr<Long>; cannot assign to Ptr<Char>.
struct Foo { Long x; }
Long main() {
    Foo f;
    Ptr<Char> wrong = &f.x;
    return 0;
}
