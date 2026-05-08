#include "parser.h"
#include "lexer.h"
#include "types.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    Lexer lex;
    Token cur;
    Token peek;
    int had_error;

    // Struct definitions parsed so far. parse_type consults this when it
    // sees an IDENT in type position.
    StructDef **structs;
    size_t nstructs, structs_cap;
} Parser;

static StructDef *parser_find_struct(Parser *p, const char *name, size_t name_len) {
    for (size_t i = 0; i < p->nstructs; i++) {
        StructDef *s = p->structs[i];
        if (s->name_len == name_len && memcmp(s->name, name, name_len) == 0)
            return s;
    }
    return NULL;
}

static void parser_add_struct(Parser *p, StructDef *s) {
    if (p->nstructs == p->structs_cap) {
        p->structs_cap = p->structs_cap ? p->structs_cap * 2 : 4;
        p->structs = realloc(p->structs, p->structs_cap * sizeof(StructDef*));
    }
    p->structs[p->nstructs++] = s;
}

static void *xmalloc(size_t n) {
    void *p = calloc(1, n);
    if (!p) { fprintf(stderr, "out of memory\n"); exit(1); }
    return p;
}

static void parse_error(Parser *p, const char *msg) {
    fprintf(stderr, "parse error at line %d: %s (got '%.*s')\n",
            p->cur.line, msg, (int)p->cur.length, p->cur.start);
    p->had_error = 1;
    exit(1);
}

static void advance_p(Parser *p) {
    p->cur = p->peek;
    p->peek = lexer_next(&p->lex);
}

static int check(Parser *p, TokenKind k)  { return p->cur.kind == k; }
static int match_p(Parser *p, TokenKind k) {
    if (!check(p, k)) return 0;
    advance_p(p);
    return 1;
}
static Token expect(Parser *p, TokenKind k, const char *msg) {
    if (!check(p, k)) parse_error(p, msg);
    Token t = p->cur;
    advance_p(p);
    return t;
}

static int is_simple_type_token(TokenKind k) {
    return k==TOK_BOOLEAN||k==TOK_CHAR||k==TOK_BYTE
        || k==TOK_INTEGER||k==TOK_UINTEGER
        || k==TOK_WHOLE||k==TOK_UWHOLE
        || k==TOK_LONG||k==TOK_ULONG
        || k==TOK_STRING;
}
static int is_type_token(TokenKind k) {
    return is_simple_type_token(k) || k == TOK_PTR;
}
static TypeKind tok_to_simple_type(TokenKind k) {
    switch (k) {
        case TOK_BOOLEAN:  return TY_BOOLEAN;
        case TOK_CHAR:     return TY_CHAR;
        case TOK_BYTE:     return TY_BYTE;
        case TOK_INTEGER:  return TY_INTEGER;
        case TOK_UINTEGER: return TY_UINTEGER;
        case TOK_WHOLE:    return TY_WHOLE;
        case TOK_UWHOLE:   return TY_UWHOLE;
        case TOK_LONG:     return TY_LONG;
        case TOK_ULONG:    return TY_ULONG;
        case TOK_STRING:   return TY_STRING;
        default:           return TY_UNKNOWN;
    }
}
// Recursive type parser: handles primitive types, Ptr<T> nestings,
// and references to previously-declared structs (by name as IDENT).
static Type parse_type(Parser *p) {
    if (check(p, TOK_PTR)) {
        advance_p(p);
        expect(p, TOK_LT, "expected '<' after 'Ptr'");
        Type inner = parse_type(p);
        expect(p, TOK_GT, "expected '>' after pointee type");
        return type_ptr(inner);
    }
    if (check(p, TOK_IDENT)) {
        StructDef *sd = parser_find_struct(p, p->cur.start, p->cur.length);
        if (!sd) parse_error(p, "unknown type name");
        advance_p(p);
        return type_struct(sd);
    }
    if (!is_simple_type_token(p->cur.kind)) parse_error(p, "expected a type");
    Type t = type_simple(tok_to_simple_type(p->cur.kind));
    advance_p(p);
    return t;
}
// Defined here because it needs Parser.
static int is_type_start_p(Parser *p) {
    if (is_type_token(p->cur.kind)) return 1;
    if (p->cur.kind == TOK_IDENT) {
        return parser_find_struct(p, p->cur.start, p->cur.length) != NULL;
    }
    return 0;
}

