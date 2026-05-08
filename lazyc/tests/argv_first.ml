// 21b: argv(0) returns the program path (whatever the kernel passed).
// We just verify it's non-null and has positive length.
// Expected exit: 0
Long ml_strlen(Ptr<Byte> s) {
    if (s == null) { return 0; }
    Long n = 0;
    Ptr<Byte> p = s;
    while (*p != cast<Byte>(0)) {
        n = n + 1;
        p = p + 1;
    }
    return n;
}

Long main() {
    Ptr<Byte> p = argv(0);
    if (p == null) { return 1; }
    if (ml_strlen(p) == 0) { return 2; }
    return 0;
}
