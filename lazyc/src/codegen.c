#include "codegen.h"
#include "symtab.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>

static void emit(FILE *o, const char *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    vfprintf(o, fmt, ap);
    va_end(ap);
    fputc('\n', o);
}

static void cg_error(const char *msg, int line) {
    fprintf(stderr, "codegen error at line %d: %s\n", line, msg);
    exit(1);
}

// ---- Label generation ----
static int label_counter = 0;
static int new_label(void) { return label_counter++; }

// Loop stack: tracks the current break/continue targets for nested loops.
// Pushed on entry to a while/for, popped on exit. Empty means we're not
// inside any loop (so break/continue are errors — caught at typecheck).
typedef struct { int break_lbl; int continue_lbl; } LoopFrame;
static LoopFrame loop_stack[64];
static int loop_depth = 0;

static void loop_push(int break_lbl, int continue_lbl) {
    if (loop_depth >= 64) {
        fprintf(stderr, "codegen error: loop nesting too deep\n");
        exit(1);
    }
    loop_stack[loop_depth].break_lbl = break_lbl;
    loop_stack[loop_depth].continue_lbl = continue_lbl;
    loop_depth++;
}

static void loop_pop(void) {
    if (loop_depth <= 0) {
        fprintf(stderr, "codegen error: loop_pop with empty stack\n");
        exit(1);
    }
    loop_depth--;
}

static int loop_break_lbl(void)    { return loop_stack[loop_depth - 1].break_lbl; }
static int loop_continue_lbl(void) { return loop_stack[loop_depth - 1].continue_lbl; }

// ---- String literal interning (step 10) ----
typedef struct {
    int label_id;
    const char *data;
    size_t len;
} StrLit;

static StrLit *strlits = NULL;
static size_t  strlits_count = 0, strlits_cap = 0;

static int intern_strlit(const char *data, size_t len) {
    if (strlits_count == strlits_cap) {
        strlits_cap = strlits_cap ? strlits_cap * 2 : 8;
        strlits = realloc(strlits, strlits_cap * sizeof(StrLit));
    }
    int id = (int)strlits_count;
    StrLit s = { id, data, len };
    strlits[strlits_count++] = s;
    return id;
}

// ---- Cooked (escape-processed) string slices for format calls ----
// These already have \n etc. decoded. Kept in a separate table from
// strlits, with their own .Lcstr<N> label namespace.
typedef struct {
    int label_id;
    char *bytes;
    size_t len;
} CookedStr;

static CookedStr *cooked = NULL;
static size_t cooked_count = 0, cooked_cap = 0;

static int intern_cooked(const char *src, size_t len) {
    char *buf = malloc(len + 1);
    if (!buf) { fprintf(stderr, "out of memory\n"); exit(1); }
    size_t out = 0;
    for (size_t i = 0; i < len; i++) {
        char c = src[i];
        if (c == '\\' && i + 1 < len) {
            char esc = src[++i];
            switch (esc) {
                case 'n':  c = '\n'; break;
                case 't':  c = '\t'; break;
                case 'r':  c = '\r'; break;
                case '0':  c = '\0'; break;
                case '\\': c = '\\'; break;
                case '\'': c = '\''; break;
                case '"':  c = '"';  break;
                case 'x': {
                    // \xHH — exactly two hex digits.
                    if (i + 2 >= len) { c = 'x'; break; }
                    char h1 = src[i+1];
                    char h2 = src[i+2];
                    int d1 = -1, d2 = -1;
                    if      (h1 >= '0' && h1 <= '9') d1 = h1 - '0';
                    else if (h1 >= 'a' && h1 <= 'f') d1 = h1 - 'a' + 10;
                    else if (h1 >= 'A' && h1 <= 'F') d1 = h1 - 'A' + 10;
                    if      (h2 >= '0' && h2 <= '9') d2 = h2 - '0';
                    else if (h2 >= 'a' && h2 <= 'f') d2 = h2 - 'a' + 10;
                    else if (h2 >= 'A' && h2 <= 'F') d2 = h2 - 'A' + 10;
                    if (d1 < 0 || d2 < 0) { c = 'x'; break; }
                    c = (char)(d1 * 16 + d2);
                    i += 2;
                    break;
                }
                default:   c = esc;  break;
            }
        }
        buf[out++] = c;
    }
    buf[out] = 0;
    if (cooked_count == cooked_cap) {
        cooked_cap = cooked_cap ? cooked_cap * 2 : 8;
        cooked = realloc(cooked, cooked_cap * sizeof(CookedStr));
    }
    int id = (int)cooked_count;
    CookedStr cs = { id, buf, out };
    cooked[cooked_count++] = cs;
    return id;
}

// ---- Type helpers ----
static int type_size(TypeKind k) {
    switch (k) {
        case TY_BOOLEAN: case TY_CHAR: case TY_BYTE:        return 1;
        case TY_INTEGER: case TY_UINTEGER:                  return 2;
        case TY_WHOLE:   case TY_UWHOLE:                    return 4;
        case TY_LONG:    case TY_ULONG:
        case TY_STRING:  case TY_PTR:                       return 8;
        default: return 8;
    }
}

static int is_signed_ty(TypeKind k) {
    return k == TY_INTEGER || k == TY_WHOLE || k == TY_LONG;
}

static void load_var(FILE *o, Type ty, int offset) {
    int sz = type_size(ty.kind);
    int sgn = is_signed_ty(ty.kind);
    switch (sz) {
        case 1:
            if (sgn) emit(o, "    movsx rax, byte [rbp-%d]", offset);
            else     emit(o, "    movzx rax, byte [rbp-%d]", offset);
            break;
        case 2:
            if (sgn) emit(o, "    movsx rax, word [rbp-%d]", offset);
            else     emit(o, "    movzx rax, word [rbp-%d]", offset);
            break;
        case 4:
            if (sgn) emit(o, "    movsxd rax, dword [rbp-%d]", offset);
            else     emit(o, "    mov eax, dword [rbp-%d]", offset);
            break;
        case 8:
        default:
            emit(o, "    mov rax, [rbp-%d]", offset);
            break;
    }
}

