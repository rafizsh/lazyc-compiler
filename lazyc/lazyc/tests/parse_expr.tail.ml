// lazyc/tests/parse_expr.tail.ml
//
// Parses a file containing a single expression and prints the AST.
// Used for cross-checking the lazyc parser's expression output against
// the C parser's. The C compiler can't directly accept a bare expression,
// so we use a wrapper-stripping protocol: the input is a function body
// `Long _expr() { return E; }` and the test reads E by tokenizing the
// whole thing and parsing the expression after `return`.
//
// A simpler approach: this driver tokenizes the entire input, finds the
// expression starting after `return`, and parses just that. It makes the
// cross-check independent of any statement-parsing logic.

Long main() {
    if (argc() < 2) {
        println("usage: parse_expr <file.ml>");
        return 1;
    }
    Ptr<Byte> path = argv(1);
    Ptr<Byte> source = readf(cast<String>(path));
    if (source == null) {
        println("error: could not read '%s'", cast<String>(path));
        return 1;
    }
    Ptr<TokenList> tl = lex_tokenize(source);

    // Find the first `return` token; the expression starts right after.
    Long n = tokenlist_count(tl);
    Long i = 0;
    Long start = -1;
    while (i < n) {
        Ptr<Token> t = tokenlist_at(tl, i);
        if ((*t).kind == TOK_RETURN()) { start = i + 1; break; }
        i = i + 1;
    }
    if (start < 0) {
        println("error: no 'return' keyword found in input");
        return 1;
    }

    Parser p;
    p.tokens = tl;
    p.pos = start;

    Ptr<Expr> e = parse_expr(&p);

    // After the expression, we expect a ';' (since we wrapped in `return E;`).
    // Anything else means parse_expr stopped early — i.e., the source had
    // structure that parse_expr doesn't recognize. Match the C compiler's
    // rejection by erroring out.
    Ptr<Token> after = parser_cur(&p);
    if ((*after).kind != TOK_SEMI()) {
        println("parse error at line %l: expected ';' after expression (got '%s')",
                (*after).line, cast<String>(token_kind_name((*after).kind)));
        return 1;
    }

    ast_print_expr(e, 0);
    return 0;
}
