// lazyc/compiler/codegen.ml
//
// Codegen for lazyc. Step 21j+k+l in one file.
//
// Mirrors src/codegen.c. Walks a typechecked Program and emits NASM
// x86-64 assembly to a Ptr<Buf>. Stack-machine evaluation strategy: every
// expression pushes its result on the runtime stack; statements pop and
// consume. Local variables live in stack slots negative-indexed from rbp.
//
// The codegen output must be byte-identical to the C codegen's output
// for the same input program — that's required for the fixed-point test
// at 21m. So we mirror the C version's emit order and label numbering
// EXACTLY.

// ---- Codegen context ----
//
// Holds all the state the C version uses module-globals for:
//   * out: the Buf we're appending asm to
//   * label_counter: monotonically increasing integer for .L<N> labels
//   * loop stack: nested break/continue targets
//   * string-literal pool (intern_strlit)
//   * cooked-string pool (intern_cooked) for format-string fragments
//   * symbol table for the current function (set per gen_func)
struct Symbol {
    Ptr<Byte> name;
    Long      name_len;
    Long      offset;          // bytes below rbp
    Ptr<Type> ty;
}

struct SymTab {
    Ptr<PtrVec> items;         // PtrVec of Ptr<Symbol>
    Long        next_offset;
}

struct LoopFrame {
    Long break_lbl;
    Long continue_lbl;
}

struct StrLit {
    Long      label_id;
    Ptr<Byte> data;            // raw inner bytes (escapes NOT yet processed)
    Long      len;
}

struct CookedStr {
    Long      label_id;
    Ptr<Byte> bytes;           // already-decoded bytes
    Long      len;
}

struct CgCtx {
    Ptr<Buf>    out;
    Long        label_counter;
    Ptr<PtrVec> loop_stack;    // PtrVec of Ptr<LoopFrame>
    Ptr<PtrVec> strlits;       // PtrVec of Ptr<StrLit>
    Ptr<PtrVec> cooked;        // PtrVec of Ptr<CookedStr>
    Ptr<SymTab> sym;           // current function's symbol table (or null)
}

// ---- Constructors ----

Ptr<Symbol> sym_new(Ptr<Byte> name, Long name_len, Long offset, Ptr<Type> ty) {
    Ptr<Byte> raw = alloc(32);
    Ptr<Symbol> s = cast<Ptr<Symbol>>(raw);
    (*s).name     = name;
    (*s).name_len = name_len;
    (*s).offset   = offset;
    (*s).ty       = ty;
    return s;
}

Ptr<SymTab> symtab_new() {
    Ptr<Byte> raw = alloc(16);
    Ptr<SymTab> st = cast<Ptr<SymTab>>(raw);
    Ptr<Byte> raw_pv = alloc(24);
    Ptr<PtrVec> items = cast<Ptr<PtrVec>>(raw_pv);
    ptrvec_init(items);
    (*st).items = items;
    (*st).next_offset = 0;
    return st;
}

Ptr<Symbol> symtab_find(Ptr<SymTab> st, Ptr<Byte> name, Long name_len) {
    Ptr<PtrVec> items = (*st).items;
    Long n = (*items).count;
    Long i = 0;
    while (i < n) {
        Ptr<Symbol> sy = cast<Ptr<Symbol>>(ptrvec_get(items, i));
        if (lex_slice_eq(name, name_len, (*sy).name)) { return sy; }
        i = i + 1;
    }
    return cast<Ptr<Symbol>>(null);
}

// Compute byte size for a type (matches C codegen's type_total_bytes,
// not the typechecker's tc_type_size_kind which only knows numerics).
Long cg_type_size(Ptr<Type> ty) {
    Long k = (*ty).kind;
    if (k == TY_BOOLEAN()) { return 1; }
    if (k == TY_CHAR())    { return 1; }
    if (k == TY_BYTE())    { return 1; }
    if (k == TY_INTEGER()) { return 2; }
    if (k == TY_UINTEGER()){ return 2; }
    if (k == TY_WHOLE())   { return 4; }
    if (k == TY_UWHOLE())  { return 4; }
    if (k == TY_LONG())    { return 8; }
    if (k == TY_ULONG())   { return 8; }
    if (k == TY_STRING())  { return 8; }
    if (k == TY_PTR())     { return 8; }
    if (k == TY_STRUCT()) {
        Ptr<StructDef> sd = cast<Ptr<StructDef>>((*ty).sdef);
        if (sd == cast<Ptr<StructDef>>(null)) { return 0; }
        return (*sd).size;
    }
    if (k == TY_ARRAY()) {
        if ((*ty).elem == cast<Ptr<Type>>(null)) { return 0; }
        return cg_type_size((*ty).elem) * (*ty).nelems;
    }
    return 0;
}

// type_size for "loadable" types only (matches C codegen's static
// type_size which only handles the leaf types). For struct/array this
// is meaningless so we return 8 as a fallback (matches default branch).
Long cg_type_size_kind(Long k) {
    if (k == TY_BOOLEAN()) { return 1; }
    if (k == TY_CHAR())    { return 1; }
    if (k == TY_BYTE())    { return 1; }
    if (k == TY_INTEGER()) { return 2; }
    if (k == TY_UINTEGER()){ return 2; }
    if (k == TY_WHOLE())   { return 4; }
    if (k == TY_UWHOLE())  { return 4; }
    if (k == TY_LONG())    { return 8; }
    if (k == TY_ULONG())   { return 8; }
    if (k == TY_STRING())  { return 8; }
    if (k == TY_PTR())     { return 8; }
    return 8;
}

Long cg_type_align(Ptr<Type> ty) {
    Long k = (*ty).kind;
    if (k == TY_STRUCT()) {
        Ptr<StructDef> sd = cast<Ptr<StructDef>>((*ty).sdef);
        if (sd == cast<Ptr<StructDef>>(null)) { return 1; }
        return (*sd).align;
    }
    if (k == TY_ARRAY()) {
        if ((*ty).elem == cast<Ptr<Type>>(null)) { return 1; }
        return cg_type_align((*ty).elem);
    }
    return cg_type_size_kind(k);
}

Boolean cg_is_signed_kind(Long k) {
    if (k == TY_INTEGER()) { return true; }
    if (k == TY_WHOLE())   { return true; }
    if (k == TY_LONG())    { return true; }
    return false;
}

// Add a binding to the symbol table, computing its stack offset with
// proper alignment. Mirrors symtab_add in C.
Long symtab_add(Ptr<SymTab> st, Ptr<Byte> name, Long name_len, Ptr<Type> ty, Long line) {
    Ptr<Symbol> existing = symtab_find(st, name, name_len);
    if (existing != cast<Ptr<Symbol>>(null)) {
        println("error at line %l: redeclaration of '%s'", line, cast<String>(name));
        exit(1);
    }
    Long sz = cg_type_size(ty);
    Long al = cg_type_align(ty);
    if (al < 1) { al = 1; }
    Long off = (*st).next_offset + sz;
    Long rem = off - (off / al) * al;
    if (rem != 0) { off = off + (al - rem); }
    (*st).next_offset = off;
    Ptr<Symbol> sy = sym_new(name, name_len, off, ty);
    ptrvec_push((*st).items, cast<Ptr<Byte>>(sy));
    return off;
}

Long symtab_stack_size_aligned(Ptr<SymTab> st) {
    Long n = (*st).next_offset;
    Long rem = n - (n / 16) * 16;
    if (rem != 0) { n = n + (16 - rem); }
    return n;
}

// ---- Cgctx ----

Ptr<CgCtx> cgctx_new(Ptr<Buf> out) {
    Ptr<Byte> raw = alloc(48);
    Ptr<CgCtx> c = cast<Ptr<CgCtx>>(raw);
    (*c).out = out;
    (*c).label_counter = 0;

    Ptr<Byte> r1 = alloc(24);
    Ptr<PtrVec> ls = cast<Ptr<PtrVec>>(r1);
    ptrvec_init(ls);
    (*c).loop_stack = ls;

    Ptr<Byte> r2 = alloc(24);
    Ptr<PtrVec> sl = cast<Ptr<PtrVec>>(r2);
    ptrvec_init(sl);
    (*c).strlits = sl;

    Ptr<Byte> r3 = alloc(24);
    Ptr<PtrVec> ck = cast<Ptr<PtrVec>>(r3);
    ptrvec_init(ck);
    (*c).cooked = ck;

    (*c).sym = cast<Ptr<SymTab>>(null);
    return c;
}

Long new_label(Ptr<CgCtx> ctx) {
    Long id = (*ctx).label_counter;
    (*ctx).label_counter = id + 1;
    return id;
}

Long loop_push(Ptr<CgCtx> ctx, Long break_lbl, Long continue_lbl) {
    Ptr<Byte> raw = alloc(16);
    Ptr<LoopFrame> lf = cast<Ptr<LoopFrame>>(raw);
    (*lf).break_lbl = break_lbl;
    (*lf).continue_lbl = continue_lbl;
    ptrvec_push((*ctx).loop_stack, cast<Ptr<Byte>>(lf));
    return 0;
}

Long loop_pop(Ptr<CgCtx> ctx) {
    Ptr<PtrVec> ls = (*ctx).loop_stack;
    (*ls).count = (*ls).count - 1;
    return 0;
}

Long loop_break_lbl(Ptr<CgCtx> ctx) {
    Ptr<PtrVec> ls = (*ctx).loop_stack;
    Ptr<LoopFrame> lf = cast<Ptr<LoopFrame>>(ptrvec_get(ls, (*ls).count - 1));
    return (*lf).break_lbl;
}

Long loop_continue_lbl(Ptr<CgCtx> ctx) {
    Ptr<PtrVec> ls = (*ctx).loop_stack;
    Ptr<LoopFrame> lf = cast<Ptr<LoopFrame>>(ptrvec_get(ls, (*ls).count - 1));
    return (*lf).continue_lbl;
}

Long loop_depth_now(Ptr<CgCtx> ctx) {
    return (*(*ctx).loop_stack).count;
}

// ---- String literal interning ----

Long intern_strlit(Ptr<CgCtx> ctx, Ptr<Byte> data, Long len) {
    Ptr<PtrVec> sl = (*ctx).strlits;
    Long id = (*sl).count;
    Ptr<Byte> raw = alloc(24);
    Ptr<StrLit> s = cast<Ptr<StrLit>>(raw);
    (*s).label_id = id;
    (*s).data     = data;
    (*s).len      = len;
    ptrvec_push(sl, cast<Ptr<Byte>>(s));
    return id;
}

