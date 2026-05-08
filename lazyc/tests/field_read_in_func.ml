// 16b: field reads work inside helper functions.
// Expected exit: 7
struct Box { Long val; }
Long sum_two_boxes() {
    Box a;
    Box b;
    Ptr<Box> pa = &a;
    Ptr<Box> pb = &b;
    Ptr<Long> pal = cast<Ptr<Long>>(pa);
    Ptr<Long> pbl = cast<Ptr<Long>>(pb);
    *pal = 3;
    *pbl = 4;
    return a.val + b.val;
}
Long main() {
    return sum_two_boxes();
}
