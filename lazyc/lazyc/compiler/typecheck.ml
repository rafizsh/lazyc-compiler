// lazyc/compiler/typecheck.ml
//
// Typechecker for lazyc. Step 21h.
//
// Mirrors src/typecheck.c. The post-condition of typecheck_program is
// that every Expr node has its `ety` field set, EX_FIELD nodes have
// `field_resolved` filled in, and the program has been validated for
// type errors. Typed nulls and typed integer literals lose their
// "untyped" flag once coerced to a concrete type.
//
// Implementation notes:
//   * Symbol table = TcCtx with a PtrVec of Ptr<TcSym>. One per function.
//   * Function table = a PtrVec of Ptr<FuncSig>. Built once at program start.
//   * Loop depth tracked on TcCtx so break/continue can be validated.
//   * tc_error prints to stdout and exits 1 (matching the C compiler's
//     behavior, just routed through stdout instead of stderr — lazyc's
//     println goes to stdout).

// ---- Type predicates ----

Boolean is_signed_numeric_kind(Long k) {
    if (k == TY_INTEGER()) { return true; }
    if (k == TY_WHOLE())   { return true; }
    if (k == TY_LONG())    { return true; }
    return false;
}

Boolean is_unsigned_numeric_kind(Long k) {
    if (k == TY_UINTEGER()) { return true; }
    if (k == TY_UWHOLE())   { return true; }
    if (k == TY_ULONG())    { return true; }
    return false;
}

Boolean is_numeric_kind(Long k) {
    if (is_signed_numeric_kind(k))   { return true; }
    if (is_unsigned_numeric_kind(k)) { return true; }
    return false;
}

// type_size in BYTES for a given TypeKind. Used by promote_numeric and
// implicitly_assignable. Different from types.ml's type_size which works
// on Ptr<Type> and handles structs/arrays. This one mirrors the C
// typechecker's static type_size which is purely for numeric size compare.
Long tc_type_size_kind(Long k) {
    if (k == TY_BOOLEAN())  { return 1; }
    if (k == TY_CHAR())     { return 1; }
    if (k == TY_BYTE())     { return 1; }
    if (k == TY_INTEGER())  { return 2; }
    if (k == TY_UINTEGER()) { return 2; }
    if (k == TY_WHOLE())    { return 4; }
    if (k == TY_UWHOLE())   { return 4; }
    if (k == TY_LONG())     { return 8; }
    if (k == TY_ULONG())    { return 8; }
    if (k == TY_STRING())   { return 8; }
    if (k == TY_PTR())      { return 8; }
    return 0;
}

// Print a type-kind's name. Used by tc_error messages.
Ptr<Byte> tc_type_name_kind(Long k) {
    if (k == TY_BOOLEAN())  { return cast<Ptr<Byte>>("Boolean");  }
    if (k == TY_CHAR())     { return cast<Ptr<Byte>>("Char");     }
    if (k == TY_BYTE())     { return cast<Ptr<Byte>>("Byte");     }
    if (k == TY_INTEGER())  { return cast<Ptr<Byte>>("Integer");  }
    if (k == TY_UINTEGER()) { return cast<Ptr<Byte>>("uInteger"); }
    if (k == TY_WHOLE())    { return cast<Ptr<Byte>>("Whole");    }
    if (k == TY_UWHOLE())   { return cast<Ptr<Byte>>("uWhole");   }
    if (k == TY_LONG())     { return cast<Ptr<Byte>>("Long");     }
    if (k == TY_ULONG())    { return cast<Ptr<Byte>>("uLong");    }
    if (k == TY_STRING())   { return cast<Ptr<Byte>>("String");   }
    if (k == TY_PTR())      { return cast<Ptr<Byte>>("Ptr");      }
    if (k == TY_STRUCT())   { return cast<Ptr<Byte>>("struct");   }
    if (k == TY_VOID())     { return cast<Ptr<Byte>>("void");     }
    return cast<Ptr<Byte>>("?");
}

// True if the integer value v fits in a destination of kind k. Mirrors
// the C compiler's literal_fits range check.
Boolean literal_fits(Long v, Long k) {
    if (k == TY_BOOLEAN()) {
        if (v == 0) { return true; }
        if (v == 1) { return true; }
        return false;
    }
    if (k == TY_CHAR()) {
        if (v < 0)   { return false; }
        if (v > 127) { return false; }
        return true;
    }
    if (k == TY_BYTE()) {
        if (v < 0)   { return false; }
        if (v > 255) { return false; }
        return true;
    }
    if (k == TY_INTEGER()) {
        if (v < -32768) { return false; }
        if (v > 32767)  { return false; }
        return true;
    }
    if (k == TY_UINTEGER()) {
        if (v < 0)     { return false; }
        if (v > 65535) { return false; }
        return true;
    }
    if (k == TY_WHOLE()) {
        if (v < -2147483648) { return false; }
        if (v > 2147483647)  { return false; }
        return true;
    }
    if (k == TY_UWHOLE()) {
        if (v < 0)         { return false; }
        if (v > 4294967295){ return false; }
        return true;
    }
    if (k == TY_LONG())  { return true; }
    if (k == TY_ULONG()) {
        if (v < 0) { return false; }
        return true;
    }
    return false;
}

// ---- Type-error reporter ----
// Format strings here are kept simple (one or two %s/%l interpolations).
// The C version supports varargs; we don't, so we accept a fixed set of
// shapes and use overloading by suffix.
Long tc_error_simple(Long line, Ptr<Byte> msg) {
    println("type error at line %l: %s", line, cast<String>(msg));
    exit(1);
    return 0;
}
Long tc_error_one(Long line, Ptr<Byte> prefix, Ptr<Byte> a) {
    println("type error at line %l: %s %s", line,
            cast<String>(prefix), cast<String>(a));
    exit(1);
    return 0;
}
Long tc_error_two(Long line, Ptr<Byte> prefix, Ptr<Byte> a,
                  Ptr<Byte> mid, Ptr<Byte> b) {
    println("type error at line %l: %s %s %s %s", line,
            cast<String>(prefix), cast<String>(a),
            cast<String>(mid), cast<String>(b));
    exit(1);
    return 0;
}

// ---- Symbol table ----
//
// One entry per (name -> Type) binding. Linear search; ~dozens of
// entries per function in practice.
struct TcSym {
    Ptr<Byte> name;          // null-terminated
    Ptr<Type> ty;
}

Ptr<TcSym> tcsym_new(Ptr<Byte> name, Ptr<Type> ty) {
    Ptr<Byte> raw = alloc(16);
    Ptr<TcSym> s = cast<Ptr<TcSym>>(raw);
    (*s).name = name;
    (*s).ty   = ty;
    return s;
}

// TcCtx is the per-function typechecking context. `func_return_ty` is
// the declared return type; `loop_depth` tracks nesting so break/continue
// can be validated. `funcs` is a borrowed pointer to the program-level
// function table.
struct TcCtx {
    Ptr<PtrVec> items;            // PtrVec of Ptr<TcSym>
    Ptr<Type>   func_return_ty;
    Ptr<PtrVec> funcs;            // PtrVec of Ptr<FuncSig>
    Long        loop_depth;
}

