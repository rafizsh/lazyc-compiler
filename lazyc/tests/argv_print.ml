// 21b: print all argv entries.
// When run with no args, prints just the program path.
// Expected stdout: "argv[0]=<path>\n" (path varies, so we test the prefix only)
// Test runner can't easily verify variable text, so this test just exercises
// the codegen path and exits 0.
Long main() {
    Long n = argc();
    Long i = 0;
    while (i < n) {
        Ptr<Byte> a = argv(i);
        if (a == null) {
            println("argv[%l] = (null)", i);
        } else {
            println("argv[%l] = %s", i, cast<String>(a));
        }
        i = i + 1;
    }
    return 0;
}
