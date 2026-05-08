// lazyc/compiler/lex.ml
//
// Lexer: source bytes -> TokenList. Behaves identically to src/lexer.c
// (same token kinds, same line tracking, same handling of escape
// sequences) so that downstream phases produce byte-identical output.
//
// One difference from the C lexer: we pre-tokenize the entire source
// into a TokenList rather than streaming. This is simpler in lazyc
// because we don't have to thread a mutable Lexer state through every
// parser function.

// State held while scanning. After tokenization completes, this is
// discarded — only the TokenList is returned.
struct LexState {
    Ptr<Byte> src;        // source buffer (NOT owned; caller manages)
    Ptr<Byte> cur;        // current position (advances through src)
    Long      line;       // current line (1-based)
}

// ---- Source-buffer primitives ----
// These match the C lexer's at_end/peek/peek2/advance/match.

Boolean lex_at_end(Ptr<LexState> l) {
    return *(*l).cur == cast<Byte>(0);
}

Byte lex_peek(Ptr<LexState> l) {
    return *(*l).cur;
}

// Look one byte ahead. Returns 0 if at end (or if the current byte is
// already 0, matching the C version's defensive read).
Byte lex_peek2(Ptr<LexState> l) {
    if (*(*l).cur == cast<Byte>(0)) { return cast<Byte>(0); }
    Ptr<Byte> next = (*l).cur + 1;
    return *next;
}

// Consume the current byte. Updates line counter on '\n'. Returns the
// consumed byte.
Byte lex_advance(Ptr<LexState> l) {
    Byte c = *(*l).cur;
    (*l).cur = (*l).cur + 1;
    if (cast<Long>(c) == 10) { (*l).line = (*l).line + 1; }
    return c;
}

// If the current byte equals `c`, consume it and return true. Otherwise
// leave the cursor unchanged and return false.
Boolean lex_match(Ptr<LexState> l, Byte c) {
    if (*(*l).cur != c) { return false; }
    (*l).cur = (*l).cur + 1;
    return true;
}

// ---- Whitespace and comments ----

Long lex_skip_ws_and_comments(Ptr<LexState> l) {
    while (true) {
        if (lex_at_end(l)) { return 0; }
        Byte c = lex_peek(l);
        Long ci = cast<Long>(c);
        // ' ', '\t', '\r', '\n'
        Boolean is_ws = false;
        if (ci == 32) { is_ws = true; }
        if (ci == 9)  { is_ws = true; }
        if (ci == 13) { is_ws = true; }
        if (ci == 10) { is_ws = true; }
        if (is_ws) {
            lex_advance(l);
            continue;
        }
        // '/' '/'  -> line comment
        if (ci == 47) {                  // '/'
            Byte n = lex_peek2(l);
            Long ni = cast<Long>(n);
            if (ni == 47) {              // "//"
                while (true) {
                    if (lex_at_end(l)) { break; }
                    if (cast<Long>(lex_peek(l)) == 10) { break; }
                    lex_advance(l);
                }
                continue;
            }
            // '/' '*'  -> block comment
            if (ni == 42) {              // "/*"
                lex_advance(l);          // '/'
                lex_advance(l);          // '*'
                while (true) {
                    if (lex_at_end(l)) { break; }
                    Byte a = lex_peek(l);
                    Byte b = lex_peek2(l);
                    Long ai = cast<Long>(a);
                    Long bi = cast<Long>(b);
                    if (ai == 42) {
                        if (bi == 47) { break; }
                    }
                    lex_advance(l);
                }
                if (!lex_at_end(l)) {
                    lex_advance(l);      // '*'
                    lex_advance(l);      // '/'
                }
                continue;
            }
        }
        // Not whitespace or comment -> stop.
        break;
    }
    return 0;
}

// ---- Token construction ----

