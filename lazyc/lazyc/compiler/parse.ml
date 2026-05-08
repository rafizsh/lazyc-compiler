// lazyc/compiler/parse.ml
//
// Parser. Step 21e: expressions only. Statements/functions come in 21f,
// structs/arrays in 21g.
//
// Mirrors src/parser.c. Same token-stream design (one-token lookahead),
// same recursive-descent precedence ladder, same AST output. Once the
// statement and function parsers are done, AST dumps will be byte-equal.

// Parser state. We pre-tokenized the entire source, so the parser is
// just a cursor into the token list, plus a struct registry that grows
// as we encounter `struct ...` decls (so that subsequent `parse_type`
// calls can recognize struct names as types).
struct Parser {
    Ptr<TokenList> tokens;
    Long           pos;          // index into tokens; points at "current"
    Ptr<PtrVec>    structs;      // PtrVec of Ptr<StructDef> (cast to Ptr<Byte>)
}

// Initialize a parser to start at the first token, with an empty struct
// registry.
Long parser_init(Ptr<Parser> p, Ptr<TokenList> tl) {
    (*p).tokens = tl;
    (*p).pos = 0;
    Ptr<Byte> raw = alloc(24);    // sizeof(PtrVec) = 24
    Ptr<PtrVec> reg = cast<Ptr<PtrVec>>(raw);
    ptrvec_init(reg);
    (*p).structs = reg;
    return 0;
}

// Look up a struct by its name (provided as a non-null-terminated slice).
// Returns null if not found.
Ptr<StructDef> parser_find_struct(Ptr<Parser> p, Ptr<Byte> name, Long name_len) {
    Ptr<PtrVec> reg = (*p).structs;
    Long n = (*reg).count;
    Long i = 0;
    while (i < n) {
        Ptr<StructDef> sd = cast<Ptr<StructDef>>(ptrvec_get(reg, i));
        if (lex_slice_eq(name, name_len, (*sd).name)) {
            return sd;
        }
        i = i + 1;
    }
    return cast<Ptr<StructDef>>(null);
}

// Append a struct to the registry. Must be done BEFORE parsing the body
// so Ptr<Self> works inside fields.
Long parser_add_struct(Ptr<Parser> p, Ptr<StructDef> sd) {
    ptrvec_push((*p).structs, cast<Ptr<Byte>>(sd));
    return 0;
}

// Get the current token (the one at `pos`).
Ptr<Token> parser_cur(Ptr<Parser> p) {
    return tokenlist_at((*p).tokens, (*p).pos);
}

// Get the next token (lookahead 1). Returns the EOF token if at end.
Ptr<Token> parser_peek_next(Ptr<Parser> p) {
    Long n = tokenlist_count((*p).tokens);
    Long i = (*p).pos + 1;
    if (i >= n) { i = n - 1; }    // EOF token is always the last one
    return tokenlist_at((*p).tokens, i);
}

// True if the current token's kind matches `k`.
Boolean parser_check(Ptr<Parser> p, Long k) {
    Ptr<Token> t = parser_cur(p);
    return (*t).kind == k;
}

// If current token is `k`, consume it and return true. Otherwise return
// false and leave the cursor unchanged.
Boolean parser_match(Ptr<Parser> p, Long k) {
    if (!parser_check(p, k)) { return false; }
    (*p).pos = (*p).pos + 1;
    return true;
}

// Advance unconditionally and return the consumed token.
Ptr<Token> parser_advance(Ptr<Parser> p) {
    Ptr<Token> t = parser_cur(p);
    (*p).pos = (*p).pos + 1;
    return t;
}

// Expect a token of kind `k`; if not present, error with `msg`.
// Returns the consumed token.
Ptr<Token> parser_expect(Ptr<Parser> p, Long k, Ptr<Byte> msg) {
    if (!parser_check(p, k)) {
        Ptr<Token> got = parser_cur(p);
        println("parse error at line %l: %s (got '%s')",
                (*got).line, cast<String>(msg),
                cast<String>(token_kind_name((*got).kind)));
        exit(1);
    }
    return parser_advance(p);
}

