// 16a: struct can contain Ptr<Self> for linked-list / AST patterns.
// Expected exit: 0
struct Node {
    Long value;
    Ptr<Node> next;
    Ptr<Node> prev;
}
Long main() {
    Node n;
    return 0;
}