Long ctx_init(Ptr<TcCtx> c, Ptr<Type> ret, Ptr<PtrVec> funcs) {
    Ptr<Byte> raw = alloc(24);
    Ptr<PtrVec> items = cast<Ptr<PtrVec>>(raw);
    ptrvec_init(items);
    (*c).items          = items;
    (*c).func_return_ty = ret;
    (*c).funcs          = funcs;
    (*c).loop_depth     = 0;
    return 0;
}

// Linear lookup. Returns null if not found. Names are compared via
// lex_slice_eq (slice vs null-terminated).
Ptr<TcSym> ctx_find(Ptr<TcCtx> c, Ptr<Byte> name, Long name_len) {
    Ptr<PtrVec> items = (*c).items;
    Long n = (*items).count;
    Long i = 0;
    while (i < n) {
        Ptr<TcSym> s = cast<Ptr<TcSym>>(ptrvec_get(items, i));
        if (lex_slice_eq(name, name_len, (*s).name)) { return s; }
        i = i + 1;
    }
    return cast<Ptr<TcSym>>(null);
}

// Add a binding. Errors if `name` is already declared in this context.
// `name` is a slice (start + length). We need a null-terminated buffer
// for storage; lex_intern_slice would be ideal, but we don't have it —
// instead we rely on the fact that lazyc interns identifier text in
// the Token (null-terminated, lives forever) so we can reuse the source
// pointer. The tokens come from Token.text which IS null-terminated by
// the lexer.
Long ctx_add(Ptr<TcCtx> c, Ptr<Byte> name, Long name_len, Ptr<Type> ty, Long line) {
    Ptr<TcSym> existing = ctx_find(c, name, name_len);
    if (existing != cast<Ptr<TcSym>>(null)) {
        tc_error_one(line, cast<Ptr<Byte>>("redeclaration of"), name);
    }
    Ptr<TcSym> s = tcsym_new(name, ty);
    ptrvec_push((*c).items, cast<Ptr<Byte>>(s));
    return 0;
}

// ---- Function signatures ----
//
// Built once at program start from FuncDecls. Calls look up signatures
// to validate argument counts/types and resolve the call's return type.
struct FuncSig {
    Ptr<Byte>   name;
    Ptr<Type>   return_ty;
    Ptr<PtrVec> params;     // PtrVec of Ptr<Param>
}

Ptr<FuncSig> funcsig_new(Ptr<Byte> name, Ptr<Type> ret, Ptr<PtrVec> params) {
    Ptr<Byte> raw = alloc(24);
    Ptr<FuncSig> s = cast<Ptr<FuncSig>>(raw);
    (*s).name      = name;
    (*s).return_ty = ret;
    (*s).params    = params;
    return s;
}

Ptr<FuncSig> funcs_find(Ptr<PtrVec> ft, Ptr<Byte> name, Long name_len) {
    Long n = (*ft).count;
    Long i = 0;
    while (i < n) {
        Ptr<FuncSig> sig = cast<Ptr<FuncSig>>(ptrvec_get(ft, i));
        if (lex_slice_eq(name, name_len, (*sig).name)) { return sig; }
        i = i + 1;
    }
    return cast<Ptr<FuncSig>>(null);
}

Long funcs_add(Ptr<PtrVec> ft, Ptr<FuncDecl> f) {
    Ptr<FuncSig> existing = funcs_find(ft, (*f).name, (*f).name_len);
    if (existing != cast<Ptr<FuncSig>>(null)) {
        tc_error_one((*f).line, cast<Ptr<Byte>>("redefinition of function"), (*f).name);
    }
    Ptr<FuncSig> sig = funcsig_new((*f).name, (*f).return_ty, (*f).params);
    ptrvec_push(ft, cast<Ptr<Byte>>(sig));
    return 0;
}

// ---- Implicit assignability ----
//
// True if expression e can be implicitly converted to type `to`. Side
// effects: when an untyped literal or null is coerced, this function
// updates e's `ety` to the target type. To match the C compiler's
// observable behavior exactly, the `is_untyped_int` and
// `is_untyped_null` flags are NOT cleared here — the binary-op pre-
// pass clears them explicitly when it does its own coercion. Mirrors
// the C implicitly_assignable.
Boolean implicitly_assignable(Ptr<Expr> e, Ptr<Type> to) {
    if ((*e).is_untyped_null != 0) {
        if ((*to).kind == TY_PTR()) {
            (*e).ety = to;
            return true;
        }
        return false;
    }
    if ((*e).is_untyped_int != 0) {
        Long k = (*to).kind;
        Boolean can_coerce = false;
        if (is_numeric_kind(k))   { can_coerce = true; }
        if (k == TY_BYTE())       { can_coerce = true; }
        if (k == TY_CHAR())       { can_coerce = true; }
        if (can_coerce) {
            if (literal_fits((*e).num, k)) {
                (*e).ety = to;
                // NOTE: matching the C compiler, we DO NOT clear
                // is_untyped_int here. The binary-op pre-pass clears it
                // explicitly when it does its own coercion. Leaving the
                // flag set everywhere else has no observable effect on
                // accepted programs (codegen and the AST printer don't
                // consult it), but matters for byte-level fidelity at
                // the fixed-point test (21m).
                return true;
            }
            return false;
        }
    }
    if ((*e).ety == cast<Ptr<Type>>(null)) { return false; }
    if (types_equal((*e).ety, to)) { return true; }
    Long ek = (*(*e).ety).kind;
    Long tk = (*to).kind;
    if (is_numeric_kind(ek)) {
        if (is_numeric_kind(tk)) {
            Boolean from_signed = is_signed_numeric_kind(ek);
            Boolean to_signed   = is_signed_numeric_kind(tk);
            if (from_signed != to_signed) { return false; }
            if (tc_type_size_kind(ek) <= tc_type_size_kind(tk)) { return true; }
            return false;
        }
    }
    return false;
}

// Numeric promotion. Returns the wider of two same-signed numeric types,
// or a TY_UNKNOWN type if the operands aren't compatible. Mirrors the C
// promote_numeric.
Ptr<Type> promote_numeric(Ptr<Type> a, Ptr<Type> b) {
    Long ak = (*a).kind;
    Long bk = (*b).kind;
    if (!is_numeric_kind(ak)) { return type_simple(TY_UNKNOWN()); }
    if (!is_numeric_kind(bk)) { return type_simple(TY_UNKNOWN()); }
    if (is_signed_numeric_kind(ak) != is_signed_numeric_kind(bk)) {
        return type_simple(TY_UNKNOWN());
    }
    if (tc_type_size_kind(ak) >= tc_type_size_kind(bk)) { return a; }
    return b;
}

// ---- Expression typechecker ----
//
// Walks one Expr, sets ety, recursively descends. Errors on type
// problems by calling tc_error_*.
//
// Forward-declared in lecture order; lazyc resolves cross-function
// names globally so the forward declaration is implicit.