// Parse error at the current token.
Long parse_error(Ptr<Parser> p, Ptr<Byte> msg) {
    Ptr<Token> t = parser_cur(p);
    println("parse error at line %l: %s (got '%s')",
            (*t).line, cast<String>(msg),
            cast<String>(token_kind_name((*t).kind)));
    exit(1);
    return 0;
}

// ---- Type parser ----
// Parses a type expression. For 21e, supports simple types and Ptr<T>.
// Struct types and arrays-as-types (in casts) come later. Cast<...>
// always uses non-struct, non-array types.

// True if the current token is the start of a type. Used by parse_unary
// for `cast<T>(x)` recognition and by parse_stmt for var-decl detection.
// Accepts type keywords AND identifiers that name a known struct.
Boolean is_type_start(Ptr<Parser> p) {
    if (parser_check(p, TOK_BOOLEAN()))  { return true; }
    if (parser_check(p, TOK_CHAR()))     { return true; }
    if (parser_check(p, TOK_BYTE()))     { return true; }
    if (parser_check(p, TOK_INTEGER()))  { return true; }
    if (parser_check(p, TOK_UINTEGER())) { return true; }
    if (parser_check(p, TOK_WHOLE()))    { return true; }
    if (parser_check(p, TOK_UWHOLE()))   { return true; }
    if (parser_check(p, TOK_LONG()))     { return true; }
    if (parser_check(p, TOK_ULONG()))    { return true; }
    if (parser_check(p, TOK_STRING()))   { return true; }
    if (parser_check(p, TOK_PTR()))      { return true; }
    if (parser_check(p, TOK_IDENT())) {
        Ptr<Token> t = parser_cur(p);
        Ptr<StructDef> sd = parser_find_struct(p, (*t).text, (*t).text_len);
        if (sd != cast<Ptr<StructDef>>(null)) { return true; }
    }
    return false;
}

// Map a type-keyword token kind to the corresponding TY_* constant.
Long type_kind_for_token(Long tk) {
    if (tk == TOK_BOOLEAN())  { return TY_BOOLEAN(); }
    if (tk == TOK_CHAR())     { return TY_CHAR(); }
    if (tk == TOK_BYTE())     { return TY_BYTE(); }
    if (tk == TOK_INTEGER())  { return TY_INTEGER(); }
    if (tk == TOK_UINTEGER()) { return TY_UINTEGER(); }
    if (tk == TOK_WHOLE())    { return TY_WHOLE(); }
    if (tk == TOK_UWHOLE())   { return TY_UWHOLE(); }
    if (tk == TOK_LONG())     { return TY_LONG(); }
    if (tk == TOK_ULONG())    { return TY_ULONG(); }
    if (tk == TOK_STRING())   { return TY_STRING(); }
    return TY_UNKNOWN();
}

