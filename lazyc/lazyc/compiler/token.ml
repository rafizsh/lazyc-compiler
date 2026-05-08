// lazyc/compiler/token.ml
//
// Token kinds and the Token struct. These values must match src/lexer.h
// exactly so that future tools (and the eventual fixed-point test) can
// compare token streams between C and lazyc lexers.
//
// Like Type kinds, we use zero-arg functions returning Long because lazyc
// lacks `enum` and globals.

// --- Special / identifier-like ---
Long TOK_NUMBER()      { return  0; }
Long TOK_CHAR_LIT()    { return  1; }
Long TOK_STRING_LIT()  { return  2; }
Long TOK_IDENT()       { return  3; }

// --- Type-name keywords ---
Long TOK_BOOLEAN()     { return  4; }
Long TOK_CHAR()        { return  5; }
Long TOK_BYTE()        { return  6; }
Long TOK_INTEGER()     { return  7; }
Long TOK_UINTEGER()    { return  8; }
Long TOK_WHOLE()       { return  9; }
Long TOK_UWHOLE()      { return 10; }
Long TOK_LONG()        { return 11; }
Long TOK_ULONG()       { return 12; }
Long TOK_STRING()      { return 13; }
Long TOK_PTR()         { return 14; }

// --- Other keywords ---
Long TOK_TRUE()        { return 15; }
Long TOK_FALSE()       { return 16; }
Long TOK_NULL()        { return 17; }
Long TOK_IF()          { return 18; }
Long TOK_ELSE()        { return 19; }
Long TOK_WHILE()       { return 20; }
Long TOK_FOR()         { return 21; }
Long TOK_RETURN()      { return 22; }
Long TOK_CAST()        { return 23; }
Long TOK_STRUCT()      { return 24; }
Long TOK_BREAK()       { return 25; }
Long TOK_CONTINUE()    { return 26; }

// --- Operators ---
Long TOK_PLUS()        { return 27; }
Long TOK_MINUS()       { return 28; }
Long TOK_STAR()        { return 29; }
Long TOK_SLASH()       { return 30; }
Long TOK_PERCENT()     { return 31; }
Long TOK_ASSIGN()      { return 32; }
Long TOK_EQ()          { return 33; }
Long TOK_NEQ()         { return 34; }
Long TOK_LT()          { return 35; }
Long TOK_GT()          { return 36; }
Long TOK_LE()          { return 37; }
Long TOK_GE()          { return 38; }
Long TOK_BANG()        { return 39; }
Long TOK_AMP()         { return 40; }

// --- Punctuation ---
Long TOK_LPAREN()      { return 41; }
Long TOK_RPAREN()      { return 42; }
Long TOK_LBRACE()      { return 43; }
Long TOK_RBRACE()      { return 44; }
Long TOK_LBRACKET()    { return 45; }
Long TOK_RBRACKET()    { return 46; }
Long TOK_SEMI()        { return 47; }
Long TOK_COMMA()       { return 48; }
Long TOK_DOT()         { return 49; }

// --- Markers ---
Long TOK_EOF()         { return 50; }
Long TOK_ERROR()       { return 51; }

// --- Late additions (added after TOK_ERROR to preserve existing IDs) ---
Long TOK_EXTERN()      { return 52; }

// A single token. `text` is heap-allocated and owned by the Token (or
// shared by interning where applicable).
//
// For TOK_IDENT and keyword tokens: `text` holds the identifier/keyword
//                                   bytes (null-terminated).
// For TOK_NUMBER:                   `text` is the numeric literal string;
//                                   `int_value` is the parsed value.
// For TOK_CHAR_LIT:                 `char_value` is the resolved code point;
//                                   `text` may be null.
// For TOK_STRING_LIT:               `text` is the RAW inner bytes between
//                                   the quotes (escape sequences NOT
//                                   resolved — codegen handles them).
// For all other kinds:              `text` may be null.
struct Token {
    Long      kind;        // TOK_*
    Long      line;        // line number where the token ENDS (matches C lexer)
    Long      int_value;   // for TOK_NUMBER
    Long      char_value;  // for TOK_CHAR_LIT (resolved)
    Ptr<Byte> text;        // owned (heap-allocated, null-terminated)
    Long      text_len;    // length excluding null terminator
}

// A list of tokens. The lexer pre-tokenizes the entire source into one of
// these; the parser walks it with an index.
struct TokenList {
    Ptr<PtrVec> items;     // each item is Ptr<Token>
}

// ---- Helpers ----

// Allocate a fresh Token with all fields zeroed and the given kind/line.
Ptr<Token> token_new(Long kind, Long line) {
    // sizeof(Token) = 8 (kind) + 8 (line) + 8 (int_value) + 8 (char_value) +
    //                 8 (text ptr) + 8 (text_len) = 48
    Ptr<Byte> raw = alloc(48);
    Ptr<Token> t = cast<Ptr<Token>>(raw);
    (*t).kind       = kind;
    (*t).line       = line;
    (*t).int_value  = 0;
    (*t).char_value = 0;
    (*t).text       = null;
    (*t).text_len   = 0;
    return t;
}

