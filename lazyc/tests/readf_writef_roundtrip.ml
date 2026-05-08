// 15: write content, read it back, write again to a different path, read that.
// Expected exit: 0
// Expected stdout: "round-trip ok\n"
Long main() {
    Boolean ok1 = writef("/tmp/mylang_test_rt_1.txt", cast<Ptr<Byte>>("round-trip ok\n"));
    if (!ok1) { exit(1); }
    Ptr<Byte> contents = readf("/tmp/mylang_test_rt_1.txt");
    if (contents == null) { exit(2); }
    Boolean ok2 = writef("/tmp/mylang_test_rt_2.txt", contents);
    if (!ok2) { exit(3); }
    Ptr<Byte> again = readf("/tmp/mylang_test_rt_2.txt");
    if (again == null) { exit(4); }
    print("%s", cast<String>(again));
    free(contents);
    free(again);
    return 0;
}
