// 13c: cannot store a String through Ptr<Long>.
Long main() {
    Long x = 0;
    Ptr<Long> p = &x;
    *p = "oops";
    return 0;
}