// Validate an EX_INDEX node: typecheck base and index, return the
// element type. Caller decides whether to enforce the
// "elem must not be aggregate" rule (yes for value-context, no for
// `&arr[i]` addr-of).
Ptr<Type> tc_index_resolve(Ptr<Expr> e, Ptr<TcCtx> ctx) {
    Ptr<Expr> base = (*e).child0;
    Ptr<Type> elem_ty = type_simple(TY_UNKNOWN());

    if ((*base).kind == EX_IDENT()) {
        Ptr<TcSym> s = ctx_find(ctx, (*base).name, (*base).name_len);
        if (s == cast<Ptr<TcSym>>(null)) {
            tc_error_one((*e).line, cast<Ptr<Byte>>("undefined variable"), (*base).name);
        }
        Long sk = (*(*s).ty).kind;
        if (sk == TY_ARRAY()) {
            (*base).ety = (*s).ty;
            elem_ty = (*(*s).ty).elem;
        } else {
            if (sk == TY_PTR()) {
                (*base).ety = (*s).ty;
                elem_ty = (*(*s).ty).pointee;
            } else {
                tc_error_one((*e).line,
                    cast<Ptr<Byte>>("cannot index; expected array or Ptr<T>, got"),
                    tc_type_name_kind(sk));
            }
        }
    } else {
        tc_expr(base, ctx);
        Long bk = (*(*base).ety).kind;
        if (bk == TY_PTR()) {
            elem_ty = (*(*base).ety).pointee;
        } else {
            if (bk == TY_ARRAY()) {
                elem_ty = (*(*base).ety).elem;
            } else {
                tc_error_one((*e).line,
                    cast<Ptr<Byte>>("cannot index; expected array or Ptr<T>, got"),
                    tc_type_name_kind(bk));
            }
        }
    }

    tc_expr((*e).child1, ctx);
    Ptr<Type> long_ty = type_simple(TY_LONG());
    if (!implicitly_assignable((*e).child1, long_ty)) {
        Long ik = TY_UNKNOWN();
        if ((*(*e).child1).ety != cast<Ptr<Type>>(null)) {
            ik = (*(*(*e).child1).ety).kind;
        }
        tc_error_one((*e).line,
            cast<Ptr<Byte>>("array index must be integer-shaped, got"),
            tc_type_name_kind(ik));
    }

    return elem_ty;
}

