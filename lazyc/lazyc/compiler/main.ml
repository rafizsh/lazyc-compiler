// lazyc/compiler/main.ml
//
// Entry point for the bootstrap compiler. Reads a source path from argv,
// runs the (stubbed) pipeline, writes output to <source>.asm.
//
// Step 21c: pipeline phases are stubs. Each subsequent substep replaces
// one stub with a real implementation; the wiring here doesn't change.

Long usage() {
    println("usage: lazyc <source.ml>");
    println("");
    println("Reads <source.ml>, compiles it, writes <source.ml.asm>.");
    return 1;
}

Long main() {
    if (argc() < 2) {
        return usage();
    }
    Ptr<Byte> path = argv(1);
    if (path == null) {
        return usage();
    }

    Ptr<Byte> source = readf(cast<String>(path));
    if (source == null) {
        println("error: could not read '%s'", cast<String>(path));
        return 1;
    }
    Long src_len = ml_strlen(source);
    println("read %l bytes from %s", src_len, cast<String>(path));

    // ---- Pipeline ----
    // Step 21d: real lexer.
    Ptr<TokenList> tokens = lex_tokenize(source);
    Long ntokens = tokenlist_count(tokens);
    println("  lex:       %l tokens", ntokens);

    // Step 21f: real parser (functions + statements; structs/arrays in 21g).
    Ptr<Program> ast = parse_program(tokens);
    Long nfuncs = (*(*ast).funcs).count;
    println("  parse:     %l functions", nfuncs);

    // Step 21h: real typechecker. Sets ety on every Expr; rejects bad programs.
    Long check_ok = typecheck_program(ast);
    if (check_ok == 0) {
        println("error: typecheck failed");
        free(source);
        return 1;
    }
    println("  typecheck: ok");

    Buf out;
    buf_init(&out);
    codegen_program(ast, &out);
    println("  codegen:   %l bytes of asm", out.len);

    // Build output path by appending ".asm" to the source path.
    Buf out_path;
    buf_init(&out_path);
    buf_push_str(&out_path, path);
    buf_push_str(&out_path, cast<Ptr<Byte>>(".asm"));

    Boolean ok = writef(cast<String>(out_path.data), out.data);
    if (!ok) {
        println("error: could not write '%s'", cast<String>(out_path.data));
        buf_free(&out);
        buf_free(&out_path);
        free(source);
        return 1;
    }
    println("wrote %s", cast<String>(out_path.data));

    buf_free(&out);
    buf_free(&out_path);
    free(source);
    return 0;
}