static void store_var(FILE *o, Type ty, int offset) {
    int sz = type_size(ty.kind);
    switch (sz) {
        case 1: emit(o, "    mov byte  [rbp-%d], al",  offset); break;
        case 2: emit(o, "    mov word  [rbp-%d], ax",  offset); break;
        case 4: emit(o, "    mov dword [rbp-%d], eax", offset); break;
        case 8:
        default: emit(o, "    mov qword [rbp-%d], rax", offset); break;
    }
}

// Byte size of any type, including struct and array. Used by zero_var
// and elsewhere when total storage size matters.
static int type_total_bytes(Type ty) {
    switch (ty.kind) {
        case TY_BOOLEAN: case TY_CHAR: case TY_BYTE:        return 1;
        case TY_INTEGER: case TY_UINTEGER:                  return 2;
        case TY_WHOLE:   case TY_UWHOLE:                    return 4;
        case TY_LONG:    case TY_ULONG:
        case TY_STRING:  case TY_PTR:                       return 8;
        case TY_STRUCT:  return ty.sdef ? ty.sdef->size : 0;
        case TY_ARRAY:   return ty.elem ? type_total_bytes(*ty.elem) * ty.nelems : 0;
        default: return 0;
    }
}

// Zero a possibly-multi-byte stack slot in 8/4/2/1-byte chunks.
static void zero_slot(FILE *o, int offset, int sz) {
    int pos = 0;
    while (pos + 8 <= sz) {
        emit(o, "    mov qword [rbp-%d], 0", offset - pos);
        pos += 8;
    }
    while (pos + 4 <= sz) {
        emit(o, "    mov dword [rbp-%d], 0", offset - pos);
        pos += 4;
    }
    while (pos + 2 <= sz) {
        emit(o, "    mov word  [rbp-%d], 0", offset - pos);
        pos += 2;
    }
    while (pos + 1 <= sz) {
        emit(o, "    mov byte  [rbp-%d], 0", offset - pos);
        pos += 1;
    }
}

static void zero_var(FILE *o, Type ty, int offset) {
    if (ty.kind == TY_STRUCT || ty.kind == TY_ARRAY) {
        zero_slot(o, offset, type_total_bytes(ty));
        return;
    }
    int sz = type_size(ty.kind);
    switch (sz) {
        case 1: emit(o, "    mov byte  [rbp-%d], 0", offset); break;
        case 2: emit(o, "    mov word  [rbp-%d], 0", offset); break;
        case 4: emit(o, "    mov dword [rbp-%d], 0", offset); break;
        case 8:
        default: emit(o, "    mov qword [rbp-%d], 0", offset); break;
    }
}

// ---- Argument-passing registers (System V AMD64) ----
static const char *arg_reg_64(int i) {
    static const char *r[] = {"rdi","rsi","rdx","rcx","r8","r9"};
    return r[i];
}
static const char *arg_reg_for_size(int i, int sz) {
    static const char *r64[] = {"rdi","rsi","rdx","rcx","r8","r9"};
    static const char *r32[] = {"edi","esi","edx","ecx","r8d","r9d"};
    static const char *r16[] = {"di","si","dx","cx","r8w","r9w"};
    static const char *r8_ [] = {"dil","sil","dl","cl","r8b","r9b"};
    switch (sz) {
        case 1: return r8_[i];
        case 2: return r16[i];
        case 4: return r32[i];
        case 8:
        default: return r64[i];
    }
}

// ---- Pass 1: collect locals ----
static void collect_locals_stmt(Stmt *s, SymTab *st) {
    if (!s) return;
    switch (s->kind) {
        case ST_VAR_DECL:
            symtab_add(st, s->var.name, s->var.name_len, s->var.ty, s->line);
            break;
        case ST_BLOCK:
            for (size_t i = 0; i < s->block.n; i++)
                collect_locals_stmt(s->block.stmts[i], st);
            break;
        case ST_IF:
            collect_locals_stmt(s->if_s.then_b, st);
            if (s->if_s.else_b) collect_locals_stmt(s->if_s.else_b, st);
            break;
        case ST_WHILE:
            collect_locals_stmt(s->while_s.body, st);
            break;
        case ST_FOR:
            collect_locals_stmt(s->for_s.init, st);
            collect_locals_stmt(s->for_s.body, st);
            break;
        default: break;
    }
}

// ---- Pass 2: emit code ----
static void gen_expr(Expr *e, FILE *o, SymTab *st);