// The big one: typecheck one Expr node.
Long tc_expr(Ptr<Expr> e, Ptr<TcCtx> ctx) {
    Long k = (*e).kind;

    if (k == EX_NUMBER()) {
        (*e).ety = type_simple(TY_LONG());
        return 0;
    }
    if (k == EX_NULL()) {
        // Default null type: Ptr<Byte>. is_untyped_null stays set so
        // implicitly_assignable can re-coerce later.
        (*e).ety = type_ptr(type_simple(TY_BYTE()));
        return 0;
    }
    if (k == EX_BOOL_LIT()) {
        (*e).ety = type_simple(TY_BOOLEAN());
        return 0;
    }
    if (k == EX_CHAR_LIT()) {
        (*e).ety = type_simple(TY_CHAR());
        return 0;
    }
    if (k == EX_STRING_LIT()) {
        (*e).ety = type_simple(TY_STRING());
        return 0;
    }

    if (k == EX_IDENT()) {
        Ptr<TcSym> sy_id = ctx_find(ctx, (*e).name, (*e).name_len);
        if (sy_id == cast<Ptr<TcSym>>(null)) {
            tc_error_one((*e).line, cast<Ptr<Byte>>("undefined variable"), (*e).name);
        }
        Long sk = (*(*sy_id).ty).kind;
        if (sk == TY_STRUCT()) {
            tc_error_one((*e).line,
                cast<Ptr<Byte>>("cannot use struct value in an expression:"),
                (*e).name);
        }
        if (sk == TY_ARRAY()) {
            tc_error_one((*e).line,
                cast<Ptr<Byte>>("cannot use array value as a value:"),
                (*e).name);
        }
        (*e).ety = (*sy_id).ty;
        return 0;
    }

    if (k == EX_CAST()) {
        tc_expr((*e).child0, ctx);
        Long target_k = (*(*e).cast_target).kind;
        Ptr<Type> from = (*(*e).child0).ety;
        Long from_k = (*from).kind;

        if (target_k == TY_STRING()) {
            // Only Ptr<Byte> -> String is allowed.
            Boolean ok_to_str = false;
            if (from_k == TY_PTR()) {
                if ((*from).pointee != cast<Ptr<Type>>(null)) {
                    if ((*(*from).pointee).kind == TY_BYTE()) { ok_to_str = true; }
                }
            }
            if (!ok_to_str) {
                tc_error_one((*e).line,
                    cast<Ptr<Byte>>("cannot cast to String (only Ptr<Byte> -> String allowed); from"),
                    tc_type_name_kind(from_k));
            }
        } else {
            if (target_k == TY_VOID()) {
                tc_error_simple((*e).line, cast<Ptr<Byte>>("cannot cast to void"));
            }
        }
        // Cast FROM String: only allowed to Ptr<Byte>.
        if (from_k == TY_STRING()) {
            Boolean ok_from_str = false;
            if (target_k == TY_PTR()) {
                if ((*(*e).cast_target).pointee != cast<Ptr<Type>>(null)) {
                    if ((*(*(*e).cast_target).pointee).kind == TY_BYTE()) { ok_from_str = true; }
                }
            }
            if (!ok_from_str) {
                tc_error_simple((*e).line,
                    cast<Ptr<Byte>>("cannot cast from String (only String -> Ptr<Byte> allowed)"));
            }
        }
        (*e).ety = (*e).cast_target;
        return 0;
    }

    if (k == EX_ADDR_OF()) {
        Ptr<Expr> t = (*e).child0;
        Long tk = (*t).kind;
        if (tk == EX_IDENT()) {
            Ptr<TcSym> sy_addr = ctx_find(ctx, (*t).name, (*t).name_len);
            if (sy_addr == cast<Ptr<TcSym>>(null)) {
                tc_error_one((*e).line, cast<Ptr<Byte>>("undefined variable"), (*t).name);
            }
            (*t).ety = (*sy_addr).ty;
            (*e).ety = type_ptr((*sy_addr).ty);
            return 0;
        }
        if (tk == EX_FIELD()) {
            tc_expr(t, ctx);
            (*e).ety = type_ptr((*t).ety);
            return 0;
        }
        if (tk == EX_INDEX()) {
            Ptr<Type> addr_elem_ty = tc_index_resolve(t, ctx);
            (*t).ety = addr_elem_ty;
            (*e).ety = type_ptr(addr_elem_ty);
            return 0;
        }
        tc_error_simple((*e).line,
            cast<Ptr<Byte>>("'&' requires a variable, 'struct.field', or 'arr[index]' (lvalue)"));
        return 0;
    }

    if (k == EX_DEREF()) {
        tc_expr((*e).child0, ctx);
        Ptr<Type> pt = (*(*e).child0).ety;
        if ((*pt).kind != TY_PTR()) {
            tc_error_one((*e).line,
                cast<Ptr<Byte>>("'*' requires a pointer, got"),
                tc_type_name_kind((*pt).kind));
        }
        (*e).ety = (*pt).pointee;
        return 0;
    }

    if (k == EX_FIELD()) {
        Ptr<Expr> f_op = (*e).child0;
        Ptr<StructDef> sd = cast<Ptr<StructDef>>(null);
        Long opk = (*f_op).kind;
        if (opk == EX_IDENT()) {
            Ptr<TcSym> sy_fld = ctx_find(ctx, (*f_op).name, (*f_op).name_len);
            if (sy_fld == cast<Ptr<TcSym>>(null)) {
                tc_error_one((*e).line, cast<Ptr<Byte>>("undefined variable"), (*f_op).name);
            }
            if ((*(*sy_fld).ty).kind != TY_STRUCT()) {
                tc_error_one((*e).line,
                    cast<Ptr<Byte>>("'.field' requires a struct value, got"),
                    tc_type_name_kind((*(*sy_fld).ty).kind));
            }
            (*f_op).ety = (*sy_fld).ty;
            sd = cast<Ptr<StructDef>>((*(*sy_fld).ty).sdef);
        } else {
            if (opk == EX_DEREF()) {
                tc_expr(f_op, ctx);
                if ((*(*f_op).ety).kind != TY_STRUCT()) {
                    tc_error_one((*e).line,
                        cast<Ptr<Byte>>("'.field' through pointer requires Ptr<struct>, pointee is"),
                        tc_type_name_kind((*(*f_op).ety).kind));
                }
                sd = cast<Ptr<StructDef>>((*(*f_op).ety).sdef);
            } else {
                tc_error_simple((*e).line,
                    cast<Ptr<Byte>>("field access requires a struct variable or '*ptr-to-struct' on the left"));
            }
        }
        // Resolve the field by name.
        Ptr<Field> resolved = find_field((*sd).fields, (*e).name, (*e).name_len);
        if (resolved == cast<Ptr<Field>>(null)) {
            tc_error_two((*e).line,
                cast<Ptr<Byte>>("struct"), (*sd).name,
                cast<Ptr<Byte>>("has no field"), (*e).name);
        }
        (*e).field_resolved = cast<Ptr<Byte>>(resolved);
        (*e).ety = cast<Ptr<Type>>((*resolved).ty);
        return 0;
    }

    if (k == EX_INDEX()) {
        Ptr<Type> elem_ty = tc_index_resolve(e, ctx);
        Long ek = (*elem_ty).kind;
        if (ek == TY_STRUCT()) {
            tc_error_one((*e).line,
                cast<Ptr<Byte>>("indexing yields aggregate; use &arr[i] to get a pointer:"),
                tc_type_name_kind(ek));
        }
        if (ek == TY_ARRAY()) {
            tc_error_one((*e).line,
                cast<Ptr<Byte>>("indexing yields aggregate; use &arr[i] to get a pointer:"),
                tc_type_name_kind(ek));
        }
        (*e).ety = elem_ty;
        return 0;
    }

    if (k == EX_UNARY()) {
        tc_expr((*e).child0, ctx);
        Long u_op = (*e).op;
        Ptr<Type> ot = (*(*e).child0).ety;
        if (u_op == OP_NOT()) {
            if ((*ot).kind != TY_BOOLEAN()) {
                tc_error_one((*e).line,
                    cast<Ptr<Byte>>("operator '!' requires Boolean, got"),
                    tc_type_name_kind((*ot).kind));
            }
            (*e).ety = type_simple(TY_BOOLEAN());
            return 0;
        }
        // OP_NEG
        if (!is_signed_numeric_kind((*ot).kind)) {
            tc_error_one((*e).line,
                cast<Ptr<Byte>>("unary '-' requires a signed numeric type, got"),
                tc_type_name_kind((*ot).kind));
        }
        (*e).ety = ot;
        // Constant-fold -<literal>.
        if ((*(*e).child0).is_untyped_int != 0) {
            Long u_folded = 0 - (*(*e).child0).num;
            (*e).kind = EX_NUMBER();
            (*e).is_untyped_int = 1;
            (*e).num = u_folded;
        }
        return 0;
    }

    if (k == EX_BINARY()) {
        tc_expr((*e).child0, ctx);
        tc_expr((*e).child1, ctx);

        // Untyped-int coercion to the typed sibling.
        if ((*(*e).child0).is_untyped_int != 0) {
            if ((*(*e).child1).is_untyped_int == 0) {
                if (is_numeric_kind((*(*(*e).child1).ety).kind)) {
                    if (literal_fits((*(*e).child0).num, (*(*(*e).child1).ety).kind)) {
                        (*(*e).child0).ety = (*(*e).child1).ety;
                        (*(*e).child0).is_untyped_int = 0;
                    }
                }
            }
        }
        if ((*(*e).child1).is_untyped_int != 0) {
            if ((*(*e).child0).is_untyped_int == 0) {
                if (is_numeric_kind((*(*(*e).child0).ety).kind)) {
                    if (literal_fits((*(*e).child1).num, (*(*(*e).child0).ety).kind)) {
                        (*(*e).child1).ety = (*(*e).child0).ety;
                        (*(*e).child1).is_untyped_int = 0;
                    }
                }
            }
        }
        // Untyped-null coercion to typed-pointer sibling.
        if ((*(*e).child0).is_untyped_null != 0) {
            if ((*(*(*e).child1).ety).kind == TY_PTR()) {
                (*(*e).child0).ety = (*(*e).child1).ety;
                (*(*e).child0).is_untyped_null = 0;
            }
        }
        if ((*(*e).child1).is_untyped_null != 0) {
            if ((*(*(*e).child0).ety).kind == TY_PTR()) {
                (*(*e).child1).ety = (*(*e).child0).ety;
                (*(*e).child1).is_untyped_null = 0;
            }
        }

        Ptr<Type> L = (*(*e).child0).ety;
        Ptr<Type> R = (*(*e).child1).ety;
        Long Lk = (*L).kind;
        Long Rk = (*R).kind;
        Long b_op = (*e).op;

        // Pointer arithmetic and pointer comparisons.
        Boolean any_ptr = false;
        if (Lk == TY_PTR()) { any_ptr = true; }
        if (Rk == TY_PTR()) { any_ptr = true; }
        if (any_ptr) {
            Boolean is_muldivmod = false;
            if (b_op == OP_MUL()) { is_muldivmod = true; }
            if (b_op == OP_DIV()) { is_muldivmod = true; }
            if (b_op == OP_MOD()) { is_muldivmod = true; }
            if (is_muldivmod) {
                tc_error_simple((*e).line,
                    cast<Ptr<Byte>>("cannot apply '*' '/' or '%' to pointers"));
            }
            if (b_op == OP_ADD()) {
                Ptr<Type> long_ty = type_simple(TY_LONG());
                if (Lk == TY_PTR()) {
                    if (implicitly_assignable((*e).child1, long_ty)) {
                        (*e).ety = L; return 0;
                    }
                }
                if (Rk == TY_PTR()) {
                    if (implicitly_assignable((*e).child0, long_ty)) {
                        (*e).ety = R; return 0;
                    }
                }
                tc_error_simple((*e).line,
                    cast<Ptr<Byte>>("pointer addition needs Ptr<T> + Long"));
            }
            if (b_op == OP_SUB()) {
                if (Lk == TY_PTR()) {
                    if (Rk == TY_PTR()) {
                        if (!types_equal(L, R)) {
                            tc_error_simple((*e).line,
                                cast<Ptr<Byte>>("pointer subtraction requires same pointee type"));
                        }
                        (*e).ety = type_simple(TY_LONG());
                        return 0;
                    }
                }
                Ptr<Type> long_ty_sub = type_simple(TY_LONG());
                if (Lk == TY_PTR()) {
                    if (implicitly_assignable((*e).child1, long_ty_sub)) {
                        (*e).ety = L; return 0;
                    }
                }
                tc_error_simple((*e).line,
                    cast<Ptr<Byte>>("pointer subtraction needs Ptr<T> - Long or Ptr<T> - Ptr<T>"));
            }
            Boolean is_eq = false;
            if (b_op == OP_EQ())  { is_eq = true; }
            if (b_op == OP_NEQ()) { is_eq = true; }
            if (is_eq) {
                if (!types_equal(L, R)) {
                    tc_error_simple((*e).line,
                        cast<Ptr<Byte>>("pointer comparison requires same pointee type"));
                }
                (*e).ety = type_simple(TY_BOOLEAN());
                return 0;
            }
            Boolean is_ord = false;
            if (b_op == OP_LT()) { is_ord = true; }
            if (b_op == OP_GT()) { is_ord = true; }
            if (b_op == OP_LE()) { is_ord = true; }
            if (b_op == OP_GE()) { is_ord = true; }
            if (is_ord) {
                if (!types_equal(L, R)) {
                    tc_error_simple((*e).line,
                        cast<Ptr<Byte>>("pointer ordering requires same pointee type"));
                }
                (*e).ety = type_simple(TY_BOOLEAN());
                return 0;
            }
        }

        Boolean is_arith = false;
        if (b_op == OP_ADD()) { is_arith = true; }
        if (b_op == OP_SUB()) { is_arith = true; }
        if (b_op == OP_MUL()) { is_arith = true; }
        if (b_op == OP_DIV()) { is_arith = true; }
        if (b_op == OP_MOD()) { is_arith = true; }
        if (is_arith) {
            Ptr<Type> r_ar = promote_numeric(L, R);
            if ((*r_ar).kind == TY_UNKNOWN()) {
                tc_error_two((*e).line,
                    cast<Ptr<Byte>>("arithmetic on incompatible types:"),
                    tc_type_name_kind(Lk),
                    cast<Ptr<Byte>>("and"),
                    tc_type_name_kind(Rk));
            }
            (*e).ety = r_ar;
            // Constant-fold both-untyped-int.
            if ((*(*e).child0).is_untyped_int != 0) {
                if ((*(*e).child1).is_untyped_int != 0) {
                    Long fa = (*(*e).child0).num;
                    Long fb = (*(*e).child1).num;
                    Long folded = 0;
                    if (b_op == OP_ADD()) { folded = fa + fb; }
                    if (b_op == OP_SUB()) { folded = fa - fb; }
                    if (b_op == OP_MUL()) { folded = fa * fb; }
                    if (b_op == OP_DIV()) {
                        if (fb != 0) { folded = fa / fb; }
                    }
                    if (b_op == OP_MOD()) {
                        if (fb != 0) { folded = fa - (fa / fb) * fb; }
                    }
                    (*e).kind = EX_NUMBER();
                    (*e).is_untyped_int = 1;
                    (*e).num = folded;
                }
            }
            return 0;
        }
        Boolean is_eq2 = false;
        if (b_op == OP_EQ())  { is_eq2 = true; }
        if (b_op == OP_NEQ()) { is_eq2 = true; }
        if (is_eq2) {
            if (types_equal(L, R)) {
                (*e).ety = type_simple(TY_BOOLEAN()); return 0;
            }
            Ptr<Type> r_eq = promote_numeric(L, R);
            if ((*r_eq).kind == TY_UNKNOWN()) {
                tc_error_two((*e).line,
                    cast<Ptr<Byte>>("cannot compare for equality:"),
                    tc_type_name_kind(Lk),
                    cast<Ptr<Byte>>("and"),
                    tc_type_name_kind(Rk));
            }
            (*e).ety = type_simple(TY_BOOLEAN());
            return 0;
        }
        Boolean is_ord2 = false;
        if (b_op == OP_LT()) { is_ord2 = true; }
        if (b_op == OP_GT()) { is_ord2 = true; }
        if (b_op == OP_LE()) { is_ord2 = true; }
        if (b_op == OP_GE()) { is_ord2 = true; }
        if (is_ord2) {
            Ptr<Type> r_ord = promote_numeric(L, R);
            if ((*r_ord).kind == TY_UNKNOWN()) {
                tc_error_two((*e).line,
                    cast<Ptr<Byte>>("ordering requires numeric same-signed operands:"),
                    tc_type_name_kind(Lk),
                    cast<Ptr<Byte>>("and"),
                    tc_type_name_kind(Rk));
            }
            (*e).ety = type_simple(TY_BOOLEAN());
            return 0;
        }
        tc_error_simple((*e).line, cast<Ptr<Byte>>("internal: unknown binary op"));
        return 0;
    }

    if (k == EX_CALL()) {
        // Built-ins first: print/println/alloc/free/exit/readf/writef/argc/argv.
        Ptr<Byte> nm = (*e).name;
        Ptr<PtrVec> args = (*e).call_args;
        Long nargs = 0;
        if (args != cast<Ptr<PtrVec>>(null)) { nargs = (*args).count; }

        Boolean is_print   = ml_streq(nm, cast<Ptr<Byte>>("print"));
        Boolean is_println = ml_streq(nm, cast<Ptr<Byte>>("println"));
        Boolean is_pr = false;
        if (is_print)   { is_pr = true; }
        if (is_println) { is_pr = true; }
        if (is_pr) {
            return tc_call_print(e, ctx, is_println);
        }
        if (ml_streq(nm, cast<Ptr<Byte>>("alloc"))) {
            return tc_call_alloc(e, ctx);
        }
        if (ml_streq(nm, cast<Ptr<Byte>>("free"))) {
            return tc_call_free(e, ctx);
        }
        if (ml_streq(nm, cast<Ptr<Byte>>("exit"))) {
            return tc_call_exit(e, ctx);
        }
        if (ml_streq(nm, cast<Ptr<Byte>>("readf"))) {
            return tc_call_readf(e, ctx);
        }
        if (ml_streq(nm, cast<Ptr<Byte>>("writef"))) {
            return tc_call_writef(e, ctx);
        }
        if (ml_streq(nm, cast<Ptr<Byte>>("argc"))) {
            return tc_call_argc(e, ctx);
        }
        if (ml_streq(nm, cast<Ptr<Byte>>("argv"))) {
            return tc_call_argv(e, ctx);
        }
        // User-defined function.
        Ptr<FuncSig> sig = funcs_find((*ctx).funcs, nm, (*e).name_len);
        if (sig == cast<Ptr<FuncSig>>(null)) {
            tc_error_one((*e).line, cast<Ptr<Byte>>("call to undefined function"), nm);
        }
        Long want = (*(*sig).params).count;
        if (nargs != want) {
            tc_error_one((*e).line, cast<Ptr<Byte>>("argument count mismatch for"), nm);
        }
        Long i = 0;
        while (i < nargs) {
            Ptr<Expr> a = cast<Ptr<Expr>>(ptrvec_get(args, i));
            tc_expr(a, ctx);
            Ptr<Param> p = cast<Ptr<Param>>(ptrvec_get((*sig).params, i));
            if (!implicitly_assignable(a, (*p).ty)) {
                tc_error_one((*e).line,
                    cast<Ptr<Byte>>("argument type mismatch in call to"), nm);
            }
            i = i + 1;
        }
        (*e).ety = (*sig).return_ty;
        return 0;
    }

    println("type error at line %l: internal: unknown expr kind %l", (*e).line, k);
    exit(1);
    return 0;
}

