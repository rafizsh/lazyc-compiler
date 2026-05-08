// Indexing on a Ptr<Struct> and using the result as a value should
// be rejected (would require copying the struct). Workaround is &p[i].
struct Foo { Long x; }
Long use_arr(Ptr<Foo> p) {
    Long y = cast<Long>(p[0]);
    return y;
}
Long main() { return 0; }
