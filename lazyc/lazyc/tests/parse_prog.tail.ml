// lazyc/tests/parse_prog.tail.ml
//
// Parses a whole program from the given source path and prints the AST
// in the same format as `./lazyc --ast-raw <path>` so the two outputs
// can be diffed.

Long main() {
    if (argc() < 2) {
        println("usage: parse_prog <file.ml>");
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
    ast_print_program(pg);
    return 0;
}