// Process backslash escapes in `src[0..len)`, returning a fresh
// null-terminated buffer. Length of output written to (*out_len).
Ptr<Byte> cook_escapes(Ptr<Byte> src, Long len, Ptr<Long> out_len) {
    Ptr<Byte> buf = alloc(len + 1);
    Long out = 0;
    Long i = 0;
    while (i < len) {
        Long c = cast<Long>(src[i]);
        Boolean did_esc = false;
        if (c == 92) {                       // '\'
            if (i + 1 < len) {
                Long esc = cast<Long>(src[i + 1]);
                if (esc == 120) {                  // 'x' -> \xHH hex escape
                    if (i + 3 < len) {
                        Long h1 = cast<Long>(src[i + 2]);
                        Long h2 = cast<Long>(src[i + 3]);
                        Long d1 = -1;
                        Long d2 = -1;
                        if (h1 >= 48) { if (h1 <= 57) { d1 = h1 - 48; } }   // 0..9
                        if (h1 >= 97) { if (h1 <= 102){ d1 = h1 - 97 + 10; } } // a..f
                        if (h1 >= 65) { if (h1 <= 70) { d1 = h1 - 65 + 10; } } // A..F
                        if (h2 >= 48) { if (h2 <= 57) { d2 = h2 - 48; } }
                        if (h2 >= 97) { if (h2 <= 102){ d2 = h2 - 97 + 10; } }
                        if (h2 >= 65) { if (h2 <= 70) { d2 = h2 - 65 + 10; } }
                        Boolean both_ok = false;
                        if (d1 >= 0) { if (d2 >= 0) { both_ok = true; } }
                        if (both_ok) {
                            buf[out] = cast<Byte>(d1 * 16 + d2);
                            out = out + 1;
                            i = i + 4;
                            did_esc = true;
                        }
                    }
                }
                if (!did_esc) {
                    Long resolved = esc;
                    if (esc == 110) { resolved = 10;  }   // n -> \n
                    if (esc == 116) { resolved = 9;   }   // t -> \t
                    if (esc == 114) { resolved = 13;  }   // r -> \r
                    if (esc == 48)  { resolved = 0;   }   // 0 -> \0
                    if (esc == 92)  { resolved = 92;  }   // \ -> \\
                    if (esc == 39)  { resolved = 39;  }   // ' -> '
                    if (esc == 34)  { resolved = 34;  }   // " -> "
                    buf[out] = cast<Byte>(resolved);
                    out = out + 1;
                    i = i + 2;
                    did_esc = true;
                }
            }
        }
        if (!did_esc) {
            buf[out] = cast<Byte>(c);
            out = out + 1;
            i = i + 1;
        }
    }
    buf[out] = cast<Byte>(0);
    *out_len = out;
    return buf;
}

Long intern_cooked(Ptr<CgCtx> ctx, Ptr<Byte> src, Long len) {
    Long out_len = 0;
    Ptr<Byte> bytes = cook_escapes(src, len, &out_len);
    Ptr<PtrVec> ck = (*ctx).cooked;
    Long id = (*ck).count;
    Ptr<Byte> raw = alloc(24);
    Ptr<CookedStr> cs = cast<Ptr<CookedStr>>(raw);
    (*cs).label_id = id;
    (*cs).bytes    = bytes;
    (*cs).len      = out_len;
    ptrvec_push(ck, cast<Ptr<Byte>>(cs));
    return id;
}

// ---- emit helpers ----

Long emit_str(Ptr<CgCtx> ctx, Ptr<Byte> s) {
    buf_push_str((*ctx).out, s);
    return 0;
}

Long emit_long(Ptr<CgCtx> ctx, Long n) {
    buf_push_long((*ctx).out, n);
    return 0;
}

Long emit_nl(Ptr<CgCtx> ctx) {
    buf_push_byte((*ctx).out, cast<Byte>(10));
    return 0;
}

// `    mov rax, <n>\n`
Long emit_mov_rax_imm(Ptr<CgCtx> ctx, Long n) {
    emit_str(ctx, cast<Ptr<Byte>>("    mov rax, "));
    emit_long(ctx, n);
    emit_nl(ctx);
    return 0;
}

// `    push rax\n`
Long emit_push_rax(Ptr<CgCtx> ctx) {
    emit_str(ctx, cast<Ptr<Byte>>("    push rax\n"));
    return 0;
}

Long emit_pop_rax(Ptr<CgCtx> ctx) {
    emit_str(ctx, cast<Ptr<Byte>>("    pop rax\n"));
    return 0;
}

Long emit_pop_rcx(Ptr<CgCtx> ctx) {
    emit_str(ctx, cast<Ptr<Byte>>("    pop rcx\n"));
    return 0;
}

// Emit `<prefix><offset>]<suffix>\n` for things like
// `    mov qword [rbp-<offset>], <reg>\n`
Long emit_mem_op(Ptr<CgCtx> ctx, Ptr<Byte> prefix, Long offset, Ptr<Byte> suffix) {
    emit_str(ctx, prefix);
    emit_long(ctx, offset);
    emit_str(ctx, suffix);
    return 0;
}

// Emit `.L<N>:\n`
Long emit_label_def(Ptr<CgCtx> ctx, Long n) {
    emit_str(ctx, cast<Ptr<Byte>>(".L"));
    emit_long(ctx, n);
    emit_str(ctx, cast<Ptr<Byte>>(":\n"));
    return 0;
}

// Emit `    jmp .L<N>\n`
Long emit_jmp(Ptr<CgCtx> ctx, Ptr<Byte> jmp_op, Long n) {
    emit_str(ctx, cast<Ptr<Byte>>("    "));
    emit_str(ctx, jmp_op);
    emit_str(ctx, cast<Ptr<Byte>>(" .L"));
    emit_long(ctx, n);
    emit_nl(ctx);
    return 0;
}

// Emit `    <op> rax, <imm>\n` for things like `add rax, 5`
Long emit_op_rax_imm(Ptr<CgCtx> ctx, Ptr<Byte> op, Long imm) {
    emit_str(ctx, cast<Ptr<Byte>>("    "));
    emit_str(ctx, op);
    emit_str(ctx, cast<Ptr<Byte>>(" rax, "));
    emit_long(ctx, imm);
    emit_nl(ctx);
    return 0;
}

// ---- Sized load/store helpers ----

// Load a value from [rbp-offset] into rax with proper width and signedness.
Long emit_load_var(Ptr<CgCtx> ctx, Ptr<Type> ty, Long offset) {
    Long sz = cg_type_size_kind((*ty).kind);
    Boolean sgn = cg_is_signed_kind((*ty).kind);
    if (sz == 1) {
        if (sgn) { emit_mem_op(ctx, cast<Ptr<Byte>>("    movsx rax, byte [rbp-"), offset, cast<Ptr<Byte>>("]\n")); }
        else     { emit_mem_op(ctx, cast<Ptr<Byte>>("    movzx rax, byte [rbp-"), offset, cast<Ptr<Byte>>("]\n")); }
        return 0;
    }
    if (sz == 2) {
        if (sgn) { emit_mem_op(ctx, cast<Ptr<Byte>>("    movsx rax, word [rbp-"), offset, cast<Ptr<Byte>>("]\n")); }
        else     { emit_mem_op(ctx, cast<Ptr<Byte>>("    movzx rax, word [rbp-"), offset, cast<Ptr<Byte>>("]\n")); }
        return 0;
    }
    if (sz == 4) {
        if (sgn) { emit_mem_op(ctx, cast<Ptr<Byte>>("    movsxd rax, dword [rbp-"), offset, cast<Ptr<Byte>>("]\n")); }
        else     { emit_mem_op(ctx, cast<Ptr<Byte>>("    mov eax, dword [rbp-"), offset, cast<Ptr<Byte>>("]\n")); }
        return 0;
    }
    emit_mem_op(ctx, cast<Ptr<Byte>>("    mov rax, [rbp-"), offset, cast<Ptr<Byte>>("]\n"));
    return 0;
}

// Store rax into [rbp-offset] with the right width.
Long emit_store_var(Ptr<CgCtx> ctx, Ptr<Type> ty, Long offset) {
    Long sz = cg_type_size_kind((*ty).kind);
    if (sz == 1) {
        emit_mem_op(ctx, cast<Ptr<Byte>>("    mov byte  [rbp-"), offset, cast<Ptr<Byte>>("], al\n"));
        return 0;
    }
    if (sz == 2) {
        emit_mem_op(ctx, cast<Ptr<Byte>>("    mov word  [rbp-"), offset, cast<Ptr<Byte>>("], ax\n"));
        return 0;
    }
    if (sz == 4) {
        emit_mem_op(ctx, cast<Ptr<Byte>>("    mov dword [rbp-"), offset, cast<Ptr<Byte>>("], eax\n"));
        return 0;
    }
    emit_mem_op(ctx, cast<Ptr<Byte>>("    mov qword [rbp-"), offset, cast<Ptr<Byte>>("], rax\n"));
    return 0;
}

// Zero a possibly-multi-byte stack slot in 8/4/2/1-byte chunks.
// Mirrors zero_slot.
Long emit_zero_slot(Ptr<CgCtx> ctx, Long offset, Long sz) {
    Long pos = 0;
    while (pos + 8 <= sz) {
        emit_mem_op(ctx, cast<Ptr<Byte>>("    mov qword [rbp-"), offset - pos, cast<Ptr<Byte>>("], 0\n"));
        pos = pos + 8;
    }
    while (pos + 4 <= sz) {
        emit_mem_op(ctx, cast<Ptr<Byte>>("    mov dword [rbp-"), offset - pos, cast<Ptr<Byte>>("], 0\n"));
        pos = pos + 4;
    }
    while (pos + 2 <= sz) {
        emit_mem_op(ctx, cast<Ptr<Byte>>("    mov word  [rbp-"), offset - pos, cast<Ptr<Byte>>("], 0\n"));
        pos = pos + 2;
    }
    while (pos + 1 <= sz) {
        emit_mem_op(ctx, cast<Ptr<Byte>>("    mov byte  [rbp-"), offset - pos, cast<Ptr<Byte>>("], 0\n"));
        pos = pos + 1;
    }
    return 0;
}