// Make a token of kind `kind`, copying the source slice [start..end) as
// its text. Records the CURRENT line of the lexer (not the start line),
// matching the C lexer's behavior.
Ptr<Token> lex_make_tok(Ptr<LexState> l, Long kind, Ptr<Byte> start, Ptr<Byte> end) {
    Long len = end - start;
    Ptr<Token> t = token_new(kind, (*l).line);
    if (len > 0) {
        (*t).text = ml_memdup(start, len);
        (*t).text_len = len;
    }
    return t;
}

// Error-token helper: also kills the program with an error message.
// (The C lexer threads error tokens through the parser; the lazyc
// version aborts immediately for simplicity. Real lexer errors are
// rare and tests verify exit-with-error rather than continuation.)
Long lex_die(Ptr<LexState> l, Ptr<Byte> msg) {
    println("lex error at line %l: %s", (*l).line, cast<String>(msg));
    exit(1);
    return 0;
}

// ---- Identifier classification ----

// Resolve an identifier slice [start..end) to a keyword token kind, or
// TOK_IDENT if no keyword matches. Mirrors src/lexer.c::ident_kind.
Long lex_ident_kind(Ptr<Byte> start, Long len) {
    // We compare against each keyword by length first (cheap), then bytes.
    // ml_streq works on null-terminated strings; we can't easily build a
    // null-terminated copy without another alloc, so do byte compares
    // inline here.
    if (len == 7) {
        if (lex_slice_eq(start, len, cast<Ptr<Byte>>("Boolean")))  { return TOK_BOOLEAN(); }
        if (lex_slice_eq(start, len, cast<Ptr<Byte>>("Integer")))  { return TOK_INTEGER(); }
        return TOK_IDENT();
    }
    if (len == 8) {
        if (lex_slice_eq(start, len, cast<Ptr<Byte>>("uInteger"))) { return TOK_UINTEGER(); }
        if (lex_slice_eq(start, len, cast<Ptr<Byte>>("continue"))) { return TOK_CONTINUE(); }
        return TOK_IDENT();
    }
    if (len == 6) {
        if (lex_slice_eq(start, len, cast<Ptr<Byte>>("uWhole")))   { return TOK_UWHOLE(); }
        if (lex_slice_eq(start, len, cast<Ptr<Byte>>("String")))   { return TOK_STRING(); }
        if (lex_slice_eq(start, len, cast<Ptr<Byte>>("return")))   { return TOK_RETURN(); }
        if (lex_slice_eq(start, len, cast<Ptr<Byte>>("struct")))   { return TOK_STRUCT(); }
        if (lex_slice_eq(start, len, cast<Ptr<Byte>>("extern")))   { return TOK_EXTERN(); }
        return TOK_IDENT();
    }
    if (len == 5) {
        if (lex_slice_eq(start, len, cast<Ptr<Byte>>("uLong")))    { return TOK_ULONG(); }
        if (lex_slice_eq(start, len, cast<Ptr<Byte>>("Whole")))    { return TOK_WHOLE(); }
        if (lex_slice_eq(start, len, cast<Ptr<Byte>>("false")))    { return TOK_FALSE(); }
        if (lex_slice_eq(start, len, cast<Ptr<Byte>>("while")))    { return TOK_WHILE(); }
        if (lex_slice_eq(start, len, cast<Ptr<Byte>>("break")))    { return TOK_BREAK(); }
        return TOK_IDENT();
    }
    if (len == 4) {
        if (lex_slice_eq(start, len, cast<Ptr<Byte>>("Char")))     { return TOK_CHAR(); }
        if (lex_slice_eq(start, len, cast<Ptr<Byte>>("Byte")))     { return TOK_BYTE(); }
        if (lex_slice_eq(start, len, cast<Ptr<Byte>>("Long")))     { return TOK_LONG(); }
        if (lex_slice_eq(start, len, cast<Ptr<Byte>>("true")))     { return TOK_TRUE(); }
        if (lex_slice_eq(start, len, cast<Ptr<Byte>>("null")))     { return TOK_NULL(); }
        if (lex_slice_eq(start, len, cast<Ptr<Byte>>("else")))     { return TOK_ELSE(); }
        if (lex_slice_eq(start, len, cast<Ptr<Byte>>("cast")))     { return TOK_CAST(); }
        return TOK_IDENT();
    }
    if (len == 3) {
        if (lex_slice_eq(start, len, cast<Ptr<Byte>>("Ptr")))      { return TOK_PTR(); }
        if (lex_slice_eq(start, len, cast<Ptr<Byte>>("for")))      { return TOK_FOR(); }
        return TOK_IDENT();
    }
    if (len == 2) {
        if (lex_slice_eq(start, len, cast<Ptr<Byte>>("if")))       { return TOK_IF(); }
        return TOK_IDENT();
    }
    return TOK_IDENT();
}

