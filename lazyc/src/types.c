#include "types.h"
#include <stdlib.h>
#include <stdio.h>

Type type_simple(TypeKind k) {
    Type t;
    t.kind = k;
    t.pointee = NULL;
    t.sdef = NULL;
    t.elem = NULL;
    t.nelems = 0;
    return t;
}

Type type_ptr(Type pointee) {
    Type t;
    t.kind = TY_PTR;
    t.pointee = malloc(sizeof(Type));
    if (!t.pointee) { fprintf(stderr, "out of memory\n"); exit(1); }
    *t.pointee = pointee;
    t.sdef = NULL;
    t.elem = NULL;
    t.nelems = 0;
    return t;
}

Type type_struct(StructDef *sdef) {
    Type t;
    t.kind = TY_STRUCT;
    t.pointee = NULL;
    t.sdef = sdef;
    t.elem = NULL;
    t.nelems = 0;
    return t;
}

Type type_array(Type elem, int nelems) {
    Type t;
    t.kind = TY_ARRAY;
    t.pointee = NULL;
    t.sdef = NULL;
    t.elem = malloc(sizeof(Type));
    if (!t.elem) { fprintf(stderr, "out of memory\n"); exit(1); }
    *t.elem = elem;
    t.nelems = nelems;
    return t;
}

int types_equal(Type a, Type b) {
    if (a.kind != b.kind) return 0;
    if (a.kind == TY_PTR) {
        if (!a.pointee || !b.pointee) return 0;
        return types_equal(*a.pointee, *b.pointee);
    }
    if (a.kind == TY_STRUCT) {
        return a.sdef == b.sdef;
    }
    if (a.kind == TY_ARRAY) {
        if (!a.elem || !b.elem) return 0;
        if (a.nelems != b.nelems) return 0;
        return types_equal(*a.elem, *b.elem);
    }
    return 1;
}
