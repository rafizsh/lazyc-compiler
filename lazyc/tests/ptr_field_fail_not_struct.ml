// (*p) where p is not a Ptr-to-struct is an error.
Long main() {
    Long x = 5;
    Ptr<Long> p = &x;
    Long y = (*p).foo;
    return 0;
}
