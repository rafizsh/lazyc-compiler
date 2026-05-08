#include "typecheck.h"
#include "funcs.h"
#include "types.h"
#include "ast.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>

static int is_signed_numeric(TypeKind k) {
    return k == TY_INTEGER || k == TY_WHOLE || k == TY_LONG;
}
static int is_unsigned_numeric(TypeKind k) {
    return k == TY_UINTEGER || k == TY_UWHOLE || k == TY_ULONG;
}
static int is_numeric(TypeKind k) {
    return is_signed_numeric(k) || is_unsigned_numeric(k);
}

static int type_size(TypeKind k) {
    switch (k) {
        case TY_BOOLEAN: case TY_CHAR: case TY_BYTE:        return 1;
        case TY_INTEGER: case TY_UINTEGER:                  return 2;
        case TY_WHOLE:   case TY_UWHOLE:                    return 4;
        case TY_LONG:    case TY_ULONG:
        case TY_STRING:  case TY_PTR:                       return 8;
        case TY_STRUCT:                                     return 0;  // not meaningful here
        default: return 0;
    }
}

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

static void tc_error(int line, const char *fmt, ...) {
    fprintf(stderr, "type error at line %d: ", line);
    va_list ap; va_start(ap, fmt);
    vfprintf(stderr, fmt, ap);
    va_end(ap);
    fputc('\n', stderr);
    exit(1);
}

static int literal_fits(long long v, TypeKind k) {
    switch (k) {
        case TY_BOOLEAN:  return v == 0 || v == 1;
        case TY_CHAR:     return v >= 0 && v <= 127;
        case TY_BYTE:     return v >= 0 && v <= 255;
        case TY_INTEGER:  return v >= -32768LL && v <= 32767LL;
        case TY_UINTEGER: return v >= 0 && v <= 65535LL;
        case TY_WHOLE:    return v >= -2147483648LL && v <= 2147483647LL;
        case TY_UWHOLE:   return v >= 0 && v <= 4294967295LL;
        case TY_LONG:     return 1;
        case TY_ULONG:    return v >= 0;
        default: return 0;
    }
}

typedef struct { const char *name; size_t name_len; Type ty; } TcSym;
typedef struct {
    TcSym *items;
    size_t count, cap;
    Type   func_return_ty;
    FuncTab *funcs;
    int     loop_depth;       // for break/continue validation
} TcCtx;

static void ctx_init(TcCtx *c, Type ret, FuncTab *funcs) {
    c->items = NULL; c->count = c->cap = 0;
    c->func_return_ty = ret;
    c->funcs = funcs;
    c->loop_depth = 0;
}
static void ctx_free(TcCtx *c) { free(c->items); }

static const TcSym *ctx_find(TcCtx *c, const char *name, size_t n) {
    for (size_t i = 0; i < c->count; i++) {
        TcSym *s = &c->items[i];
        if (s->name_len == n && memcmp(s->name, name, n) == 0) return s;
    }
    return NULL;
}

static void ctx_add(TcCtx *c, const char *name, size_t n, Type ty, int line) {
    if (ctx_find(c, name, n)) {
        tc_error(line, "redeclaration of '%.*s'", (int)n, name);
    }
    if (c->count == c->cap) {
        c->cap = c->cap ? c->cap * 2 : 8;
        c->items = realloc(c->items, c->cap * sizeof(TcSym));
    }
    TcSym s = { name, n, ty };
    c->items[c->count++] = s;
}

static int implicitly_assignable(Expr *e, Type to) {
    if (e->is_untyped_null) {
        if (to.kind == TY_PTR) {
            e->type = to;
            return 1;
        }
        return 0;
    }
    if (e->is_untyped_int) {
        TypeKind k = to.kind;
        int can_coerce = is_numeric(k) || k == TY_BYTE || k == TY_CHAR;
        if (can_coerce && literal_fits(e->num, k)) {
            e->type = to;
            return 1;
        }
        if (can_coerce) return 0;
    }
    if (types_equal(e->type, to)) return 1;
    if (is_numeric(e->type.kind) && is_numeric(to.kind)) {
        int from_signed = is_signed_numeric(e->type.kind);
        int to_signed   = is_signed_numeric(to.kind);
        if (from_signed != to_signed) return 0;
        return type_size(e->type.kind) <= type_size(to.kind);
    }
    return 0;
}

