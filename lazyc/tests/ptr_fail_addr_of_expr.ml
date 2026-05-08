// 13b: &(a+b) is not allowed (not an lvalue).
Long main() {
    Long a = 1;
    Long b = 2;
    Ptr<Long> p = &(a + b);
    return 0;
}
