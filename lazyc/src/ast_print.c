#include "ast.h"
#include <stdio.h>

static const char *type_name(TypeKind k) {
    switch (k) {
        case TY_BOOLEAN:  return "Boolean";
        case TY_CHAR:     return "Char";
        case TY_BYTE:     return "Byte";
        case TY_INTEGER:  return "Integer";
        case TY_UINTEGER: return "uInteger";
        case TY_WHOLE:    return "Whole";
        case TY_UWHOLE:   return "uWhole";
        case TY_LONG:     return "Long";
        case TY_ULONG:    return "uLong";
        case TY_STRING:   return "String";
        case TY_PTR:      return "Ptr";
        case TY_STRUCT:   return "struct";
        case TY_VOID:     return "void";
        default:          return "?";
    }
}
static const char *op_name(OpKind o) {
    static const char *n[] = {"+","-","*","/","%","==","!=","<",">","<=",">=","neg","!"};
    return n[o];
}
static void indent(int d) { for (int i=0;i<d;i++) fputs("  ", stdout); }

static void ty_suffix(Expr *e) {
    if (e->type.kind != TY_UNKNOWN) printf(" :%s", type_name(e->type.kind));
}

static void print_expr(Expr *e, int d) {
    indent(d);
    switch (e->kind) {
        case EX_NUMBER:     printf("Number %lld", e->num); ty_suffix(e); putchar('\n'); break;
        case EX_CHAR_LIT:   printf("Char '%c'", e->ch); ty_suffix(e); putchar('\n'); break;
        case EX_STRING_LIT: printf("String \"%.*s\"", (int)e->str.len, e->str.data); ty_suffix(e); putchar('\n'); break;
        case EX_BOOL_LIT:   printf("Bool %s", e->boolean?"true":"false"); ty_suffix(e); putchar('\n'); break;
        case EX_NULL:       printf("Null"); ty_suffix(e); putchar('\n'); break;
        case EX_IDENT:      printf("Ident %.*s", (int)e->ident.len, e->ident.name); ty_suffix(e); putchar('\n'); break;
        case EX_BINARY:
            printf("Binary %s", op_name(e->bin.op)); ty_suffix(e); putchar('\n');
            print_expr(e->bin.lhs, d+1);
            print_expr(e->bin.rhs, d+1);
            break;
        case EX_UNARY:
            printf("Unary %s", op_name(e->un.op)); ty_suffix(e); putchar('\n');
            print_expr(e->un.operand, d+1);
            break;
        case EX_CALL:
            printf("Call %.*s", (int)e->call.name_len, e->call.name); ty_suffix(e); putchar('\n');
            for (size_t i=0;i<e->call.nargs;i++) print_expr(e->call.args[i], d+1);
            break;
        case EX_CAST:
            printf("Cast<%s>", type_name(e->cast.target.kind)); ty_suffix(e); putchar('\n');
            print_expr(e->cast.operand, d+1);
            break;
        case EX_ADDR_OF:
            printf("AddrOf"); ty_suffix(e); putchar('\n');
            print_expr(e->addr.target, d+1);
            break;
        case EX_DEREF:
            printf("Deref"); ty_suffix(e); putchar('\n');
            print_expr(e->deref.operand, d+1);
            break;
        case EX_FIELD:
            printf("Field .%.*s", (int)e->field.name_len, e->field.name);
            ty_suffix(e); putchar('\n');
            print_expr(e->field.operand, d+1);
            break;
        case EX_INDEX:
            printf("Index"); ty_suffix(e); putchar('\n');
            print_expr(e->index.base, d+1);
            print_expr(e->index.index, d+1);
            break;
    }
}

static void print_stmt(Stmt *s, int d) {
    indent(d);
    switch (s->kind) {
        case ST_VAR_DECL:
            printf("VarDecl %s %.*s\n", type_name(s->var.ty.kind),
                   (int)s->var.name_len, s->var.name);
            if (s->var.init) print_expr(s->var.init, d+1);
            break;
        case ST_ASSIGN:
            printf("Assign %.*s\n", (int)s->assign.name_len, s->assign.name);
            print_expr(s->assign.value, d+1);
            break;
        case ST_PTR_STORE:
            printf("PtrStore\n");
            print_expr(s->ptr_store.target, d+1);
            print_expr(s->ptr_store.value, d+1);
            break;
        case ST_FIELD_STORE:
            printf("FieldStore\n");
            print_expr(s->field_store.target, d+1);
            print_expr(s->field_store.value, d+1);
            break;
        case ST_INDEX_STORE:
            printf("IndexStore\n");
            print_expr(s->index_store.target, d+1);
            print_expr(s->index_store.value, d+1);
            break;
        case ST_IF:
            printf("If\n");
            print_expr(s->if_s.cond, d+1);
            indent(d); printf("Then:\n"); print_stmt(s->if_s.then_b, d+1);
            if (s->if_s.else_b) { indent(d); printf("Else:\n"); print_stmt(s->if_s.else_b, d+1); }
            break;
        case ST_WHILE:
            printf("While\n");
            print_expr(s->while_s.cond, d+1);
            print_stmt(s->while_s.body, d+1);
            break;
        case ST_FOR:
            printf("For\n");
            if (s->for_s.init)   { indent(d+1); printf("Init:\n");   print_stmt(s->for_s.init, d+2); }
            if (s->for_s.cond)   { indent(d+1); printf("Cond:\n");   print_expr(s->for_s.cond, d+2); }
            if (s->for_s.update) { indent(d+1); printf("Update:\n"); print_stmt(s->for_s.update, d+2); }
            print_stmt(s->for_s.body, d+1);
            break;
        case ST_RETURN:
            printf("Return\n");
            if (s->ret.value) print_expr(s->ret.value, d+1);
            break;
        case ST_BREAK:
            printf("Break\n");
            break;
        case ST_CONTINUE:
            printf("Continue\n");
            break;
        case ST_BLOCK:
            printf("Block\n");
            for (size_t i=0;i<s->block.n;i++) print_stmt(s->block.stmts[i], d+1);
            break;
        case ST_EXPR:
            printf("ExprStmt\n");
            print_expr(s->expr_s.expr, d+1);
            break;
    }
}

void print_program(Program *p) {
    for (size_t i=0; i<p->nfuncs; i++) {
        FuncDecl *f = p->funcs[i];
        if (f->is_extern) {
            printf("Extern %s %.*s(", type_name(f->return_ty.kind),
                   (int)f->name_len, f->name);
        } else {
            printf("Func %s %.*s(", type_name(f->return_ty.kind),
                   (int)f->name_len, f->name);
        }
        for (size_t j=0;j<f->nparams;j++) {
            if (j) printf(", ");
            printf("%s %.*s", type_name(f->params[j].ty.kind),
                   (int)f->params[j].name_len, f->params[j].name);
        }
        printf(")\n");
        if (!f->is_extern) print_stmt(f->body, 1);
    }
}