// Compare a non-null-terminated slice [start..start+len) to a null-
// terminated literal. True iff exactly equal in length and bytes.
Boolean lex_slice_eq(Ptr<Byte> start, Long len, Ptr<Byte> lit) {
    Long lit_len = ml_strlen(lit);
    if (lit_len != len) { return false; }
    Long i = 0;
    while (i < len) {
        if (start[i] != lit[i]) { return false; }
        i = i + 1;
    }
    return true;
}

// ---- Per-kind scanners ----

// Identifier or keyword: [A-Za-z_][A-Za-z0-9_]*
Ptr<Token> lex_ident(Ptr<LexState> l, Ptr<Byte> start) {
    while (true) {
        if (lex_at_end(l)) { break; }
        if (!ml_is_ident_cont(lex_peek(l))) { break; }
        lex_advance(l);
    }
    Ptr<Byte> end = (*l).cur;
    Long len = end - start;
    Long kind = lex_ident_kind(start, len);
    return lex_make_tok(l, kind, start, end);
}

// Decimal number: [0-9]+
Ptr<Token> lex_number(Ptr<LexState> l, Ptr<Byte> start) {
    while (true) {
        if (lex_at_end(l)) { break; }
        if (!ml_is_digit(lex_peek(l))) { break; }
        lex_advance(l);
    }
    Ptr<Byte> end = (*l).cur;
    Ptr<Token> t = lex_make_tok(l, TOK_NUMBER(), start, end);
    // Parse the integer value. Our text is null-terminated by ml_memdup.
    (*t).int_value = ml_atol((*t).text);
    return t;
}

// Char literal: '\'' (char | escape) '\''
// Resolves the escape and stores the resulting code point in char_value.
Ptr<Token> lex_char(Ptr<LexState> l, Ptr<Byte> start) {
    if (lex_at_end(l)) { lex_die(l, cast<Ptr<Byte>>("unterminated char literal")); }
    Byte c = lex_advance(l);
    Long cv = cast<Long>(c);
    if (cv == 92) {                          // '\\'
        if (lex_at_end(l)) { lex_die(l, cast<Ptr<Byte>>("unterminated char literal")); }
        Byte esc = lex_advance(l);
        Long ei = cast<Long>(esc);
        if (ei == 110)      { cv = 10; }     // '\n'
        else if (ei == 116) { cv = 9;  }     // '\t'
        else if (ei == 114) { cv = 13; }     // '\r'
        else if (ei == 48)  { cv = 0;  }     // '\0'
        else if (ei == 92)  { cv = 92; }     // '\\'
        else if (ei == 39)  { cv = 39; }     // '\''
        else if (ei == 34)  { cv = 34; }     // '\"'
        else { lex_die(l, cast<Ptr<Byte>>("unknown escape in char literal")); }
    }
    // Expect closing quote.
    Boolean bad = false;
    if (lex_at_end(l)) { bad = true; }
    if (!bad) {
        if (cast<Long>(lex_peek(l)) != 39) { bad = true; }
    }
    if (bad) {
        lex_die(l, cast<Ptr<Byte>>("unterminated char literal"));
    }
    lex_advance(l);                          // consume closing '\''
    Ptr<Byte> end = (*l).cur;
    Ptr<Token> t = lex_make_tok(l, TOK_CHAR_LIT(), start, end);
    (*t).char_value = cv;
    return t;
}