static Expr *parse_expr(Parser *p);
static Expr *parse_comparison(Parser *p);
static Expr *parse_additive(Parser *p);
static Expr *parse_term(Parser *p);
static Expr *parse_unary(Parser *p);
static Expr *parse_primary(Parser *p);

static Expr *new_expr(ExprKind k, int line) {
    Expr *e = xmalloc(sizeof(Expr));
    e->kind = k;
    e->type.kind = TY_UNKNOWN;
    e->line = line;
    e->is_untyped_int = 0;
    return e;
}

static OpKind tok_to_binop(TokenKind k) {
    switch (k) {
        case TOK_PLUS:    return OP_ADD;
        case TOK_MINUS:   return OP_SUB;
        case TOK_STAR:    return OP_MUL;
        case TOK_SLASH:   return OP_DIV;
        case TOK_PERCENT: return OP_MOD;
        case TOK_EQ:      return OP_EQ;
        case TOK_NEQ:     return OP_NEQ;
        case TOK_LT:      return OP_LT;
        case TOK_GT:      return OP_GT;
        case TOK_LE:      return OP_LE;
        case TOK_GE:      return OP_GE;
        default:          return OP_ADD;
    }
}

static Expr *parse_expr(Parser *p) { return parse_comparison(p); }

static Expr *parse_comparison(Parser *p) {
    Expr *lhs = parse_additive(p);
    while (check(p,TOK_EQ)||check(p,TOK_NEQ)||check(p,TOK_LT)||
           check(p,TOK_GT)||check(p,TOK_LE)||check(p,TOK_GE)) {
        int line = p->cur.line;
        OpKind op = tok_to_binop(p->cur.kind);
        advance_p(p);
        Expr *rhs = parse_additive(p);
        Expr *e = new_expr(EX_BINARY, line);
        e->bin.op = op; e->bin.lhs = lhs; e->bin.rhs = rhs;
        lhs = e;
    }
    return lhs;
}

static Expr *parse_additive(Parser *p) {
    Expr *lhs = parse_term(p);
    while (check(p,TOK_PLUS)||check(p,TOK_MINUS)) {
        int line = p->cur.line;
        OpKind op = tok_to_binop(p->cur.kind);
        advance_p(p);
        Expr *rhs = parse_term(p);
        Expr *e = new_expr(EX_BINARY, line);
        e->bin.op = op; e->bin.lhs = lhs; e->bin.rhs = rhs;
        lhs = e;
    }
    return lhs;
}

static Expr *parse_term(Parser *p) {
    Expr *lhs = parse_unary(p);
    while (check(p,TOK_STAR)||check(p,TOK_SLASH)||check(p,TOK_PERCENT)) {
        int line = p->cur.line;
        OpKind op = tok_to_binop(p->cur.kind);
        advance_p(p);
        Expr *rhs = parse_unary(p);
        Expr *e = new_expr(EX_BINARY, line);
        e->bin.op = op; e->bin.lhs = lhs; e->bin.rhs = rhs;
        lhs = e;
    }
    return lhs;
}

