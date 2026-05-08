Long main() {
    Long x = 5;
    Ptr<Long> p = &x;
    free(p);
    return 0;
}
