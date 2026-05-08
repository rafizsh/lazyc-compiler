// 16d: two struct locals, address fields of each, distinct addresses.
// Expected exit: 30
struct Box { Long val; }
Long add_via(Ptr<Long> a, Ptr<Long> b) {
    return *a + *b;
}
Long main() {
    Box one;
    Box two;
    one.val = 10;
    two.val = 20;
    return add_via(&one.val, &two.val);
}
