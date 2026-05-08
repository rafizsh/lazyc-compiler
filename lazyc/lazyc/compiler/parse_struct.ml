// lazyc/compiler/parse_struct.ml
//
// Struct declaration parsing. Step 21g.
//
// `struct Foo { Type field1; Type field2; ... }` becomes a StructDef
// with computed field offsets, total size, and alignment. The struct is
// added to the parser's registry tentatively before parsing its body so
// fields like `Ptr<Self>` can resolve.

// Compute alignment of a Ptr<Type>. Mirrors the C parser_type_align.
Long type_align(Ptr<Type> t) {
    Long k = (*t).kind;
    if (k == TY_STRUCT()) {
        Ptr<StructDef> sd = cast<Ptr<StructDef>>((*t).sdef);
        if (sd == cast<Ptr<StructDef>>(null)) { return 1; }
        return (*sd).align;
    }
    if (k == TY_ARRAY()) {
        if ((*t).elem == cast<Ptr<Type>>(null)) { return 1; }
        return type_align((*t).elem);
    }
    // For simple types, alignment equals size.
    return type_size(t);
}

// Append a Field to a PtrVec of fields. Mirrors the inline bookkeeping in
// the C parser's parse_struct_decl loop.
Long add_field(Ptr<PtrVec> fields, Ptr<Type> ty, Ptr<Byte> name, Long name_len) {
    // Build a Ptr<Field>. sizeof(Field) = 24 (ty + name + name_len)
    //   plus offset = 32. Round to 32 for safety.
    Ptr<Byte> raw = alloc(32);
    Ptr<Field> f = cast<Ptr<Field>>(raw);
    (*f).name   = name;
    (*f).ty     = cast<Ptr<Byte>>(ty);   // opaque pointer to Type
    (*f).offset = 0;
    ptrvec_push(fields, cast<Ptr<Byte>>(f));
    return 0;
}

// Look up a field by name in a fields PtrVec. Returns null if not found.
Ptr<Field> find_field(Ptr<PtrVec> fields, Ptr<Byte> name, Long name_len) {
    Long n = (*fields).count;
    Long i = 0;
    while (i < n) {
        Ptr<Field> f = cast<Ptr<Field>>(ptrvec_get(fields, i));
        if (lex_slice_eq(name, name_len, (*f).name)) { return f; }
        i = i + 1;
    }
    return cast<Ptr<Field>>(null);
}

// Parse `struct Name { Type field1; Type field2; ... }`. Caller has not
// consumed the `struct` keyword.
Ptr<StructDef> parse_struct_decl(Ptr<Parser> p) {
    Ptr<Token> first = parser_cur(p);
    Long line = (*first).line;
    parser_expect(p, TOK_STRUCT(), cast<Ptr<Byte>>("expected 'struct'"));
    Ptr<Token> name_tok = parser_expect(p, TOK_IDENT(),
        cast<Ptr<Byte>>("expected struct name"));

    // Reject redeclaration.
    if (parser_find_struct(p, (*name_tok).text, (*name_tok).text_len)
        != cast<Ptr<StructDef>>(null)) {
        parse_error(p, cast<Ptr<Byte>>("redeclaration of struct"));
    }

    // Allocate the StructDef and register it BEFORE parsing the body so
    // self-references like Ptr<Self> can resolve. sizeof(StructDef) =
    // 4 fields * 8 = 32 (name, fields PtrVec, size, align).
    Ptr<Byte> raw = alloc(40);
    Ptr<StructDef> sd = cast<Ptr<StructDef>>(raw);
    (*sd).name  = (*name_tok).text;
    (*sd).size  = 0;
    (*sd).align = 1;

    // Heap-allocate the fields PtrVec.
    Ptr<Byte> raw_pv = alloc(24);
    Ptr<PtrVec> fields = cast<Ptr<PtrVec>>(raw_pv);
    ptrvec_init(fields);
    (*sd).fields = fields;

    parser_add_struct(p, sd);

    parser_expect(p, TOK_LBRACE(), cast<Ptr<Byte>>("expected '{' to begin struct body"));

    while (true) {
        if (parser_check(p, TOK_RBRACE())) { break; }
        if (parser_check(p, TOK_EOF())) {
            parse_error(p, cast<Ptr<Byte>>("unexpected EOF inside struct body"));
        }
        Ptr<Type> fty = parse_type(p);
        Ptr<Token> fname = parser_expect(p, TOK_IDENT(),
            cast<Ptr<Byte>>("expected field name"));
        // Optional `[N]` after the field name turns the base type into an
        // array (e.g. `Long histogram[26];`).
        fty = wrap_with_array_suffix(p, fty);
        parser_expect(p, TOK_SEMI(), cast<Ptr<Byte>>("expected ';' after field"));

        Long fk = (*fty).kind;
        if (fk == TY_VOID()) {
            parse_error(p, cast<Ptr<Byte>>("invalid field type"));
        }
        if (fk == TY_UNKNOWN()) {
            parse_error(p, cast<Ptr<Byte>>("invalid field type"));
        }
        // Reject `struct Foo { Foo f; }` — must use Ptr<Self>.
        if (fk == TY_STRUCT()) {
            Ptr<StructDef> fsd = cast<Ptr<StructDef>>((*fty).sdef);
            if (fsd == sd) {
                parse_error(p, cast<Ptr<Byte>>("struct cannot directly contain itself; use Ptr<Self>"));
            }
        }
        // Reject duplicate field names.
        Ptr<Field> existing = find_field(fields, (*fname).text, (*fname).text_len);
        if (existing != cast<Ptr<Field>>(null)) {
            parse_error(p, cast<Ptr<Byte>>("duplicate field name"));
        }
        add_field(fields, fty, (*fname).text, (*fname).text_len);
    }
    parser_expect(p, TOK_RBRACE(), cast<Ptr<Byte>>("expected '}' to close struct body"));

    // Compute offsets, struct size, and alignment.
    Long off = 0;
    Long max_align = 1;
    Long n = (*fields).count;
    Long i = 0;
    while (i < n) {
        Ptr<Field> f = cast<Ptr<Field>>(ptrvec_get(fields, i));
        Ptr<Type> ft = cast<Ptr<Type>>((*f).ty);
        Long fsz = type_size(ft);
        Long fal = type_align(ft);
        if (fal < 1) { fal = 1; }
        // Pad up to alignment.
        Long rem = off - (off / fal) * fal;
        if (rem != 0) { off = off + (fal - rem); }
        (*f).offset = off;
        off = off + fsz;
        if (fal > max_align) { max_align = fal; }
        i = i + 1;
    }
    // Final pad to struct alignment.
    if (max_align > 0) {
        Long final_rem = off - (off / max_align) * max_align;
        if (final_rem != 0) { off = off + (max_align - final_rem); }
    }
    if (off == 0) { off = 1; }   // empty struct still takes 1 byte

    (*sd).size  = off;
    (*sd).align = max_align;
    return sd;
}
