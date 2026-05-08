#include "desugar.h"
#include "ast.h"
#include <stdlib.h>
#include <stdio.h>

// As of step 20, this pass is essentially a no-op walker — but it's
// retained because future lowerings may want to live here. We previously
// rewrote `for` into `while`, but that made `continue` inside a `for`
// hard to wire up correctly (continue must jump to the step, not skip it).
// Codegen now handles ST_FOR directly.
static void desugar_stmt(Stmt *s);

static void desugar_stmt(Stmt *s) {
    if (!s) return;
    switch (s->kind) {
        case ST_FOR:
            if (s->for_s.init) desugar_stmt(s->for_s.init);
            if (s->for_s.update) desugar_stmt(s->for_s.update);
            if (s->for_s.body) desugar_stmt(s->for_s.body);
            return;
        case ST_BLOCK:
            for (size_t i = 0; i < s->block.n; i++)
                desugar_stmt(s->block.stmts[i]);
            return;
        case ST_IF:
            desugar_stmt(s->if_s.then_b);
            if (s->if_s.else_b) desugar_stmt(s->if_s.else_b);
            return;
        case ST_WHILE:
            desugar_stmt(s->while_s.body);
            return;
        default: return;
    }
}

void desugar_program(Program *p) {
    for (size_t i = 0; i < p->nfuncs; i++) {
        desugar_stmt(p->funcs[i]->body);
    }
}
