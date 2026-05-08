#ifndef FUNCS_H
#define FUNCS_H

#include "ast.h"

typedef struct {
    const char *name;
    size_t name_len;
    Type return_ty;
    Param *params;
    size_t nparams;
} FuncSig;

typedef struct {
    FuncSig *items;
    size_t count, cap;
} FuncTab;

void funcs_init(FuncTab *t);
void funcs_free(FuncTab *t);
void funcs_add(FuncTab *t, FuncDecl *f);
const FuncSig *funcs_find(FuncTab *t, const char *name, size_t name_len);

#endif
