// lazyc/compiler/ast_print.ml
//
// Print AST nodes in the same text format as src/ast_print.c, so that
// AST dumps can be diffed across compilers for cross-validation.
//
// Step 21e: expression printing only. Statements come in 21f.

// Print n levels of indentation (2 spaces each).
Long ast_print_indent(Long d) {
    Long i = 0;
    while (i < d) {
        print("  ");
        i = i + 1;
    }
    return 0;
}

// Print a Ptr<Type> as the type name. Mirrors src/ast_print.c::type_name
// — note this prints the SHORT form ("Ptr" not "Ptr<...>") to match.
Long ast_print_type_short(Ptr<Type> t) {
    if (t == cast<Ptr<Type>>(null)) {
        print("?");
        return 0;
    }
    Long k = (*t).kind;
    if (k == TY_BOOLEAN())  { print("Boolean");  return 0; }
    if (k == TY_CHAR())     { print("Char");     return 0; }
    if (k == TY_BYTE())     { print("Byte");     return 0; }
    if (k == TY_INTEGER())  { print("Integer");  return 0; }
    if (k == TY_UINTEGER()) { print("uInteger"); return 0; }
    if (k == TY_WHOLE())    { print("Whole");    return 0; }
    if (k == TY_UWHOLE())   { print("uWhole");   return 0; }
    if (k == TY_LONG())     { print("Long");     return 0; }
    if (k == TY_ULONG())    { print("uLong");    return 0; }
    if (k == TY_STRING())   { print("String");   return 0; }
    if (k == TY_PTR())      { print("Ptr");      return 0; }
    if (k == TY_STRUCT())   { print("struct");   return 0; }
    if (k == TY_VOID())     { print("void");     return 0; }
    print("?");
    return 0;
}

// If e->ety is set (typechecker has run), print " :TypeName". Otherwise
// nothing. Mirrors C ast_print.c::ty_suffix exactly.
Long ast_ty_suffix(Ptr<Expr> e) {
    Ptr<Type> t = (*e).ety;
    if (t == cast<Ptr<Type>>(null)) { return 0; }
    if ((*t).kind == TY_UNKNOWN()) { return 0; }
    print(" :");
    ast_print_type_short(t);
    return 0;
}

// Print one expression node and its children, recursively, indented.
Long ast_print_expr(Ptr<Expr> e, Long d) {
    ast_print_indent(d);
    Long k = (*e).kind;

    if (k == EX_NUMBER()) {
        print("Number ");
        // We need to print a Long without %l format... use println? Actually
        // we have buf_push_long for buffers, but here we're streaming to
        // stdout. Use println but suppress its newline by streaming pieces.
        // Easiest: build into a Buf, then write_bytes. But we don't have
        // raw write_bytes exposed. Use println to emit the number alone.
        // The C compiler prints "Number %lld" then ty_suffix then '\n'.
        // We approximate with println("%l", ...) which adds a newline, so
        // we need a no-newline version. lazyc has only print/println; the
        // print function does NOT add a newline. Use it.
        print("%l", (*e).num);
        ast_ty_suffix(e);
        println("");
        return 0;
    }
    if (k == EX_CHAR_LIT()) {
        print("Char '%c'", cast<Char>((*e).char_val));
        ast_ty_suffix(e);
        println("");
        return 0;
    }
    if (k == EX_STRING_LIT()) {
        // C uses printf("%.*s") to print the slice without the
        // surrounding quotes added by lazyc. For us, str_data is the
        // raw inner content already.
        print("String \"%s\"", cast<String>((*e).str_data));
        ast_ty_suffix(e);
        println("");
        return 0;
    }
    if (k == EX_BOOL_LIT()) {
        if ((*e).bool_val == 1) { print("Bool true"); }
        else                    { print("Bool false"); }
        ast_ty_suffix(e);
        println("");
        return 0;
    }
    if (k == EX_NULL()) {
        print("Null");
        ast_ty_suffix(e);
        println("");
        return 0;
    }
    if (k == EX_IDENT()) {
        print("Ident %s", cast<String>((*e).name));
        ast_ty_suffix(e);
        println("");
        return 0;
    }
    if (k == EX_BINARY()) {
        print("Binary %s", cast<String>(op_name((*e).op)));
        ast_ty_suffix(e);
        println("");
        ast_print_expr((*e).child0, d + 1);
        ast_print_expr((*e).child1, d + 1);
        return 0;
    }
    if (k == EX_UNARY()) {
        print("Unary %s", cast<String>(op_name((*e).op)));
        ast_ty_suffix(e);
        println("");
        ast_print_expr((*e).child0, d + 1);
        return 0;
    }
    if (k == EX_CALL()) {
        print("Call %s", cast<String>((*e).name));
        ast_ty_suffix(e);
        println("");
        Ptr<PtrVec> args = (*e).call_args;
        if (args != cast<Ptr<PtrVec>>(null)) {
            Long n = (*args).count;
            Long i = 0;
            while (i < n) {
                Ptr<Expr> a = cast<Ptr<Expr>>(ptrvec_get(args, i));
                ast_print_expr(a, d + 1);
                i = i + 1;
            }
        }
        return 0;
    }
    if (k == EX_CAST()) {
        print("Cast<");
        ast_print_type_short((*e).cast_target);
        print(">");
        ast_ty_suffix(e);
        println("");
        ast_print_expr((*e).child0, d + 1);
        return 0;
    }
    if (k == EX_ADDR_OF()) {
        print("AddrOf");
        ast_ty_suffix(e);
        println("");
        ast_print_expr((*e).child0, d + 1);
        return 0;
    }
    if (k == EX_DEREF()) {
        print("Deref");
        ast_ty_suffix(e);
        println("");
        ast_print_expr((*e).child0, d + 1);
        return 0;
    }
    if (k == EX_FIELD()) {
        print("Field .%s", cast<String>((*e).name));
        ast_ty_suffix(e);
        println("");
        ast_print_expr((*e).child0, d + 1);
        return 0;
    }
    if (k == EX_INDEX()) {
        print("Index");
        ast_ty_suffix(e);
        println("");
        ast_print_expr((*e).child0, d + 1);
        ast_print_expr((*e).child1, d + 1);
        return 0;
    }
    println("?Expr kind=%l", k);
    return 0;
}
