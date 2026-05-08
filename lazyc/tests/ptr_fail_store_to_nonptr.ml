// 13c: cannot deref-assign a non-pointer.
Long main() {
    Long x = 5;
    *x = 7;
    return 0;
}
