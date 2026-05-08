// 17: populate via loop, read at non-zero index.
// Expected exit: 49
Long main() {
    Long buf[10];
    Long i = 0;
    while (i < 10) {
        buf[i] = i * i;
        i = i + 1;
    }
    return buf[7];
}
