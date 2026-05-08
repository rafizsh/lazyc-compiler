// 17: write then sum via second loop.
// Expected exit: 45  (sum of 0..9)
Long main() {
    Long arr[10];
    Long i = 0;
    while (i < 10) {
        arr[i] = i;
        i = i + 1;
    }
    Long total = 0;
    Long j = 0;
    while (j < 10) {
        total = total + arr[j];
        j = j + 1;
    }
    return total;
}
