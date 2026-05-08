// 15: writef with a longer buffer.
// Expected exit: 1
Long main() {
    Boolean ok = writef("/tmp/mylang_test_writef_long.txt", cast<Ptr<Byte>>("line one\nline two\nline three\n"));
    if (ok) { return 1; }
    return 0;
}