static void gen_binary(Expr *e, FILE *o, SymTab *st) {
    // Pointer arithmetic and pointer comparisons need special handling.
    Type Lt = e->bin.lhs->type;
    Type Rt = e->bin.rhs->type;
    int lhs_is_ptr = (Lt.kind == TY_PTR);
    int rhs_is_ptr = (Rt.kind == TY_PTR);

    // Helper: emit code to scale rax by sizeof(pointee) for the given pointer type.
    // For sz==1 we skip the scale entirely.
    if ((lhs_is_ptr || rhs_is_ptr) &&
        (e->bin.op == OP_ADD || e->bin.op == OP_SUB)) {

        // Result type tells us the pointee for ADD and Ptr-Long SUB.
        // For Ptr - Ptr, both operand types share the pointee.
        // We use type_total_bytes (not type_size) so that Ptr<struct>
        // and Ptr<T[N]> scale by the correct full size.
        Type ptr_ty;
        if (lhs_is_ptr) ptr_ty = Lt;
        else            ptr_ty = Rt;
        int sz = type_total_bytes(*ptr_ty.pointee);

        // Evaluate both sides; pop into rax (lhs) and rcx (rhs).
        gen_expr(e->bin.lhs, o, st);
        gen_expr(e->bin.rhs, o, st);
        emit(o, "    pop rcx");
        emit(o, "    pop rax");

        if (e->bin.op == OP_ADD) {
            // One side is Ptr, other is Long. Scale the Long side.
            // After our pop: rax = lhs, rcx = rhs.
            if (lhs_is_ptr) {
                // rax is ptr, rcx is Long -> scale rcx
                if (sz != 1) emit(o, "    imul rcx, rcx, %d", sz);
                emit(o, "    add rax, rcx");
            } else {
                // rax is Long, rcx is ptr -> scale rax, then add (commutative)
                if (sz != 1) emit(o, "    imul rax, rax, %d", sz);
                emit(o, "    add rax, rcx");
            }
            emit(o, "    push rax");
            return;
        }

        // OP_SUB
        if (lhs_is_ptr && rhs_is_ptr) {
            // (lhs - rhs) / sz  -> count of Ts between them
            emit(o, "    sub rax, rcx");
            if (sz != 1) {
                emit(o, "    cqo");
                emit(o, "    mov r10, %d", sz);
                emit(o, "    idiv r10");
            }
            emit(o, "    push rax");
            return;
        }
        // ptr - Long: scale rcx, then sub.
        if (sz != 1) emit(o, "    imul rcx, rcx, %d", sz);
        emit(o, "    sub rax, rcx");
        emit(o, "    push rax");
        return;
    }

    // Default path (numeric arithmetic, comparisons).
    gen_expr(e->bin.lhs, o, st);
    gen_expr(e->bin.rhs, o, st);
    emit(o, "    pop rcx");
    emit(o, "    pop rax");
    switch (e->bin.op) {
        case OP_ADD: emit(o, "    add rax, rcx"); break;
        case OP_SUB: emit(o, "    sub rax, rcx"); break;
        case OP_MUL: emit(o, "    imul rax, rcx"); break;
        case OP_DIV:
            emit(o, "    cqo");
            emit(o, "    idiv rcx");
            break;
        case OP_MOD:
            emit(o, "    cqo");
            emit(o, "    idiv rcx");
            emit(o, "    mov rax, rdx");
            break;
        case OP_EQ: case OP_NEQ:
        case OP_LT: case OP_GT: case OP_LE: case OP_GE: {
            emit(o, "    cmp rax, rcx");
            // Pointers are compared unsigned. Same-typed primitives use the
            // signedness of the operand type.
            int unsigned_cmp = (lhs_is_ptr || rhs_is_ptr)
                ? 1
                : !is_signed_ty(e->bin.lhs->type.kind);
            const char *setcc;
            switch (e->bin.op) {
                case OP_EQ:  setcc = "sete";  break;
                case OP_NEQ: setcc = "setne"; break;
                case OP_LT:  setcc = unsigned_cmp ? "setb"  : "setl";  break;
                case OP_GT:  setcc = unsigned_cmp ? "seta"  : "setg";  break;
                case OP_LE:  setcc = unsigned_cmp ? "setbe" : "setle"; break;
                case OP_GE:  setcc = unsigned_cmp ? "setae" : "setge"; break;
                default: setcc = "sete";
            }
            emit(o, "    %s al", setcc);
            emit(o, "    movzx rax, al");
            break;
        }
        default: cg_error("unknown binary op", e->line);
    }
    emit(o, "    push rax");
}

static void gen_unary(Expr *e, FILE *o, SymTab *st) {
    gen_expr(e->un.operand, o, st);
    emit(o, "    pop rax");
    switch (e->un.op) {
        case OP_NEG:
            emit(o, "    neg rax");
            break;
        case OP_NOT:
            emit(o, "    cmp rax, 0");
            emit(o, "    sete al");
            emit(o, "    movzx rax, al");
            break;
        default: cg_error("unknown unary op", e->line);
    }
    emit(o, "    push rax");
}

static void gen_cast(Expr *e, FILE *o, SymTab *st) {
    gen_expr(e->cast.operand, o, st);
    emit(o, "    pop rax");

    Type from = e->cast.operand->type;
    Type to   = e->cast.target;

    if (to.kind == TY_BOOLEAN) {
        emit(o, "    cmp rax, 0");
        emit(o, "    setne al");
        emit(o, "    movzx rax, al");
        emit(o, "    push rax");
        return;
    }

    int from_sz = type_size(from.kind);
    int to_sz   = type_size(to.kind);
    int from_sgn = is_signed_ty(from.kind);

    if (from.kind == TY_BOOLEAN || from.kind == TY_CHAR || from.kind == TY_BYTE)
        from_sgn = 0;

    if (to_sz > from_sz) {
        switch (from_sz) {
            case 1:
                if (from_sgn) emit(o, "    movsx rax, al");
                else          emit(o, "    movzx rax, al");
                break;
            case 2:
                if (from_sgn) emit(o, "    movsx rax, ax");
                else          emit(o, "    movzx rax, ax");
                break;
            case 4:
                if (from_sgn) emit(o, "    movsxd rax, eax");
                else          emit(o, "    mov eax, eax");
                break;
        }
    } else if (to_sz < from_sz) {
        int to_sgn = (to.kind == TY_INTEGER || to.kind == TY_WHOLE || to.kind == TY_LONG);
        switch (to_sz) {
            case 1:
                if (to_sgn) emit(o, "    movsx rax, al");
                else        emit(o, "    movzx rax, al");
                break;
            case 2:
                if (to_sgn) emit(o, "    movsx rax, ax");
                else        emit(o, "    movzx rax, ax");
                break;
            case 4:
                if (to_sgn) emit(o, "    movsxd rax, eax");
                else        emit(o, "    mov eax, eax");
                break;
        }
    }
    emit(o, "    push rax");
}

static int name_eq_str(const char *a, size_t an, const char *b) {
    size_t bn = strlen(b);
    return an == bn && memcmp(a, b, an) == 0;
}

