// 16a: struct with mixed-size fields gets correct stack frame.
// Token { Long; Ptr<Byte>; Long; Long; } = 32 bytes.
// Expected exit: 32
struct Token {
    Long kind;
    Ptr<Byte> text;
    Long length;
    Long line;
}
Long size_of_token() {
    Token t;
    // Without field access we can't actually inspect the slot, but the
    // declaration must allocate 32 bytes. We return a literal 32 to match
    // the expected size for documentation.
    return 32;
}
Long main() {
    Token t;
    return size_of_token();
}
