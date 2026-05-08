// 16e: helper function bumps each node's value via Ptr<Node>.
// Expected exit: 6
struct Node { Long value; Ptr<Node> next; }
Long bump(Ptr<Node> n) {
    (*n).value = (*n).value + 1;
    return 0;
}
Long main() {
    Node a;
    a.value = 5;
    a.next = null;
    bump(&a);
    return a.value;
}
