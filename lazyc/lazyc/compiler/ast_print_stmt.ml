// lazyc/compiler/ast_print_stmt.ml
//
// Statement and program AST printer. Matches the format of
// src/ast_print.c::print_stmt and print_program.

Long ast_print_stmt(Ptr<Stmt> s, Long d) {
    ast_print_indent(d);
    Long k = (*s).kind;

    if (k == ST_VAR_DECL()) {
        print("VarDecl ");
        ast_print_type_short((*s).var_ty);
        println(" %s", cast<String>((*s).var_name));
        if ((*s).var_init != cast<Ptr<Expr>>(null)) {
            ast_print_expr((*s).var_init, d + 1);
        }
        return 0;
    }
    if (k == ST_ASSIGN()) {
        println("Assign %s", cast<String>((*s).var_name));
        ast_print_expr((*s).assign_value, d + 1);
        return 0;
    }
    if (k == ST_PTR_STORE()) {
        println("PtrStore");
        ast_print_expr((*s).store_target, d + 1);
        ast_print_expr((*s).store_value, d + 1);
        return 0;
    }
    if (k == ST_FIELD_STORE()) {
        println("FieldStore");
        ast_print_expr((*s).store_target, d + 1);
        ast_print_expr((*s).store_value, d + 1);
        return 0;
    }
    if (k == ST_INDEX_STORE()) {
        println("IndexStore");
        ast_print_expr((*s).store_target, d + 1);
        ast_print_expr((*s).store_value, d + 1);
        return 0;
    }
    if (k == ST_IF()) {
        println("If");
        ast_print_expr((*s).cond, d + 1);
        ast_print_indent(d);
        println("Then:");
        ast_print_stmt((*s).then_b, d + 1);
        if ((*s).else_b != cast<Ptr<Stmt>>(null)) {
            ast_print_indent(d);
            println("Else:");
            ast_print_stmt((*s).else_b, d + 1);
        }
        return 0;
    }
    if (k == ST_WHILE()) {
        println("While");
        ast_print_expr((*s).cond, d + 1);
        ast_print_stmt((*s).body, d + 1);
        return 0;
    }
    if (k == ST_FOR()) {
        println("For");
        if ((*s).for_init != cast<Ptr<Stmt>>(null)) {
            ast_print_indent(d + 1);
            println("Init:");
            ast_print_stmt((*s).for_init, d + 2);
        }
        if ((*s).cond != cast<Ptr<Expr>>(null)) {
            ast_print_indent(d + 1);
            println("Cond:");
            ast_print_expr((*s).cond, d + 2);
        }
        if ((*s).for_update != cast<Ptr<Stmt>>(null)) {
            ast_print_indent(d + 1);
            println("Update:");
            ast_print_stmt((*s).for_update, d + 2);
        }
        ast_print_stmt((*s).body, d + 1);
        return 0;
    }
    if (k == ST_RETURN()) {
        println("Return");
        if ((*s).ret_value != cast<Ptr<Expr>>(null)) {
            ast_print_expr((*s).ret_value, d + 1);
        }
        return 0;
    }
    if (k == ST_BREAK()) {
        println("Break");
        return 0;
    }
    if (k == ST_CONTINUE()) {
        println("Continue");
        return 0;
    }
    if (k == ST_BLOCK()) {
        println("Block");
        Ptr<PtrVec> stmts = (*s).block_stmts;
        if (stmts != cast<Ptr<PtrVec>>(null)) {
            Long n = (*stmts).count;
            Long i = 0;
            while (i < n) {
                Ptr<Stmt> child = cast<Ptr<Stmt>>(ptrvec_get(stmts, i));
                ast_print_stmt(child, d + 1);
                i = i + 1;
            }
        }
        return 0;
    }
    if (k == ST_EXPR()) {
        println("ExprStmt");
        ast_print_expr((*s).expr, d + 1);
        return 0;
    }
    println("?Stmt kind=%l", k);
    return 0;
}

// Print one function declaration, matching the C compiler's
// "Func RetType name(P1Ty p1, P2Ty p2, ...)" header line. For extern
// declarations the header reads "Extern RetType name(...)" and no body
// follows.
Long ast_print_func(Ptr<FuncDecl> f) {
    if ((*f).is_extern != 0) {
        print("Extern ");
    } else {
        print("Func ");
    }
    ast_print_type_short((*f).return_ty);
    print(" %s(", cast<String>((*f).name));

    Ptr<PtrVec> params = (*f).params;
    if (params != cast<Ptr<PtrVec>>(null)) {
        Long n = (*params).count;
        Long i = 0;
        while (i < n) {
            if (i > 0) { print(", "); }
            Ptr<Param> param = cast<Ptr<Param>>(ptrvec_get(params, i));
            ast_print_type_short((*param).ty);
            print(" %s", cast<String>((*param).name));
            i = i + 1;
        }
    }
    println(")");
    if ((*f).is_extern == 0) {
        ast_print_stmt((*f).body, 1);
    }
    return 0;
}

// Print the whole program: every function in declaration order.
// Structs are NOT printed (matches the C compiler's --ast-raw output).
Long ast_print_program(Ptr<Program> pg) {
    Ptr<PtrVec> funcs = (*pg).funcs;
    Long n = (*funcs).count;
    Long i = 0;
    while (i < n) {
        Ptr<FuncDecl> f = cast<Ptr<FuncDecl>>(ptrvec_get(funcs, i));
        ast_print_func(f);
        i = i + 1;
    }
    return 0;
}