// Emit a print/println call by walking the format string and emitting one
// runtime call per segment. Typechecker has already validated everything.
static void gen_format_call(Expr *e, FILE *o, SymTab *st, int append_newline) {
    Expr *fmt = e->call.args[0];
    const char *src = fmt->str.data;
    size_t len = fmt->str.len;

    size_t i = 0;
    size_t arg_idx = 1;

    while (i < len) {
        // Collect a raw run up to the next '%'.
        size_t start = i;
        while (i < len && src[i] != '%') i++;

        if (i > start) {
            int id = intern_cooked(src + start, i - start);
            size_t cooked_len = cooked[cooked_count - 1].len;
            emit(o, "    lea rdi, [rel Lcstr_%d]", id);
            emit(o, "    mov rsi, %zu", cooked_len);
            emit(o, "    call lazyc_write_bytes");
        }

        if (i >= len) break;
        i++;                     // consume '%'
        char spec = src[i++];    // consume spec char

        if (spec == '%') {
            int id = intern_cooked("%", 1);
            emit(o, "    lea rdi, [rel Lcstr_%d]", id);
            emit(o, "    mov rsi, 1");
            emit(o, "    call lazyc_write_bytes");
            continue;
        }

        // Evaluate the corresponding arg via the stack machine, then pop into rdi.
        gen_expr(e->call.args[arg_idx++], o, st);
        emit(o, "    pop rdi");

        switch (spec) {
            case 'c': emit(o, "    call lazyc_print_char");   break;
            case 'i': emit(o, "    call lazyc_print_int16");  break;
            case 'l': emit(o, "    call lazyc_print_long");   break;
            case 's': emit(o, "    call lazyc_print_string"); break;
            default:
                cg_error("internal: unknown format specifier in codegen", e->line);
        }
    }

    if (append_newline) {
        emit(o, "    call lazyc_print_newline");
    }
}

static void gen_call(Expr *e, FILE *o, SymTab *st) {
    int is_print   = name_eq_str(e->call.name, e->call.name_len, "print");
    int is_println = name_eq_str(e->call.name, e->call.name_len, "println");

    if (is_print || is_println) {
        gen_format_call(e, o, st, /*append_newline=*/is_println);
        // print/println return void, but our stack machine pushes a value
        // for every expression. Push a dummy 0 so ST_EXPR can `add rsp, 8`.
        emit(o, "    push 0");
        return;
    }

    // Heap and process built-ins. Same calling pattern: 1 arg in rdi,
    // result in rax which we push for the stack machine.
    int is_alloc = name_eq_str(e->call.name, e->call.name_len, "alloc");
    int is_free  = name_eq_str(e->call.name, e->call.name_len, "free");
    int is_exit  = name_eq_str(e->call.name, e->call.name_len, "exit");
    if (is_alloc || is_free || is_exit) {
        gen_expr(e->call.args[0], o, st);
        emit(o, "    pop rdi");
        if (is_alloc)      emit(o, "    call lazyc_alloc");
        else if (is_free)  emit(o, "    call lazyc_free");
        else               emit(o, "    call lazyc_exit");
        emit(o, "    push rax");
        return;
    }

    // File I/O built-ins (step 15).
    int is_readf  = name_eq_str(e->call.name, e->call.name_len, "readf");
    int is_writef = name_eq_str(e->call.name, e->call.name_len, "writef");
    if (is_readf) {
        gen_expr(e->call.args[0], o, st);
        emit(o, "    pop rdi");
        emit(o, "    call lazyc_readf");
        emit(o, "    push rax");
        return;
    }
    if (is_writef) {
        gen_expr(e->call.args[0], o, st);
        gen_expr(e->call.args[1], o, st);
        emit(o, "    pop rsi");                  // contents (last arg)
        emit(o, "    pop rdi");                  // path
        emit(o, "    call lazyc_writef");
        emit(o, "    push rax");
        return;
    }

    // argv built-ins (step 21b).
    int is_argc = name_eq_str(e->call.name, e->call.name_len, "argc");
    int is_argv = name_eq_str(e->call.name, e->call.name_len, "argv");
    if (is_argc) {
        emit(o, "    call lazyc_argc");
        emit(o, "    push rax");
        return;
    }
    if (is_argv) {
        gen_expr(e->call.args[0], o, st);
        emit(o, "    pop rdi");
        emit(o, "    call lazyc_argv");
        emit(o, "    push rax");
        return;
    }

    if (e->call.nargs > 6)
        cg_error("calls with more than 6 arguments are not supported", e->line);

    for (size_t i = 0; i < e->call.nargs; i++)
        gen_expr(e->call.args[i], o, st);
    for (size_t i = e->call.nargs; i > 0; i--)
        emit(o, "    pop %s", arg_reg_64((int)(i - 1)));

    emit(o, "    call %.*s", (int)e->call.name_len, e->call.name);
    emit(o, "    push rax");
}

// Push the byte address of an lvalue expression onto the stack.
// Lvalue forms supported:
//   EX_IDENT          -> &local
//   EX_FIELD          -> &s.f or &(*p).f
//   EX_INDEX          -> &arr[i] or &p[i]
//   EX_DEREF          -> *p (the dereferenced address is just p's value)
static void gen_lvalue_address(Expr *e, FILE *o, SymTab *st) {
    if (e->kind == EX_IDENT) {
        const Symbol *sy = symtab_find(st, e->ident.name, e->ident.len);
        if (!sy) cg_error("internal: addr of unknown var", e->line);
        emit(o, "    lea rax, [rbp-%d]", sy->offset);
        emit(o, "    push rax");
        return;
    }
    if (e->kind == EX_DEREF) {
        // The address being dereferenced is just the operand's value.
        gen_expr(e->deref.operand, o, st);
        return;
    }
    if (e->kind == EX_FIELD) {
        Expr *op = e->field.operand;
        Field *f = e->field.resolved;
        if (!f) cg_error("internal: field not resolved", e->line);

        if (op->kind == EX_IDENT && op->type.kind == TY_STRUCT) {
            const Symbol *sy = symtab_find(st, op->ident.name, op->ident.len);
            if (!sy) cg_error("internal: addr-of field on unknown var", e->line);
            int addr = sy->offset - f->offset;
            emit(o, "    lea rax, [rbp-%d]", addr);
            emit(o, "    push rax");
            return;
        }
        if (op->kind == EX_DEREF) {
            // &(*p).field == p + f->offset
            gen_expr(op->deref.operand, o, st);
            emit(o, "    pop rax");
            if (f->offset != 0) emit(o, "    add rax, %d", f->offset);
            emit(o, "    push rax");
            return;
        }
        cg_error("internal: addr-of field with unexpected operand", e->line);
        return;
    }
    if (e->kind == EX_INDEX) {
        int sz = type_total_bytes(e->type);
        // Recurse: get base address (handles array fields, etc).
        Expr *base = e->index.base;
        if (base->type.kind == TY_ARRAY) {
            gen_lvalue_address(base, o, st);
        } else if (base->type.kind == TY_PTR) {
            gen_expr(base, o, st);
        } else {
            cg_error("internal: index base has wrong type", e->line);
        }
        gen_expr(e->index.index, o, st);
        emit(o, "    pop rax");                 // index
        if (sz != 1) emit(o, "    imul rax, rax, %d", sz);
        emit(o, "    pop rcx");                 // base address
        emit(o, "    add rax, rcx");
        emit(o, "    push rax");
        return;
    }
    cg_error("internal: not an lvalue", e->line);
}

