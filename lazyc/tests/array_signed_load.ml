// 17: signed-load for Whole element type.
// Expected exit: 99
Long main() {
    Whole arr[3];
    arr[0] = 99;
    arr[1] = 200;
    arr[2] = -1;
    return cast<Long>(arr[0]);
}
