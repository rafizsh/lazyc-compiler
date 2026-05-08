// lazyc — substrate library
// Growable pointer-array. Used for collections in the parser/typechecker
// (struct registry, function table, parameter lists, statement lists)
// where we'd reach for realloc in C.

struct PtrVec {
    Ptr<Ptr<Byte>> items;     // heap-allocated array of cap pointers
    Long           count;
    Long           cap;
}

Long ptrvec_init(Ptr<PtrVec> v) {
    Long initial = 4;
    // 8 bytes per pointer.
    Ptr<Byte> raw = alloc(initial * 8);
    if (raw == null) { exit(1); }
    (*v).items = cast<Ptr<Ptr<Byte>>>(raw);
    (*v).count = 0;
    (*v).cap = initial;
    return 0;
}

Long ptrvec_free(Ptr<PtrVec> v) {
    if ((*v).items != null) {
        free(cast<Ptr<Byte>>((*v).items));
        (*v).items = cast<Ptr<Ptr<Byte>>>(null);
    }
    (*v).count = 0;
    (*v).cap = 0;
    return 0;
}

// Internal: grow to at least `need` slots.
Long ptrvec_reserve(Ptr<PtrVec> v, Long need) {
    if ((*v).cap >= need) { return 0; }
    Long new_cap = (*v).cap;
    if (new_cap < 4) { new_cap = 4; }
    while (new_cap < need) {
        new_cap = new_cap * 2;
    }
    Ptr<Byte> new_raw = alloc(new_cap * 8);
    if (new_raw == null) { exit(1); }
    Ptr<Ptr<Byte>> new_items = cast<Ptr<Ptr<Byte>>>(new_raw);
    Long i = 0;
    while (i < (*v).count) {
        new_items[i] = (*v).items[i];
        i = i + 1;
    }
    free(cast<Ptr<Byte>>((*v).items));
    (*v).items = new_items;
    (*v).cap = new_cap;
    return 0;
}

Long ptrvec_push(Ptr<PtrVec> v, Ptr<Byte> p) {
    ptrvec_reserve(v, (*v).count + 1);
    (*v).items[(*v).count] = p;
    (*v).count = (*v).count + 1;
    return 0;
}

// Get the pointer at index i. No bounds check.
Ptr<Byte> ptrvec_get(Ptr<PtrVec> v, Long i) {
    return (*v).items[i];
}

// Set the pointer at index i. No bounds check.
Long ptrvec_set(Ptr<PtrVec> v, Long i, Ptr<Byte> p) {
    (*v).items[i] = p;
    return 0;
}
