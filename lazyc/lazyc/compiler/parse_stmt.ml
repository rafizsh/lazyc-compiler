// lazyc/compiler/parse_stmt.ml
//
// Statement, function, and (in 21g) struct declaration parser.
// Builds on parse.ml (which has parse_expr, parse_type, struct registry).
// Output: Ptr<Program> with lists of Ptr<FuncDecl> and Ptr<StructDef>.

// ---- Type-decoration helper ----
//
// In a variable or field declaration, after the name we may see `[N]` to
// turn the base type into a fixed-size array. Mirrors the C parser's
// wrap_with_array_suffix.
Ptr<Type> wrap_with_array_suffix(Ptr<Parser> p, Ptr<Type> base) {
    if (!parser_match(p, TOK_LBRACKET())) { return base; }
    if (!parser_check(p, TOK_NUMBER())) {
        parse_error(p, cast<Ptr<Byte>>("expected integer literal in array size"));
    }
    Ptr<Token> size_tok = parser_cur(p);
    Long n = (*size_tok).int_value;
    if (n <= 0) {
        parse_error(p, cast<Ptr<Byte>>("array size must be positive"));
    }
    if (n > 1000000) {
        parse_error(p, cast<Ptr<Byte>>("array size too large"));
    }
    parser_advance(p);
    parser_expect(p, TOK_RBRACKET(), cast<Ptr<Byte>>("expected ']' after array size"));
    return type_array(base, n);
}

// ---- Per-kind statement parsers ----

// Parse a variable declaration: TYPE NAME [= EXPR];
// Caller has verified that the current token starts a type.
Ptr<Stmt> parse_var_decl(Ptr<Parser> p) {
    Ptr<Token> first = parser_cur(p);
    Long line = (*first).line;
    Ptr<Stmt> s = parse_var_decl_no_semi(p);
    parser_expect(p, TOK_SEMI(), cast<Ptr<Byte>>("expected ';' after variable declaration"));
    // line was already set by no_semi version; keep as-is
    return s;
}

// Parse a variable declaration without trailing ';'. Used by `for` init.
Ptr<Stmt> parse_var_decl_no_semi(Ptr<Parser> p) {
    Ptr<Token> first = parser_cur(p);
    Long line = (*first).line;
    Ptr<Type> ty = parse_type(p);
    Ptr<Token> name_tok = parser_expect(p, TOK_IDENT(),
        cast<Ptr<Byte>>("expected variable name"));
    // After the name, accept an optional `[N]` array suffix to turn the
    // base type into a fixed-size array.
    ty = wrap_with_array_suffix(p, ty);
    Ptr<Stmt> s = stmt_new(ST_VAR_DECL(), line);
    (*s).var_ty       = ty;
    (*s).var_name     = (*name_tok).text;
    (*s).var_name_len = (*name_tok).text_len;
    if (parser_match(p, TOK_ASSIGN())) {
        (*s).var_init = parse_expr(p);
    }
    return s;
}

// Parse `name = expr` (used by for-init and for-update). No semicolon
// is consumed here; caller decides.
Ptr<Stmt> parse_assign_no_semi(Ptr<Parser> p) {
    Ptr<Token> name_tok = parser_expect(p, TOK_IDENT(),
        cast<Ptr<Byte>>("expected identifier on left of '='"));
    Long line = (*name_tok).line;
    parser_expect(p, TOK_ASSIGN(), cast<Ptr<Byte>>("expected '='"));
    Ptr<Expr> value = parse_expr(p);
    Ptr<Stmt> s = stmt_new(ST_ASSIGN(), line);
    (*s).var_name     = (*name_tok).text;
    (*s).var_name_len = (*name_tok).text_len;
    (*s).assign_value = value;
    return s;
}

// Parse a brace-delimited block.
Ptr<Stmt> parse_block(Ptr<Parser> p) {
    Ptr<Token> open = parser_expect(p, TOK_LBRACE(),
        cast<Ptr<Byte>>("expected '{' to begin block"));
    Long line = (*open).line;
    Ptr<Stmt> s = stmt_new(ST_BLOCK(), line);
    Ptr<Byte> raw = alloc(24);
    Ptr<PtrVec> stmts = cast<Ptr<PtrVec>>(raw);
    ptrvec_init(stmts);
    while (true) {
        if (parser_check(p, TOK_RBRACE())) { break; }
        if (parser_check(p, TOK_EOF())) {
            parse_error(p, cast<Ptr<Byte>>("unexpected EOF inside block"));
        }
        Ptr<Stmt> child = parse_stmt(p);
        ptrvec_push(stmts, cast<Ptr<Byte>>(child));
    }
    parser_expect(p, TOK_RBRACE(), cast<Ptr<Byte>>("expected '}' to close block"));
    (*s).block_stmts = stmts;
    return s;
}