// Push the byte address of `base[index]` onto the stack.
// Used by EX_INDEX (read), ST_INDEX_STORE (write), and &arr[i] (no load).
static void gen_index_addr(Expr *base, Expr *index, int elem_size, FILE *o, SymTab *st) {
    // Get base address: if base is an array, take its lvalue address;
    // if base is Ptr<T>, take its value (which IS the address).
    if (base->type.kind == TY_ARRAY) {
        gen_lvalue_address(base, o, st);
    } else if (base->type.kind == TY_PTR) {
        gen_expr(base, o, st);
    } else {
        cg_error("internal: index on non-array, non-pointer", base->line);
    }
    gen_expr(index, o, st);
    emit(o, "    pop rax");                 // index
    if (elem_size != 1)
        emit(o, "    imul rax, rax, %d", elem_size);
    emit(o, "    pop rcx");                 // base address
    emit(o, "    add rax, rcx");
    emit(o, "    push rax");                // address of element
}

static void gen_expr(Expr *e, FILE *o, SymTab *st) {
    switch (e->kind) {
        case EX_NUMBER:
            emit(o, "    mov rax, %lld", e->num);
            emit(o, "    push rax");
            break;
        case EX_BOOL_LIT:
            emit(o, "    mov rax, %d", e->boolean ? 1 : 0);
            emit(o, "    push rax");
            break;
        case EX_NULL:
            emit(o, "    xor rax, rax");
            emit(o, "    push rax");
            break;
        case EX_CHAR_LIT:
            emit(o, "    mov rax, %d", (int)(unsigned char)e->ch);
            emit(o, "    push rax");
            break;
        case EX_STRING_LIT: {
            int id = intern_strlit(e->str.data, e->str.len);
            emit(o, "    lea rax, [rel Lstr_%d]", id);
            emit(o, "    push rax");
            break;
        }
        case EX_IDENT: {
            const Symbol *sy = symtab_find(st, e->ident.name, e->ident.len);
            if (!sy) cg_error("internal: variable not in symtab", e->line);
            load_var(o, sy->ty, sy->offset);
            emit(o, "    push rax");
            break;
        }
        case EX_CAST:   gen_cast(e, o, st);   break;
        case EX_BINARY: gen_binary(e, o, st); break;
        case EX_UNARY:  gen_unary(e, o, st);  break;
        case EX_CALL:   gen_call(e, o, st);   break;
        case EX_ADDR_OF: {
            Expr *t = e->addr.target;
            if (t->kind == EX_IDENT) {
                const Symbol *sy = symtab_find(st, t->ident.name, t->ident.len);
                if (!sy) cg_error("internal: addr-of unknown var", e->line);
                emit(o, "    lea rax, [rbp-%d]", sy->offset);
                emit(o, "    push rax");
                break;
            }
            if (t->kind == EX_FIELD) {
                Expr *op = t->field.operand;
                Field *f = t->field.resolved;
                if (!f) cg_error("internal: field not resolved", e->line);

                if (op->kind == EX_IDENT) {
                    // 16d: address inside a stack-allocated struct.
                    const Symbol *sy = symtab_find(st, op->ident.name, op->ident.len);
                    if (!sy) cg_error("internal: addr-of field on unknown var", e->line);
                    int addr = sy->offset - f->offset;
                    emit(o, "    lea rax, [rbp-%d]", addr);
                    emit(o, "    push rax");
                    break;
                }
                if (op->kind == EX_DEREF) {
                    // 16e: &(*p).field == p + f->offset.
                    gen_expr(op->deref.operand, o, st);
                    emit(o, "    pop rax");
                    if (f->offset != 0)
                        emit(o, "    add rax, %d", f->offset);
                    emit(o, "    push rax");
                    break;
                }
                cg_error("internal: addr-of field with unexpected operand", e->line);
                break;
            }
            if (t->kind == EX_INDEX) {
                // 17: &arr[i] = address arithmetic, no load.
                // Use type_total_bytes so this works even for aggregate
                // element types (where the EX_INDEX value-form is rejected
                // but &arr[i] is allowed).
                int sz = type_total_bytes(t->type);
                gen_index_addr(t->index.base, t->index.index, sz, o, st);
                // gen_index_addr already pushed the address.
                break;
            }
            cg_error("internal: unsupported addr-of operand", e->line);
            break;
        }
        case EX_DEREF: {
            // Evaluate the pointer expression, leaving the address in rax.
            gen_expr(e->deref.operand, o, st);
            emit(o, "    pop rax");
            // Now load *rax with the right width and signedness for the pointee.
            Type pointee = *e->deref.operand->type.pointee;
            int sz = type_size(pointee.kind);
            int sgn = is_signed_ty(pointee.kind);
            switch (sz) {
                case 1:
                    if (sgn) emit(o, "    movsx rax, byte [rax]");
                    else     emit(o, "    movzx rax, byte [rax]");
                    break;
                case 2:
                    if (sgn) emit(o, "    movsx rax, word [rax]");
                    else     emit(o, "    movzx rax, word [rax]");
                    break;
                case 4:
                    if (sgn) emit(o, "    movsxd rax, dword [rax]");
                    else     emit(o, "    mov eax, dword [rax]");
                    break;
                case 8:
                default:
                    emit(o, "    mov rax, [rax]");
                    break;
            }
            emit(o, "    push rax");
            break;
        }
        case EX_FIELD: {
            // Operand is either EX_IDENT-of-struct (16b) or EX_DEREF-of-Ptr<struct> (16e).
            // In both cases we compute a pointer to the field, then load.
            Expr *op = e->field.operand;
            Field *f = e->field.resolved;
            if (!f) cg_error("internal: field not resolved by typechecker", e->line);
            int sz = type_size(f->ty.kind);
            int sgn = is_signed_ty(f->ty.kind);

            if (op->kind == EX_IDENT) {
                // Field address is a stack-slot offset.
                const Symbol *sy = symtab_find(st, op->ident.name, op->ident.len);
                if (!sy) cg_error("internal: field access on unknown var", e->line);
                int addr = sy->offset - f->offset;
                switch (sz) {
                    case 1:
                        if (sgn) emit(o, "    movsx rax, byte [rbp-%d]", addr);
                        else     emit(o, "    movzx rax, byte [rbp-%d]", addr);
                        break;
                    case 2:
                        if (sgn) emit(o, "    movsx rax, word [rbp-%d]", addr);
                        else     emit(o, "    movzx rax, word [rbp-%d]", addr);
                        break;
                    case 4:
                        if (sgn) emit(o, "    movsxd rax, dword [rbp-%d]", addr);
                        else     emit(o, "    mov eax, dword [rbp-%d]", addr);
                        break;
                    case 8:
                    default:
                        emit(o, "    mov rax, [rbp-%d]", addr);
                        break;
                }
                emit(o, "    push rax");
                break;
            }

            // op->kind == EX_DEREF: evaluate the *pointer* (the deref's operand),
            // not the deref itself. Add field offset, then load via [rax].
            // Typechecker guarantees op->deref.operand is a Ptr<struct>.
            gen_expr(op->deref.operand, o, st);
            emit(o, "    pop rax");
            if (f->offset != 0)
                emit(o, "    add rax, %d", f->offset);
            switch (sz) {
                case 1:
                    if (sgn) emit(o, "    movsx rax, byte [rax]");
                    else     emit(o, "    movzx rax, byte [rax]");
                    break;
                case 2:
                    if (sgn) emit(o, "    movsx rax, word [rax]");
                    else     emit(o, "    movzx rax, word [rax]");
                    break;
                case 4:
                    if (sgn) emit(o, "    movsxd rax, dword [rax]");
                    else     emit(o, "    mov eax, dword [rax]");
                    break;
                case 8:
                default:
                    emit(o, "    mov rax, [rax]");
                    break;
            }
            emit(o, "    push rax");
            break;
        }
        case EX_INDEX: {
            // The element type is e->type (set by typechecker).
            int sz = type_size(e->type.kind);
            // Special-case: element is a struct or array — we don't have a
            // value-load for those. (Falling into the default branch below
            // still emits a load, which would be wrong for sub-aggregates.)
            // For 17 we don't allow indexing-into-aggregate-element to read
            // the whole sub-aggregate as a value. So restrict here.
            if (e->type.kind == TY_STRUCT || e->type.kind == TY_ARRAY) {
                cg_error("internal: indexed read of aggregate element type "
                         "is not supported (use &arr[i] then field access)", e->line);
            }
            gen_index_addr(e->index.base, e->index.index, sz, o, st);
            // Pop address into rax, do sized/signed load.
            emit(o, "    pop rax");
            int sgn = is_signed_ty(e->type.kind);
            switch (sz) {
                case 1:
                    if (sgn) emit(o, "    movsx rax, byte [rax]");
                    else     emit(o, "    movzx rax, byte [rax]");
                    break;
                case 2:
                    if (sgn) emit(o, "    movsx rax, word [rax]");
                    else     emit(o, "    movzx rax, word [rax]");
                    break;
                case 4:
                    if (sgn) emit(o, "    movsxd rax, dword [rax]");
                    else     emit(o, "    mov eax, dword [rax]");
                    break;
                case 8:
                default:
                    emit(o, "    mov rax, [rax]");
                    break;
            }
            emit(o, "    push rax");
            break;
        }
    }
}