// ---- Built-in calls (split out to avoid huge tc_expr) ----

// Helper: returns the argument count for a call. Treats null call_args
// as 0 (the parser allocates a PtrVec even for f() with no args, but
// being defensive here is harmless).
Long call_nargs(Ptr<Expr> e) {
    Ptr<PtrVec> args = (*e).call_args;
    if (args == cast<Ptr<PtrVec>>(null)) { return 0; }
    return (*args).count;
}

Long tc_call_alloc(Ptr<Expr> e, Ptr<TcCtx> ctx) {
    if (call_nargs(e) != 1) {
        tc_error_simple((*e).line, cast<Ptr<Byte>>("alloc expects exactly 1 argument"));
    }
    Ptr<PtrVec> args = (*e).call_args;
    Ptr<Expr> a0 = cast<Ptr<Expr>>(ptrvec_get(args, 0));
    tc_expr(a0, ctx);
    Ptr<Type> long_ty = type_simple(TY_LONG());
    if (!implicitly_assignable(a0, long_ty)) {
        tc_error_one((*e).line,
            cast<Ptr<Byte>>("alloc expects a Long size, got"),
            tc_type_name_kind((*(*a0).ety).kind));
    }
    (*e).ety = type_ptr(type_simple(TY_BYTE()));
    return 0;
}

