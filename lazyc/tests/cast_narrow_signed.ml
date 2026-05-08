Long main() {
    Long  big = -1;
    Whole w   = cast<Whole>(big);
    Long  back = cast<Long>(w);
    println("%l", back);
    return 0;
}