static Type promote_numeric(Type a, Type b) {
    Type bad = type_simple(TY_UNKNOWN);
    if (!is_numeric(a.kind) || !is_numeric(b.kind)) return bad;
    if (is_signed_numeric(a.kind) != is_signed_numeric(b.kind)) return bad;
    return (type_size(a.kind) >= type_size(b.kind)) ? a : b;
}

static int name_eq(const char *a, size_t an, const char *b) {
    size_t bn = strlen(b);
    return an == bn && memcmp(a, b, an) == 0;
}

static void tc_expr(Expr *e, TcCtx *ctx);

// Validate an EX_INDEX node: typecheck base and index, return element type.
// Does NOT enforce the "elem must not be aggregate" rule — the caller decides
// (yes for value-context, no for &arr[i] addr-of).
static Type tc_index_resolve(Expr *e, TcCtx *ctx) {
    Expr *base = e->index.base;
    Type elem_ty;
    elem_ty.kind = TY_UNKNOWN; elem_ty.pointee = NULL;
    elem_ty.sdef = NULL; elem_ty.elem = NULL; elem_ty.nelems = 0;

    if (base->kind == EX_IDENT) {
        const TcSym *s = ctx_find(ctx, base->ident.name, base->ident.len);
        if (!s) tc_error(e->line, "undefined variable '%.*s'",
                         (int)base->ident.len, base->ident.name);
        if (s->ty.kind == TY_ARRAY) {
            base->type = s->ty;       // annotate ident with array type
            elem_ty = *s->ty.elem;
        } else if (s->ty.kind == TY_PTR) {
            base->type = s->ty;
            elem_ty = *s->ty.pointee;
        } else {
            tc_error(e->line,
                "cannot index type %s; expected array or Ptr<T>",
                type_name(s->ty.kind));
        }
    } else {
        tc_expr(base, ctx);
        if (base->type.kind == TY_PTR) {
            elem_ty = *base->type.pointee;
        } else if (base->type.kind == TY_ARRAY) {
            elem_ty = *base->type.elem;
        } else {
            tc_error(e->line,
                "cannot index type %s; expected array or Ptr<T>",
                type_name(base->type.kind));
        }
    }

    tc_expr(e->index.index, ctx);
    Type long_ty = type_simple(TY_LONG);
    if (!implicitly_assignable(e->index.index, long_ty))
        tc_error(e->line,
            "array index must be integer-shaped, got %s",
            type_name(e->index.index->type.kind));

    return elem_ty;
}