static Expr *parse_unary(Parser *p) {
    if (check(p, TOK_AMP)) {
        int line = p->cur.line;
        advance_p(p);
        Expr *operand = parse_unary(p);
        Expr *e = new_expr(EX_ADDR_OF, line);
        e->addr.target = operand;
        return e;
    }
    if (check(p, TOK_STAR)) {
        int line = p->cur.line;
        advance_p(p);
        Expr *operand = parse_unary(p);
        Expr *e = new_expr(EX_DEREF, line);
        e->deref.operand = operand;
        return e;
    }
    if (check(p,TOK_MINUS) || check(p,TOK_BANG)) {
        int line = p->cur.line;
        OpKind op = check(p,TOK_MINUS) ? OP_NEG : OP_NOT;
        advance_p(p);
        Expr *operand = parse_unary(p);
        Expr *e = new_expr(EX_UNARY, line);
        e->un.op = op; e->un.operand = operand;
        return e;
    }
    return parse_primary(p);
}

static Expr *parse_primary_inner(Parser *p) {
    int line = p->cur.line;

    if (check(p,TOK_NUMBER)) {
        Expr *e = new_expr(EX_NUMBER, line);
        e->num = p->cur.int_value;
        e->is_untyped_int = 1;
        advance_p(p);
        return e;
    }
    if (check(p,TOK_CHAR_LIT)) {
        Expr *e = new_expr(EX_CHAR_LIT, line);
        e->ch = p->cur.char_value;
        advance_p(p);
        return e;
    }
    if (check(p,TOK_STRING_LIT)) {
        Expr *e = new_expr(EX_STRING_LIT, line);
        e->str.data = p->cur.start + 1;
        e->str.len  = p->cur.length - 2;
        advance_p(p);
        return e;
    }
    if (check(p,TOK_TRUE) || check(p,TOK_FALSE)) {
        Expr *e = new_expr(EX_BOOL_LIT, line);
        e->boolean = check(p,TOK_TRUE) ? 1 : 0;
        advance_p(p);
        return e;
    }
    if (check(p,TOK_NULL)) {
        Expr *e = new_expr(EX_NULL, line);
        e->is_untyped_null = 1;
        advance_p(p);
        return e;
    }
    if (check(p,TOK_CAST)) {
        advance_p(p);
        expect(p, TOK_LT, "expected '<' after 'cast'");
        Type t = parse_type(p);
        expect(p, TOK_GT, "expected '>' after cast type");
        expect(p, TOK_LPAREN, "expected '(' after cast<T>");
        Expr *inner = parse_expr(p);
        expect(p, TOK_RPAREN, "expected ')'");
        Expr *e = new_expr(EX_CAST, line);
        e->cast.target = t;
        e->cast.operand = inner;
        return e;
    }
    if (check(p,TOK_LPAREN)) {
        advance_p(p);
        Expr *inner = parse_expr(p);
        expect(p, TOK_RPAREN, "expected ')'");
        return inner;
    }
    if (check(p,TOK_IDENT)) {
        Token name = p->cur;
        advance_p(p);
        if (match_p(p, TOK_LPAREN)) {
            Expr **args = NULL;
            size_t nargs = 0, cap = 0;
            if (!check(p,TOK_RPAREN)) {
                for (;;) {
                    Expr *a = parse_expr(p);
                    if (nargs == cap) {
                        cap = cap ? cap*2 : 4;
                        args = realloc(args, cap*sizeof(Expr*));
                    }
                    args[nargs++] = a;
                    if (!match_p(p, TOK_COMMA)) break;
                }
            }
            expect(p, TOK_RPAREN, "expected ')'");
            Expr *e = new_expr(EX_CALL, line);
            e->call.name = name.start;
            e->call.name_len = name.length;
            e->call.args = args;
            e->call.nargs = nargs;
            return e;
        }
        Expr *e = new_expr(EX_IDENT, line);
        e->ident.name = name.start;
        e->ident.len  = name.length;
        return e;
    }
    parse_error(p, "expected an expression");
    return NULL;
}

