// break in a function body but not in a loop.
Long helper() {
    break;
    return 0;
}
Long main() {
    return helper();
}