// Parse a single type. Recursive: Ptr<T> nests. Accepts simple type
// keywords, Ptr<...>, and identifiers that name a registered struct.
Ptr<Type> parse_type(Ptr<Parser> p) {
    if (parser_check(p, TOK_PTR())) {
        parser_advance(p);
        parser_expect(p, TOK_LT(), cast<Ptr<Byte>>("expected '<' after Ptr"));
        Ptr<Type> inner = parse_type(p);
        parser_expect(p, TOK_GT(), cast<Ptr<Byte>>("expected '>' after pointee type"));
        return type_ptr(inner);
    }
    // Simple type keyword.
    if (parser_check(p, TOK_BOOLEAN())) { parser_advance(p); return type_simple(TY_BOOLEAN()); }
    if (parser_check(p, TOK_CHAR()))    { parser_advance(p); return type_simple(TY_CHAR()); }
    if (parser_check(p, TOK_BYTE()))    { parser_advance(p); return type_simple(TY_BYTE()); }
    if (parser_check(p, TOK_INTEGER())) { parser_advance(p); return type_simple(TY_INTEGER()); }
    if (parser_check(p, TOK_UINTEGER())){ parser_advance(p); return type_simple(TY_UINTEGER()); }
    if (parser_check(p, TOK_WHOLE()))   { parser_advance(p); return type_simple(TY_WHOLE()); }
    if (parser_check(p, TOK_UWHOLE()))  { parser_advance(p); return type_simple(TY_UWHOLE()); }
    if (parser_check(p, TOK_LONG()))    { parser_advance(p); return type_simple(TY_LONG()); }
    if (parser_check(p, TOK_ULONG()))   { parser_advance(p); return type_simple(TY_ULONG()); }
    if (parser_check(p, TOK_STRING()))  { parser_advance(p); return type_simple(TY_STRING()); }
    // Struct name (must be in the registry).
    if (parser_check(p, TOK_IDENT())) {
        Ptr<Token> t = parser_cur(p);
        Ptr<StructDef> sd = parser_find_struct(p, (*t).text, (*t).text_len);
        if (sd == cast<Ptr<StructDef>>(null)) {
            parse_error(p, cast<Ptr<Byte>>("unknown type name"));
        }
        parser_advance(p);
        return type_struct(cast<Ptr<Byte>>(sd));
    }
    parse_error(p, cast<Ptr<Byte>>("expected type name"));
    return cast<Ptr<Type>>(null);   // unreachable
}

// ---- Forward declarations needed inside expression parser ----
//
// lazyc resolves function names across the whole program, so forward
// references work without explicit declarations. Just listing here for
// human readers:
//   parse_expr        — entry point
//   parse_comparison  — handles  ==, !=, <, >, <=, >=
//   parse_additive    — handles  +, -
//   parse_term        — handles  *, /, %
//   parse_unary       — handles  -, !, &, *
//   parse_primary     — handles atoms + postfix chain ([i], .f)
//   parse_primary_inner — atoms only

// ---- Expression parser: precedence ladder ----

// Top-level: expression is a comparison. Higher-precedence ops cascade.
Ptr<Expr> parse_expr(Ptr<Parser> p) {
    return parse_comparison(p);
}

// Map a comparison token to its OP_* code; -1 means "not a comparison".
Long token_to_cmp_op(Long tk) {
    if (tk == TOK_EQ())  { return OP_EQ(); }
    if (tk == TOK_NEQ()) { return OP_NEQ(); }
    if (tk == TOK_LT())  { return OP_LT(); }
    if (tk == TOK_GT())  { return OP_GT(); }
    if (tk == TOK_LE())  { return OP_LE(); }
    if (tk == TOK_GE())  { return OP_GE(); }
    return -1;
}

Ptr<Expr> parse_comparison(Ptr<Parser> p) {
    Ptr<Expr> left = parse_additive(p);
    while (true) {
        Ptr<Token> t = parser_cur(p);
        Long op = token_to_cmp_op((*t).kind);
        if (op < 0) { break; }
        Long line = (*t).line;
        parser_advance(p);
        Ptr<Expr> right = parse_additive(p);
        Ptr<Expr> e = expr_new(EX_BINARY(), line);
        (*e).op = op;
        (*e).child0 = left;
        (*e).child1 = right;
        left = e;
    }
    return left;
}

Ptr<Expr> parse_additive(Ptr<Parser> p) {
    Ptr<Expr> left = parse_term(p);
    while (true) {
        Ptr<Token> t = parser_cur(p);
        Long tk = (*t).kind;
        Long op = -1;
        if (tk == TOK_PLUS())  { op = OP_ADD(); }
        if (tk == TOK_MINUS()) { op = OP_SUB(); }
        if (op < 0) { break; }
        Long line = (*t).line;
        parser_advance(p);
        Ptr<Expr> right = parse_term(p);
        Ptr<Expr> e = expr_new(EX_BINARY(), line);
        (*e).op = op;
        (*e).child0 = left;
        (*e).child1 = right;
        left = e;
    }
    return left;
}