// Wrap parse_primary_inner with a postfix loop for '.field' and '[index]'.
// Both are left-associative, so a chain like a.b[i].c parses as ((a.b)[i]).c.
static Expr *parse_primary(Parser *p) {
    Expr *e = parse_primary_inner(p);
    while (check(p, TOK_DOT) || check(p, TOK_LBRACKET)) {
        int line = p->cur.line;
        if (check(p, TOK_DOT)) {
            advance_p(p);
            Token fname = expect(p, TOK_IDENT, "expected field name after '.'");
            Expr *f = new_expr(EX_FIELD, line);
            f->field.operand = e;
            f->field.name = fname.start;
            f->field.name_len = fname.length;
            f->field.resolved = NULL;
            e = f;
        } else {
            // TOK_LBRACKET
            advance_p(p);
            Expr *idx = parse_expr(p);
            expect(p, TOK_RBRACKET, "expected ']' after index expression");
            Expr *ix = new_expr(EX_INDEX, line);
            ix->index.base = e;
            ix->index.index = idx;
            e = ix;
        }
    }
    return e;
}

static Stmt *parse_stmt(Parser *p);
static Stmt *parse_block(Parser *p);

static Stmt *new_stmt(StmtKind k, int line) {
    Stmt *s = xmalloc(sizeof(Stmt));
    s->kind = k;
    s->line = line;
    return s;
}

// Parse an optional [N] suffix after a type-and-name pair. Used in
// variable declarations and struct fields. If we see '[', the variable
// has type Array<base, N> (with N a literal integer).
static Type wrap_with_array_suffix(Parser *p, Type base) {
    if (!match_p(p, TOK_LBRACKET)) return base;
    if (!check(p, TOK_NUMBER)) parse_error(p, "expected integer literal in array size");
    long long n = p->cur.int_value;
    if (n <= 0) parse_error(p, "array size must be positive");
    if (n > 1000000) parse_error(p, "array size too large");
    advance_p(p);
    expect(p, TOK_RBRACKET, "expected ']' after array size");
    return type_array(base, (int)n);
}

static Stmt *parse_var_decl(Parser *p) {
    int line = p->cur.line;
    Type ty = parse_type(p);
    Token name = expect(p, TOK_IDENT, "expected variable name");
    ty = wrap_with_array_suffix(p, ty);
    Expr *init = NULL;
    if (match_p(p, TOK_ASSIGN)) init = parse_expr(p);
    expect(p, TOK_SEMI, "expected ';'");
    Stmt *s = new_stmt(ST_VAR_DECL, line);
    s->var.ty = ty;
    s->var.name = name.start;
    s->var.name_len = name.length;
    s->var.init = init;
    return s;
}

static Stmt *parse_var_decl_no_semi(Parser *p) {
    int line = p->cur.line;
    Type ty = parse_type(p);
    Token name = expect(p, TOK_IDENT, "expected variable name");
    ty = wrap_with_array_suffix(p, ty);
    Expr *init = NULL;
    if (match_p(p, TOK_ASSIGN)) init = parse_expr(p);
    Stmt *s = new_stmt(ST_VAR_DECL, line);
    s->var.ty = ty;
    s->var.name = name.start;
    s->var.name_len = name.length;
    s->var.init = init;
    return s;
}

static Stmt *parse_assign_no_semi(Parser *p) {
    int line = p->cur.line;
    Token name = expect(p, TOK_IDENT, "expected identifier");
    expect(p, TOK_ASSIGN, "expected '='");
    Expr *val = parse_expr(p);
    Stmt *s = new_stmt(ST_ASSIGN, line);
    s->assign.name = name.start;
    s->assign.name_len = name.length;
    s->assign.value = val;
    return s;
}