// Print the human-readable name of a token kind. Used for error messages.
// Returns a string literal — caller must NOT free.
Ptr<Byte> token_kind_name(Long k) {
    if (k == TOK_NUMBER())     { return cast<Ptr<Byte>>("NUMBER"); }
    if (k == TOK_CHAR_LIT())   { return cast<Ptr<Byte>>("CHAR_LIT"); }
    if (k == TOK_STRING_LIT()) { return cast<Ptr<Byte>>("STRING_LIT"); }
    if (k == TOK_IDENT())      { return cast<Ptr<Byte>>("IDENT"); }
    if (k == TOK_BOOLEAN())    { return cast<Ptr<Byte>>("Boolean"); }
    if (k == TOK_CHAR())       { return cast<Ptr<Byte>>("Char"); }
    if (k == TOK_BYTE())       { return cast<Ptr<Byte>>("Byte"); }
    if (k == TOK_INTEGER())    { return cast<Ptr<Byte>>("Integer"); }
    if (k == TOK_UINTEGER())   { return cast<Ptr<Byte>>("uInteger"); }
    if (k == TOK_WHOLE())      { return cast<Ptr<Byte>>("Whole"); }
    if (k == TOK_UWHOLE())     { return cast<Ptr<Byte>>("uWhole"); }
    if (k == TOK_LONG())       { return cast<Ptr<Byte>>("Long"); }
    if (k == TOK_ULONG())      { return cast<Ptr<Byte>>("uLong"); }
    if (k == TOK_STRING())     { return cast<Ptr<Byte>>("String"); }
    if (k == TOK_PTR())        { return cast<Ptr<Byte>>("Ptr"); }
    if (k == TOK_TRUE())       { return cast<Ptr<Byte>>("true"); }
    if (k == TOK_FALSE())      { return cast<Ptr<Byte>>("false"); }
    if (k == TOK_NULL())       { return cast<Ptr<Byte>>("null"); }
    if (k == TOK_IF())         { return cast<Ptr<Byte>>("if"); }
    if (k == TOK_ELSE())       { return cast<Ptr<Byte>>("else"); }
    if (k == TOK_WHILE())      { return cast<Ptr<Byte>>("while"); }
    if (k == TOK_FOR())        { return cast<Ptr<Byte>>("for"); }
    if (k == TOK_RETURN())     { return cast<Ptr<Byte>>("return"); }
    if (k == TOK_CAST())       { return cast<Ptr<Byte>>("cast"); }
    if (k == TOK_STRUCT())     { return cast<Ptr<Byte>>("struct"); }
    if (k == TOK_BREAK())      { return cast<Ptr<Byte>>("break"); }
    if (k == TOK_CONTINUE())   { return cast<Ptr<Byte>>("continue"); }
    if (k == TOK_EXTERN())     { return cast<Ptr<Byte>>("extern"); }
    if (k == TOK_PLUS())       { return cast<Ptr<Byte>>("+"); }
    if (k == TOK_MINUS())      { return cast<Ptr<Byte>>("-"); }
    if (k == TOK_STAR())       { return cast<Ptr<Byte>>("*"); }
    if (k == TOK_SLASH())      { return cast<Ptr<Byte>>("/"); }
    if (k == TOK_PERCENT())    { return cast<Ptr<Byte>>("%"); }
    if (k == TOK_ASSIGN())     { return cast<Ptr<Byte>>("="); }
    if (k == TOK_EQ())         { return cast<Ptr<Byte>>("=="); }
    if (k == TOK_NEQ())        { return cast<Ptr<Byte>>("!="); }
    if (k == TOK_LT())         { return cast<Ptr<Byte>>("<"); }
    if (k == TOK_GT())         { return cast<Ptr<Byte>>(">"); }
    if (k == TOK_LE())         { return cast<Ptr<Byte>>("<="); }
    if (k == TOK_GE())         { return cast<Ptr<Byte>>(">="); }
    if (k == TOK_BANG())       { return cast<Ptr<Byte>>("!"); }
    if (k == TOK_AMP())        { return cast<Ptr<Byte>>("&"); }
    if (k == TOK_LPAREN())     { return cast<Ptr<Byte>>("("); }
    if (k == TOK_RPAREN())     { return cast<Ptr<Byte>>(")"); }
    if (k == TOK_LBRACE())     { return cast<Ptr<Byte>>("{"); }
    if (k == TOK_RBRACE())     { return cast<Ptr<Byte>>("}"); }
    if (k == TOK_LBRACKET())   { return cast<Ptr<Byte>>("["); }
    if (k == TOK_RBRACKET())   { return cast<Ptr<Byte>>("]"); }
    if (k == TOK_SEMI())       { return cast<Ptr<Byte>>(";"); }
    if (k == TOK_COMMA())      { return cast<Ptr<Byte>>(","); }
    if (k == TOK_DOT())        { return cast<Ptr<Byte>>("."); }
    if (k == TOK_EOF())        { return cast<Ptr<Byte>>("EOF"); }
    if (k == TOK_ERROR())      { return cast<Ptr<Byte>>("ERROR"); }
    return cast<Ptr<Byte>>("<bad-token>");
}
