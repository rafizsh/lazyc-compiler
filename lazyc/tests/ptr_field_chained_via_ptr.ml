// 16e: real-world chain: pull a Ptr<Node> out of a node, then deref it.
// node_a.next = &node_b; (*node_a.next).value should equal node_b.value.
// Expected exit: 7
struct Node { Long value; Ptr<Node> next; }
Long main() {
    Node a;
    Node b;
    a.value = 3; a.next = &b;
    b.value = 7; b.next = null;
    return (*a.next).value;
}