static Stmt *parse_block(Parser *p) {
    int line = p->cur.line;
    expect(p, TOK_LBRACE, "expected '{'");
    Stmt **list = NULL;
    size_t n = 0, cap = 0;
    while (!check(p,TOK_RBRACE) && !check(p,TOK_EOF)) {
        Stmt *s = parse_stmt(p);
        if (n == cap) {
            cap = cap ? cap*2 : 8;
            list = realloc(list, cap*sizeof(Stmt*));
        }
        list[n++] = s;
    }
    expect(p, TOK_RBRACE, "expected '}'");
    Stmt *blk = new_stmt(ST_BLOCK, line);
    blk->block.stmts = list;
    blk->block.n = n;
    return blk;
}

static Stmt *parse_stmt(Parser *p) {
    int line = p->cur.line;

    if (is_type_start_p(p)) return parse_var_decl(p);
    if (check(p, TOK_LBRACE)) return parse_block(p);

    if (match_p(p, TOK_IF)) {
        expect(p, TOK_LPAREN, "expected '(' after 'if'");
        Expr *cond = parse_expr(p);
        expect(p, TOK_RPAREN, "expected ')'");
        Stmt *then_b = parse_block(p);
        Stmt *else_b = NULL;
        if (match_p(p, TOK_ELSE)) {
            // Allow `else if (...)` by recursing into parse_stmt; otherwise
            // require a brace block.
            if (check(p, TOK_IF))   else_b = parse_stmt(p);
            else                    else_b = parse_block(p);
        }
        Stmt *s = new_stmt(ST_IF, line);
        s->if_s.cond = cond;
        s->if_s.then_b = then_b;
        s->if_s.else_b = else_b;
        return s;
    }

    if (match_p(p, TOK_WHILE)) {
        expect(p, TOK_LPAREN, "expected '('");
        Expr *cond = parse_expr(p);
        expect(p, TOK_RPAREN, "expected ')'");
        Stmt *body = parse_block(p);
        Stmt *s = new_stmt(ST_WHILE, line);
        s->while_s.cond = cond;
        s->while_s.body = body;
        return s;
    }

    if (match_p(p, TOK_FOR)) {
        expect(p, TOK_LPAREN, "expected '('");
        Stmt *init = NULL;
        if (!check(p, TOK_SEMI)) {
            if (is_type_start_p(p))         init = parse_var_decl_no_semi(p);
            else                            init = parse_assign_no_semi(p);
        }
        expect(p, TOK_SEMI, "expected ';' in for");
        Expr *cond = NULL;
        if (!check(p, TOK_SEMI)) cond = parse_expr(p);
        expect(p, TOK_SEMI, "expected ';' in for");
        Stmt *update = NULL;
        if (!check(p, TOK_RPAREN)) update = parse_assign_no_semi(p);
        expect(p, TOK_RPAREN, "expected ')'");
        Stmt *body = parse_block(p);
        Stmt *s = new_stmt(ST_FOR, line);
        s->for_s.init = init;
        s->for_s.cond = cond;
        s->for_s.update = update;
        s->for_s.body = body;
        return s;
    }

    if (match_p(p, TOK_RETURN)) {
        Expr *v = NULL;
        if (!check(p, TOK_SEMI)) v = parse_expr(p);
        expect(p, TOK_SEMI, "expected ';' after return");
        Stmt *s = new_stmt(ST_RETURN, line);
        s->ret.value = v;
        return s;
    }

    if (match_p(p, TOK_BREAK)) {
        expect(p, TOK_SEMI, "expected ';' after 'break'");
        return new_stmt(ST_BREAK, line);
    }

    if (match_p(p, TOK_CONTINUE)) {
        expect(p, TOK_SEMI, "expected ';' after 'continue'");
        return new_stmt(ST_CONTINUE, line);
    }

    if (check(p,TOK_IDENT) && p->peek.kind == TOK_ASSIGN) {
        Stmt *s = parse_assign_no_semi(p);
        expect(p, TOK_SEMI, "expected ';'");
        return s;
    }

    // Parse an expression and decide between:
    //   *p = e;       -- pointer store
    //   s.f = e;      -- field store
    //   arr[i] = e;   -- index store
    //   foo();        -- expression statement
    Expr *e = parse_expr(p);
    if (check(p, TOK_ASSIGN)) {
        if (e->kind == EX_DEREF) {
            advance_p(p);
            Expr *value = parse_expr(p);
            expect(p, TOK_SEMI, "expected ';'");
            Stmt *s = new_stmt(ST_PTR_STORE, line);
            s->ptr_store.target = e;
            s->ptr_store.value = value;
            return s;
        }
        if (e->kind == EX_FIELD) {
            advance_p(p);
            Expr *value = parse_expr(p);
            expect(p, TOK_SEMI, "expected ';'");
            Stmt *s = new_stmt(ST_FIELD_STORE, line);
            s->field_store.target = e;
            s->field_store.value = value;
            return s;
        }
        if (e->kind == EX_INDEX) {
            advance_p(p);
            Expr *value = parse_expr(p);
            expect(p, TOK_SEMI, "expected ';'");
            Stmt *s = new_stmt(ST_INDEX_STORE, line);
            s->index_store.target = e;
            s->index_store.value = value;
            return s;
        }
        parse_error(p, "left side of '=' must be a variable, '*pointer', 'struct.field', or 'arr[index]'");
    }
    expect(p, TOK_SEMI, "expected ';'");
    Stmt *s = new_stmt(ST_EXPR, line);
    s->expr_s.expr = e;
    return s;
}