static void gen_stmt(Stmt *s, FILE *o, SymTab *st) {
    switch (s->kind) {
        case ST_VAR_DECL: {
            const Symbol *sy = symtab_find(st, s->var.name, s->var.name_len);
            if (!sy) cg_error("internal: var not in symtab", s->line);
            if (s->var.init) {
                gen_expr(s->var.init, o, st);
                emit(o, "    pop rax");
                store_var(o, sy->ty, sy->offset);
            } else {
                zero_var(o, sy->ty, sy->offset);
            }
            break;
        }
        case ST_ASSIGN: {
            const Symbol *sy = symtab_find(st, s->assign.name, s->assign.name_len);
            if (!sy) cg_error("internal: assignment to unknown var", s->line);
            gen_expr(s->assign.value, o, st);
            emit(o, "    pop rax");
            store_var(o, sy->ty, sy->offset);
            break;
        }
        case ST_PTR_STORE: {
            // s->ptr_store.target is an EX_DEREF; we need the *pointer* not the
            // dereferenced value. So we evaluate target->deref.operand directly.
            Expr *deref = s->ptr_store.target;
            Expr *pexpr = deref->deref.operand;     // the pointer expression
            // Pointee type from typechecker (= type of the deref expression).
            Type pointee = deref->type;

            // Evaluate pointer first, then value (left-to-right semantics).
            gen_expr(pexpr, o, st);
            gen_expr(s->ptr_store.value, o, st);
            emit(o, "    pop rax");                  // value
            emit(o, "    pop rcx");                  // pointer
            int sz = type_size(pointee.kind);
            switch (sz) {
                case 1: emit(o, "    mov byte  [rcx], al");  break;
                case 2: emit(o, "    mov word  [rcx], ax");  break;
                case 4: emit(o, "    mov dword [rcx], eax"); break;
                case 8:
                default: emit(o, "    mov qword [rcx], rax"); break;
            }
            break;
        }
        case ST_FIELD_STORE: {
            // target is EX_FIELD whose operand is either EX_IDENT (16c) or EX_DEREF (16e).
            Expr *fld = s->field_store.target;
            Expr *op  = fld->field.operand;
            Field *f = fld->field.resolved;
            if (!f) cg_error("internal: field not resolved", s->line);
            int sz = type_size(f->ty.kind);

            if (op->kind == EX_IDENT) {
                const Symbol *sy = symtab_find(st, op->ident.name, op->ident.len);
                if (!sy) cg_error("internal: field-store on unknown var", s->line);
                int addr = sy->offset - f->offset;

                gen_expr(s->field_store.value, o, st);
                emit(o, "    pop rax");
                switch (sz) {
                    case 1: emit(o, "    mov byte  [rbp-%d], al",  addr); break;
                    case 2: emit(o, "    mov word  [rbp-%d], ax",  addr); break;
                    case 4: emit(o, "    mov dword [rbp-%d], eax", addr); break;
                    case 8:
                    default: emit(o, "    mov qword [rbp-%d], rax", addr); break;
                }
                break;
            }

            // op->kind == EX_DEREF: write through pointer + field offset.
            // Evaluate pointer, then value (left-to-right, like ST_PTR_STORE).
            gen_expr(op->deref.operand, o, st);
            gen_expr(s->field_store.value, o, st);
            emit(o, "    pop rax");          // value
            emit(o, "    pop rcx");          // pointer to struct
            if (f->offset != 0)
                emit(o, "    add rcx, %d", f->offset);
            switch (sz) {
                case 1: emit(o, "    mov byte  [rcx], al");  break;
                case 2: emit(o, "    mov word  [rcx], ax");  break;
                case 4: emit(o, "    mov dword [rcx], eax"); break;
                case 8:
                default: emit(o, "    mov qword [rcx], rax"); break;
            }
            break;
        }
        case ST_INDEX_STORE: {
            // target is EX_INDEX (parser enforces). Evaluate base+i*sz to get
            // the address, then evaluate value, then store with the right width.
            Expr *idx = s->index_store.target;
            int sz = type_size(idx->type.kind);
            gen_index_addr(idx->index.base, idx->index.index, sz, o, st);
            // Stack: [..., addr]. Now push value.
            gen_expr(s->index_store.value, o, st);
            emit(o, "    pop rax");                  // value
            emit(o, "    pop rcx");                  // address
            switch (sz) {
                case 1: emit(o, "    mov byte  [rcx], al");  break;
                case 2: emit(o, "    mov word  [rcx], ax");  break;
                case 4: emit(o, "    mov dword [rcx], eax"); break;
                case 8:
                default: emit(o, "    mov qword [rcx], rax"); break;
            }
            break;
        }
        case ST_RETURN:
            if (s->ret.value) {
                gen_expr(s->ret.value, o, st);
                emit(o, "    pop rax");
            } else {
                emit(o, "    xor rax, rax");
            }
            emit(o, "    leave");
            emit(o, "    ret");
            break;
        case ST_BLOCK:
            for (size_t i = 0; i < s->block.n; i++)
                gen_stmt(s->block.stmts[i], o, st);
            break;
        case ST_EXPR:
            gen_expr(s->expr_s.expr, o, st);
            emit(o, "    add rsp, 8");
            break;
        case ST_IF: {
            int else_lbl = new_label();
            int end_lbl  = s->if_s.else_b ? new_label() : else_lbl;

            gen_expr(s->if_s.cond, o, st);
            emit(o, "    pop rax");
            emit(o, "    cmp rax, 0");
            emit(o, "    je .L%d", else_lbl);

            gen_stmt(s->if_s.then_b, o, st);
            if (s->if_s.else_b) {
                emit(o, "    jmp .L%d", end_lbl);
                emit(o, ".L%d:", else_lbl);
                gen_stmt(s->if_s.else_b, o, st);
            }
            emit(o, ".L%d:", end_lbl);
            break;
        }
        case ST_WHILE: {
            int top_lbl = new_label();
            int end_lbl = new_label();

            emit(o, ".L%d:", top_lbl);
            gen_expr(s->while_s.cond, o, st);
            emit(o, "    pop rax");
            emit(o, "    cmp rax, 0");
            emit(o, "    je .L%d", end_lbl);

            // continue jumps to top (re-eval cond); break jumps to end.
            loop_push(end_lbl, top_lbl);
            gen_stmt(s->while_s.body, o, st);
            loop_pop();

            emit(o, "    jmp .L%d", top_lbl);
            emit(o, ".L%d:", end_lbl);
            break;
        }
        case ST_FOR: {
            int top_lbl  = new_label();
            int step_lbl = new_label();
            int end_lbl  = new_label();

            // Emit init once, before the loop.
            if (s->for_s.init) gen_stmt(s->for_s.init, o, st);

            emit(o, ".L%d:", top_lbl);
            // Cond is optional. If absent, behave as `while (true)`.
            if (s->for_s.cond) {
                gen_expr(s->for_s.cond, o, st);
                emit(o, "    pop rax");
                emit(o, "    cmp rax, 0");
                emit(o, "    je .L%d", end_lbl);
            }

            // Continue jumps to step (NOT to top — step must run).
            loop_push(end_lbl, step_lbl);
            gen_stmt(s->for_s.body, o, st);
            loop_pop();

            emit(o, ".L%d:", step_lbl);
            if (s->for_s.update) gen_stmt(s->for_s.update, o, st);
            emit(o, "    jmp .L%d", top_lbl);
            emit(o, ".L%d:", end_lbl);
            break;
        }
        case ST_BREAK: {
            // Typechecker has already verified we're in a loop, but be defensive.
            if (loop_depth == 0)
                cg_error("internal: 'break' outside loop reached codegen", s->line);
            emit(o, "    jmp .L%d", loop_break_lbl());
            break;
        }
        case ST_CONTINUE: {
            if (loop_depth == 0)
                cg_error("internal: 'continue' outside loop reached codegen", s->line);
            emit(o, "    jmp .L%d", loop_continue_lbl());
            break;
        }
        default:
            cg_error("statement not supported", s->line);
    }
}

