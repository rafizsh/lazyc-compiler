#include "funcs.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void funcs_init(FuncTab *t) { t->items = NULL; t->count = t->cap = 0; }
void funcs_free(FuncTab *t) { free(t->items); t->items = NULL; t->count = t->cap = 0; }

const FuncSig *funcs_find(FuncTab *t, const char *name, size_t n) {
    for (size_t i = 0; i < t->count; i++) {
        FuncSig *s = &t->items[i];
        if (s->name_len == n && memcmp(s->name, name, n) == 0) return s;
    }
    return NULL;
}

void funcs_add(FuncTab *t, FuncDecl *f) {
    if (funcs_find(t, f->name, f->name_len)) {
        fprintf(stderr, "error at line %d: redefinition of function '%.*s'\n",
                f->line, (int)f->name_len, f->name);
        exit(1);
    }
    if (t->count == t->cap) {
        t->cap = t->cap ? t->cap * 2 : 8;
        t->items = realloc(t->items, t->cap * sizeof(FuncSig));
    }
    FuncSig s = {
        .name = f->name, .name_len = f->name_len,
        .return_ty = f->return_ty,
        .params = f->params, .nparams = f->nparams,
    };
    t->items[t->count++] = s;
}