// Zero a variable (any type).
Long emit_zero_var(Ptr<CgCtx> ctx, Ptr<Type> ty, Long offset) {
    Long k = (*ty).kind;
    if (k == TY_STRUCT()) {
        emit_zero_slot(ctx, offset, cg_type_size(ty));
        return 0;
    }
    if (k == TY_ARRAY()) {
        emit_zero_slot(ctx, offset, cg_type_size(ty));
        return 0;
    }
    Long sz = cg_type_size_kind(k);
    if (sz == 1) {
        emit_mem_op(ctx, cast<Ptr<Byte>>("    mov byte  [rbp-"), offset, cast<Ptr<Byte>>("], 0\n"));
        return 0;
    }
    if (sz == 2) {
        emit_mem_op(ctx, cast<Ptr<Byte>>("    mov word  [rbp-"), offset, cast<Ptr<Byte>>("], 0\n"));
        return 0;
    }
    if (sz == 4) {
        emit_mem_op(ctx, cast<Ptr<Byte>>("    mov dword [rbp-"), offset, cast<Ptr<Byte>>("], 0\n"));
        return 0;
    }
    emit_mem_op(ctx, cast<Ptr<Byte>>("    mov qword [rbp-"), offset, cast<Ptr<Byte>>("], 0\n"));
    return 0;
}

// Argument register for parameter index i, sized.
Ptr<Byte> arg_reg_for(Long i, Long sz) {
    if (sz == 1) {
        if (i == 0) { return cast<Ptr<Byte>>("dil"); }
        if (i == 1) { return cast<Ptr<Byte>>("sil"); }
        if (i == 2) { return cast<Ptr<Byte>>("dl");  }
        if (i == 3) { return cast<Ptr<Byte>>("cl");  }
        if (i == 4) { return cast<Ptr<Byte>>("r8b"); }
        return cast<Ptr<Byte>>("r9b");
    }
    if (sz == 2) {
        if (i == 0) { return cast<Ptr<Byte>>("di");  }
        if (i == 1) { return cast<Ptr<Byte>>("si");  }
        if (i == 2) { return cast<Ptr<Byte>>("dx");  }
        if (i == 3) { return cast<Ptr<Byte>>("cx");  }
        if (i == 4) { return cast<Ptr<Byte>>("r8w"); }
        return cast<Ptr<Byte>>("r9w");
    }
    if (sz == 4) {
        if (i == 0) { return cast<Ptr<Byte>>("edi"); }
        if (i == 1) { return cast<Ptr<Byte>>("esi"); }
        if (i == 2) { return cast<Ptr<Byte>>("edx"); }
        if (i == 3) { return cast<Ptr<Byte>>("ecx"); }
        if (i == 4) { return cast<Ptr<Byte>>("r8d"); }
        return cast<Ptr<Byte>>("r9d");
    }
    if (i == 0) { return cast<Ptr<Byte>>("rdi"); }
    if (i == 1) { return cast<Ptr<Byte>>("rsi"); }
    if (i == 2) { return cast<Ptr<Byte>>("rdx"); }
    if (i == 3) { return cast<Ptr<Byte>>("rcx"); }
    if (i == 4) { return cast<Ptr<Byte>>("r8");  }
    return cast<Ptr<Byte>>("r9");
}

// ---- Pass 1: collect locals from a Stmt subtree ----

Long collect_locals_stmt(Ptr<Stmt> s, Ptr<SymTab> st) {
    if (s == cast<Ptr<Stmt>>(null)) { return 0; }
    Long k = (*s).kind;
    if (k == ST_VAR_DECL()) {
        symtab_add(st, (*s).var_name, (*s).var_name_len, (*s).var_ty, (*s).line);
        return 0;
    }
    if (k == ST_BLOCK()) {
        Ptr<PtrVec> ss = (*s).block_stmts;
        if (ss != cast<Ptr<PtrVec>>(null)) {
            Long n = (*ss).count;
            Long i = 0;
            while (i < n) {
                Ptr<Stmt> child = cast<Ptr<Stmt>>(ptrvec_get(ss, i));
                collect_locals_stmt(child, st);
                i = i + 1;
            }
        }
        return 0;
    }
    if (k == ST_IF()) {
        collect_locals_stmt((*s).then_b, st);
        if ((*s).else_b != cast<Ptr<Stmt>>(null)) {
            collect_locals_stmt((*s).else_b, st);
        }
        return 0;
    }
    if (k == ST_WHILE()) {
        collect_locals_stmt((*s).body, st);
        return 0;
    }
    if (k == ST_FOR()) {
        if ((*s).for_init != cast<Ptr<Stmt>>(null)) {
            collect_locals_stmt((*s).for_init, st);
        }
        collect_locals_stmt((*s).body, st);
        return 0;
    }
    return 0;
}

// ---- Codegen error ----
Long cg_error_at(Long line, Ptr<Byte> msg) {
    println("codegen error at line %l: %s", line, cast<String>(msg));
    exit(1);
    return 0;
}

// ---- gen_expr: dispatch ----
//
// Each case appends asm to ctx.out and ends with the result on the
// stack (i.e., emit_push_rax was called).

// gen_expr, gen_binary, gen_unary, gen_cast, gen_call, gen_format_call,
// gen_lvalue_address, gen_index_addr, gen_stmt: defined below. lazyc
// resolves names globally so no forward declarations needed.

// Emit a sized load from [rax] into rax, given the pointee type.
Long emit_load_via_rax(Ptr<CgCtx> ctx, Ptr<Type> pointee) {
    Long sz = cg_type_size_kind((*pointee).kind);
    Boolean sgn = cg_is_signed_kind((*pointee).kind);
    if (sz == 1) {
        if (sgn) { emit_str(ctx, cast<Ptr<Byte>>("    movsx rax, byte [rax]\n")); }
        else     { emit_str(ctx, cast<Ptr<Byte>>("    movzx rax, byte [rax]\n")); }
        return 0;
    }
    if (sz == 2) {
        if (sgn) { emit_str(ctx, cast<Ptr<Byte>>("    movsx rax, word [rax]\n")); }
        else     { emit_str(ctx, cast<Ptr<Byte>>("    movzx rax, word [rax]\n")); }
        return 0;
    }
    if (sz == 4) {
        if (sgn) { emit_str(ctx, cast<Ptr<Byte>>("    movsxd rax, dword [rax]\n")); }
        else     { emit_str(ctx, cast<Ptr<Byte>>("    mov eax, dword [rax]\n")); }
        return 0;
    }
    emit_str(ctx, cast<Ptr<Byte>>("    mov rax, [rax]\n"));
    return 0;
}

// Emit a sized store of rax through rcx (for ptr/field/index stores).
Long emit_store_via_rcx(Ptr<CgCtx> ctx, Long sz) {
    if (sz == 1) {
        emit_str(ctx, cast<Ptr<Byte>>("    mov byte  [rcx], al\n"));
        return 0;
    }
    if (sz == 2) {
        emit_str(ctx, cast<Ptr<Byte>>("    mov word  [rcx], ax\n"));
        return 0;
    }
    if (sz == 4) {
        emit_str(ctx, cast<Ptr<Byte>>("    mov dword [rcx], eax\n"));
        return 0;
    }
    emit_str(ctx, cast<Ptr<Byte>>("    mov qword [rcx], rax\n"));
    return 0;
}