static void gen_func(FuncDecl *f, FILE *o) {
    if (f->nparams > 6)
        cg_error("functions with more than 6 parameters are not supported", f->line);

    // Don't reset label_counter — labels must be unique across the whole
    // compilation unit, not just within a single function.
    // Do reset the loop stack — it should be empty at function entry/exit.
    loop_depth = 0;

    SymTab st; symtab_init(&st);
    // Parameters first (slots in declaration order).
    for (size_t i = 0; i < f->nparams; i++)
        symtab_add(&st, f->params[i].name, f->params[i].name_len,
                   f->params[i].ty, f->line);
    collect_locals_stmt(f->body, &st);
    int frame = symtab_stack_size_aligned(&st);

    emit(o, "global %.*s", (int)f->name_len, f->name);
    emit(o, "%.*s:", (int)f->name_len, f->name);
    emit(o, "    push rbp");
    emit(o, "    mov rbp, rsp");
    if (frame > 0) emit(o, "    sub rsp, %d", frame);

    // Spill parameter registers into stack slots.
    for (size_t i = 0; i < f->nparams; i++) {
        const Symbol *sy = symtab_find(&st, f->params[i].name, f->params[i].name_len);
        int sz = type_size(sy->ty.kind);
        const char *reg = arg_reg_for_size((int)i, sz);
        switch (sz) {
            case 1: emit(o, "    mov byte  [rbp-%d], %s", sy->offset, reg); break;
            case 2: emit(o, "    mov word  [rbp-%d], %s", sy->offset, reg); break;
            case 4: emit(o, "    mov dword [rbp-%d], %s", sy->offset, reg); break;
            case 8: emit(o, "    mov qword [rbp-%d], %s", sy->offset, reg); break;
        }
    }

    gen_stmt(f->body, o, &st);

    // Default epilogue (in case the body fell through).
    emit(o, "    xor rax, rax");
    emit(o, "    leave");
    emit(o, "    ret");

    symtab_free(&st);
}

