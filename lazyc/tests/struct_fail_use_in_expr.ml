struct Foo { Long x; }
Long main() {
    Foo f;
    Long y = cast<Long>(f);
    return y;
}