static FuncDecl *parse_func(Parser *p) {
    int line = p->cur.line;
    int is_extern = 0;
    if (check(p, TOK_EXTERN)) {
        is_extern = 1;
        advance_p(p);
    }
    Type ret = parse_type(p);
    Token name = expect(p, TOK_IDENT, "expected function name");
    expect(p, TOK_LPAREN, "expected '('");
    Param *params = NULL;
    size_t n = 0, cap = 0;
    if (!check(p, TOK_RPAREN)) {
        for (;;) {
            Type pty = parse_type(p);
            Token pname = expect(p, TOK_IDENT, "expected parameter name");
            if (n == cap) { cap = cap?cap*2:4; params = realloc(params, cap*sizeof(Param)); }
            params[n].ty = pty;
            params[n].name = pname.start;
            params[n].name_len = pname.length;
            n++;
            if (!match_p(p, TOK_COMMA)) break;
        }
    }
    expect(p, TOK_RPAREN, "expected ')'");
    Stmt *body = NULL;
    if (is_extern) {
        expect(p, TOK_SEMI, "expected ';' after extern declaration");
    } else {
        body = parse_block(p);
    }
    FuncDecl *f = xmalloc(sizeof(FuncDecl));
    f->return_ty = ret;
    f->name = name.start;
    f->name_len = name.length;
    f->params = params;
    f->nparams = n;
    f->body = body;
    f->is_extern = is_extern;
    f->line = line;
    return f;
}

// ---- Struct declaration parsing (step 16a) ----

static int parser_type_size(Type t) {
    switch (t.kind) {
        case TY_BOOLEAN: case TY_CHAR: case TY_BYTE:        return 1;
        case TY_INTEGER: case TY_UINTEGER:                  return 2;
        case TY_WHOLE:   case TY_UWHOLE:                    return 4;
        case TY_LONG:    case TY_ULONG:
        case TY_STRING:  case TY_PTR:                       return 8;
        case TY_STRUCT:  return t.sdef ? t.sdef->size : 0;
        case TY_ARRAY:   return t.elem ? parser_type_size(*t.elem) * t.nelems : 0;
        default: return 0;
    }
}
static int parser_type_align(Type t) {
    if (t.kind == TY_STRUCT) return t.sdef ? t.sdef->align : 1;
    if (t.kind == TY_ARRAY) return t.elem ? parser_type_align(*t.elem) : 1;
    return parser_type_size(t);
}

