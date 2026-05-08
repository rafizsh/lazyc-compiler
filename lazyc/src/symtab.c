#include "symtab.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int type_size_bytes(Type ty) {
    switch (ty.kind) {
        case TY_BOOLEAN: case TY_CHAR: case TY_BYTE:        return 1;
        case TY_INTEGER: case TY_UINTEGER:                  return 2;
        case TY_WHOLE:   case TY_UWHOLE:                    return 4;
        case TY_LONG:    case TY_ULONG:
        case TY_STRING:  case TY_PTR:                       return 8;
        case TY_STRUCT:  return ty.sdef ? ty.sdef->size : 8;
        case TY_ARRAY:   return ty.elem ? type_size_bytes(*ty.elem) * ty.nelems : 8;
        default: return 8;
    }
}

static int type_align_bytes(Type ty) {
    if (ty.kind == TY_STRUCT) return ty.sdef ? ty.sdef->align : 1;
    if (ty.kind == TY_ARRAY) return ty.elem ? type_align_bytes(*ty.elem) : 1;
    return type_size_bytes(ty);
}

void symtab_init(SymTab *s) {
    s->items = NULL;
    s->count = 0;
    s->cap   = 0;
    s->next_offset = 0;
}

void symtab_free(SymTab *s) {
    free(s->items);
    s->items = NULL;
    s->count = s->cap = 0;
    s->next_offset = 0;
}

const Symbol *symtab_find(SymTab *s, const char *name, size_t name_len) {
    for (size_t i = 0; i < s->count; i++) {
        Symbol *sy = &s->items[i];
        if (sy->name_len == name_len && memcmp(sy->name, name, name_len) == 0)
            return sy;
    }
    return NULL;
}

int symtab_add(SymTab *s, const char *name, size_t name_len, Type ty, int line) {
    if (symtab_find(s, name, name_len)) {
        fprintf(stderr, "error at line %d: redeclaration of '%.*s'\n",
                line, (int)name_len, name);
        exit(1);
    }
    if (s->count == s->cap) {
        s->cap = s->cap ? s->cap * 2 : 8;
        s->items = realloc(s->items, s->cap * sizeof(Symbol));
        if (!s->items) { fprintf(stderr, "out of memory\n"); exit(1); }
    }

    int sz = type_size_bytes(ty);
    int align = type_align_bytes(ty);
    if (align < 1) align = 1;

    int offset = s->next_offset + sz;
    if (offset % align != 0) offset += align - (offset % align);
    s->next_offset = offset;

    Symbol sy = {
        .name = name, .name_len = name_len,
        .offset = offset,
        .ty = ty,
    };
    s->items[s->count++] = sy;
    return offset;
}

int symtab_stack_size_aligned(SymTab *s) {
    int n = s->next_offset;
    if (n % 16 != 0) n += 16 - (n % 16);
    return n;
}
