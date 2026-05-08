// 17: struct with array field has correct alignment.
// Expected exit: 0
struct Buf {
    Char tag;
    Long data[4];
    Char end;
}
Long main() {
    Buf b;
    b.tag = 'a';
    b.data[0] = 1;
    b.data[3] = 4;
    b.end = 'z';
    return 0;
}