static void tc_expr(Expr *e, TcCtx *ctx) {
    switch (e->kind) {
        case EX_NUMBER:
            e->type.kind = TY_LONG;
            return;
        case EX_NULL:
            // Untyped null. Resolves to a concrete Ptr<T> via implicit
            // coercion (same way EX_NUMBER becomes a concrete numeric type).
            // Default if used in an ambiguous context: Ptr<Byte>.
            e->type = type_ptr(type_simple(TY_BYTE));
            return;
        case EX_BOOL_LIT:
            e->type.kind = TY_BOOLEAN;
            return;
        case EX_CHAR_LIT:
            e->type.kind = TY_CHAR;
            return;
        case EX_STRING_LIT:
            e->type.kind = TY_STRING;
            return;
        case EX_IDENT: {
            const TcSym *s = ctx_find(ctx, e->ident.name, e->ident.len);
            if (!s) tc_error(e->line, "undefined variable '%.*s'",
                             (int)e->ident.len, e->ident.name);
            if (s->ty.kind == TY_STRUCT)
                tc_error(e->line,
                    "cannot use struct value '%.*s' in an expression yet "
                    "(field access lands in 16b)",
                    (int)e->ident.len, e->ident.name);
            if (s->ty.kind == TY_ARRAY)
                tc_error(e->line,
                    "cannot use array value '%.*s' as a value; use '%.*s[i]' to index "
                    "or '&%.*s[0]' to get a pointer",
                    (int)e->ident.len, e->ident.name,
                    (int)e->ident.len, e->ident.name,
                    (int)e->ident.len, e->ident.name);
            e->type = s->ty;
            return;
        }
        case EX_CAST:
            tc_expr(e->cast.operand, ctx);
            // Allow cast from Ptr<Byte> to String (heap-backed text).
            // Otherwise casting to String is forbidden.
            if (e->cast.target.kind == TY_STRING) {
                Type from = e->cast.operand->type;
                int ok = (from.kind == TY_PTR
                          && from.pointee
                          && from.pointee->kind == TY_BYTE);
                if (!ok)
                    tc_error(e->line,
                        "cannot cast %s to String (only Ptr<Byte> -> String is allowed)",
                        type_name(from.kind));
            } else if (e->cast.target.kind == TY_VOID) {
                tc_error(e->line, "cannot cast to %s", type_name(e->cast.target.kind));
            }
            // Cast from String: only allowed to Ptr<Byte> (the inverse direction).
            if (e->cast.operand->type.kind == TY_STRING) {
                Type to = e->cast.target;
                int ok = (to.kind == TY_PTR
                          && to.pointee
                          && to.pointee->kind == TY_BYTE);
                if (!ok)
                    tc_error(e->line,
                        "cannot cast from String (only String -> Ptr<Byte> is allowed)");
            }
            e->type = e->cast.target;
            return;
        case EX_ADDR_OF: {
            Expr *t = e->addr.target;
            if (t->kind == EX_IDENT) {
                const TcSym *s = ctx_find(ctx, t->ident.name, t->ident.len);
                if (!s) tc_error(e->line, "undefined variable '%.*s'",
                                 (int)t->ident.len, t->ident.name);
                t->type = s->ty;
                e->type = type_ptr(s->ty);
                return;
            }
            if (t->kind == EX_FIELD) {
                tc_expr(t, ctx);
                e->type = type_ptr(t->type);
                return;
            }
            if (t->kind == EX_INDEX) {
                // For &arr[i], resolve without the aggregate-elem restriction —
                // taking a pointer to a struct or array element is allowed.
                Type elem_ty = tc_index_resolve(t, ctx);
                t->type = elem_ty;
                e->type = type_ptr(elem_ty);
                return;
            }
            tc_error(e->line,
                "'&' requires a variable, 'struct.field', or 'arr[index]' (lvalue), not an expression");
            return;
        }
        case EX_DEREF: {
            tc_expr(e->deref.operand, ctx);
            Type pt = e->deref.operand->type;
            if (pt.kind != TY_PTR)
                tc_error(e->line, "'*' requires a pointer, got %s", type_name(pt.kind));
            e->type = *pt.pointee;
            return;
        }
        case EX_FIELD: {
            // Operand must be either:
            //   (a) EX_IDENT whose type is a struct (16b)
            //   (b) EX_DEREF whose result type is a struct (16e)
            Expr *op = e->field.operand;
            StructDef *sd = NULL;

            if (op->kind == EX_IDENT) {
                const TcSym *s = ctx_find(ctx, op->ident.name, op->ident.len);
                if (!s)
                    tc_error(e->line, "undefined variable '%.*s'",
                             (int)op->ident.len, op->ident.name);
                if (s->ty.kind != TY_STRUCT)
                    tc_error(e->line,
                        "'.field' requires a struct value, got %s",
                        type_name(s->ty.kind));
                op->type = s->ty;     // annotate ident (codegen needs it)
                sd = s->ty.sdef;
            } else if (op->kind == EX_DEREF) {
                // Typecheck the deref normally; result must be a struct.
                tc_expr(op, ctx);
                if (op->type.kind != TY_STRUCT)
                    tc_error(e->line,
                        "'.field' through pointer requires Ptr<struct>, got pointer to %s",
                        type_name(op->type.kind));
                sd = op->type.sdef;
            } else {
                tc_error(e->line,
                    "field access requires a struct variable or '*ptr-to-struct' on the left");
            }

            // Look up the field by name.
            Field *resolved = NULL;
            for (size_t i = 0; i < sd->nfields; i++) {
                Field *f = &sd->fields[i];
                if (f->name_len == e->field.name_len
                    && memcmp(f->name, e->field.name, f->name_len) == 0) {
                    resolved = f;
                    break;
                }
            }
            if (!resolved)
                tc_error(e->line,
                    "struct '%.*s' has no field '%.*s'",
                    (int)sd->name_len, sd->name,
                    (int)e->field.name_len, e->field.name);
            e->field.resolved = resolved;
            e->type = resolved->ty;
            return;
        }
        case EX_INDEX: {
            Type elem_ty = tc_index_resolve(e, ctx);
            // For 17 we don't support indexing-as-value when the element type
            // is itself an aggregate (struct or array). The user can take
            // &arr[i] and dereference fields through the resulting Ptr<>.
            if (elem_ty.kind == TY_STRUCT || elem_ty.kind == TY_ARRAY)
                tc_error(e->line,
                    "indexing yields an aggregate (%s); use &arr[i] to get a pointer "
                    "and access fields through it",
                    type_name(elem_ty.kind));
            e->type = elem_ty;
            return;
        }
        case EX_UNARY:
            tc_expr(e->un.operand, ctx);
            if (e->un.op == OP_NOT) {
                if (e->un.operand->type.kind != TY_BOOLEAN)
                    tc_error(e->line, "operator '!' requires Boolean, got %s",
                             type_name(e->un.operand->type.kind));
                e->type.kind = TY_BOOLEAN;
            } else {
                if (!is_signed_numeric(e->un.operand->type.kind))
                    tc_error(e->line, "unary '-' requires a signed numeric type, got %s",
                             type_name(e->un.operand->type.kind));
                e->type = e->un.operand->type;
                if (e->un.operand->is_untyped_int) {
                    long long folded = -e->un.operand->num;
                    e->kind = EX_NUMBER;
                    e->is_untyped_int = 1;
                    e->num = folded;
                }
            }
            return;
        case EX_BINARY: {
            tc_expr(e->bin.lhs, ctx);
            tc_expr(e->bin.rhs, ctx);

            if (e->bin.lhs->is_untyped_int && !e->bin.rhs->is_untyped_int
                && is_numeric(e->bin.rhs->type.kind)
                && literal_fits(e->bin.lhs->num, e->bin.rhs->type.kind)) {
                e->bin.lhs->type = e->bin.rhs->type;
                e->bin.lhs->is_untyped_int = 0;
            }
            if (e->bin.rhs->is_untyped_int && !e->bin.lhs->is_untyped_int
                && is_numeric(e->bin.lhs->type.kind)
                && literal_fits(e->bin.rhs->num, e->bin.lhs->type.kind)) {
                e->bin.rhs->type = e->bin.lhs->type;
                e->bin.rhs->is_untyped_int = 0;
            }

            // Untyped null vs typed pointer: coerce null to that pointer type.
            if (e->bin.lhs->is_untyped_null && e->bin.rhs->type.kind == TY_PTR) {
                e->bin.lhs->type = e->bin.rhs->type;
                e->bin.lhs->is_untyped_null = 0;
            }
            if (e->bin.rhs->is_untyped_null && e->bin.lhs->type.kind == TY_PTR) {
                e->bin.rhs->type = e->bin.lhs->type;
                e->bin.rhs->is_untyped_null = 0;
            }

            Type L = e->bin.lhs->type, R = e->bin.rhs->type;

            // Pointer arithmetic (step 13d).
            // Allowed: Ptr<T> + Long, Long + Ptr<T>, Ptr<T> - Long,
            //          Ptr<T> - Ptr<T>, and pointer comparisons.
            if (L.kind == TY_PTR || R.kind == TY_PTR) {
                if (e->bin.op == OP_MUL || e->bin.op == OP_DIV || e->bin.op == OP_MOD) {
                    tc_error(e->line, "cannot apply '*' '/' or '%%' to pointers");
                }
                if (e->bin.op == OP_ADD) {
                    Type long_ty = type_simple(TY_LONG);
                    if (L.kind == TY_PTR && implicitly_assignable(e->bin.rhs, long_ty)) {
                        e->type = L;
                        return;
                    }
                    if (R.kind == TY_PTR && implicitly_assignable(e->bin.lhs, long_ty)) {
                        e->type = R;
                        return;
                    }
                    tc_error(e->line, "pointer addition needs Ptr<T> + Long");
                }
                if (e->bin.op == OP_SUB) {
                    if (L.kind == TY_PTR && R.kind == TY_PTR) {
                        if (!types_equal(L, R))
                            tc_error(e->line,
                                "pointer subtraction requires same pointee type");
                        e->type = type_simple(TY_LONG);
                        return;
                    }
                    Type long_ty = type_simple(TY_LONG);
                    if (L.kind == TY_PTR && implicitly_assignable(e->bin.rhs, long_ty)) {
                        e->type = L;
                        return;
                    }
                    tc_error(e->line, "pointer subtraction needs Ptr<T> - Long or Ptr<T> - Ptr<T>");
                }
                if (e->bin.op == OP_EQ || e->bin.op == OP_NEQ) {
                    if (!types_equal(L, R))
                        tc_error(e->line,
                            "pointer comparison requires same pointee type");
                    e->type.kind = TY_BOOLEAN;
                    return;
                }
                if (e->bin.op == OP_LT || e->bin.op == OP_GT
                    || e->bin.op == OP_LE || e->bin.op == OP_GE) {
                    if (!types_equal(L, R))
                        tc_error(e->line,
                            "pointer ordering requires same pointee type");
                    e->type.kind = TY_BOOLEAN;
                    return;
                }
            }

            switch (e->bin.op) {
                case OP_ADD: case OP_SUB: case OP_MUL:
                case OP_DIV: case OP_MOD: {
                    Type r = promote_numeric(L, R);
                    if (r.kind == TY_UNKNOWN)
                        tc_error(e->line,
                            "arithmetic on incompatible types %s and %s "
                            "(use cast<T>(x) for sign/category conversion)",
                            type_name(L.kind), type_name(R.kind));
                    e->type = r;
                    if (e->bin.lhs->is_untyped_int && e->bin.rhs->is_untyped_int) {
                        OpKind op = e->bin.op;
                        long long a = e->bin.lhs->num, b = e->bin.rhs->num;
                        long long folded = 0;
                        switch (op) {
                            case OP_ADD: folded = a + b; break;
                            case OP_SUB: folded = a - b; break;
                            case OP_MUL: folded = a * b; break;
                            case OP_DIV: folded = b ? a / b : 0; break;
                            case OP_MOD: folded = b ? a % b : 0; break;
                            default: break;
                        }
                        e->kind = EX_NUMBER;
                        e->is_untyped_int = 1;
                        e->num = folded;
                    }
                    return;
                }
                case OP_EQ: case OP_NEQ: {
                    if (types_equal(L, R)) { e->type.kind = TY_BOOLEAN; return; }
                    Type r = promote_numeric(L, R);
                    if (r.kind == TY_UNKNOWN)
                        tc_error(e->line,
                            "cannot compare %s and %s for equality",
                            type_name(L.kind), type_name(R.kind));
                    e->type.kind = TY_BOOLEAN;
                    return;
                }
                case OP_LT: case OP_GT: case OP_LE: case OP_GE: {
                    Type r = promote_numeric(L, R);
                    if (r.kind == TY_UNKNOWN)
                        tc_error(e->line,
                            "ordering '%s' requires numeric same-signed operands, got %s and %s",
                            (e->bin.op==OP_LT?"<":e->bin.op==OP_GT?">":
                             e->bin.op==OP_LE?"<=":">="),
                            type_name(L.kind), type_name(R.kind));
                    e->type.kind = TY_BOOLEAN;
                    return;
                }
                default:
                    tc_error(e->line, "internal: unknown binary op");
            }
            return;
        }
        case EX_CALL: {
            int is_print   = name_eq(e->call.name, e->call.name_len, "print");
            int is_println = name_eq(e->call.name, e->call.name_len, "println");

            if (is_print || is_println) {
                if (e->call.nargs < 1)
                    tc_error(e->line, "%s requires at least a format string",
                             is_print ? "print" : "println");

                Expr *fmt = e->call.args[0];
                if (fmt->kind != EX_STRING_LIT)
                    tc_error(e->line, "%s format must be a string literal",
                             is_print ? "print" : "println");
                fmt->type.kind = TY_STRING;

                size_t arg_idx = 1;
                for (size_t i = 0; i < fmt->str.len; i++) {
                    char c = fmt->str.data[i];
                    if (c != '%') continue;
                    if (i + 1 >= fmt->str.len)
                        tc_error(e->line, "trailing '%%' in format string");
                    char spec = fmt->str.data[i + 1];
                    i++;

                    if (spec == '%') continue;

                    TypeKind want;
                    const char *want_name;
                    switch (spec) {
                        case 'c': want = TY_CHAR;    want_name = "Char";    break;
                        case 'i': want = TY_INTEGER; want_name = "Integer"; break;
                        case 'l': want = TY_LONG;    want_name = "Long";    break;
                        case 's': want = TY_STRING;  want_name = "String";  break;
                        default:
                            tc_error(e->line,
                                "unknown format specifier '%%%c' (use %%c %%i %%l %%s or %%%%)",
                                spec);
                            return;  /* unreachable */
                    }

                    if (arg_idx >= e->call.nargs)
                        tc_error(e->line,
                            "format string has more specifiers than arguments");

                    Expr *a = e->call.args[arg_idx++];
                    tc_expr(a, ctx);
                    Type want_ty = type_simple(want);
                    if (!implicitly_assignable(a, want_ty))
                        tc_error(e->line,
                            "argument %zu: '%%%c' expects %s, got %s",
                            arg_idx, spec, want_name, type_name(a->type.kind));
                }

                if (arg_idx != e->call.nargs)
                    tc_error(e->line,
                        "format string has %zu specifier(s) but %zu argument(s) supplied",
                        arg_idx - 1, e->call.nargs - 1);

                e->type.kind = TY_VOID;
                return;
            }

            // Heap and process control built-ins (step 14).
            int is_alloc = name_eq(e->call.name, e->call.name_len, "alloc");
            int is_free  = name_eq(e->call.name, e->call.name_len, "free");
            int is_exit  = name_eq(e->call.name, e->call.name_len, "exit");
            if (is_alloc) {
                if (e->call.nargs != 1)
                    tc_error(e->line, "alloc expects exactly 1 argument, got %zu", e->call.nargs);
                tc_expr(e->call.args[0], ctx);
                Type long_ty = type_simple(TY_LONG);
                if (!implicitly_assignable(e->call.args[0], long_ty))
                    tc_error(e->line, "alloc expects a Long size, got %s",
                             type_name(e->call.args[0]->type.kind));
                e->type = type_ptr(type_simple(TY_BYTE));
                return;
            }
            if (is_free) {
                if (e->call.nargs != 1)
                    tc_error(e->line, "free expects exactly 1 argument, got %zu", e->call.nargs);
                tc_expr(e->call.args[0], ctx);
                Type byte_ptr = type_ptr(type_simple(TY_BYTE));
                if (!implicitly_assignable(e->call.args[0], byte_ptr))
                    tc_error(e->line, "free expects Ptr<Byte>, got %s",
                             type_name(e->call.args[0]->type.kind));
                e->type = type_simple(TY_BOOLEAN);
                return;
            }
            if (is_exit) {
                if (e->call.nargs != 1)
                    tc_error(e->line, "exit expects exactly 1 argument, got %zu", e->call.nargs);
                tc_expr(e->call.args[0], ctx);
                Type long_ty = type_simple(TY_LONG);
                if (!implicitly_assignable(e->call.args[0], long_ty))
                    tc_error(e->line, "exit expects a Long code, got %s",
                             type_name(e->call.args[0]->type.kind));
                e->type = type_simple(TY_LONG);  // never returns; type for tc convenience
                return;
            }

            // File I/O built-ins (step 15).
            int is_readf  = name_eq(e->call.name, e->call.name_len, "readf");
            int is_writef = name_eq(e->call.name, e->call.name_len, "writef");
            if (is_readf) {
                if (e->call.nargs != 1)
                    tc_error(e->line, "readf expects exactly 1 argument, got %zu", e->call.nargs);
                tc_expr(e->call.args[0], ctx);
                Type str_ty = type_simple(TY_STRING);
                if (!implicitly_assignable(e->call.args[0], str_ty))
                    tc_error(e->line, "readf expects a String path, got %s",
                             type_name(e->call.args[0]->type.kind));
                e->type = type_ptr(type_simple(TY_BYTE));
                return;
            }
            if (is_writef) {
                if (e->call.nargs != 2)
                    tc_error(e->line, "writef expects exactly 2 arguments, got %zu", e->call.nargs);
                tc_expr(e->call.args[0], ctx);
                tc_expr(e->call.args[1], ctx);
                Type str_ty = type_simple(TY_STRING);
                Type byte_ptr = type_ptr(type_simple(TY_BYTE));
                if (!implicitly_assignable(e->call.args[0], str_ty))
                    tc_error(e->line, "writef expects a String path, got %s",
                             type_name(e->call.args[0]->type.kind));
                if (!implicitly_assignable(e->call.args[1], byte_ptr))
                    tc_error(e->line, "writef expects Ptr<Byte> contents, got %s",
                             type_name(e->call.args[1]->type.kind));
                e->type = type_simple(TY_BOOLEAN);
                return;
            }

            // argv built-ins (step 21b).
            int is_argc = name_eq(e->call.name, e->call.name_len, "argc");
            int is_argv = name_eq(e->call.name, e->call.name_len, "argv");
            if (is_argc) {
                if (e->call.nargs != 0)
                    tc_error(e->line, "argc expects 0 arguments, got %zu", e->call.nargs);
                e->type = type_simple(TY_LONG);
                return;
            }
            if (is_argv) {
                if (e->call.nargs != 1)
                    tc_error(e->line, "argv expects exactly 1 argument, got %zu", e->call.nargs);
                tc_expr(e->call.args[0], ctx);
                Type long_ty = type_simple(TY_LONG);
                if (!implicitly_assignable(e->call.args[0], long_ty))
                    tc_error(e->line, "argv expects a Long index, got %s",
                             type_name(e->call.args[0]->type.kind));
                e->type = type_ptr(type_simple(TY_BYTE));
                return;
            }

            // User-defined function.
            const FuncSig *sig = funcs_find(ctx->funcs, e->call.name, e->call.name_len);
            if (!sig)
                tc_error(e->line, "call to undefined function '%.*s'",
                         (int)e->call.name_len, e->call.name);
            if (e->call.nargs != sig->nparams)
                tc_error(e->line, "function '%.*s' expects %zu argument(s), got %zu",
                         (int)e->call.name_len, e->call.name,
                         sig->nparams, e->call.nargs);
            for (size_t i = 0; i < e->call.nargs; i++) {
                tc_expr(e->call.args[i], ctx);
                if (!implicitly_assignable(e->call.args[i], sig->params[i].ty))
                    tc_error(e->line,
                        "argument %zu to '%.*s': cannot pass %s to parameter of type %s",
                        i + 1,
                        (int)e->call.name_len, e->call.name,
                        type_name(e->call.args[i]->type.kind),
                        type_name(sig->params[i].ty.kind));
            }
            e->type = sig->return_ty;
            return;
        }
    }
}