Ptr<Expr> parse_term(Ptr<Parser> p) {
    Ptr<Expr> left = parse_unary(p);
    while (true) {
        Ptr<Token> t = parser_cur(p);
        Long tk = (*t).kind;
        Long op = -1;
        if (tk == TOK_STAR())    { op = OP_MUL(); }
        if (tk == TOK_SLASH())   { op = OP_DIV(); }
        if (tk == TOK_PERCENT()) { op = OP_MOD(); }
        if (op < 0) { break; }
        Long line = (*t).line;
        parser_advance(p);
        Ptr<Expr> right = parse_unary(p);
        Ptr<Expr> e = expr_new(EX_BINARY(), line);
        (*e).op = op;
        (*e).child0 = left;
        (*e).child1 = right;
        left = e;
    }
    return left;
}

// Unary: -x, !x, &x, *p. Right-associative (we recurse on the operand).
Ptr<Expr> parse_unary(Ptr<Parser> p) {
    Ptr<Token> t = parser_cur(p);
    Long tk = (*t).kind;
    Long line = (*t).line;
    if (tk == TOK_MINUS()) {
        parser_advance(p);
        Ptr<Expr> neg_op = parse_unary(p);
        Ptr<Expr> e_neg = expr_new(EX_UNARY(), line);
        (*e_neg).op = OP_NEG();
        (*e_neg).child0 = neg_op;
        return e_neg;
    }
    if (tk == TOK_BANG()) {
        parser_advance(p);
        Ptr<Expr> not_op = parse_unary(p);
        Ptr<Expr> e_not = expr_new(EX_UNARY(), line);
        (*e_not).op = OP_NOT();
        (*e_not).child0 = not_op;
        return e_not;
    }
    if (tk == TOK_AMP()) {
        parser_advance(p);
        Ptr<Expr> addr_op = parse_unary(p);
        Ptr<Expr> e_addr = expr_new(EX_ADDR_OF(), line);
        (*e_addr).child0 = addr_op;
        return e_addr;
    }
    if (tk == TOK_STAR()) {
        parser_advance(p);
        Ptr<Expr> deref_op = parse_unary(p);
        Ptr<Expr> e_deref = expr_new(EX_DEREF(), line);
        (*e_deref).child0 = deref_op;
        return e_deref;
    }
    return parse_primary(p);
}

