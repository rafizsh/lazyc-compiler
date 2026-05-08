// Field name doesn't exist on the struct.
struct Foo { Long x; }
Long main() {
    Foo f;
    Ptr<Foo> p = &f;
    Long y = (*p).bogus;
    return 0;
}
