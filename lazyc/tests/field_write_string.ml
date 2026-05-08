// 16c: assign a string-literal-cast-Ptr<Byte> to a Ptr<Byte> field.
// Expected exit: 0
// Expected stdout: "hello\n"
struct Tagged {
    Long kind;
    Ptr<Byte> text;
}
Long main() {
    Tagged t;
    t.kind = 1;
    t.text = cast<Ptr<Byte>>("hello");
    println("%s", cast<String>(t.text));
    return 0;
}
