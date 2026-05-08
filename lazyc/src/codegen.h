#ifndef CODEGEN_H
#define CODEGEN_H
#include "ast.h"
#include <stdio.h>
void codegen_program(Program *p, FILE *out);
#endif