// gen_expr: walk an expression and push its value on the stack.
Long gen_expr(Ptr<Expr> e, Ptr<CgCtx> ctx) {
    Long ek = (*e).kind;

    if (ek == EX_NUMBER()) {
        emit_mov_rax_imm(ctx, (*e).num);
        emit_push_rax(ctx);
        return 0;
    }
    if (ek == EX_BOOL_LIT()) {
        Long bv = 0;
        if ((*e).bool_val == 1) { bv = 1; }
        emit_mov_rax_imm(ctx, bv);
        emit_push_rax(ctx);
        return 0;
    }
    if (ek == EX_NULL()) {
        emit_str(ctx, cast<Ptr<Byte>>("    xor rax, rax\n"));
        emit_push_rax(ctx);
        return 0;
    }
    if (ek == EX_CHAR_LIT()) {
        // Mask to 0..255 for the literal value (matches C unsigned-char cast).
        Long cv = (*e).char_val;
        if (cv < 0) { cv = cv + 256; }
        emit_mov_rax_imm(ctx, cv);
        emit_push_rax(ctx);
        return 0;
    }
    if (ek == EX_STRING_LIT()) {
        Long sid = intern_strlit(ctx, (*e).str_data, (*e).str_len);
        emit_str(ctx, cast<Ptr<Byte>>("    lea rax, [rel Lstr_"));
        emit_long(ctx, sid);
        emit_str(ctx, cast<Ptr<Byte>>("]\n"));
        emit_push_rax(ctx);
        return 0;
    }
    if (ek == EX_IDENT()) {
        Ptr<Symbol> sy_id = symtab_find((*ctx).sym, (*e).name, (*e).name_len);
        if (sy_id == cast<Ptr<Symbol>>(null)) {
            cg_error_at((*e).line, cast<Ptr<Byte>>("internal: variable not in symtab"));
        }
        emit_load_var(ctx, (*sy_id).ty, (*sy_id).offset);
        emit_push_rax(ctx);
        return 0;
    }
    if (ek == EX_CAST())   { return gen_cast(e, ctx);   }
    if (ek == EX_BINARY()) { return gen_binary(e, ctx); }
    if (ek == EX_UNARY())  { return gen_unary(e, ctx);  }
    if (ek == EX_CALL())   { return gen_call(e, ctx);   }

    if (ek == EX_ADDR_OF()) {
        Ptr<Expr> ta = (*e).child0;
        Long tk = (*ta).kind;
        if (tk == EX_IDENT()) {
            Ptr<Symbol> sy_a = symtab_find((*ctx).sym, (*ta).name, (*ta).name_len);
            if (sy_a == cast<Ptr<Symbol>>(null)) {
                cg_error_at((*e).line, cast<Ptr<Byte>>("internal: addr-of unknown var"));
            }
            emit_mem_op(ctx, cast<Ptr<Byte>>("    lea rax, [rbp-"), (*sy_a).offset, cast<Ptr<Byte>>("]\n"));
            emit_push_rax(ctx);
            return 0;
        }
        if (tk == EX_FIELD()) {
            Ptr<Expr> op_a = (*ta).child0;
            Ptr<Field> f_a = cast<Ptr<Field>>((*ta).field_resolved);
            if (f_a == cast<Ptr<Field>>(null)) {
                cg_error_at((*e).line, cast<Ptr<Byte>>("internal: field not resolved"));
            }
            if ((*op_a).kind == EX_IDENT()) {
                Ptr<Symbol> sy_b = symtab_find((*ctx).sym, (*op_a).name, (*op_a).name_len);
                if (sy_b == cast<Ptr<Symbol>>(null)) {
                    cg_error_at((*e).line, cast<Ptr<Byte>>("internal: addr-of field on unknown var"));
                }
                Long addr_a = (*sy_b).offset - (*f_a).offset;
                emit_mem_op(ctx, cast<Ptr<Byte>>("    lea rax, [rbp-"), addr_a, cast<Ptr<Byte>>("]\n"));
                emit_push_rax(ctx);
                return 0;
            }
            if ((*op_a).kind == EX_DEREF()) {
                gen_expr((*op_a).child0, ctx);
                emit_pop_rax(ctx);
                if ((*f_a).offset != 0) {
                    emit_op_rax_imm(ctx, cast<Ptr<Byte>>("add"), (*f_a).offset);
                }
                emit_push_rax(ctx);
                return 0;
            }
            cg_error_at((*e).line, cast<Ptr<Byte>>("internal: addr-of field with unexpected operand"));
        }
        if (tk == EX_INDEX()) {
            Long idx_sz = cg_type_size((*ta).ety);
            gen_index_addr((*ta).child0, (*ta).child1, idx_sz, ctx);
            return 0;
        }
        cg_error_at((*e).line, cast<Ptr<Byte>>("internal: unsupported addr-of operand"));
    }

    if (ek == EX_DEREF()) {
        gen_expr((*e).child0, ctx);
        emit_pop_rax(ctx);
        Ptr<Type> pty_d = (*(*e).child0).ety;
        Ptr<Type> pointee_d = (*pty_d).pointee;
        emit_load_via_rax(ctx, pointee_d);
        emit_push_rax(ctx);
        return 0;
    }

    if (ek == EX_FIELD()) {
        Ptr<Expr> op_f = (*e).child0;
        Ptr<Field> f_f = cast<Ptr<Field>>((*e).field_resolved);
        if (f_f == cast<Ptr<Field>>(null)) {
            cg_error_at((*e).line, cast<Ptr<Byte>>("internal: field not resolved by typechecker"));
        }
        Ptr<Type> fty_f = cast<Ptr<Type>>((*f_f).ty);
        Long fsz_f = cg_type_size_kind((*fty_f).kind);
        Boolean fsgn_f = cg_is_signed_kind((*fty_f).kind);
        if ((*op_f).kind == EX_IDENT()) {
            Ptr<Symbol> sy_f = symtab_find((*ctx).sym, (*op_f).name, (*op_f).name_len);
            if (sy_f == cast<Ptr<Symbol>>(null)) {
                cg_error_at((*e).line, cast<Ptr<Byte>>("internal: field access on unknown var"));
            }
            Long addr_f = (*sy_f).offset - (*f_f).offset;
            if (fsz_f == 1) {
                if (fsgn_f) { emit_mem_op(ctx, cast<Ptr<Byte>>("    movsx rax, byte [rbp-"), addr_f, cast<Ptr<Byte>>("]\n")); }
                else        { emit_mem_op(ctx, cast<Ptr<Byte>>("    movzx rax, byte [rbp-"), addr_f, cast<Ptr<Byte>>("]\n")); }
            } else {
                if (fsz_f == 2) {
                    if (fsgn_f) { emit_mem_op(ctx, cast<Ptr<Byte>>("    movsx rax, word [rbp-"), addr_f, cast<Ptr<Byte>>("]\n")); }
                    else        { emit_mem_op(ctx, cast<Ptr<Byte>>("    movzx rax, word [rbp-"), addr_f, cast<Ptr<Byte>>("]\n")); }
                } else {
                    if (fsz_f == 4) {
                        if (fsgn_f) { emit_mem_op(ctx, cast<Ptr<Byte>>("    movsxd rax, dword [rbp-"), addr_f, cast<Ptr<Byte>>("]\n")); }
                        else        { emit_mem_op(ctx, cast<Ptr<Byte>>("    mov eax, dword [rbp-"), addr_f, cast<Ptr<Byte>>("]\n")); }
                    } else {
                        emit_mem_op(ctx, cast<Ptr<Byte>>("    mov rax, [rbp-"), addr_f, cast<Ptr<Byte>>("]\n"));
                    }
                }
            }
            emit_push_rax(ctx);
            return 0;
        }
        // op_f is EX_DEREF: evaluate the pointer (operand of deref), add field offset, load.
        gen_expr((*op_f).child0, ctx);
        emit_pop_rax(ctx);
        if ((*f_f).offset != 0) {
            emit_op_rax_imm(ctx, cast<Ptr<Byte>>("add"), (*f_f).offset);
        }
        emit_load_via_rax(ctx, fty_f);
        emit_push_rax(ctx);
        return 0;
    }

    if (ek == EX_INDEX()) {
        Long isz = cg_type_size_kind((*(*e).ety).kind);
        Long iek = (*(*e).ety).kind;
        if (iek == TY_STRUCT()) {
            cg_error_at((*e).line, cast<Ptr<Byte>>("internal: indexed read of aggregate not supported"));
        }
        if (iek == TY_ARRAY()) {
            cg_error_at((*e).line, cast<Ptr<Byte>>("internal: indexed read of aggregate not supported"));
        }
        gen_index_addr((*e).child0, (*e).child1, isz, ctx);
        emit_pop_rax(ctx);
        emit_load_via_rax(ctx, (*e).ety);
        emit_push_rax(ctx);
        return 0;
    }

    cg_error_at((*e).line, cast<Ptr<Byte>>("internal: unknown expr kind in codegen"));
    return 0;
}

// ---- gen_binary ----

Long gen_binary(Ptr<Expr> e, Ptr<CgCtx> ctx) {
    Ptr<Type> Lt = (*(*e).child0).ety;
    Ptr<Type> Rt = (*(*e).child1).ety;
    Boolean lhs_is_ptr = false;
    if ((*Lt).kind == TY_PTR()) { lhs_is_ptr = true; }
    Boolean rhs_is_ptr = false;
    if ((*Rt).kind == TY_PTR()) { rhs_is_ptr = true; }
    Long bop = (*e).op;

    Boolean any_ptr = false;
    if (lhs_is_ptr) { any_ptr = true; }
    if (rhs_is_ptr) { any_ptr = true; }

    Boolean is_addsub = false;
    if (bop == OP_ADD()) { is_addsub = true; }
    if (bop == OP_SUB()) { is_addsub = true; }

    if (any_ptr) {
        if (is_addsub) {
            Ptr<Type> ptr_ty = Lt;
            if (!lhs_is_ptr) { ptr_ty = Rt; }
            // Use cg_type_size (which handles struct/array fully) so
            // that Ptr<struct> and Ptr<T[N]> scale by the correct full
            // size, not the leaf-only size.
            Long psz = cg_type_size((*ptr_ty).pointee);

            gen_expr((*e).child0, ctx);
            gen_expr((*e).child1, ctx);
            emit_pop_rcx(ctx);
            emit_pop_rax(ctx);

            if (bop == OP_ADD()) {
                if (lhs_is_ptr) {
                    if (psz != 1) {
                        emit_str(ctx, cast<Ptr<Byte>>("    imul rcx, rcx, "));
                        emit_long(ctx, psz);
                        emit_nl(ctx);
                    }
                    emit_str(ctx, cast<Ptr<Byte>>("    add rax, rcx\n"));
                } else {
                    if (psz != 1) {
                        emit_str(ctx, cast<Ptr<Byte>>("    imul rax, rax, "));
                        emit_long(ctx, psz);
                        emit_nl(ctx);
                    }
                    emit_str(ctx, cast<Ptr<Byte>>("    add rax, rcx\n"));
                }
                emit_push_rax(ctx);
                return 0;
            }
            // OP_SUB
            if (lhs_is_ptr) {
                if (rhs_is_ptr) {
                    emit_str(ctx, cast<Ptr<Byte>>("    sub rax, rcx\n"));
                    if (psz != 1) {
                        emit_str(ctx, cast<Ptr<Byte>>("    cqo\n"));
                        emit_str(ctx, cast<Ptr<Byte>>("    mov r10, "));
                        emit_long(ctx, psz);
                        emit_nl(ctx);
                        emit_str(ctx, cast<Ptr<Byte>>("    idiv r10\n"));
                    }
                    emit_push_rax(ctx);
                    return 0;
                }
            }
            // ptr - Long
            if (psz != 1) {
                emit_str(ctx, cast<Ptr<Byte>>("    imul rcx, rcx, "));
                emit_long(ctx, psz);
                emit_nl(ctx);
            }
            emit_str(ctx, cast<Ptr<Byte>>("    sub rax, rcx\n"));
            emit_push_rax(ctx);
            return 0;
        }
    }

    // Default path.
    gen_expr((*e).child0, ctx);
    gen_expr((*e).child1, ctx);
    emit_pop_rcx(ctx);
    emit_pop_rax(ctx);

    if (bop == OP_ADD()) { emit_str(ctx, cast<Ptr<Byte>>("    add rax, rcx\n"));  emit_push_rax(ctx); return 0; }
    if (bop == OP_SUB()) { emit_str(ctx, cast<Ptr<Byte>>("    sub rax, rcx\n"));  emit_push_rax(ctx); return 0; }
    if (bop == OP_MUL()) { emit_str(ctx, cast<Ptr<Byte>>("    imul rax, rcx\n")); emit_push_rax(ctx); return 0; }
    if (bop == OP_DIV()) {
        emit_str(ctx, cast<Ptr<Byte>>("    cqo\n"));
        emit_str(ctx, cast<Ptr<Byte>>("    idiv rcx\n"));
        emit_push_rax(ctx);
        return 0;
    }
    if (bop == OP_MOD()) {
        emit_str(ctx, cast<Ptr<Byte>>("    cqo\n"));
        emit_str(ctx, cast<Ptr<Byte>>("    idiv rcx\n"));
        emit_str(ctx, cast<Ptr<Byte>>("    mov rax, rdx\n"));
        emit_push_rax(ctx);
        return 0;
    }
    // Comparisons.
    Boolean is_cmp = false;
    if (bop == OP_EQ())  { is_cmp = true; }
    if (bop == OP_NEQ()) { is_cmp = true; }
    if (bop == OP_LT())  { is_cmp = true; }
    if (bop == OP_GT())  { is_cmp = true; }
    if (bop == OP_LE())  { is_cmp = true; }
    if (bop == OP_GE())  { is_cmp = true; }
    if (is_cmp) {
        emit_str(ctx, cast<Ptr<Byte>>("    cmp rax, rcx\n"));
        Boolean unsigned_cmp = false;
        if (any_ptr) {
            unsigned_cmp = true;
        } else {
            if (!cg_is_signed_kind((*Lt).kind)) { unsigned_cmp = true; }
        }
        Ptr<Byte> setcc = cast<Ptr<Byte>>("sete");
        if (bop == OP_EQ())  { setcc = cast<Ptr<Byte>>("sete");  }
        if (bop == OP_NEQ()) { setcc = cast<Ptr<Byte>>("setne"); }
        if (bop == OP_LT())  {
            if (unsigned_cmp) { setcc = cast<Ptr<Byte>>("setb"); }
            else              { setcc = cast<Ptr<Byte>>("setl"); }
        }
        if (bop == OP_GT())  {
            if (unsigned_cmp) { setcc = cast<Ptr<Byte>>("seta"); }
            else              { setcc = cast<Ptr<Byte>>("setg"); }
        }
        if (bop == OP_LE())  {
            if (unsigned_cmp) { setcc = cast<Ptr<Byte>>("setbe"); }
            else              { setcc = cast<Ptr<Byte>>("setle"); }
        }
        if (bop == OP_GE())  {
            if (unsigned_cmp) { setcc = cast<Ptr<Byte>>("setae"); }
            else              { setcc = cast<Ptr<Byte>>("setge"); }
        }
        emit_str(ctx, cast<Ptr<Byte>>("    "));
        emit_str(ctx, setcc);
        emit_str(ctx, cast<Ptr<Byte>>(" al\n"));
        emit_str(ctx, cast<Ptr<Byte>>("    movzx rax, al\n"));
        emit_push_rax(ctx);
        return 0;
    }
    cg_error_at((*e).line, cast<Ptr<Byte>>("unknown binary op"));
    return 0;
}

