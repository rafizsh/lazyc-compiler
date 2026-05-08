// 17: byte-typed array used as a char buffer.
// Expected exit: 0
// Expected stdout: "hi\n"
Long main() {
    Byte buf[16];
    buf[0] = cast<Byte>('h');
    buf[1] = cast<Byte>('i');
    buf[2] = cast<Byte>(0);
    Ptr<Byte> p = &buf[0];
    println("%s", cast<String>(p));
    return 0;
}