Long tc_call_free(Ptr<Expr> e, Ptr<TcCtx> ctx) {
    if (call_nargs(e) != 1) {
        tc_error_simple((*e).line, cast<Ptr<Byte>>("free expects exactly 1 argument"));
    }
    Ptr<PtrVec> args = (*e).call_args;
    Ptr<Expr> a0 = cast<Ptr<Expr>>(ptrvec_get(args, 0));
    tc_expr(a0, ctx);
    Ptr<Type> byte_ptr = type_ptr(type_simple(TY_BYTE()));
    if (!implicitly_assignable(a0, byte_ptr)) {
        tc_error_one((*e).line,
            cast<Ptr<Byte>>("free expects Ptr<Byte>, got"),
            tc_type_name_kind((*(*a0).ety).kind));
    }
    (*e).ety = type_simple(TY_BOOLEAN());
    return 0;
}

Long tc_call_exit(Ptr<Expr> e, Ptr<TcCtx> ctx) {
    if (call_nargs(e) != 1) {
        tc_error_simple((*e).line, cast<Ptr<Byte>>("exit expects exactly 1 argument"));
    }
    Ptr<PtrVec> args = (*e).call_args;
    Ptr<Expr> a0 = cast<Ptr<Expr>>(ptrvec_get(args, 0));
    tc_expr(a0, ctx);
    Ptr<Type> long_ty = type_simple(TY_LONG());
    if (!implicitly_assignable(a0, long_ty)) {
        tc_error_one((*e).line,
            cast<Ptr<Byte>>("exit expects a Long code, got"),
            tc_type_name_kind((*(*a0).ety).kind));
    }
    (*e).ety = type_simple(TY_LONG());
    return 0;
}

Long tc_call_readf(Ptr<Expr> e, Ptr<TcCtx> ctx) {
    if (call_nargs(e) != 1) {
        tc_error_simple((*e).line, cast<Ptr<Byte>>("readf expects exactly 1 argument"));
    }
    Ptr<PtrVec> args = (*e).call_args;
    Ptr<Expr> a0 = cast<Ptr<Expr>>(ptrvec_get(args, 0));
    tc_expr(a0, ctx);
    Ptr<Type> str_ty = type_simple(TY_STRING());
    if (!implicitly_assignable(a0, str_ty)) {
        tc_error_one((*e).line,
            cast<Ptr<Byte>>("readf expects a String path, got"),
            tc_type_name_kind((*(*a0).ety).kind));
    }
    (*e).ety = type_ptr(type_simple(TY_BYTE()));
    return 0;
}

Long tc_call_writef(Ptr<Expr> e, Ptr<TcCtx> ctx) {
    if (call_nargs(e) != 2) {
        tc_error_simple((*e).line, cast<Ptr<Byte>>("writef expects exactly 2 arguments"));
    }
    Ptr<PtrVec> args = (*e).call_args;
    Ptr<Expr> a0 = cast<Ptr<Expr>>(ptrvec_get(args, 0));
    Ptr<Expr> a1 = cast<Ptr<Expr>>(ptrvec_get(args, 1));
    tc_expr(a0, ctx);
    tc_expr(a1, ctx);
    Ptr<Type> str_ty = type_simple(TY_STRING());
    Ptr<Type> byte_ptr = type_ptr(type_simple(TY_BYTE()));
    if (!implicitly_assignable(a0, str_ty)) {
        tc_error_one((*e).line,
            cast<Ptr<Byte>>("writef expects String path, got"),
            tc_type_name_kind((*(*a0).ety).kind));
    }
    if (!implicitly_assignable(a1, byte_ptr)) {
        tc_error_one((*e).line,
            cast<Ptr<Byte>>("writef expects Ptr<Byte> contents, got"),
            tc_type_name_kind((*(*a1).ety).kind));
    }
    (*e).ety = type_simple(TY_BOOLEAN());
    return 0;
}