// ---- gen_unary ----

Long gen_unary(Ptr<Expr> e, Ptr<CgCtx> ctx) {
    gen_expr((*e).child0, ctx);
    emit_pop_rax(ctx);
    Long uop = (*e).op;
    if (uop == OP_NEG()) {
        emit_str(ctx, cast<Ptr<Byte>>("    neg rax\n"));
        emit_push_rax(ctx);
        return 0;
    }
    if (uop == OP_NOT()) {
        emit_str(ctx, cast<Ptr<Byte>>("    cmp rax, 0\n"));
        emit_str(ctx, cast<Ptr<Byte>>("    sete al\n"));
        emit_str(ctx, cast<Ptr<Byte>>("    movzx rax, al\n"));
        emit_push_rax(ctx);
        return 0;
    }
    cg_error_at((*e).line, cast<Ptr<Byte>>("unknown unary op"));
    return 0;
}

// ---- gen_cast ----

Long gen_cast(Ptr<Expr> e, Ptr<CgCtx> ctx) {
    gen_expr((*e).child0, ctx);
    emit_pop_rax(ctx);
    Ptr<Type> from = (*(*e).child0).ety;
    Ptr<Type> to_t = (*e).cast_target;
    Long fk = (*from).kind;
    Long tk = (*to_t).kind;

    if (tk == TY_BOOLEAN()) {
        emit_str(ctx, cast<Ptr<Byte>>("    cmp rax, 0\n"));
        emit_str(ctx, cast<Ptr<Byte>>("    setne al\n"));
        emit_str(ctx, cast<Ptr<Byte>>("    movzx rax, al\n"));
        emit_push_rax(ctx);
        return 0;
    }
    Long from_sz = cg_type_size_kind(fk);
    Long to_sz = cg_type_size_kind(tk);
    Boolean from_sgn = cg_is_signed_kind(fk);
    if (fk == TY_BOOLEAN()) { from_sgn = false; }
    if (fk == TY_CHAR())    { from_sgn = false; }
    if (fk == TY_BYTE())    { from_sgn = false; }

    if (to_sz > from_sz) {
        if (from_sz == 1) {
            if (from_sgn) { emit_str(ctx, cast<Ptr<Byte>>("    movsx rax, al\n")); }
            else          { emit_str(ctx, cast<Ptr<Byte>>("    movzx rax, al\n")); }
        }
        if (from_sz == 2) {
            if (from_sgn) { emit_str(ctx, cast<Ptr<Byte>>("    movsx rax, ax\n")); }
            else          { emit_str(ctx, cast<Ptr<Byte>>("    movzx rax, ax\n")); }
        }
        if (from_sz == 4) {
            if (from_sgn) { emit_str(ctx, cast<Ptr<Byte>>("    movsxd rax, eax\n")); }
            else          { emit_str(ctx, cast<Ptr<Byte>>("    mov eax, eax\n")); }
        }
    } else {
        if (to_sz < from_sz) {
            Boolean to_sgn = false;
            if (tk == TY_INTEGER()) { to_sgn = true; }
            if (tk == TY_WHOLE())   { to_sgn = true; }
            if (tk == TY_LONG())    { to_sgn = true; }
            if (to_sz == 1) {
                if (to_sgn) { emit_str(ctx, cast<Ptr<Byte>>("    movsx rax, al\n")); }
                else        { emit_str(ctx, cast<Ptr<Byte>>("    movzx rax, al\n")); }
            }
            if (to_sz == 2) {
                if (to_sgn) { emit_str(ctx, cast<Ptr<Byte>>("    movsx rax, ax\n")); }
                else        { emit_str(ctx, cast<Ptr<Byte>>("    movzx rax, ax\n")); }
            }
            if (to_sz == 4) {
                if (to_sgn) { emit_str(ctx, cast<Ptr<Byte>>("    movsxd rax, eax\n")); }
                else        { emit_str(ctx, cast<Ptr<Byte>>("    mov eax, eax\n")); }
            }
        }
    }
    emit_push_rax(ctx);
    return 0;
}

// ---- gen_format_call: print/println ----

Long gen_format_call(Ptr<Expr> e, Ptr<CgCtx> ctx, Boolean append_newline) {
    Ptr<PtrVec> args_f = (*e).call_args;
    Ptr<Expr> fmt = cast<Ptr<Expr>>(ptrvec_get(args_f, 0));
    Ptr<Byte> src = (*fmt).str_data;
    Long len_f = (*fmt).str_len;

    Long i_f = 0;
    Long arg_idx = 1;

    while (i_f < len_f) {
        Long start_f = i_f;
        while (i_f < len_f) {
            if (cast<Long>(src[i_f]) == 37) { break; }    // '%'
            i_f = i_f + 1;
        }
        if (i_f > start_f) {
            Long cid = intern_cooked(ctx, src + start_f, i_f - start_f);
            Ptr<PtrVec> ck = (*ctx).cooked;
            Ptr<CookedStr> cs = cast<Ptr<CookedStr>>(ptrvec_get(ck, (*ck).count - 1));
            Long cooked_len = (*cs).len;
            emit_str(ctx, cast<Ptr<Byte>>("    lea rdi, [rel Lcstr_"));
            emit_long(ctx, cid);
            emit_str(ctx, cast<Ptr<Byte>>("]\n"));
            emit_str(ctx, cast<Ptr<Byte>>("    mov rsi, "));
            emit_long(ctx, cooked_len);
            emit_nl(ctx);
            emit_str(ctx, cast<Ptr<Byte>>("    call lazyc_write_bytes\n"));
        }
        if (i_f >= len_f) { break; }
        i_f = i_f + 1;     // consume '%'
        Long spec = cast<Long>(src[i_f]);
        i_f = i_f + 1;

        if (spec == 37) {       // '%%'
            Long pid = intern_cooked(ctx, cast<Ptr<Byte>>("%"), 1);
            emit_str(ctx, cast<Ptr<Byte>>("    lea rdi, [rel Lcstr_"));
            emit_long(ctx, pid);
            emit_str(ctx, cast<Ptr<Byte>>("]\n"));
            emit_str(ctx, cast<Ptr<Byte>>("    mov rsi, 1\n"));
            emit_str(ctx, cast<Ptr<Byte>>("    call lazyc_write_bytes\n"));
            continue;
        }

        Ptr<Expr> a_f = cast<Ptr<Expr>>(ptrvec_get(args_f, arg_idx));
        arg_idx = arg_idx + 1;
        gen_expr(a_f, ctx);
        emit_str(ctx, cast<Ptr<Byte>>("    pop rdi\n"));

        if (spec == 99)  { emit_str(ctx, cast<Ptr<Byte>>("    call lazyc_print_char\n"));   }
        if (spec == 105) { emit_str(ctx, cast<Ptr<Byte>>("    call lazyc_print_int16\n"));  }
        if (spec == 108) { emit_str(ctx, cast<Ptr<Byte>>("    call lazyc_print_long\n"));   }
        if (spec == 115) { emit_str(ctx, cast<Ptr<Byte>>("    call lazyc_print_string\n")); }
    }
    if (append_newline) {
        emit_str(ctx, cast<Ptr<Byte>>("    call lazyc_print_newline\n"));
    }
    return 0;
}

// ---- gen_call ----

