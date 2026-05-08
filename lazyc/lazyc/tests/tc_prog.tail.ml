// lazyc/tests/tc_prog.tail.ml
//
// Parse + typecheck a program, then dump the AST. Output should match
// the C compiler's `--ast` (post-typecheck) output byte-for-byte for
// accepted programs.

Long main() {
    if (argc() < 2) {
        println("usage: tc_prog <file.ml>");
        return 1;
    }
    Ptr<Byte> path = argv(1);
    Ptr<Byte> source = readf(cast<String>(path));
    if (source == null) {
        println("error: could not read '%s'", cast<String>(path));
        return 1;
    }
    Ptr<TokenList> tl = lex_tokenize(source);
    Ptr<Program> pg = parse_program(tl);
    typecheck_program(pg);
    ast_print_program(pg);
    return 0;
}
