// 16c: build a 2-node linked list using Ptr<Node> fields.
// Expected exit: 12
struct Node {
    Long value;
    Ptr<Node> next;
}
Long main() {
    Node a;
    Node b;
    a.value = 5;
    a.next = &b;
    b.value = 7;
    b.next = null;
    // Traverse: start at a, sum values.
    Long total = a.value;
    if (a.next != null) {
        total = total + b.value;   // can't deref a.next yet (16e), so use b directly
    }
    return total;
}
