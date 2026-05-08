struct Inner { Long x; }
struct Outer { Inner i; }
Long main() {
    Outer o;
    return o.i.x;
}