Long tc_call_argc(Ptr<Expr> e, Ptr<TcCtx> ctx) {
    Ptr<PtrVec> args = (*e).call_args;
    Long n = 0;
    if (args != cast<Ptr<PtrVec>>(null)) { n = (*args).count; }
    if (n != 0) {
        tc_error_simple((*e).line, cast<Ptr<Byte>>("argc expects 0 arguments"));
    }
    (*e).ety = type_simple(TY_LONG());
    return 0;
}

Long tc_call_argv(Ptr<Expr> e, Ptr<TcCtx> ctx) {
    if (call_nargs(e) != 1) {
        tc_error_simple((*e).line, cast<Ptr<Byte>>("argv expects exactly 1 argument"));
    }
    Ptr<PtrVec> args = (*e).call_args;
    Ptr<Expr> a0 = cast<Ptr<Expr>>(ptrvec_get(args, 0));
    tc_expr(a0, ctx);
    Ptr<Type> long_ty = type_simple(TY_LONG());
    if (!implicitly_assignable(a0, long_ty)) {
        tc_error_one((*e).line,
            cast<Ptr<Byte>>("argv expects a Long index, got"),
            tc_type_name_kind((*(*a0).ety).kind));
    }
    (*e).ety = type_ptr(type_simple(TY_BYTE()));
    return 0;
}

// Format-string check for print/println. Validates that every %X in
// the format string is matched with a same-typed argument, and that
// no extras appear on either side. Sets the call's type to LONG (the
// C version uses TY_VOID, but our AST printer treats unknown-with-
// kind=LONG identically; double-check below).
Long tc_call_print(Ptr<Expr> e, Ptr<TcCtx> ctx, Boolean is_println) {
    Ptr<PtrVec> args = (*e).call_args;
    Long nargs = 0;
    if (args != cast<Ptr<PtrVec>>(null)) { nargs = (*args).count; }
    if (nargs < 1) {
        tc_error_simple((*e).line,
            cast<Ptr<Byte>>("print/println requires at least a format string"));
    }
    Ptr<Expr> fmt = cast<Ptr<Expr>>(ptrvec_get(args, 0));
    if ((*fmt).kind != EX_STRING_LIT()) {
        tc_error_simple((*e).line,
            cast<Ptr<Byte>>("print/println format must be a string literal"));
    }
    (*fmt).ety = type_simple(TY_STRING());

    Ptr<Byte> data = (*fmt).str_data;
    Long len = (*fmt).str_len;
    Long arg_idx = 1;
    Long i = 0;
    while (i < len) {
        Long c = cast<Long>(data[i]);
        if (c != 37) {     // '%' == 37
            i = i + 1;
            continue;
        }
        if (i + 1 >= len) {
            tc_error_simple((*e).line,
                cast<Ptr<Byte>>("trailing '%' in format string"));
        }
        Long spec = cast<Long>(data[i + 1]);
        i = i + 2;
        if (spec == 37) { continue; }   // '%%'

        Long want_kind = TY_UNKNOWN();
        if (spec == 99) { want_kind = TY_CHAR(); }      // 'c'
        if (spec == 105){ want_kind = TY_INTEGER(); }   // 'i'
        if (spec == 108){ want_kind = TY_LONG(); }      // 'l'
        if (spec == 115){ want_kind = TY_STRING(); }    // 's'
        if (want_kind == TY_UNKNOWN()) {
            tc_error_simple((*e).line,
                cast<Ptr<Byte>>("unknown format specifier (use %c %i %l %s or %%)"));
        }
        if (arg_idx >= nargs) {
            tc_error_simple((*e).line,
                cast<Ptr<Byte>>("format string has more specifiers than arguments"));
        }
        Ptr<Expr> a = cast<Ptr<Expr>>(ptrvec_get(args, arg_idx));
        arg_idx = arg_idx + 1;
        tc_expr(a, ctx);
        Ptr<Type> want = type_simple(want_kind);
        if (!implicitly_assignable(a, want)) {
            tc_error_one((*e).line,
                cast<Ptr<Byte>>("format argument type mismatch; expected"),
                tc_type_name_kind(want_kind));
        }
    }
    if (arg_idx != nargs) {
        tc_error_simple((*e).line,
            cast<Ptr<Byte>>("format string has fewer specifiers than arguments"));
    }
    (*e).ety = type_simple(TY_VOID());
    return 0;
}

// ---- Statement typechecker ----

