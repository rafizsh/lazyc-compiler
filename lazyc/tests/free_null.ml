// 14: free(null) is a no-op that returns false
// Expected exit: 0
Long main() {
    Boolean ok = free(null);
    if (ok) { return 1; }
    return 0;
}
