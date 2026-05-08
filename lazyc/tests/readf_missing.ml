// 15: readf returns null for nonexistent file.
// Expected exit: 0
Long main() {
    Ptr<Byte> p = readf("/tmp/this_does_not_exist_zzz_12345.txt");
    if (p == null) { return 0; }
    return 1;
}
