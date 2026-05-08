// 20 + 17: linear search with early break.
// Expected exit: 4   (index of value 50)
Long find(Ptr<Long> arr, Long n, Long target) {
    for (Long i = 0; i < n; i = i + 1) {
        if (arr[i] == target) { return i; }
    }
    return -1;
}
Long main() {
    Long arr[5];
    arr[0] = 10;
    arr[1] = 20;
    arr[2] = 30;
    arr[3] = 40;
    arr[4] = 50;
    return find(&arr[0], 5, 50);
}
