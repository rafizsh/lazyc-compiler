// 17: &arr[i] gives Ptr<T> at the right offset.
// Expected exit: 1
Long main() {
    Long buf[5];
    buf[0] = 0;
    buf[1] = 0;
    Ptr<Long> p0 = &buf[0];
    Ptr<Long> p1 = &buf[1];
    Long diff = p1 - p0;
    return diff;
}
