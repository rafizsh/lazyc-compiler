// 17: declare an array, write three elements, read them back.
// Expected exit: 60
Long main() {
    Long buf[5];
    buf[0] = 10;
    buf[1] = 20;
    buf[2] = 30;
    return buf[0] + buf[1] + buf[2];
}