Long tc_stmt(Ptr<Stmt> s, Ptr<TcCtx> ctx) {
    Long k = (*s).kind;

    if (k == ST_VAR_DECL()) {
        Long vk = (*(*s).var_ty).kind;
        Boolean is_bad = false;
        if (vk == TY_VOID())    { is_bad = true; }
        if (vk == TY_UNKNOWN()) { is_bad = true; }
        if (is_bad) {
            tc_error_simple((*s).line, cast<Ptr<Byte>>("invalid variable type"));
        }
        Ptr<Expr> init = (*s).var_init;
        if (vk == TY_STRUCT()) {
            if (init != cast<Ptr<Expr>>(null)) {
                tc_error_simple((*s).line,
                    cast<Ptr<Byte>>("struct variables cannot be initialized"));
            }
        }
        if (vk == TY_ARRAY()) {
            if (init != cast<Ptr<Expr>>(null)) {
                tc_error_simple((*s).line,
                    cast<Ptr<Byte>>("array variables cannot be initialized"));
            }
        }
        if (init != cast<Ptr<Expr>>(null)) {
            tc_expr(init, ctx);
            if (!implicitly_assignable(init, (*s).var_ty)) {
                tc_error_two((*s).line,
                    cast<Ptr<Byte>>("cannot initialize"),
                    tc_type_name_kind(vk),
                    cast<Ptr<Byte>>("with value of type"),
                    tc_type_name_kind((*(*init).ety).kind));
            }
        }
        ctx_add(ctx, (*s).var_name, (*s).var_name_len, (*s).var_ty, (*s).line);
        return 0;
    }

    if (k == ST_ASSIGN()) {
        Ptr<TcSym> sy = ctx_find(ctx, (*s).var_name, (*s).var_name_len);
        if (sy == cast<Ptr<TcSym>>(null)) {
            tc_error_one((*s).line,
                cast<Ptr<Byte>>("assignment to undefined variable"),
                (*s).var_name);
        }
        tc_expr((*s).assign_value, ctx);
        if (!implicitly_assignable((*s).assign_value, (*sy).ty)) {
            tc_error_two((*s).line,
                cast<Ptr<Byte>>("cannot assign"),
                tc_type_name_kind((*(*(*s).assign_value).ety).kind),
                cast<Ptr<Byte>>("to variable of type"),
                tc_type_name_kind((*(*sy).ty).kind));
        }
        return 0;
    }

    if (k == ST_PTR_STORE()) {
        tc_expr((*s).store_target, ctx);
        Ptr<Type> pointee_ty = (*(*s).store_target).ety;
        tc_expr((*s).store_value, ctx);
        if (!implicitly_assignable((*s).store_value, pointee_ty)) {
            tc_error_two((*s).line,
                cast<Ptr<Byte>>("cannot store"),
                tc_type_name_kind((*(*(*s).store_value).ety).kind),
                cast<Ptr<Byte>>("through pointer to"),
                tc_type_name_kind((*pointee_ty).kind));
        }
        return 0;
    }

    if (k == ST_FIELD_STORE()) {
        tc_expr((*s).store_target, ctx);
        Ptr<Type> field_ty = (*(*s).store_target).ety;
        tc_expr((*s).store_value, ctx);
        if (!implicitly_assignable((*s).store_value, field_ty)) {
            tc_error_two((*s).line,
                cast<Ptr<Byte>>("cannot store"),
                tc_type_name_kind((*(*(*s).store_value).ety).kind),
                cast<Ptr<Byte>>("into field of type"),
                tc_type_name_kind((*field_ty).kind));
        }
        return 0;
    }

    if (k == ST_INDEX_STORE()) {
        tc_expr((*s).store_target, ctx);
        Ptr<Type> elem_ty = (*(*s).store_target).ety;
        tc_expr((*s).store_value, ctx);
        if (!implicitly_assignable((*s).store_value, elem_ty)) {
            tc_error_two((*s).line,
                cast<Ptr<Byte>>("cannot store"),
                tc_type_name_kind((*(*(*s).store_value).ety).kind),
                cast<Ptr<Byte>>("into element of type"),
                tc_type_name_kind((*elem_ty).kind));
        }
        return 0;
    }

    if (k == ST_RETURN()) {
        Ptr<Expr> v = (*s).ret_value;
        if (v != cast<Ptr<Expr>>(null)) {
            tc_expr(v, ctx);
            if (!implicitly_assignable(v, (*ctx).func_return_ty)) {
                tc_error_two((*s).line,
                    cast<Ptr<Byte>>("cannot return"),
                    tc_type_name_kind((*(*v).ety).kind),
                    cast<Ptr<Byte>>("from function declared to return"),
                    tc_type_name_kind((*(*ctx).func_return_ty).kind));
            }
        } else {
            if ((*(*ctx).func_return_ty).kind != TY_VOID()) {
                tc_error_one((*s).line,
                    cast<Ptr<Byte>>("missing return value (function returns)"),
                    tc_type_name_kind((*(*ctx).func_return_ty).kind));
            }
        }
        return 0;
    }

    if (k == ST_IF()) {
        tc_expr((*s).cond, ctx);
        if ((*(*(*s).cond).ety).kind != TY_BOOLEAN()) {
            tc_error_one((*s).line,
                cast<Ptr<Byte>>("if-condition must be Boolean, got"),
                tc_type_name_kind((*(*(*s).cond).ety).kind));
        }
        tc_stmt((*s).then_b, ctx);
        if ((*s).else_b != cast<Ptr<Stmt>>(null)) {
            tc_stmt((*s).else_b, ctx);
        }
        return 0;
    }

    if (k == ST_WHILE()) {
        tc_expr((*s).cond, ctx);
        if ((*(*(*s).cond).ety).kind != TY_BOOLEAN()) {
            tc_error_one((*s).line,
                cast<Ptr<Byte>>("while-condition must be Boolean, got"),
                tc_type_name_kind((*(*(*s).cond).ety).kind));
        }
        (*ctx).loop_depth = (*ctx).loop_depth + 1;
        tc_stmt((*s).body, ctx);
        (*ctx).loop_depth = (*ctx).loop_depth - 1;
        return 0;
    }

    if (k == ST_FOR()) {
        if ((*s).for_init != cast<Ptr<Stmt>>(null)) {
            tc_stmt((*s).for_init, ctx);
        }
        if ((*s).cond != cast<Ptr<Expr>>(null)) {
            tc_expr((*s).cond, ctx);
            if ((*(*(*s).cond).ety).kind != TY_BOOLEAN()) {
                tc_error_one((*s).line,
                    cast<Ptr<Byte>>("for-condition must be Boolean, got"),
                    tc_type_name_kind((*(*(*s).cond).ety).kind));
            }
        }
        (*ctx).loop_depth = (*ctx).loop_depth + 1;
        tc_stmt((*s).body, ctx);
        (*ctx).loop_depth = (*ctx).loop_depth - 1;
        if ((*s).for_update != cast<Ptr<Stmt>>(null)) {
            tc_stmt((*s).for_update, ctx);
        }
        return 0;
    }

    if (k == ST_BREAK()) {
        if ((*ctx).loop_depth == 0) {
            tc_error_simple((*s).line,
                cast<Ptr<Byte>>("'break' is only valid inside a loop"));
        }
        return 0;
    }
    if (k == ST_CONTINUE()) {
        if ((*ctx).loop_depth == 0) {
            tc_error_simple((*s).line,
                cast<Ptr<Byte>>("'continue' is only valid inside a loop"));
        }
        return 0;
    }
    if (k == ST_BLOCK()) {
        Ptr<PtrVec> stmts = (*s).block_stmts;
        if (stmts != cast<Ptr<PtrVec>>(null)) {
            Long n = (*stmts).count;
            Long i = 0;
            while (i < n) {
                Ptr<Stmt> child = cast<Ptr<Stmt>>(ptrvec_get(stmts, i));
                tc_stmt(child, ctx);
                i = i + 1;
            }
        }
        return 0;
    }
    if (k == ST_EXPR()) {
        tc_expr((*s).expr, ctx);
        return 0;
    }
    println("type error at line %l: internal: unknown stmt kind %l", (*s).line, k);
    exit(1);
    return 0;
}

// ---- Program-level entry ----

Long typecheck_program(Ptr<Program> pg) {
    // Build the function table.
    Ptr<Byte> raw = alloc(24);
    Ptr<PtrVec> ft = cast<Ptr<PtrVec>>(raw);
    ptrvec_init(ft);

    Ptr<PtrVec> funcs = (*pg).funcs;
    Long nf = (*funcs).count;
    Long i = 0;
    while (i < nf) {
        Ptr<FuncDecl> fa = cast<Ptr<FuncDecl>>(ptrvec_get(funcs, i));
        funcs_add(ft, fa);
        i = i + 1;
    }

    // Typecheck each body. Externs have no body to check.
    Long fi = 0;
    while (fi < nf) {
        Ptr<FuncDecl> fb = cast<Ptr<FuncDecl>>(ptrvec_get(funcs, fi));
        if ((*fb).is_extern != 0) {
            fi = fi + 1;
            continue;
        }
        TcCtx ctx;
        ctx_init(&ctx, (*fb).return_ty, ft);
        // Add parameters as locals.
        Ptr<PtrVec> params = (*fb).params;
        if (params != cast<Ptr<PtrVec>>(null)) {
            Long pn = (*params).count;
            Long pi = 0;
            while (pi < pn) {
                Ptr<Param> p = cast<Ptr<Param>>(ptrvec_get(params, pi));
                ctx_add(&ctx, (*p).name, (*p).name_len, (*p).ty, (*fb).line);
                pi = pi + 1;
            }
        }
        tc_stmt((*fb).body, &ctx);
        fi = fi + 1;
    }
    return 1;
}
