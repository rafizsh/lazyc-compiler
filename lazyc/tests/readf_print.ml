// 15: write a file, read it back, print it.
// Expected exit: 0
// Expected stdout: "hello world\n"
Long main() {
    Ptr<Byte> msg = cast<Ptr<Byte>>("hello world\n");
    Boolean ok = writef("/tmp/mylang_test_readf_print.txt", msg);
    if (!ok) { exit(1); }
    Ptr<Byte> got = readf("/tmp/mylang_test_readf_print.txt");
    if (got == null) { exit(2); }
    print("%s", cast<String>(got));
    free(got);
    return 0;
}