// Parse `struct Name { Type field1; Type field2; ... }`.
// Computes field offsets, total size, and alignment. The struct is added
// to the parser's struct registry tentatively before parsing the body, so
// fields like Ptr<Self> can resolve.
static StructDef *parse_struct_decl(Parser *p) {
    int line = p->cur.line;
    expect(p, TOK_STRUCT, "expected 'struct'");
    Token name = expect(p, TOK_IDENT, "expected struct name");
    if (parser_find_struct(p, name.start, name.length)) {
        parse_error(p, "redeclaration of struct");
    }

    StructDef *sd = xmalloc(sizeof(StructDef));
    sd->name = name.start;
    sd->name_len = name.length;
    sd->line = line;
    sd->fields = NULL;
    sd->nfields = 0;
    sd->size = 0;
    sd->align = 1;
    parser_add_struct(p, sd);  // register before parsing body so Ptr<Self> works

    expect(p, TOK_LBRACE, "expected '{' to begin struct body");

    Field *fields = NULL;
    size_t nf = 0, cap = 0;

    while (!check(p, TOK_RBRACE) && !check(p, TOK_EOF)) {
        Type fty = parse_type(p);
        Token fname = expect(p, TOK_IDENT, "expected field name");
        fty = wrap_with_array_suffix(p, fty);
        expect(p, TOK_SEMI, "expected ';' after field");
        if (fty.kind == TY_VOID || fty.kind == TY_UNKNOWN)
            parse_error(p, "invalid field type");
        if (fty.kind == TY_STRUCT && fty.sdef == sd)
            parse_error(p, "struct cannot directly contain itself; use Ptr<Self>");

        for (size_t i = 0; i < nf; i++) {
            if (fields[i].name_len == fname.length
                && memcmp(fields[i].name, fname.start, fname.length) == 0) {
                parse_error(p, "duplicate field name");
            }
        }
        if (nf == cap) { cap = cap ? cap*2 : 4; fields = realloc(fields, cap*sizeof(Field)); }
        Field f;
        f.ty = fty;
        f.name = fname.start;
        f.name_len = fname.length;
        f.offset = 0;
        fields[nf++] = f;
    }
    expect(p, TOK_RBRACE, "expected '}' to close struct body");

    // Compute offsets, struct size, and alignment.
    int off = 0;
    int align = 1;
    for (size_t i = 0; i < nf; i++) {
        int fsz = parser_type_size(fields[i].ty);
        int fal = parser_type_align(fields[i].ty);
        if (fal < 1) fal = 1;
        if ((off % fal) != 0) off += fal - (off % fal);
        fields[i].offset = off;
        off += fsz;
        if (fal > align) align = fal;
    }
    if (align > 0 && (off % align) != 0) off += align - (off % align);
    if (off == 0) off = 1;

    sd->fields = fields;
    sd->nfields = nf;
    sd->size = off;
    sd->align = align;
    return sd;
}

Program *parse_program(const char *src) {
    Parser p = {0};
    lexer_init(&p.lex, src);
    advance_p(&p); advance_p(&p);

    Program *prog = xmalloc(sizeof(Program));
    FuncDecl **flist = NULL;
    size_t fn = 0, fcap = 0;
    StructDef **slist = NULL;
    size_t sn = 0, scap = 0;

    while (!check(&p, TOK_EOF)) {
        if (check(&p, TOK_STRUCT)) {
            StructDef *sd = parse_struct_decl(&p);
            if (sn == scap) { scap = scap?scap*2:4; slist = realloc(slist, scap*sizeof(StructDef*)); }
            slist[sn++] = sd;
        } else {
            FuncDecl *f = parse_func(&p);
            if (fn == fcap) { fcap = fcap?fcap*2:4; flist = realloc(flist, fcap*sizeof(FuncDecl*)); }
            flist[fn++] = f;
        }
    }
    prog->funcs = flist;
    prog->nfuncs = fn;
    prog->structs = slist;
    prog->nstructs = sn;
    return prog;
}