void codegen_program(Program *p, FILE *out) {
    strlits_count = 0;
    cooked_count = 0;
    label_counter = 0;

    emit(out, "; auto-generated by lazyc");
    // Builtin externs: emitted by default so user code doesn't need to
    // declare them. But if the current program defines one of these
    // names as a non-extern function (e.g. when compiling runtime.ml
    // itself), skip the `extern` to avoid nasm's "label inconsistently
    // redefined" error.
    static const char *builtin_externs[] = {
        "lazyc_write_bytes", "lazyc_print_char", "lazyc_print_int16",
        "lazyc_print_long", "lazyc_print_string", "lazyc_print_newline",
        "lazyc_alloc", "lazyc_free", "lazyc_exit",
        "lazyc_readf", "lazyc_writef", "lazyc_argc", "lazyc_argv",
        NULL
    };
    for (size_t bi = 0; builtin_externs[bi]; bi++) {
        const char *name = builtin_externs[bi];
        size_t name_len = strlen(name);
        int defined_locally = 0;
        for (size_t i = 0; i < p->nfuncs; i++) {
            if (p->funcs[i]->is_extern) continue;
            if (p->funcs[i]->name_len == (int)name_len &&
                memcmp(p->funcs[i]->name, name, name_len) == 0) {
                defined_locally = 1;
                break;
            }
        }
        if (!defined_locally) {
            emit(out, "extern %s", name);
        }
    }
    // Emit `extern <name>` for each user-declared `extern` function.
    for (size_t i = 0; i < p->nfuncs; i++) {
        if (p->funcs[i]->is_extern)
            emit(out, "extern %.*s",
                 (int)p->funcs[i]->name_len, p->funcs[i]->name);
    }
    emit(out, "section .text");
    for (size_t i = 0; i < p->nfuncs; i++) {
        if (p->funcs[i]->is_extern) continue;
        gen_func(p->funcs[i], out);
    }

    int has_rodata = (strlits_count > 0) || (cooked_count > 0);
    if (has_rodata) {
        emit(out, "section .rodata");
        for (size_t i = 0; i < strlits_count; i++) {
            StrLit *s = &strlits[i];
            fprintf(out, "Lstr_%d: db ", s->label_id);
            int first = 1;
            for (size_t j = 0; j < s->len; j++) {
                unsigned char c = (unsigned char)s->data[j];
                if (c == '\\' && j + 1 < s->len) {
                    char esc = s->data[j+1];
                    j++;
                    switch (esc) {
                        case 'n':  c = '\n'; break;
                        case 't':  c = '\t'; break;
                        case 'r':  c = '\r'; break;
                        case '0':  c = '\0'; break;
                        case '\\': c = '\\'; break;
                        case '\'': c = '\''; break;
                        case '"':  c = '"';  break;
                        case 'x': {
                            if (j + 2 >= s->len) { c = 'x'; break; }
                            char h1 = s->data[j+1];
                            char h2 = s->data[j+2];
                            int d1 = -1, d2 = -1;
                            if      (h1 >= '0' && h1 <= '9') d1 = h1 - '0';
                            else if (h1 >= 'a' && h1 <= 'f') d1 = h1 - 'a' + 10;
                            else if (h1 >= 'A' && h1 <= 'F') d1 = h1 - 'A' + 10;
                            if      (h2 >= '0' && h2 <= '9') d2 = h2 - '0';
                            else if (h2 >= 'a' && h2 <= 'f') d2 = h2 - 'a' + 10;
                            else if (h2 >= 'A' && h2 <= 'F') d2 = h2 - 'A' + 10;
                            if (d1 < 0 || d2 < 0) { c = 'x'; break; }
                            c = (unsigned char)(d1 * 16 + d2);
                            j += 2;
                            break;
                        }
                        default:   c = (unsigned char)esc; break;
                    }
                }
                if (!first) fprintf(out, ",");
                fprintf(out, "%u", c);
                first = 0;
            }
            if (!first) fprintf(out, ",");
            fprintf(out, "0\n");
        }
        for (size_t i = 0; i < cooked_count; i++) {
            CookedStr *cs = &cooked[i];
            fprintf(out, "Lcstr_%d: db ", cs->label_id);
            if (cs->len == 0) {
                fprintf(out, "0");          // placeholder so `db` has an operand
            } else {
                for (size_t j = 0; j < cs->len; j++) {
                    if (j) fputc(',', out);
                    fprintf(out, "%u", (unsigned char)cs->bytes[j]);
                }
            }
            fputc('\n', out);
        }
    }
}