Long gen_call(Ptr<Expr> e, Ptr<CgCtx> ctx) {
    Ptr<Byte> nm = (*e).name;
    Ptr<PtrVec> args_c = (*e).call_args;
    Long nargs = 0;
    if (args_c != cast<Ptr<PtrVec>>(null)) { nargs = (*args_c).count; }

    Boolean is_print   = ml_streq(nm, cast<Ptr<Byte>>("print"));
    Boolean is_println = ml_streq(nm, cast<Ptr<Byte>>("println"));
    Boolean is_pr = false;
    if (is_print)   { is_pr = true; }
    if (is_println) { is_pr = true; }
    if (is_pr) {
        gen_format_call(e, ctx, is_println);
        emit_str(ctx, cast<Ptr<Byte>>("    push 0\n"));
        return 0;
    }

    Boolean is_alloc = ml_streq(nm, cast<Ptr<Byte>>("alloc"));
    Boolean is_free  = ml_streq(nm, cast<Ptr<Byte>>("free"));
    Boolean is_exit  = ml_streq(nm, cast<Ptr<Byte>>("exit"));
    Boolean is_one_arg_builtin = false;
    if (is_alloc) { is_one_arg_builtin = true; }
    if (is_free)  { is_one_arg_builtin = true; }
    if (is_exit)  { is_one_arg_builtin = true; }
    if (is_one_arg_builtin) {
        Ptr<Expr> a0_b = cast<Ptr<Expr>>(ptrvec_get(args_c, 0));
        gen_expr(a0_b, ctx);
        emit_str(ctx, cast<Ptr<Byte>>("    pop rdi\n"));
        if (is_alloc)     { emit_str(ctx, cast<Ptr<Byte>>("    call lazyc_alloc\n")); }
        if (is_free)      { emit_str(ctx, cast<Ptr<Byte>>("    call lazyc_free\n")); }
        if (is_exit)      { emit_str(ctx, cast<Ptr<Byte>>("    call lazyc_exit\n")); }
        emit_push_rax(ctx);
        return 0;
    }

    Boolean is_readf  = ml_streq(nm, cast<Ptr<Byte>>("readf"));
    Boolean is_writef = ml_streq(nm, cast<Ptr<Byte>>("writef"));
    if (is_readf) {
        Ptr<Expr> a0_r = cast<Ptr<Expr>>(ptrvec_get(args_c, 0));
        gen_expr(a0_r, ctx);
        emit_str(ctx, cast<Ptr<Byte>>("    pop rdi\n"));
        emit_str(ctx, cast<Ptr<Byte>>("    call lazyc_readf\n"));
        emit_push_rax(ctx);
        return 0;
    }
    if (is_writef) {
        Ptr<Expr> a0_w = cast<Ptr<Expr>>(ptrvec_get(args_c, 0));
        Ptr<Expr> a1_w = cast<Ptr<Expr>>(ptrvec_get(args_c, 1));
        gen_expr(a0_w, ctx);
        gen_expr(a1_w, ctx);
        emit_str(ctx, cast<Ptr<Byte>>("    pop rsi\n"));
        emit_str(ctx, cast<Ptr<Byte>>("    pop rdi\n"));
        emit_str(ctx, cast<Ptr<Byte>>("    call lazyc_writef\n"));
        emit_push_rax(ctx);
        return 0;
    }

    Boolean is_argc = ml_streq(nm, cast<Ptr<Byte>>("argc"));
    Boolean is_argv = ml_streq(nm, cast<Ptr<Byte>>("argv"));
    if (is_argc) {
        emit_str(ctx, cast<Ptr<Byte>>("    call lazyc_argc\n"));
        emit_push_rax(ctx);
        return 0;
    }
    if (is_argv) {
        Ptr<Expr> a0_v = cast<Ptr<Expr>>(ptrvec_get(args_c, 0));
        gen_expr(a0_v, ctx);
        emit_str(ctx, cast<Ptr<Byte>>("    pop rdi\n"));
        emit_str(ctx, cast<Ptr<Byte>>("    call lazyc_argv\n"));
        emit_push_rax(ctx);
        return 0;
    }

    if (nargs > 6) {
        cg_error_at((*e).line, cast<Ptr<Byte>>("calls with more than 6 arguments are not supported"));
    }
    Long ci = 0;
    while (ci < nargs) {
        Ptr<Expr> ai = cast<Ptr<Expr>>(ptrvec_get(args_c, ci));
        gen_expr(ai, ctx);
        ci = ci + 1;
    }
    Long pi = nargs;
    while (pi > 0) {
        pi = pi - 1;
        Ptr<Byte> reg = arg_reg_for(pi, 8);
        emit_str(ctx, cast<Ptr<Byte>>("    pop "));
        emit_str(ctx, reg);
        emit_nl(ctx);
    }
    emit_str(ctx, cast<Ptr<Byte>>("    call "));
    emit_str(ctx, nm);
    emit_nl(ctx);
    emit_push_rax(ctx);
    return 0;
}

// ---- Lvalue address (for &x, &s.f, &arr[i]) ----

Long gen_lvalue_address(Ptr<Expr> e, Ptr<CgCtx> ctx) {
    Long lk = (*e).kind;
    if (lk == EX_IDENT()) {
        Ptr<Symbol> sy_l = symtab_find((*ctx).sym, (*e).name, (*e).name_len);
        if (sy_l == cast<Ptr<Symbol>>(null)) {
            cg_error_at((*e).line, cast<Ptr<Byte>>("internal: addr of unknown var"));
        }
        emit_mem_op(ctx, cast<Ptr<Byte>>("    lea rax, [rbp-"), (*sy_l).offset, cast<Ptr<Byte>>("]\n"));
        emit_push_rax(ctx);
        return 0;
    }
    if (lk == EX_DEREF()) {
        gen_expr((*e).child0, ctx);
        return 0;
    }
    if (lk == EX_FIELD()) {
        Ptr<Expr> op_l = (*e).child0;
        Ptr<Field> f_l = cast<Ptr<Field>>((*e).field_resolved);
        if (f_l == cast<Ptr<Field>>(null)) {
            cg_error_at((*e).line, cast<Ptr<Byte>>("internal: field not resolved"));
        }
        Long opk = (*op_l).kind;
        Boolean op_is_struct_ident = false;
        if (opk == EX_IDENT()) {
            if ((*(*op_l).ety).kind == TY_STRUCT()) { op_is_struct_ident = true; }
        }
        if (op_is_struct_ident) {
            Ptr<Symbol> sy_lf = symtab_find((*ctx).sym, (*op_l).name, (*op_l).name_len);
            if (sy_lf == cast<Ptr<Symbol>>(null)) {
                cg_error_at((*e).line, cast<Ptr<Byte>>("internal: addr-of field on unknown var"));
            }
            Long addr_l = (*sy_lf).offset - (*f_l).offset;
            emit_mem_op(ctx, cast<Ptr<Byte>>("    lea rax, [rbp-"), addr_l, cast<Ptr<Byte>>("]\n"));
            emit_push_rax(ctx);
            return 0;
        }
        if (opk == EX_DEREF()) {
            gen_expr((*op_l).child0, ctx);
            emit_pop_rax(ctx);
            if ((*f_l).offset != 0) {
                emit_op_rax_imm(ctx, cast<Ptr<Byte>>("add"), (*f_l).offset);
            }
            emit_push_rax(ctx);
            return 0;
        }
        cg_error_at((*e).line, cast<Ptr<Byte>>("internal: addr-of field with unexpected operand"));
    }
    if (lk == EX_INDEX()) {
        Long sz_l = cg_type_size((*e).ety);
        Ptr<Expr> base_l = (*e).child0;
        if ((*(*base_l).ety).kind == TY_ARRAY()) {
            gen_lvalue_address(base_l, ctx);
        } else {
            if ((*(*base_l).ety).kind == TY_PTR()) {
                gen_expr(base_l, ctx);
            } else {
                cg_error_at((*e).line, cast<Ptr<Byte>>("internal: index base has wrong type"));
            }
        }
        gen_expr((*e).child1, ctx);
        emit_pop_rax(ctx);
        if (sz_l != 1) {
            emit_str(ctx, cast<Ptr<Byte>>("    imul rax, rax, "));
            emit_long(ctx, sz_l);
            emit_nl(ctx);
        }
        emit_pop_rcx(ctx);
        emit_str(ctx, cast<Ptr<Byte>>("    add rax, rcx\n"));
        emit_push_rax(ctx);
        return 0;
    }
    cg_error_at((*e).line, cast<Ptr<Byte>>("internal: not an lvalue"));
    return 0;
}

// Push base[index] address with the given element size.
Long gen_index_addr(Ptr<Expr> base, Ptr<Expr> index, Long elem_size, Ptr<CgCtx> ctx) {
    if ((*(*base).ety).kind == TY_ARRAY()) {
        gen_lvalue_address(base, ctx);
    } else {
        if ((*(*base).ety).kind == TY_PTR()) {
            gen_expr(base, ctx);
        } else {
            cg_error_at((*base).line, cast<Ptr<Byte>>("internal: index on non-array, non-pointer"));
        }
    }
    gen_expr(index, ctx);
    emit_pop_rax(ctx);
    if (elem_size != 1) {
        emit_str(ctx, cast<Ptr<Byte>>("    imul rax, rax, "));
        emit_long(ctx, elem_size);
        emit_nl(ctx);
    }
    emit_pop_rcx(ctx);
    emit_str(ctx, cast<Ptr<Byte>>("    add rax, rcx\n"));
    emit_push_rax(ctx);
    return 0;
}

// ---- gen_stmt ----