static void tc_stmt(Stmt *s, TcCtx *ctx) {
    switch (s->kind) {
        case ST_VAR_DECL: {
            if (s->var.ty.kind == TY_VOID || s->var.ty.kind == TY_UNKNOWN)
                tc_error(s->line, "invalid variable type");
            if (s->var.ty.kind == TY_STRUCT && s->var.init) {
                tc_error(s->line,
                    "struct variables cannot be initialized yet "
                    "(struct values aren't constructible until later steps)");
            }
            if (s->var.ty.kind == TY_ARRAY && s->var.init) {
                tc_error(s->line,
                    "array variables cannot be initialized yet "
                    "(use arr[i] = ... in subsequent statements)");
            }
            if (s->var.init) {
                tc_expr(s->var.init, ctx);
                if (!implicitly_assignable(s->var.init, s->var.ty))
                    tc_error(s->line,
                        "cannot initialize %s with value of type %s",
                        type_name(s->var.ty.kind),
                        type_name(s->var.init->type.kind));
            }
            ctx_add(ctx, s->var.name, s->var.name_len, s->var.ty, s->line);
            return;
        }
        case ST_ASSIGN: {
            const TcSym *sy = ctx_find(ctx, s->assign.name, s->assign.name_len);
            if (!sy) tc_error(s->line, "assignment to undefined variable '%.*s'",
                              (int)s->assign.name_len, s->assign.name);
            tc_expr(s->assign.value, ctx);
            if (!implicitly_assignable(s->assign.value, sy->ty))
                tc_error(s->line,
                    "cannot assign %s to variable '%.*s' of type %s",
                    type_name(s->assign.value->type.kind),
                    (int)s->assign.name_len, s->assign.name,
                    type_name(sy->ty.kind));
            return;
        }
        case ST_PTR_STORE: {
            // s->ptr_store.target is an EX_DEREF (parser enforces this).
            // Typecheck the deref so its type becomes the pointee type T.
            tc_expr(s->ptr_store.target, ctx);
            Type pointee_ty = s->ptr_store.target->type;
            tc_expr(s->ptr_store.value, ctx);
            if (!implicitly_assignable(s->ptr_store.value, pointee_ty))
                tc_error(s->line,
                    "cannot store %s through pointer to %s",
                    type_name(s->ptr_store.value->type.kind),
                    type_name(pointee_ty.kind));
            return;
        }
        case ST_FIELD_STORE: {
            // s->field_store.target is an EX_FIELD (parser enforces this).
            // Typecheck it so .resolved gets filled in and its type becomes
            // the field's type.
            tc_expr(s->field_store.target, ctx);
            Type field_ty = s->field_store.target->type;
            tc_expr(s->field_store.value, ctx);
            if (!implicitly_assignable(s->field_store.value, field_ty))
                tc_error(s->line,
                    "cannot store %s into field of type %s",
                    type_name(s->field_store.value->type.kind),
                    type_name(field_ty.kind));
            return;
        }
        case ST_INDEX_STORE: {
            // s->index_store.target is an EX_INDEX (parser enforces this).
            // Typechecking it sets its type to the element type.
            tc_expr(s->index_store.target, ctx);
            Type elem_ty = s->index_store.target->type;
            tc_expr(s->index_store.value, ctx);
            if (!implicitly_assignable(s->index_store.value, elem_ty))
                tc_error(s->line,
                    "cannot store %s into element of type %s",
                    type_name(s->index_store.value->type.kind),
                    type_name(elem_ty.kind));
            return;
        }
        case ST_RETURN: {
            if (s->ret.value) {
                tc_expr(s->ret.value, ctx);
                if (!implicitly_assignable(s->ret.value, ctx->func_return_ty))
                    tc_error(s->line,
                        "cannot return %s from function declared to return %s",
                        type_name(s->ret.value->type.kind),
                        type_name(ctx->func_return_ty.kind));
            } else if (ctx->func_return_ty.kind != TY_VOID) {
                tc_error(s->line,
                    "missing return value (function returns %s)",
                    type_name(ctx->func_return_ty.kind));
            }
            return;
        }
        case ST_IF:
            tc_expr(s->if_s.cond, ctx);
            if (s->if_s.cond->type.kind != TY_BOOLEAN)
                tc_error(s->line, "if-condition must be Boolean, got %s",
                         type_name(s->if_s.cond->type.kind));
            tc_stmt(s->if_s.then_b, ctx);
            if (s->if_s.else_b) tc_stmt(s->if_s.else_b, ctx);
            return;
        case ST_WHILE:
            tc_expr(s->while_s.cond, ctx);
            if (s->while_s.cond->type.kind != TY_BOOLEAN)
                tc_error(s->line, "while-condition must be Boolean, got %s",
                         type_name(s->while_s.cond->type.kind));
            ctx->loop_depth++;
            tc_stmt(s->while_s.body, ctx);
            ctx->loop_depth--;
            return;
        case ST_FOR:
            if (s->for_s.init) tc_stmt(s->for_s.init, ctx);
            if (s->for_s.cond) {
                tc_expr(s->for_s.cond, ctx);
                if (s->for_s.cond->type.kind != TY_BOOLEAN)
                    tc_error(s->line, "for-condition must be Boolean, got %s",
                             type_name(s->for_s.cond->type.kind));
            }
            ctx->loop_depth++;
            tc_stmt(s->for_s.body, ctx);
            ctx->loop_depth--;
            // The update runs after each iteration; typecheck it AFTER body so
            // names declared in init are in scope for body and update.
            // (Update can't legally be a var-decl per the parser, but type-
            // checking it doesn't hurt.)
            if (s->for_s.update) tc_stmt(s->for_s.update, ctx);
            return;
        case ST_BREAK:
            if (ctx->loop_depth == 0)
                tc_error(s->line, "'break' is only valid inside a loop");
            return;
        case ST_CONTINUE:
            if (ctx->loop_depth == 0)
                tc_error(s->line, "'continue' is only valid inside a loop");
            return;
        case ST_BLOCK:
            for (size_t i = 0; i < s->block.n; i++)
                tc_stmt(s->block.stmts[i], ctx);
            return;
        case ST_EXPR:
            tc_expr(s->expr_s.expr, ctx);
            return;
    }
}

void typecheck_program(Program *p) {
    FuncTab funcs; funcs_init(&funcs);

    // Pass A: collect signatures so calls (including recursive) can find them.
    for (size_t i = 0; i < p->nfuncs; i++) funcs_add(&funcs, p->funcs[i]);

    // Pass B: check each body.
    for (size_t i = 0; i < p->nfuncs; i++) {
        if (p->funcs[i]->is_extern) continue;
        TcCtx ctx; ctx_init(&ctx, p->funcs[i]->return_ty, &funcs);
        for (size_t j = 0; j < p->funcs[i]->nparams; j++)
            ctx_add(&ctx, p->funcs[i]->params[j].name,
                    p->funcs[i]->params[j].name_len,
                    p->funcs[i]->params[j].ty,
                    p->funcs[i]->line);
        tc_stmt(p->funcs[i]->body, &ctx);
        ctx_free(&ctx);
    }

    funcs_free(&funcs);
}
