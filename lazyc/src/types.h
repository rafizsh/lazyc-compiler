#ifndef TYPES_H
#define TYPES_H

#include "ast.h"

Type type_simple(TypeKind k);
Type type_ptr(Type pointee);
Type type_struct(StructDef *sdef);
Type type_array(Type elem, int nelems);
int  types_equal(Type a, Type b);

#endif
