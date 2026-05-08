Long main() {
    uLong small = 1;
    uLong big   = cast<uLong>(1000000);
    if (small < big) { return 1; }
    return 0;
}
