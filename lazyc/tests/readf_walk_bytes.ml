// 13d + 15: read a file, walk byte-by-byte, count occurrences of 'l'.
// Expected exit: 3
Long main() {
    Boolean ok = writef("/tmp/mylang_walk_test.txt", cast<Ptr<Byte>>("hello world"));
    if (!ok) { exit(1); }
    Ptr<Byte> p = readf("/tmp/mylang_walk_test.txt");
    if (p == null) { exit(2); }
    Ptr<Byte> cur = p;
    Long count = 0;
    while (*cur != cast<Byte>(0)) {
        if (*cur == cast<Byte>('l')) {
            count = count + 1;
        }
        cur = cur + 1;
    }
    free(p);
    return count;
}
