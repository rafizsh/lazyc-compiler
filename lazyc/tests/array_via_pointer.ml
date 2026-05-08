// 17: pass &arr[0] to a function, modify through Ptr<T>.
// Expected exit: 5
Long sum_first_n(Ptr<Long> p, Long n) {
    Long total = 0;
    Long i = 0;
    while (i < n) {
        total = total + p[i];
        i = i + 1;
    }
    return total;
}
Long main() {
    Long arr[5];
    arr[0] = 1;
    arr[1] = 1;
    arr[2] = 1;
    arr[3] = 1;
    arr[4] = 1;
    return sum_first_n(&arr[0], 5);
}
