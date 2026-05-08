// 14: combine alloc + print to show heap-backed work and a visible message
// Expected exit: 0
// Expected stdout: "ok\n"
Long main() {
    Ptr<Byte> buf = alloc(64);
    if (buf == null) {
        println("alloc failed");
        return 1;
    }
    println("ok");
    free(buf);
    return 0;
}
