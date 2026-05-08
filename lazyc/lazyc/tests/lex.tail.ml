// lazyc/tests/lex.tail.ml
//
// Compare the lazyc lexer's output to a known-good reference.
// Reads a source file from argv(1), prints one line per token.

Long print_token(Ptr<Token> t) {
    Ptr<Byte> text = (*t).text;
    if (text == null) { text = cast<Ptr<Byte>>(""); }
    println("L%l %s [%s] num=%l ch=%l",
            (*t).line,
            cast<String>(token_kind_name((*t).kind)),
            cast<String>(text),
            (*t).int_value,
            (*t).char_value);
    return 0;
}

Long main() {
    if (argc() < 2) {
        println("usage: lextest <source.ml>");
        return 1;
    }
    Ptr<Byte> path = argv(1);
    Ptr<Byte> source = readf(cast<String>(path));
    if (source == null) {
        println("error: could not read '%s'", cast<String>(path));
        return 1;
    }

    Ptr<TokenList> tl = lex_tokenize(source);
    Long n = tokenlist_count(tl);
    Long i = 0;
    while (i < n) {
        Ptr<Token> t = tokenlist_at(tl, i);
        print_token(t);
        i = i + 1;
    }
    return 0;
}