// Primary atoms — literals, identifiers, calls, parens, cast<T>(x).
Ptr<Expr> parse_primary_inner(Ptr<Parser> p) {
    Ptr<Token> t = parser_cur(p);
    Long tk = (*t).kind;
    Long line = (*t).line;
    Ptr<Expr> e = cast<Ptr<Expr>>(null);

    if (tk == TOK_NUMBER()) {
        parser_advance(p);
        e = expr_new(EX_NUMBER(), line);
        (*e).num = (*t).int_value;
        (*e).is_untyped_int = 1;
        return e;
    }
    if (tk == TOK_CHAR_LIT()) {
        parser_advance(p);
        e = expr_new(EX_CHAR_LIT(), line);
        (*e).char_val = (*t).char_value;
        return e;
    }
    if (tk == TOK_STRING_LIT()) {
        parser_advance(p);
        e = expr_new(EX_STRING_LIT(), line);
        // The token's text is already the raw inner content (no quotes,
        // no escape resolution). Share the buffer — Token owns it but
        // the Token outlives the Expr in our pre-tokenized model.
        (*e).str_data = (*t).text;
        (*e).str_len  = (*t).text_len;
        return e;
    }
    if (tk == TOK_TRUE()) {
        parser_advance(p);
        e = expr_new(EX_BOOL_LIT(), line);
        (*e).bool_val = 1;
        return e;
    }
    if (tk == TOK_FALSE()) {
        parser_advance(p);
        e = expr_new(EX_BOOL_LIT(), line);
        (*e).bool_val = 0;
        return e;
    }
    if (tk == TOK_NULL()) {
        parser_advance(p);
        e = expr_new(EX_NULL(), line);
        (*e).is_untyped_null = 1;
        return e;
    }

    if (tk == TOK_LPAREN()) {
        parser_advance(p);
        Ptr<Expr> inner = parse_expr(p);
        parser_expect(p, TOK_RPAREN(), cast<Ptr<Byte>>("expected ')'"));
        return inner;
    }

    if (tk == TOK_CAST()) {
        parser_advance(p);
        parser_expect(p, TOK_LT(), cast<Ptr<Byte>>("expected '<' after cast"));
        Ptr<Type> target = parse_type(p);
        parser_expect(p, TOK_GT(), cast<Ptr<Byte>>("expected '>' after cast type"));
        parser_expect(p, TOK_LPAREN(), cast<Ptr<Byte>>("expected '(' after cast<T>"));
        Ptr<Expr> cast_op = parse_expr(p);
        parser_expect(p, TOK_RPAREN(), cast<Ptr<Byte>>("expected ')' after cast operand"));
        e = expr_new(EX_CAST(), line);
        (*e).cast_target = target;
        (*e).child0 = cast_op;
        return e;
    }

    if (tk == TOK_IDENT()) {
        // Either a bare identifier or a function call f(args).
        parser_advance(p);
        if (parser_check(p, TOK_LPAREN())) {
            // Function call.
            parser_advance(p);
            PtrVec args;
            ptrvec_init(&args);
            if (!parser_check(p, TOK_RPAREN())) {
                while (true) {
                    Ptr<Expr> a = parse_expr(p);
                    ptrvec_push(&args, cast<Ptr<Byte>>(a));
                    if (!parser_match(p, TOK_COMMA())) { break; }
                }
            }
            parser_expect(p, TOK_RPAREN(), cast<Ptr<Byte>>("expected ')' to close call"));
            e = expr_new(EX_CALL(), line);
            (*e).name     = (*t).text;
            (*e).name_len = (*t).text_len;
            // Move the PtrVec onto the heap so it survives this stack frame.
            Ptr<Byte> raw = alloc(24);
            Ptr<PtrVec> pv = cast<Ptr<PtrVec>>(raw);
            (*pv).items = args.items;
            (*pv).count = args.count;
            (*pv).cap   = args.cap;
            (*e).call_args = pv;
            return e;
        }
        // Bare identifier.
        e = expr_new(EX_IDENT(), line);
        (*e).name     = (*t).text;
        (*e).name_len = (*t).text_len;
        return e;
    }

    parse_error(p, cast<Ptr<Byte>>("expected expression"));
    return cast<Ptr<Expr>>(null);   // unreachable
}

// Primary + postfix chain: [i], .f, can repeat.
Ptr<Expr> parse_primary(Ptr<Parser> p) {
    Ptr<Expr> base = parse_primary_inner(p);
    while (true) {
        Ptr<Token> t = parser_cur(p);
        Long tk = (*t).kind;
        Long line = (*t).line;
        if (tk == TOK_LBRACKET()) {
            parser_advance(p);
            Ptr<Expr> idx = parse_expr(p);
            parser_expect(p, TOK_RBRACKET(), cast<Ptr<Byte>>("expected ']'"));
            Ptr<Expr> e_idx = expr_new(EX_INDEX(), line);
            (*e_idx).child0 = base;
            (*e_idx).child1 = idx;
            base = e_idx;
            continue;
        }
        if (tk == TOK_DOT()) {
            parser_advance(p);
            Ptr<Token> name_tok = parser_expect(p, TOK_IDENT(),
                cast<Ptr<Byte>>("expected field name after '.'"));
            Ptr<Expr> e_fld = expr_new(EX_FIELD(), line);
            (*e_fld).child0   = base;
            (*e_fld).name     = (*name_tok).text;
            (*e_fld).name_len = (*name_tok).text_len;
            base = e_fld;
            continue;
        }
        break;
    }
    return base;
}
