// 15: writef writes a string to a file.
// Expected exit: 1
Long main() {
    Boolean ok = writef("/tmp/mylang_test_writef.txt", cast<Ptr<Byte>>("hello\n"));
    if (ok) { return 1; }
    return 0;
}
