#ifndef SYMTAB_H
#define SYMTAB_H

#include "ast.h"
#include <stddef.h>

typedef struct {
    const char *name;
    size_t      name_len;
    int         offset;
    Type        ty;
} Symbol;

typedef struct {
    Symbol *items;
    size_t  count;
    size_t  cap;
    int     next_offset;
} SymTab;

void   symtab_init(SymTab *s);
void   symtab_free(SymTab *s);
int    symtab_add(SymTab *s, const char *name, size_t name_len, Type ty, int line);
const Symbol *symtab_find(SymTab *s, const char *name, size_t name_len);
int    symtab_stack_size_aligned(SymTab *s);

#endif