Long gen_stmt(Ptr<Stmt> s, Ptr<CgCtx> ctx) {
    Long sk = (*s).kind;
    if (sk == ST_VAR_DECL()) {
        Ptr<Symbol> sy_v = symtab_find((*ctx).sym, (*s).var_name, (*s).var_name_len);
        if (sy_v == cast<Ptr<Symbol>>(null)) {
            cg_error_at((*s).line, cast<Ptr<Byte>>("internal: var not in symtab"));
        }
        if ((*s).var_init != cast<Ptr<Expr>>(null)) {
            gen_expr((*s).var_init, ctx);
            emit_pop_rax(ctx);
            emit_store_var(ctx, (*sy_v).ty, (*sy_v).offset);
        } else {
            emit_zero_var(ctx, (*sy_v).ty, (*sy_v).offset);
        }
        return 0;
    }
    if (sk == ST_ASSIGN()) {
        Ptr<Symbol> sy_a = symtab_find((*ctx).sym, (*s).var_name, (*s).var_name_len);
        if (sy_a == cast<Ptr<Symbol>>(null)) {
            cg_error_at((*s).line, cast<Ptr<Byte>>("internal: assignment to unknown var"));
        }
        gen_expr((*s).assign_value, ctx);
        emit_pop_rax(ctx);
        emit_store_var(ctx, (*sy_a).ty, (*sy_a).offset);
        return 0;
    }
    if (sk == ST_PTR_STORE()) {
        Ptr<Expr> deref_e = (*s).store_target;
        Ptr<Expr> pexpr = (*deref_e).child0;
        Ptr<Type> pointee_t = (*deref_e).ety;
        gen_expr(pexpr, ctx);
        gen_expr((*s).store_value, ctx);
        emit_pop_rax(ctx);
        emit_pop_rcx(ctx);
        Long sz_p = cg_type_size_kind((*pointee_t).kind);
        emit_store_via_rcx(ctx, sz_p);
        return 0;
    }
    if (sk == ST_FIELD_STORE()) {
        Ptr<Expr> fld_e = (*s).store_target;
        Ptr<Expr> op_fs = (*fld_e).child0;
        Ptr<Field> f_fs = cast<Ptr<Field>>((*fld_e).field_resolved);
        if (f_fs == cast<Ptr<Field>>(null)) {
            cg_error_at((*s).line, cast<Ptr<Byte>>("internal: field not resolved"));
        }
        Ptr<Type> fty_fs = cast<Ptr<Type>>((*f_fs).ty);
        Long sz_fs = cg_type_size_kind((*fty_fs).kind);
        if ((*op_fs).kind == EX_IDENT()) {
            Ptr<Symbol> sy_fs = symtab_find((*ctx).sym, (*op_fs).name, (*op_fs).name_len);
            if (sy_fs == cast<Ptr<Symbol>>(null)) {
                cg_error_at((*s).line, cast<Ptr<Byte>>("internal: field-store on unknown var"));
            }
            Long addr_fs = (*sy_fs).offset - (*f_fs).offset;
            gen_expr((*s).store_value, ctx);
            emit_pop_rax(ctx);
            if (sz_fs == 1) {
                emit_mem_op(ctx, cast<Ptr<Byte>>("    mov byte  [rbp-"), addr_fs, cast<Ptr<Byte>>("], al\n"));
            } else {
                if (sz_fs == 2) {
                    emit_mem_op(ctx, cast<Ptr<Byte>>("    mov word  [rbp-"), addr_fs, cast<Ptr<Byte>>("], ax\n"));
                } else {
                    if (sz_fs == 4) {
                        emit_mem_op(ctx, cast<Ptr<Byte>>("    mov dword [rbp-"), addr_fs, cast<Ptr<Byte>>("], eax\n"));
                    } else {
                        emit_mem_op(ctx, cast<Ptr<Byte>>("    mov qword [rbp-"), addr_fs, cast<Ptr<Byte>>("], rax\n"));
                    }
                }
            }
            return 0;
        }
        // EX_DEREF case
        gen_expr((*op_fs).child0, ctx);
        gen_expr((*s).store_value, ctx);
        emit_pop_rax(ctx);
        emit_pop_rcx(ctx);
        if ((*f_fs).offset != 0) {
            emit_str(ctx, cast<Ptr<Byte>>("    add rcx, "));
            emit_long(ctx, (*f_fs).offset);
            emit_nl(ctx);
        }
        emit_store_via_rcx(ctx, sz_fs);
        return 0;
    }
    if (sk == ST_INDEX_STORE()) {
        Ptr<Expr> idx_e = (*s).store_target;
        Long sz_is = cg_type_size_kind((*(*idx_e).ety).kind);
        gen_index_addr((*idx_e).child0, (*idx_e).child1, sz_is, ctx);
        gen_expr((*s).store_value, ctx);
        emit_pop_rax(ctx);
        emit_pop_rcx(ctx);
        emit_store_via_rcx(ctx, sz_is);
        return 0;
    }
    if (sk == ST_RETURN()) {
        if ((*s).ret_value != cast<Ptr<Expr>>(null)) {
            gen_expr((*s).ret_value, ctx);
            emit_pop_rax(ctx);
        } else {
            emit_str(ctx, cast<Ptr<Byte>>("    xor rax, rax\n"));
        }
        emit_str(ctx, cast<Ptr<Byte>>("    leave\n"));
        emit_str(ctx, cast<Ptr<Byte>>("    ret\n"));
        return 0;
    }
    if (sk == ST_BLOCK()) {
        Ptr<PtrVec> ss = (*s).block_stmts;
        if (ss != cast<Ptr<PtrVec>>(null)) {
            Long n = (*ss).count;
            Long bi = 0;
            while (bi < n) {
                Ptr<Stmt> child = cast<Ptr<Stmt>>(ptrvec_get(ss, bi));
                gen_stmt(child, ctx);
                bi = bi + 1;
            }
        }
        return 0;
    }
    if (sk == ST_EXPR()) {
        gen_expr((*s).expr, ctx);
        emit_str(ctx, cast<Ptr<Byte>>("    add rsp, 8\n"));
        return 0;
    }
    if (sk == ST_IF()) {
        Long if_else_lbl = new_label(ctx);
        Long if_end_lbl = if_else_lbl;
        Boolean has_else = false;
        if ((*s).else_b != cast<Ptr<Stmt>>(null)) {
            has_else = true;
            if_end_lbl = new_label(ctx);
        }
        gen_expr((*s).cond, ctx);
        emit_pop_rax(ctx);
        emit_str(ctx, cast<Ptr<Byte>>("    cmp rax, 0\n"));
        emit_jmp(ctx, cast<Ptr<Byte>>("je"), if_else_lbl);
        gen_stmt((*s).then_b, ctx);
        if (has_else) {
            emit_jmp(ctx, cast<Ptr<Byte>>("jmp"), if_end_lbl);
            emit_label_def(ctx, if_else_lbl);
            gen_stmt((*s).else_b, ctx);
        }
        emit_label_def(ctx, if_end_lbl);
        return 0;
    }
    if (sk == ST_WHILE()) {
        Long wh_top_lbl = new_label(ctx);
        Long wh_end_lbl = new_label(ctx);
        emit_label_def(ctx, wh_top_lbl);
        gen_expr((*s).cond, ctx);
        emit_pop_rax(ctx);
        emit_str(ctx, cast<Ptr<Byte>>("    cmp rax, 0\n"));
        emit_jmp(ctx, cast<Ptr<Byte>>("je"), wh_end_lbl);
        loop_push(ctx, wh_end_lbl, wh_top_lbl);
        gen_stmt((*s).body, ctx);
        loop_pop(ctx);
        emit_jmp(ctx, cast<Ptr<Byte>>("jmp"), wh_top_lbl);
        emit_label_def(ctx, wh_end_lbl);
        return 0;
    }
    if (sk == ST_FOR()) {
        Long for_top_lbl  = new_label(ctx);
        Long for_step_lbl = new_label(ctx);
        Long for_end_lbl  = new_label(ctx);
        if ((*s).for_init != cast<Ptr<Stmt>>(null)) { gen_stmt((*s).for_init, ctx); }
        emit_label_def(ctx, for_top_lbl);
        if ((*s).cond != cast<Ptr<Expr>>(null)) {
            gen_expr((*s).cond, ctx);
            emit_pop_rax(ctx);
            emit_str(ctx, cast<Ptr<Byte>>("    cmp rax, 0\n"));
            emit_jmp(ctx, cast<Ptr<Byte>>("je"), for_end_lbl);
        }
        loop_push(ctx, for_end_lbl, for_step_lbl);
        gen_stmt((*s).body, ctx);
        loop_pop(ctx);
        emit_label_def(ctx, for_step_lbl);
        if ((*s).for_update != cast<Ptr<Stmt>>(null)) { gen_stmt((*s).for_update, ctx); }
        emit_jmp(ctx, cast<Ptr<Byte>>("jmp"), for_top_lbl);
        emit_label_def(ctx, for_end_lbl);
        return 0;
    }
    if (sk == ST_BREAK()) {
        if (loop_depth_now(ctx) == 0) {
            cg_error_at((*s).line, cast<Ptr<Byte>>("internal: 'break' outside loop reached codegen"));
        }
        emit_jmp(ctx, cast<Ptr<Byte>>("jmp"), loop_break_lbl(ctx));
        return 0;
    }
    if (sk == ST_CONTINUE()) {
        if (loop_depth_now(ctx) == 0) {
            cg_error_at((*s).line, cast<Ptr<Byte>>("internal: 'continue' outside loop reached codegen"));
        }
        emit_jmp(ctx, cast<Ptr<Byte>>("jmp"), loop_continue_lbl(ctx));
        return 0;
    }
    cg_error_at((*s).line, cast<Ptr<Byte>>("statement not supported"));
    return 0;
}

// ---- gen_func ----

