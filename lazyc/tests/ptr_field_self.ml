// 16e: traverse a 3-node linked list, sum values.
// Expected exit: 111
struct Node { Long value; Ptr<Node> next; }
Long sum_list(Ptr<Node> head) {
    Long total = 0;
    Ptr<Node> cur = head;
    while (cur != null) {
        total = total + (*cur).value;
        cur = (*cur).next;
    }
    return total;
}
Long main() {
    Node a;
    Node b;
    Node c;
    a.value = 1;   a.next = &b;
    b.value = 10;  b.next = &c;
    c.value = 100; c.next = null;
    return sum_list(&a);
}