// Parse a single statement.
Ptr<Stmt> parse_stmt(Ptr<Parser> p) {
    Ptr<Token> first = parser_cur(p);
    Long line = (*first).line;

    // Variable declaration: starts with a type-name token.
    if (is_type_start(p)) { return parse_var_decl(p); }

    // Block.
    if (parser_check(p, TOK_LBRACE())) { return parse_block(p); }

    // if (cond) { ... } [else { ... } | else if ...]
    if (parser_match(p, TOK_IF())) {
        parser_expect(p, TOK_LPAREN(), cast<Ptr<Byte>>("expected '(' after 'if'"));
        Ptr<Expr> if_cond = parse_expr(p);
        parser_expect(p, TOK_RPAREN(), cast<Ptr<Byte>>("expected ')'"));
        Ptr<Stmt> then_blk = parse_block(p);
        Ptr<Stmt> else_blk = cast<Ptr<Stmt>>(null);
        if (parser_match(p, TOK_ELSE())) {
            if (parser_check(p, TOK_IF())) { else_blk = parse_stmt(p); }
            else                            { else_blk = parse_block(p); }
        }
        Ptr<Stmt> s_if = stmt_new(ST_IF(), line);
        (*s_if).cond   = if_cond;
        (*s_if).then_b = then_blk;
        (*s_if).else_b = else_blk;
        return s_if;
    }

    // while (cond) { ... }
    if (parser_match(p, TOK_WHILE())) {
        parser_expect(p, TOK_LPAREN(), cast<Ptr<Byte>>("expected '(' after 'while'"));
        Ptr<Expr> while_cond = parse_expr(p);
        parser_expect(p, TOK_RPAREN(), cast<Ptr<Byte>>("expected ')'"));
        Ptr<Stmt> while_body = parse_block(p);
        Ptr<Stmt> s_while = stmt_new(ST_WHILE(), line);
        (*s_while).cond = while_cond;
        (*s_while).body = while_body;
        return s_while;
    }

    // for (init; cond; update) { ... }
    if (parser_match(p, TOK_FOR())) {
        parser_expect(p, TOK_LPAREN(), cast<Ptr<Byte>>("expected '('"));
        Ptr<Stmt> for_init_s = cast<Ptr<Stmt>>(null);
        if (!parser_check(p, TOK_SEMI())) {
            if (is_type_start(p)) { for_init_s = parse_var_decl_no_semi(p); }
            else                  { for_init_s = parse_assign_no_semi(p); }
        }
        parser_expect(p, TOK_SEMI(), cast<Ptr<Byte>>("expected ';' in for"));
        Ptr<Expr> for_cond = cast<Ptr<Expr>>(null);
        if (!parser_check(p, TOK_SEMI())) { for_cond = parse_expr(p); }
        parser_expect(p, TOK_SEMI(), cast<Ptr<Byte>>("expected ';' in for"));
        Ptr<Stmt> for_update_s = cast<Ptr<Stmt>>(null);
        if (!parser_check(p, TOK_RPAREN())) { for_update_s = parse_assign_no_semi(p); }
        parser_expect(p, TOK_RPAREN(), cast<Ptr<Byte>>("expected ')'"));
        Ptr<Stmt> for_body = parse_block(p);
        Ptr<Stmt> s_for = stmt_new(ST_FOR(), line);
        (*s_for).for_init   = for_init_s;
        (*s_for).cond       = for_cond;
        (*s_for).for_update = for_update_s;
        (*s_for).body       = for_body;
        return s_for;
    }

    // return [expr];
    if (parser_match(p, TOK_RETURN())) {
        Ptr<Expr> v = cast<Ptr<Expr>>(null);
        if (!parser_check(p, TOK_SEMI())) { v = parse_expr(p); }
        parser_expect(p, TOK_SEMI(), cast<Ptr<Byte>>("expected ';' after return"));
        Ptr<Stmt> s_ret = stmt_new(ST_RETURN(), line);
        (*s_ret).ret_value = v;
        return s_ret;
    }

    // break;
    if (parser_match(p, TOK_BREAK())) {
        parser_expect(p, TOK_SEMI(), cast<Ptr<Byte>>("expected ';' after 'break'"));
        return stmt_new(ST_BREAK(), line);
    }

    // continue;
    if (parser_match(p, TOK_CONTINUE())) {
        parser_expect(p, TOK_SEMI(), cast<Ptr<Byte>>("expected ';' after 'continue'"));
        return stmt_new(ST_CONTINUE(), line);
    }

    // Lookahead: if `IDENT =` we have an assign.
    if (parser_check(p, TOK_IDENT())) {
        Ptr<Token> nxt = parser_peek_next(p);
        if ((*nxt).kind == TOK_ASSIGN()) {
            Ptr<Stmt> s_asn = parse_assign_no_semi(p);
            parser_expect(p, TOK_SEMI(), cast<Ptr<Byte>>("expected ';'"));
            return s_asn;
        }
    }

    // Otherwise, parse an expression and decide between:
    //   *p = e;       -- pointer store
    //   s.f = e;      -- field store
    //   arr[i] = e;   -- index store
    //   foo();        -- expression statement
    Ptr<Expr> e = parse_expr(p);
    if (parser_check(p, TOK_ASSIGN())) {
        parser_advance(p);
        Ptr<Expr> value = parse_expr(p);
        parser_expect(p, TOK_SEMI(), cast<Ptr<Byte>>("expected ';'"));
        Long ek = (*e).kind;
        Long sk = -1;
        if (ek == EX_DEREF()) { sk = ST_PTR_STORE(); }
        if (ek == EX_FIELD()) { sk = ST_FIELD_STORE(); }
        if (ek == EX_INDEX()) { sk = ST_INDEX_STORE(); }
        if (sk < 0) {
            parse_error(p, cast<Ptr<Byte>>("left side of '=' must be a variable, '*pointer', 'struct.field', or 'arr[index]'"));
        }
        Ptr<Stmt> s_store = stmt_new(sk, line);
        (*s_store).store_target = e;
        (*s_store).store_value  = value;
        return s_store;
    }
    parser_expect(p, TOK_SEMI(), cast<Ptr<Byte>>("expected ';'"));
    Ptr<Stmt> s_expr = stmt_new(ST_EXPR(), line);
    (*s_expr).expr = e;
    return s_expr;
}