Long gen_func(Ptr<FuncDecl> f, Ptr<CgCtx> ctx) {
    Ptr<PtrVec> params = (*f).params;
    Long nparams = 0;
    if (params != cast<Ptr<PtrVec>>(null)) { nparams = (*params).count; }
    if (nparams > 6) {
        cg_error_at((*f).line, cast<Ptr<Byte>>("functions with more than 6 parameters are not supported"));
    }
    // Reset loop stack at function entry/exit.
    Ptr<PtrVec> ls = (*ctx).loop_stack;
    (*ls).count = 0;

    Ptr<SymTab> st = symtab_new();
    (*ctx).sym = st;
    // Add parameters first.
    Long pi_a = 0;
    while (pi_a < nparams) {
        Ptr<Param> pa = cast<Ptr<Param>>(ptrvec_get(params, pi_a));
        symtab_add(st, (*pa).name, (*pa).name_len, (*pa).ty, (*f).line);
        pi_a = pi_a + 1;
    }
    collect_locals_stmt((*f).body, st);
    Long frame = symtab_stack_size_aligned(st);

    emit_str(ctx, cast<Ptr<Byte>>("global "));
    emit_str(ctx, (*f).name);
    emit_nl(ctx);
    emit_str(ctx, (*f).name);
    emit_str(ctx, cast<Ptr<Byte>>(":\n"));
    emit_str(ctx, cast<Ptr<Byte>>("    push rbp\n"));
    emit_str(ctx, cast<Ptr<Byte>>("    mov rbp, rsp\n"));
    if (frame > 0) {
        emit_str(ctx, cast<Ptr<Byte>>("    sub rsp, "));
        emit_long(ctx, frame);
        emit_nl(ctx);
    }

    // Spill parameter registers.
    Long pi_s = 0;
    while (pi_s < nparams) {
        Ptr<Param> ps = cast<Ptr<Param>>(ptrvec_get(params, pi_s));
        Ptr<Symbol> sy_sp = symtab_find(st, (*ps).name, (*ps).name_len);
        Long sz_sp = cg_type_size_kind((*(*sy_sp).ty).kind);
        Ptr<Byte> reg = arg_reg_for(pi_s, sz_sp);
        if (sz_sp == 1) {
            emit_str(ctx, cast<Ptr<Byte>>("    mov byte  [rbp-"));
        } else {
            if (sz_sp == 2) {
                emit_str(ctx, cast<Ptr<Byte>>("    mov word  [rbp-"));
            } else {
                if (sz_sp == 4) {
                    emit_str(ctx, cast<Ptr<Byte>>("    mov dword [rbp-"));
                } else {
                    emit_str(ctx, cast<Ptr<Byte>>("    mov qword [rbp-"));
                }
            }
        }
        emit_long(ctx, (*sy_sp).offset);
        emit_str(ctx, cast<Ptr<Byte>>("], "));
        emit_str(ctx, reg);
        emit_nl(ctx);
        pi_s = pi_s + 1;
    }

    gen_stmt((*f).body, ctx);

    // Default epilogue.
    emit_str(ctx, cast<Ptr<Byte>>("    xor rax, rax\n"));
    emit_str(ctx, cast<Ptr<Byte>>("    leave\n"));
    emit_str(ctx, cast<Ptr<Byte>>("    ret\n"));

    return 0;
}

// ---- codegen_program ----

// Emit one StrLit's data in `db ...,0` form. The bytes go through escape
// processing on the fly (matches the C compiler's emit-time decoding for
// strlits, distinct from the cooked-pool which decoded earlier).
Long emit_strlit_data(Ptr<CgCtx> ctx, Ptr<StrLit> s) {
    emit_str(ctx, cast<Ptr<Byte>>("Lstr_"));
    emit_long(ctx, (*s).label_id);
    emit_str(ctx, cast<Ptr<Byte>>(": db "));
    Long len_s = (*s).len;
    Ptr<Byte> data_s = (*s).data;
    Boolean first = true;
    Long j = 0;
    while (j < len_s) {
        Long c = cast<Long>(data_s[j]);
        Boolean did_esc = false;
        if (c == 92) {                 // '\'
            if (j + 1 < len_s) {
                Long esc = cast<Long>(data_s[j + 1]);
                if (esc == 120) {                // 'x' -> \xHH
                    if (j + 3 < len_s) {
                        Long h1 = cast<Long>(data_s[j + 2]);
                        Long h2 = cast<Long>(data_s[j + 3]);
                        Long d1 = -1;
                        Long d2 = -1;
                        if (h1 >= 48) { if (h1 <= 57) { d1 = h1 - 48; } }
                        if (h1 >= 97) { if (h1 <= 102){ d1 = h1 - 97 + 10; } }
                        if (h1 >= 65) { if (h1 <= 70) { d1 = h1 - 65 + 10; } }
                        if (h2 >= 48) { if (h2 <= 57) { d2 = h2 - 48; } }
                        if (h2 >= 97) { if (h2 <= 102){ d2 = h2 - 97 + 10; } }
                        if (h2 >= 65) { if (h2 <= 70) { d2 = h2 - 65 + 10; } }
                        Boolean both_ok = false;
                        if (d1 >= 0) { if (d2 >= 0) { both_ok = true; } }
                        if (both_ok) {
                            c = d1 * 16 + d2;
                            j = j + 4;
                            did_esc = true;
                        }
                    }
                }
                if (!did_esc) {
                    Long resolved = esc;
                    if (esc == 110) { resolved = 10;  }
                    if (esc == 116) { resolved = 9;   }
                    if (esc == 114) { resolved = 13;  }
                    if (esc == 48)  { resolved = 0;   }
                    if (esc == 92)  { resolved = 92;  }
                    if (esc == 39)  { resolved = 39;  }
                    if (esc == 34)  { resolved = 34;  }
                    c = resolved;
                    j = j + 2;
                    did_esc = true;
                }
            }
        }
        if (!did_esc) { j = j + 1; }
        if (!first) {
            emit_str(ctx, cast<Ptr<Byte>>(","));
        }
        emit_long(ctx, c);
        first = false;
    }
    if (!first) {
        emit_str(ctx, cast<Ptr<Byte>>(","));
    }
    emit_str(ctx, cast<Ptr<Byte>>("0\n"));
    return 0;
}

Long emit_cooked_data(Ptr<CgCtx> ctx, Ptr<CookedStr> cs) {
    emit_str(ctx, cast<Ptr<Byte>>("Lcstr_"));
    emit_long(ctx, (*cs).label_id);
    emit_str(ctx, cast<Ptr<Byte>>(": db "));
    Long ln = (*cs).len;
    if (ln == 0) {
        emit_str(ctx, cast<Ptr<Byte>>("0\n"));
        return 0;
    }
    Long j = 0;
    while (j < ln) {
        if (j != 0) { emit_str(ctx, cast<Ptr<Byte>>(",")); }
        emit_long(ctx, cast<Long>((*cs).bytes[j]));
        j = j + 1;
    }
    emit_nl(ctx);
    return 0;
}

Long codegen_program(Ptr<Program> pg, Ptr<Buf> out) {
    Ptr<CgCtx> ctx = cgctx_new(out);

    emit_str(ctx, cast<Ptr<Byte>>("; auto-generated by lazyc\n"));

    // Builtin externs: emitted by default so user code doesn't need to
    // declare them. But if the current program defines one of these
    // names as a non-extern function (e.g. when compiling runtime.ml
    // itself), skip the `extern` to avoid nasm's "label inconsistently
    // redefined" error.
    Ptr<PtrVec> pg_funcs = (*pg).funcs;
    Long pg_nf = (*pg_funcs).count;

    // Walk through the 13 builtin names; for each, scan the program's
    // funcs for a matching non-extern definition and only emit the
    // `extern` if no match is found.
    Long bi = 0;
    while (bi < 13) {
        Ptr<Byte> bname = cast<Ptr<Byte>>(null);
        if (bi == 0)  { bname = cast<Ptr<Byte>>("lazyc_write_bytes"); }
        if (bi == 1)  { bname = cast<Ptr<Byte>>("lazyc_print_char"); }
        if (bi == 2)  { bname = cast<Ptr<Byte>>("lazyc_print_int16"); }
        if (bi == 3)  { bname = cast<Ptr<Byte>>("lazyc_print_long"); }
        if (bi == 4)  { bname = cast<Ptr<Byte>>("lazyc_print_string"); }
        if (bi == 5)  { bname = cast<Ptr<Byte>>("lazyc_print_newline"); }
        if (bi == 6)  { bname = cast<Ptr<Byte>>("lazyc_alloc"); }
        if (bi == 7)  { bname = cast<Ptr<Byte>>("lazyc_free"); }
        if (bi == 8)  { bname = cast<Ptr<Byte>>("lazyc_exit"); }
        if (bi == 9)  { bname = cast<Ptr<Byte>>("lazyc_readf"); }
        if (bi == 10) { bname = cast<Ptr<Byte>>("lazyc_writef"); }
        if (bi == 11) { bname = cast<Ptr<Byte>>("lazyc_argc"); }
        if (bi == 12) { bname = cast<Ptr<Byte>>("lazyc_argv"); }

        Boolean defined_locally = false;
        Long pi = 0;
        while (pi < pg_nf) {
            Ptr<FuncDecl> pf = cast<Ptr<FuncDecl>>(ptrvec_get(pg_funcs, pi));
            if ((*pf).is_extern == 0) {
                if (ml_streq((*pf).name, bname)) {
                    defined_locally = true;
                }
            }
            pi = pi + 1;
        }

        if (!defined_locally) {
            emit_str(ctx, cast<Ptr<Byte>>("extern "));
            emit_str(ctx, bname);
            emit_nl(ctx);
        }
        bi = bi + 1;
    }

    // User-declared externs (e.g. syscall trampolines): emit one
    // `extern <name>` per is_extern function so the linker can resolve
    // calls to it.
    Ptr<PtrVec> all_funcs_for_extern = (*pg).funcs;
    Long n_for_extern = (*all_funcs_for_extern).count;
    Long fxi = 0;
    while (fxi < n_for_extern) {
        Ptr<FuncDecl> fx = cast<Ptr<FuncDecl>>(ptrvec_get(all_funcs_for_extern, fxi));
        if ((*fx).is_extern != 0) {
            emit_str(ctx, cast<Ptr<Byte>>("extern "));
            emit_str(ctx, (*fx).name);
            emit_nl(ctx);
        }
        fxi = fxi + 1;
    }
    emit_str(ctx, cast<Ptr<Byte>>("section .text\n"));

    Ptr<PtrVec> funcs = (*pg).funcs;
    Long nf = (*funcs).count;
    Long fi = 0;
    while (fi < nf) {
        Ptr<FuncDecl> fd = cast<Ptr<FuncDecl>>(ptrvec_get(funcs, fi));
        if ((*fd).is_extern == 0) {
            gen_func(fd, ctx);
        }
        fi = fi + 1;
    }

    Ptr<PtrVec> sl = (*ctx).strlits;
    Ptr<PtrVec> ck = (*ctx).cooked;
    Boolean has_rodata = false;
    if ((*sl).count > 0) { has_rodata = true; }
    if ((*ck).count > 0) { has_rodata = true; }

    if (has_rodata) {
        emit_str(ctx, cast<Ptr<Byte>>("section .rodata\n"));
        Long si = 0;
        while (si < (*sl).count) {
            Ptr<StrLit> s = cast<Ptr<StrLit>>(ptrvec_get(sl, si));
            emit_strlit_data(ctx, s);
            si = si + 1;
        }
        Long ci = 0;
        while (ci < (*ck).count) {
            Ptr<CookedStr> cs = cast<Ptr<CookedStr>>(ptrvec_get(ck, ci));
            emit_cooked_data(ctx, cs);
            ci = ci + 1;
        }
    }
    return 0;
}