// String literal: '"' (char | escape)* '"'
// Does NOT resolve escapes — codegen interprets them when emitting the
// .rodata table. The token's `text` holds the RAW inner bytes, with
// backslashes and following character intact, but EXCLUDING the quotes.
Ptr<Token> lex_string(Ptr<LexState> l, Ptr<Byte> start) {
    // start points at the opening quote. Inner text begins at start+1.
    Ptr<Byte> inner_start = start + 1;
    while (true) {
        if (lex_at_end(l)) { lex_die(l, cast<Ptr<Byte>>("unterminated string literal")); }
        Byte c = lex_peek(l);
        Long ci = cast<Long>(c);
        if (ci == 34) { break; }             // closing '"'
        if (ci == 92) { lex_advance(l); }    // skip backslash...
        if (lex_at_end(l)) { lex_die(l, cast<Ptr<Byte>>("unterminated string literal")); }
        lex_advance(l);                      // ...and the escaped byte
    }
    Ptr<Byte> inner_end = (*l).cur;          // points at the closing quote
    lex_advance(l);                          // consume closing '"'
    Ptr<Byte> end = (*l).cur;
    // Build the token with the FULL slice (including quotes) so line
    // tracking matches; then overwrite text with just the inner bytes
    // since downstream code wants the unwrapped contents.
    Ptr<Token> t = lex_make_tok(l, TOK_STRING_LIT(), start, end);
    if ((*t).text != null) {
        free((*t).text);
        (*t).text = null;
        (*t).text_len = 0;
    }
    Long inner_len = inner_end - inner_start;
    if (inner_len > 0) {
        (*t).text = ml_memdup(inner_start, inner_len);
        (*t).text_len = inner_len;
    } else {
        // Empty string literal: still allocate a valid null-terminated buffer.
        (*t).text = alloc(1);
        (*t).text[0] = cast<Byte>(0);
        (*t).text_len = 0;
    }
    return t;
}

// ---- Main scan loop ----