// ---- Function declarations ----

// Parse one function: `RetType name(Type p1, Type p2, ...) { body }`.
Ptr<FuncDecl> parse_func(Ptr<Parser> p) {
    Ptr<Token> first = parser_cur(p);
    Long line = (*first).line;
    Long is_ext = 0;
    if (parser_check(p, TOK_EXTERN())) {
        is_ext = 1;
        parser_advance(p);
    }
    Ptr<Type> ret = parse_type(p);
    Ptr<Token> name_tok = parser_expect(p, TOK_IDENT(),
        cast<Ptr<Byte>>("expected function name"));
    parser_expect(p, TOK_LPAREN(), cast<Ptr<Byte>>("expected '('"));

    Ptr<Byte> raw_pv = alloc(24);
    Ptr<PtrVec> params = cast<Ptr<PtrVec>>(raw_pv);
    ptrvec_init(params);

    if (!parser_check(p, TOK_RPAREN())) {
        while (true) {
            Ptr<Type> pty = parse_type(p);
            Ptr<Token> pname = parser_expect(p, TOK_IDENT(),
                cast<Ptr<Byte>>("expected parameter name"));
            Ptr<Param> param = param_new(pty, (*pname).text, (*pname).text_len);
            ptrvec_push(params, cast<Ptr<Byte>>(param));
            if (!parser_match(p, TOK_COMMA())) { break; }
        }
    }
    parser_expect(p, TOK_RPAREN(), cast<Ptr<Byte>>("expected ')'"));

    Ptr<Stmt> body = cast<Ptr<Stmt>>(null);
    if (is_ext != 0) {
        parser_expect(p, TOK_SEMI(),
            cast<Ptr<Byte>>("expected ';' after extern declaration"));
    } else {
        body = parse_block(p);
    }

    Ptr<FuncDecl> f = funcdecl_new(line);
    (*f).return_ty = ret;
    (*f).name      = (*name_tok).text;
    (*f).name_len  = (*name_tok).text_len;
    (*f).params    = params;
    (*f).body      = body;
    (*f).is_extern = is_ext;
    return f;
}

// ---- Top-level program parser ----

// Parse a whole program: zero or more struct or function declarations,
// in any order, followed by EOF.
Ptr<Program> parse_program(Ptr<TokenList> tl) {
    Ptr<Program> pg = program_new();
    Parser p;
    parser_init(&p, tl);
    while (true) {
        if (parser_check(&p, TOK_EOF())) { break; }
        if (parser_check(&p, TOK_STRUCT())) {
            Ptr<StructDef> sd = parse_struct_decl(&p);
            ptrvec_push((*pg).structs, cast<Ptr<Byte>>(sd));
        } else {
            Ptr<FuncDecl> f = parse_func(&p);
            ptrvec_push((*pg).funcs, cast<Ptr<Byte>>(f));
        }
    }
    return pg;
}
