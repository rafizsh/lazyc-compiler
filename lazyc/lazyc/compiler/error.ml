// lazyc/compiler/error.ml
//
// Error reporting. Each phase reports errors in a consistent format
// "<phase> error at line N: <message>" and exits. We don't have varargs
// so we provide a few common shapes.

Long die(Ptr<Byte> phase, Long line, Ptr<Byte> msg) {
    println("%s error at line %l: %s",
            cast<String>(phase), line, cast<String>(msg));
    exit(1);
    return 0;
}

// "<phase> error at line N: <prefix> '<name>'"
Long die_named(Ptr<Byte> phase, Long line, Ptr<Byte> prefix, Ptr<Byte> name) {
    println("%s error at line %l: %s '%s'",
            cast<String>(phase), line,
            cast<String>(prefix), cast<String>(name));
    exit(1);
    return 0;
}

// "<phase> error at line N: <prefix> got <got>, want <want>"
Long die_type_mismatch(Ptr<Byte> phase, Long line, Ptr<Byte> prefix,
                       Ptr<Byte> got, Ptr<Byte> want) {
    println("%s error at line %l: %s got %s, want %s",
            cast<String>(phase), line,
            cast<String>(prefix),
            cast<String>(got), cast<String>(want));
    exit(1);
    return 0;
}

// Fatal internal error — not user-facing, but a bug in the compiler.
Long die_internal(Ptr<Byte> where, Ptr<Byte> msg) {
    println("internal error in %s: %s",
            cast<String>(where), cast<String>(msg));
    exit(2);
    return 0;
}