// Scan the next token. Caller must have called lex_skip_ws_and_comments.
// Returns the token (always non-null; errors abort).
Ptr<Token> lex_next(Ptr<LexState> l) {
    if (lex_at_end(l)) { return token_new(TOK_EOF(), (*l).line); }
    Ptr<Byte> start = (*l).cur;
    Byte c = lex_advance(l);
    Long ci = cast<Long>(c);

    if (ml_is_ident_start(c)) {
        return lex_ident(l, start);
    }
    if (ml_is_digit(c)) {
        return lex_number(l, start);
    }
    if (ci == 39) {                          // '\''
        // C lexer passes start+1 (skipping the opening quote) so the
        // recorded text excludes the leading quote. Match that.
        return lex_char(l, start + 1);
    }
    if (ci == 34) {                          // '"'
        return lex_string(l, start);
    }

    // Single-byte operators.
    if (ci == 43) { return lex_make_tok(l, TOK_PLUS(),    start, (*l).cur); }
    if (ci == 45) { return lex_make_tok(l, TOK_MINUS(),   start, (*l).cur); }
    if (ci == 42) { return lex_make_tok(l, TOK_STAR(),    start, (*l).cur); }
    if (ci == 47) { return lex_make_tok(l, TOK_SLASH(),   start, (*l).cur); }
    if (ci == 37) { return lex_make_tok(l, TOK_PERCENT(), start, (*l).cur); }
    if (ci == 40) { return lex_make_tok(l, TOK_LPAREN(),  start, (*l).cur); }
    if (ci == 41) { return lex_make_tok(l, TOK_RPAREN(),  start, (*l).cur); }
    if (ci == 123) { return lex_make_tok(l, TOK_LBRACE(),   start, (*l).cur); }
    if (ci == 125) { return lex_make_tok(l, TOK_RBRACE(),   start, (*l).cur); }
    if (ci == 91) { return lex_make_tok(l, TOK_LBRACKET(), start, (*l).cur); }
    if (ci == 93) { return lex_make_tok(l, TOK_RBRACKET(), start, (*l).cur); }
    if (ci == 59) { return lex_make_tok(l, TOK_SEMI(),    start, (*l).cur); }
    if (ci == 44) { return lex_make_tok(l, TOK_COMMA(),   start, (*l).cur); }
    if (ci == 46) { return lex_make_tok(l, TOK_DOT(),     start, (*l).cur); }
    if (ci == 38) { return lex_make_tok(l, TOK_AMP(),     start, (*l).cur); }

    // Two-character punctuators (= == != < <= > >= !).
    if (ci == 61) {                          // '='
        if (lex_match(l, cast<Byte>(61))) { return lex_make_tok(l, TOK_EQ(), start, (*l).cur); }
        return lex_make_tok(l, TOK_ASSIGN(), start, (*l).cur);
    }
    if (ci == 33) {                          // '!'
        if (lex_match(l, cast<Byte>(61))) { return lex_make_tok(l, TOK_NEQ(), start, (*l).cur); }
        return lex_make_tok(l, TOK_BANG(), start, (*l).cur);
    }
    if (ci == 60) {                          // '<'
        if (lex_match(l, cast<Byte>(61))) { return lex_make_tok(l, TOK_LE(), start, (*l).cur); }
        return lex_make_tok(l, TOK_LT(), start, (*l).cur);
    }
    if (ci == 62) {                          // '>'
        if (lex_match(l, cast<Byte>(61))) { return lex_make_tok(l, TOK_GE(), start, (*l).cur); }
        return lex_make_tok(l, TOK_GT(), start, (*l).cur);
    }

    println("lex error at line %l: unexpected character '%c' (code %l)",
            (*l).line, cast<Char>(ci), ci);
    exit(1);
    return null;     // unreachable
}

// ---- Public entry point ----

// Tokenize the entire source. Returns a TokenList ending with a TOK_EOF.
// `source` must be null-terminated (readf gives us this).
Ptr<TokenList> lex_tokenize(Ptr<Byte> source) {
    LexState ls;
    ls.src  = source;
    ls.cur  = source;
    ls.line = 1;

    PtrVec items;
    ptrvec_init(&items);

    while (true) {
        lex_skip_ws_and_comments(&ls);
        Ptr<Token> t = lex_next(&ls);
        ptrvec_push(&items, cast<Ptr<Byte>>(t));
        if ((*t).kind == TOK_EOF()) { break; }
    }

    // Wrap in a heap-allocated TokenList.
    Ptr<Byte> raw = alloc(8);
    Ptr<TokenList> tl = cast<Ptr<TokenList>>(raw);
    // Move the PtrVec onto the heap so it outlives this function frame.
    Ptr<Byte> pv_raw = alloc(24);    // sizeof(PtrVec) = 8+8+8 = 24
    Ptr<PtrVec> pv = cast<Ptr<PtrVec>>(pv_raw);
    (*pv).items = items.items;
    (*pv).count = items.count;
    (*pv).cap   = items.cap;
    (*tl).items = pv;
    return tl;
}

// Number of tokens in the list (including the trailing EOF).
Long tokenlist_count(Ptr<TokenList> tl) {
    return (*(*tl).items).count;
}

// Get token at index i. No bounds check.
Ptr<Token> tokenlist_at(Ptr<TokenList> tl, Long i) {
    return cast<Ptr<Token>>(ptrvec_get((*tl).items, i));
}
