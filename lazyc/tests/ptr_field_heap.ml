// 16e: allocate a struct on the heap, set fields, read them back, free.
// Expected exit: 42
struct Box { Long value; }
Long main() {
    Ptr<Byte> raw = alloc(8);
    Ptr<Box> b = cast<Ptr<Box>>(raw);
    (*b).value = 42;
    Long got = (*b).value;
    free(raw);
    return got;
}
