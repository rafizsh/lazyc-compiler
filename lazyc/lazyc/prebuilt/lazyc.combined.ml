// lazyc — substrate library
// 21a: byte-level string and memory primitives
//
// Everything here is built only from lazyc primitives (alloc/free,
// pointer arithmetic, basic loops). No standard-library dependence.

// Length of a null-terminated byte buffer.
Long ml_strlen(Ptr<Byte> s) {
    if (s == null) { return 0; }
    Long n = 0;
    Ptr<Byte> p = s;
    while (*p != cast<Byte>(0)) {
        n = n + 1;
        p = p + 1;
    }
    return n;
}

// Equality of two null-terminated buffers.
Boolean ml_streq(Ptr<Byte> a, Ptr<Byte> b) {
    if (a == null) {
        if (b == null) { return true; }
        return false;
    }
    if (b == null) { return false; }
    Ptr<Byte> pa = a;
    Ptr<Byte> pb = b;
    while (true) {
        Byte ca = *pa;
        Byte cb = *pb;
        if (ca != cb) { return false; }
        if (ca == cast<Byte>(0)) { return true; }
        pa = pa + 1;
        pb = pb + 1;
    }
    return false;   // unreachable; lazyc requires return on all paths
}

// strncmp-style: -1 / 0 / 1.
Long ml_strcmp(Ptr<Byte> a, Ptr<Byte> b) {
    if (a == null) {
        if (b == null) { return 0; }
        return -1;
    }
    if (b == null) { return 1; }
    Ptr<Byte> pa = a;
    Ptr<Byte> pb = b;
    while (true) {
        Long ca = cast<Long>(*pa);
        Long cb = cast<Long>(*pb);
        if (ca < cb) { return -1; }
        if (ca > cb) { return 1; }
        if (ca == 0) { return 0; }
        pa = pa + 1;
        pb = pb + 1;
    }
    return 0;       // unreachable
}

// Memcpy: copy n bytes from src to dst. Caller ensures non-overlap.
Long ml_memcpy(Ptr<Byte> dst, Ptr<Byte> src, Long n) {
    Long i = 0;
    while (i < n) {
        dst[i] = src[i];
        i = i + 1;
    }
    return 0;
}

// Allocate a fresh null-terminated copy of [src .. src+n).
Ptr<Byte> ml_memdup(Ptr<Byte> src, Long n) {
    Ptr<Byte> buf = alloc(n + 1);
    if (buf == null) { return null; }
    Long i = 0;
    while (i < n) {
        buf[i] = src[i];
        i = i + 1;
    }
    buf[n] = cast<Byte>(0);
    return buf;
}

// Allocate a fresh null-terminated copy of an existing null-terminated string.
Ptr<Byte> ml_strdup(Ptr<Byte> s) {
    if (s == null) { return null; }
    Long n = ml_strlen(s);
    return ml_memdup(s, n);
}

// True if the byte is an ASCII digit '0'..'9'.
Boolean ml_is_digit(Byte b) {
    Long c = cast<Long>(b);
    if (c < 48) { return false; }   // '0'
    if (c > 57) { return false; }   // '9'
    return true;
}

// True if the byte is an ASCII letter or underscore.
Boolean ml_is_ident_start(Byte b) {
    Long c = cast<Long>(b);
    if (c == 95) { return true; }                  // '_'
    if (c >= 65) { if (c <= 90)  { return true; } } // 'A'..'Z'
    if (c >= 97) { if (c <= 122) { return true; } } // 'a'..'z'
    return false;
}

// True if the byte is letter, digit, or underscore.
Boolean ml_is_ident_cont(Byte b) {
    if (ml_is_ident_start(b)) { return true; }
    return ml_is_digit(b);
}

// True if whitespace: space, tab, newline, carriage return.
Boolean ml_is_space(Byte b) {
    Long c = cast<Long>(b);
    if (c == 32) { return true; }    // ' '
    if (c == 9)  { return true; }    // '\t'
    if (c == 10) { return true; }    // '\n'
    if (c == 13) { return true; }    // '\r'
    return false;
}

// Parse a decimal Long from a null-terminated buffer. Returns 0 on no digits.
// Stops at the first non-digit. Does not handle overflow gracefully.
Long ml_atol(Ptr<Byte> s) {
    if (s == null) { return 0; }
    Long n = 0;
    Long sign = 1;
    Ptr<Byte> p = s;
    if (cast<Long>(*p) == 45) { sign = -1; p = p + 1; }   // '-'
    while (true) {
        Byte b = *p;
        if (!ml_is_digit(b)) { break; }
        n = n * 10 + (cast<Long>(b) - 48);
        p = p + 1;
    }
    return n * sign;
}
// lazyc — substrate library
// Growable byte buffer "Buf". Used for accumulating assembly output
// before writing it to disk, since lazyc's writef takes a whole buffer.
//
// Doesn't currently use realloc (we don't have one) — instead grows by
// allocating a new buffer of doubled capacity, copying, freeing the old.

struct Buf {
    Ptr<Byte> data;     // heap-allocated, null-terminated; len bytes valid
    Long      len;      // bytes currently held (excluding null terminator)
    Long      cap;      // bytes allocated (always at least len + 1)
}

// Initialize a Buf with a small initial capacity.
Long buf_init(Ptr<Buf> b) {
    Long initial = 64;
    Ptr<Byte> data = alloc(initial);
    if (data == null) { exit(1); }
    data[0] = cast<Byte>(0);
    (*b).data = data;
    (*b).len = 0;
    (*b).cap = initial;
    return 0;
}

// Free a Buf's storage. Safe to call on already-freed bufs (data == null).
Long buf_free(Ptr<Buf> b) {
    if ((*b).data != null) {
        free((*b).data);
        (*b).data = null;
    }
    (*b).len = 0;
    (*b).cap = 0;
    return 0;
}

// Internal: ensure cap is at least `need` bytes (including null terminator).
// Grows by powers of 2.
Long buf_reserve(Ptr<Buf> b, Long need) {
    if ((*b).cap >= need) { return 0; }
    Long new_cap = (*b).cap;
    if (new_cap < 64) { new_cap = 64; }
    while (new_cap < need) {
        new_cap = new_cap * 2;
    }
    Ptr<Byte> new_data = alloc(new_cap);
    if (new_data == null) { exit(1); }
    // Copy existing bytes (len + 1 to include the null).
    Long i = 0;
    Long copy_n = (*b).len + 1;
    while (i < copy_n) {
        new_data[i] = (*b).data[i];
        i = i + 1;
    }
    free((*b).data);
    (*b).data = new_data;
    (*b).cap = new_cap;
    return 0;
}

// Append a single byte.
Long buf_push_byte(Ptr<Buf> b, Byte c) {
    buf_reserve(b, (*b).len + 2);    // need len+1 for byte + len+2 for null
    (*b).data[(*b).len] = c;
    (*b).len = (*b).len + 1;
    (*b).data[(*b).len] = cast<Byte>(0);
    return 0;
}

// Append n bytes from src.
Long buf_push_bytes(Ptr<Buf> b, Ptr<Byte> src, Long n) {
    if (n <= 0) { return 0; }
    buf_reserve(b, (*b).len + n + 1);
    Long i = 0;
    while (i < n) {
        (*b).data[(*b).len + i] = src[i];
        i = i + 1;
    }
    (*b).len = (*b).len + n;
    (*b).data[(*b).len] = cast<Byte>(0);
    return 0;
}

// Append a null-terminated string.
Long buf_push_str(Ptr<Buf> b, Ptr<Byte> s) {
    if (s == null) { return 0; }
    Long n = ml_strlen(s);
    return buf_push_bytes(b, s, n);
}

// Append the decimal representation of a Long.
Long buf_push_long(Ptr<Buf> b, Long n) {
    if (n == 0) {
        buf_push_byte(b, cast<Byte>(48));    // '0'
        return 0;
    }
    // Special-case LONG_MIN since negating it overflows.
    if (n == -9223372036854775807 - 1) {
        buf_push_str(b, cast<Ptr<Byte>>("-9223372036854775808"));
        return 0;
    }
    Boolean neg = false;
    Long v = n;
    if (v < 0) {
        neg = true;
        v = 0 - v;
    }
    // Build digits in reverse (max ~20 digits for a 64-bit Long).
    Byte digits[24];
    Long ndigits = 0;
    while (v > 0) {
        digits[ndigits] = cast<Byte>(48 + (v % 10));
        ndigits = ndigits + 1;
        v = v / 10;
    }
    if (neg) {
        buf_push_byte(b, cast<Byte>(45));    // '-'
    }
    // Emit in correct order.
    Long i = ndigits - 1;
    while (i >= 0) {
        buf_push_byte(b, digits[i]);
        i = i - 1;
    }
    return 0;
}
// lazyc — substrate library
// Growable pointer-array. Used for collections in the parser/typechecker
// (struct registry, function table, parameter lists, statement lists)
// where we'd reach for realloc in C.

struct PtrVec {
    Ptr<Ptr<Byte>> items;     // heap-allocated array of cap pointers
    Long           count;
    Long           cap;
}

Long ptrvec_init(Ptr<PtrVec> v) {
    Long initial = 4;
    // 8 bytes per pointer.
    Ptr<Byte> raw = alloc(initial * 8);
    if (raw == null) { exit(1); }
    (*v).items = cast<Ptr<Ptr<Byte>>>(raw);
    (*v).count = 0;
    (*v).cap = initial;
    return 0;
}

Long ptrvec_free(Ptr<PtrVec> v) {
    if ((*v).items != null) {
        free(cast<Ptr<Byte>>((*v).items));
        (*v).items = cast<Ptr<Ptr<Byte>>>(null);
    }
    (*v).count = 0;
    (*v).cap = 0;
    return 0;
}

// Internal: grow to at least `need` slots.
Long ptrvec_reserve(Ptr<PtrVec> v, Long need) {
    if ((*v).cap >= need) { return 0; }
    Long new_cap = (*v).cap;
    if (new_cap < 4) { new_cap = 4; }
    while (new_cap < need) {
        new_cap = new_cap * 2;
    }
    Ptr<Byte> new_raw = alloc(new_cap * 8);
    if (new_raw == null) { exit(1); }
    Ptr<Ptr<Byte>> new_items = cast<Ptr<Ptr<Byte>>>(new_raw);
    Long i = 0;
    while (i < (*v).count) {
        new_items[i] = (*v).items[i];
        i = i + 1;
    }
    free(cast<Ptr<Byte>>((*v).items));
    (*v).items = new_items;
    (*v).cap = new_cap;
    return 0;
}

Long ptrvec_push(Ptr<PtrVec> v, Ptr<Byte> p) {
    ptrvec_reserve(v, (*v).count + 1);
    (*v).items[(*v).count] = p;
    (*v).count = (*v).count + 1;
    return 0;
}

// Get the pointer at index i. No bounds check.
Ptr<Byte> ptrvec_get(Ptr<PtrVec> v, Long i) {
    return (*v).items[i];
}

// Set the pointer at index i. No bounds check.
Long ptrvec_set(Ptr<PtrVec> v, Long i, Ptr<Byte> p) {
    (*v).items[i] = p;
    return 0;
}
// lazyc/compiler/types.ml
//
// AST type representation. This is the foundation: Type, Field, StructDef.
// These are mutually recursive in the C compiler, but lazyc doesn't allow
// mutual struct recursion across distinct types — only self-recursion. So
// cross-type pointers between Type/Field/StructDef are stored as Ptr<Byte>
// and cast at use sites. (Self-pointers like Type->Type for `pointee` work
// fine without the workaround.)
//
// Type kinds (matches src/ast.h enum order):
Long TY_BOOLEAN()  { return 0; }
Long TY_CHAR()     { return 1; }
Long TY_BYTE()     { return 2; }
Long TY_INTEGER()  { return 3; }
Long TY_UINTEGER() { return 4; }
Long TY_WHOLE()    { return 5; }
Long TY_UWHOLE()   { return 6; }
Long TY_LONG()     { return 7; }
Long TY_ULONG()    { return 8; }
Long TY_STRING()   { return 9; }
Long TY_PTR()      { return 10; }
Long TY_STRUCT()   { return 11; }
Long TY_ARRAY()    { return 12; }
Long TY_VOID()     { return 13; }
Long TY_UNKNOWN()  { return 14; }

// A Type describes a value's shape. For simple kinds (Long, Boolean, etc.)
// only `kind` matters; for Ptr<T>, `pointee` is set; for arrays, `elem` and
// `nelems`; for structs, `sdef`. The other fields are zero/null and ignored.
struct Type {
    Long      kind;       // TY_*
    Ptr<Type> pointee;    // TY_PTR: the pointed-to type (self-recursive, OK)
    Ptr<Type> elem;       // TY_ARRAY: element type
    Long      nelems;     // TY_ARRAY: element count (always > 0)
    Ptr<Byte> sdef;       // TY_STRUCT: really Ptr<StructDef> (cast at use)
}

// A struct field: name, type, byte offset within the struct.
struct Field {
    Ptr<Byte> name;       // null-terminated identifier
    Ptr<Byte> ty;         // really Ptr<Type> (cast at use)
    Long      offset;     // byte offset from start of struct
}

// A struct declaration: tag name, list of fields, total size.
struct StructDef {
    Ptr<Byte> name;       // null-terminated tag
    Ptr<PtrVec> fields;   // PtrVec of Ptr<Field>
    Long      size;       // total size in bytes (sum of aligned fields)
    Long      align;      // alignment (max of fields' alignment)
}

// ---- Type constructors and predicates ----

// Allocate a fresh Type with given kind, all other fields zeroed.
Ptr<Type> type_new(Long kind) {
    Ptr<Byte> raw = alloc(40);    // sizeof(Type) = 8 + 8 + 8 + 8 + 8 = 40
    Ptr<Type> t = cast<Ptr<Type>>(raw);
    (*t).kind = kind;
    (*t).pointee = cast<Ptr<Type>>(null);
    (*t).elem    = cast<Ptr<Type>>(null);
    (*t).nelems  = 0;
    (*t).sdef    = null;
    return t;
}

Ptr<Type> type_simple(Long kind) {
    return type_new(kind);
}

Ptr<Type> type_ptr(Ptr<Type> pointee) {
    Ptr<Type> t = type_new(TY_PTR());
    (*t).pointee = pointee;
    return t;
}

Ptr<Type> type_array(Ptr<Type> elem, Long n) {
    Ptr<Type> t = type_new(TY_ARRAY());
    (*t).elem = elem;
    (*t).nelems = n;
    return t;
}

// Test two types for structural equality. Mirrors src/types.c::types_equal.
// Two types are equal if their kinds match and their inner structure
// matches (pointee for Ptr, sdef pointer identity for struct, elem+nelems
// for array). Simple types match by kind alone.
Boolean types_equal(Ptr<Type> a, Ptr<Type> b) {
    if ((*a).kind != (*b).kind) { return false; }
    if ((*a).kind == TY_PTR()) {
        if ((*a).pointee == cast<Ptr<Type>>(null)) { return false; }
        if ((*b).pointee == cast<Ptr<Type>>(null)) { return false; }
        return types_equal((*a).pointee, (*b).pointee);
    }
    if ((*a).kind == TY_STRUCT()) {
        return (*a).sdef == (*b).sdef;
    }
    if ((*a).kind == TY_ARRAY()) {
        if ((*a).elem == cast<Ptr<Type>>(null)) { return false; }
        if ((*b).elem == cast<Ptr<Type>>(null)) { return false; }
        if ((*a).nelems != (*b).nelems) { return false; }
        return types_equal((*a).elem, (*b).elem);
    }
    return true;
}

Ptr<Type> type_struct(Ptr<Byte> sdef) {
    Ptr<Type> t = type_new(TY_STRUCT());
    (*t).sdef = sdef;
    return t;
}

// Size in bytes of a value of the given type.
Long type_size(Ptr<Type> t) {
    Long k = (*t).kind;
    if (k == TY_BOOLEAN()) { return 1; }
    if (k == TY_CHAR())    { return 1; }
    if (k == TY_BYTE())    { return 1; }
    if (k == TY_INTEGER()) { return 2; }
    if (k == TY_UINTEGER()){ return 2; }
    if (k == TY_WHOLE())   { return 4; }
    if (k == TY_UWHOLE())  { return 4; }
    if (k == TY_LONG())    { return 8; }
    if (k == TY_ULONG())   { return 8; }
    if (k == TY_STRING())  { return 8; }
    if (k == TY_PTR())     { return 8; }
    if (k == TY_ARRAY()) {
        Long elem_sz = type_size((*t).elem);
        return elem_sz * (*t).nelems;
    }
    if (k == TY_STRUCT()) {
        // Cast the opaque sdef back to StructDef; size is precomputed.
        Ptr<StructDef> s = cast<Ptr<StructDef>>((*t).sdef);
        return (*s).size;
    }
    // TY_VOID, TY_UNKNOWN: zero size.
    return 0;
}

// True if `kind` is a signed integer type.
Boolean type_kind_is_signed_int(Long k) {
    if (k == TY_INTEGER()) { return true; }
    if (k == TY_WHOLE())   { return true; }
    if (k == TY_LONG())    { return true; }
    return false;
}

// True if `kind` is an unsigned integer type (excluding Boolean/Char/Byte).
Boolean type_kind_is_unsigned_int(Long k) {
    if (k == TY_UINTEGER()) { return true; }
    if (k == TY_UWHOLE())   { return true; }
    if (k == TY_ULONG())    { return true; }
    return false;
}

// True if `kind` is any integer-shaped type (signed/unsigned ints + Char/Byte).
Boolean type_kind_is_integer_shaped(Long k) {
    if (k == TY_CHAR())     { return true; }
    if (k == TY_BYTE())     { return true; }
    if (type_kind_is_signed_int(k))   { return true; }
    if (type_kind_is_unsigned_int(k)) { return true; }
    return false;
}

// String name of a type kind, for error messages. Returns a literal — caller
// must NOT free.
Ptr<Byte> type_kind_name(Long k) {
    if (k == TY_BOOLEAN())  { return cast<Ptr<Byte>>("Boolean"); }
    if (k == TY_CHAR())     { return cast<Ptr<Byte>>("Char"); }
    if (k == TY_BYTE())     { return cast<Ptr<Byte>>("Byte"); }
    if (k == TY_INTEGER())  { return cast<Ptr<Byte>>("Integer"); }
    if (k == TY_UINTEGER()) { return cast<Ptr<Byte>>("uInteger"); }
    if (k == TY_WHOLE())    { return cast<Ptr<Byte>>("Whole"); }
    if (k == TY_UWHOLE())   { return cast<Ptr<Byte>>("uWhole"); }
    if (k == TY_LONG())     { return cast<Ptr<Byte>>("Long"); }
    if (k == TY_ULONG())    { return cast<Ptr<Byte>>("uLong"); }
    if (k == TY_STRING())   { return cast<Ptr<Byte>>("String"); }
    if (k == TY_PTR())      { return cast<Ptr<Byte>>("Ptr<...>"); }
    if (k == TY_STRUCT())   { return cast<Ptr<Byte>>("struct"); }
    if (k == TY_ARRAY())    { return cast<Ptr<Byte>>("array"); }
    if (k == TY_VOID())     { return cast<Ptr<Byte>>("Void"); }
    return cast<Ptr<Byte>>("<unknown>");
}
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
// lazyc/compiler/ast.ml
//
// AST: Expression nodes, expression kinds, operator kinds.
// Statements come in 21f.
//
// All expression variants share one `Expr` struct (lazyc has no unions).
// Each variant uses the relevant subset of fields. Unused fields are
// zero/null. Memory cost is ~200 bytes per node, which is trivial for the
// compiler's working set.

// --- Expression kinds (must match src/ast.h enum order for the
//     eventual fixed-point test) ---
Long EX_NUMBER()      { return  0; }
Long EX_CHAR_LIT()    { return  1; }
Long EX_STRING_LIT()  { return  2; }
Long EX_BOOL_LIT()    { return  3; }
Long EX_IDENT()       { return  4; }
Long EX_BINARY()      { return  5; }
Long EX_UNARY()       { return  6; }
Long EX_CALL()        { return  7; }
Long EX_CAST()        { return  8; }
Long EX_ADDR_OF()     { return  9; }
Long EX_DEREF()       { return 10; }
Long EX_NULL()        { return 11; }
Long EX_FIELD()       { return 12; }
Long EX_INDEX()       { return 13; }

// --- Operator kinds ---
Long OP_ADD()  { return 0; }
Long OP_SUB()  { return 1; }
Long OP_MUL()  { return 2; }
Long OP_DIV()  { return 3; }
Long OP_MOD()  { return 4; }
Long OP_EQ()   { return 5; }
Long OP_NEQ()  { return 6; }
Long OP_LT()   { return 7; }
Long OP_GT()   { return 8; }
Long OP_LE()   { return 9; }
Long OP_GE()   { return 10; }
Long OP_NEG()  { return 11; }
Long OP_NOT()  { return 12; }

// Print a binary/unary operator's symbolic name. Mirrors the table in
// src/ast_print.c::op_name (used for AST dumping during cross-checks).
Ptr<Byte> op_name(Long o) {
    if (o == OP_ADD()) { return cast<Ptr<Byte>>("+"); }
    if (o == OP_SUB()) { return cast<Ptr<Byte>>("-"); }
    if (o == OP_MUL()) { return cast<Ptr<Byte>>("*"); }
    if (o == OP_DIV()) { return cast<Ptr<Byte>>("/"); }
    if (o == OP_MOD()) { return cast<Ptr<Byte>>("%"); }
    if (o == OP_EQ())  { return cast<Ptr<Byte>>("=="); }
    if (o == OP_NEQ()) { return cast<Ptr<Byte>>("!="); }
    if (o == OP_LT())  { return cast<Ptr<Byte>>("<"); }
    if (o == OP_GT())  { return cast<Ptr<Byte>>(">"); }
    if (o == OP_LE())  { return cast<Ptr<Byte>>("<="); }
    if (o == OP_GE())  { return cast<Ptr<Byte>>(">="); }
    if (o == OP_NEG()) { return cast<Ptr<Byte>>("neg"); }
    if (o == OP_NOT()) { return cast<Ptr<Byte>>("!"); }
    return cast<Ptr<Byte>>("?");
}

// One Expr node. The fields used for any given `kind` are documented
// inline. All other fields are null/0 and ignored.
struct Expr {
    Long      kind;             // EX_*
    Long      line;             // source line number
    Ptr<Type> ety;              // resolved type (set by typechecker; null until then)
    Long      is_untyped_int;   // for numeric literals before typing
    Long      is_untyped_null;  // for `null` literals before typing

    // Numeric/bool/char/null payload (overlapping uses):
    Long      num;              // EX_NUMBER: parsed integer value
    Long      char_val;         // EX_CHAR_LIT: resolved code point
    Long      bool_val;         // EX_BOOL_LIT: 0 or 1

    // String literal payload:
    Ptr<Byte> str_data;         // EX_STRING_LIT: raw inner bytes (escapes NOT resolved)
    Long      str_len;          // EX_STRING_LIT: byte length

    // Identifier / call / field name (overlapping):
    Ptr<Byte> name;             // EX_IDENT, EX_CALL, EX_FIELD: null-terminated
    Long      name_len;         // length excluding null

    // Operator code:
    Long      op;               // EX_BINARY, EX_UNARY: OP_*

    // First child Expr — used by:
    //   EX_BINARY (lhs), EX_UNARY (operand), EX_CAST (operand),
    //   EX_ADDR_OF (target), EX_DEREF (operand), EX_FIELD (operand),
    //   EX_INDEX (base)
    Ptr<Expr> child0;

    // Second child Expr — used by:
    //   EX_BINARY (rhs), EX_INDEX (index)
    Ptr<Expr> child1;

    // Call argument list (PtrVec of Ptr<Expr>):
    Ptr<PtrVec> call_args;      // EX_CALL only

    // Cast target type:
    Ptr<Type> cast_target;      // EX_CAST only

    // Field resolution: set by typechecker. Stored as Ptr<Byte> because
    // Field is in the Type/Field/StructDef cycle (see types.ml).
    Ptr<Byte> field_resolved;   // EX_FIELD only; null until typechecker
}

// Allocate a fresh Expr with all fields zeroed and the given kind/line.
Ptr<Expr> expr_new(Long kind, Long line) {
    // sizeof(Expr) = 14 fields * 8 bytes = 112... let me count exactly:
    //   kind, line, ety, is_untyped_int             4 * 8 = 32
    //   num, char_val, bool_val                     3 * 8 = 24
    //   str_data, str_len                           2 * 8 = 16
    //   name, name_len                              2 * 8 = 16
    //   op                                          1 * 8 =  8
    //   child0, child1                              2 * 8 = 16
    //   call_args                                   1 * 8 =  8
    //   cast_target                                 1 * 8 =  8
    //   field_resolved                              1 * 8 =  8
    // Total: 136 bytes. Round up: alloc 144 for safety margin.
    Ptr<Byte> raw = alloc(144);
    Ptr<Expr> e = cast<Ptr<Expr>>(raw);
    (*e).kind            = kind;
    (*e).line            = line;
    (*e).ety             = cast<Ptr<Type>>(null);
    (*e).is_untyped_int  = 0;
    (*e).is_untyped_null = 0;
    (*e).num             = 0;
    (*e).char_val        = 0;
    (*e).bool_val        = 0;
    (*e).str_data        = null;
    (*e).str_len         = 0;
    (*e).name            = null;
    (*e).name_len        = 0;
    (*e).op              = 0;
    (*e).child0          = cast<Ptr<Expr>>(null);
    (*e).child1          = cast<Ptr<Expr>>(null);
    (*e).call_args       = cast<Ptr<PtrVec>>(null);
    (*e).cast_target     = cast<Ptr<Type>>(null);
    (*e).field_resolved  = null;
    return e;
}
// lazyc/compiler/stmt.ml
//
// Statement nodes, parameter, function declaration, program. Mirrors the
// statement-side of src/ast.h. Like Expr, all variants share one Stmt
// struct; unused fields are zero/null and ignored based on `kind`.

// --- Statement kinds (must match src/ast.h enum order) ---
Long ST_VAR_DECL()    { return  0; }
Long ST_ASSIGN()      { return  1; }
Long ST_PTR_STORE()   { return  2; }
Long ST_FIELD_STORE() { return  3; }
Long ST_INDEX_STORE() { return  4; }
Long ST_IF()          { return  5; }
Long ST_WHILE()       { return  6; }
Long ST_FOR()         { return  7; }
Long ST_RETURN()      { return  8; }
Long ST_BREAK()       { return  9; }
Long ST_CONTINUE()    { return 10; }
Long ST_BLOCK()       { return 11; }
Long ST_EXPR()        { return 12; }

// One Stmt node. The fields used for any given `kind` are documented
// inline. All other fields are null/0 and ignored.
struct Stmt {
    Long kind;          // ST_*
    Long line;

    // ST_VAR_DECL: type + name + optional init expression
    Ptr<Type> var_ty;
    Ptr<Byte> var_name;          // ALSO used by ST_ASSIGN as the LHS name
    Long      var_name_len;
    Ptr<Expr> var_init;          // null if no initializer

    // ST_ASSIGN: var_name above + value
    // ST_PTR_STORE / ST_FIELD_STORE / ST_INDEX_STORE: target Expr + value Expr
    Ptr<Expr> assign_value;      // ST_ASSIGN value
    Ptr<Expr> store_target;      // ST_PTR/FIELD/INDEX_STORE target
    Ptr<Expr> store_value;       // ST_PTR/FIELD/INDEX_STORE value

    // ST_IF / ST_WHILE / ST_FOR: condition Expr
    Ptr<Expr> cond;

    // ST_IF: then-block + optional else-block
    Ptr<Stmt> then_b;
    Ptr<Stmt> else_b;

    // ST_WHILE / ST_FOR: body
    Ptr<Stmt> body;

    // ST_FOR: init Stmt + update Stmt (cond is `cond` above)
    Ptr<Stmt> for_init;
    Ptr<Stmt> for_update;

    // ST_RETURN: optional return value
    Ptr<Expr> ret_value;

    // ST_BLOCK: list of statements (PtrVec of Ptr<Stmt>)
    Ptr<PtrVec> block_stmts;

    // ST_EXPR: the expression
    Ptr<Expr> expr;
}

// Allocate a fresh Stmt with all fields zeroed and the given kind/line.
Ptr<Stmt> stmt_new(Long kind, Long line) {
    // 16 fields * 8 bytes = 128. Round up to 144 for safety.
    Ptr<Byte> raw = alloc(144);
    Ptr<Stmt> s = cast<Ptr<Stmt>>(raw);
    (*s).kind          = kind;
    (*s).line          = line;
    (*s).var_ty        = cast<Ptr<Type>>(null);
    (*s).var_name      = null;
    (*s).var_name_len  = 0;
    (*s).var_init      = cast<Ptr<Expr>>(null);
    (*s).assign_value  = cast<Ptr<Expr>>(null);
    (*s).store_target  = cast<Ptr<Expr>>(null);
    (*s).store_value   = cast<Ptr<Expr>>(null);
    (*s).cond          = cast<Ptr<Expr>>(null);
    (*s).then_b        = cast<Ptr<Stmt>>(null);
    (*s).else_b        = cast<Ptr<Stmt>>(null);
    (*s).body          = cast<Ptr<Stmt>>(null);
    (*s).for_init      = cast<Ptr<Stmt>>(null);
    (*s).for_update    = cast<Ptr<Stmt>>(null);
    (*s).ret_value     = cast<Ptr<Expr>>(null);
    (*s).block_stmts   = cast<Ptr<PtrVec>>(null);
    (*s).expr          = cast<Ptr<Expr>>(null);
    return s;
}

// A function parameter: type + name.
struct Param {
    Ptr<Type> ty;
    Ptr<Byte> name;           // null-terminated
    Long      name_len;
}

// A function declaration: return type, name, params, body, source line.
struct FuncDecl {
    Ptr<Type>   return_ty;
    Ptr<Byte>   name;          // null-terminated
    Long        name_len;
    Ptr<PtrVec> params;        // PtrVec of Ptr<Param>
    Ptr<Stmt>   body;          // ST_BLOCK (null if is_extern)
    Long        is_extern;     // 1 if this is `extern Type fn(...);`, else 0
    Long        line;
}

// A program: list of functions plus list of struct decls (structs come
// in 21g; for 21f the structs PtrVec is always empty).
struct Program {
    Ptr<PtrVec> funcs;         // PtrVec of Ptr<FuncDecl>
    Ptr<PtrVec> structs;       // PtrVec of Ptr<Byte> (opaque; 21g)
}

// ---- Constructors ----

Ptr<Param> param_new(Ptr<Type> ty, Ptr<Byte> name, Long name_len) {
    // sizeof(Param) = 24
    Ptr<Byte> raw = alloc(24);
    Ptr<Param> p = cast<Ptr<Param>>(raw);
    (*p).ty       = ty;
    (*p).name     = name;
    (*p).name_len = name_len;
    return p;
}

Ptr<FuncDecl> funcdecl_new(Long line) {
    // sizeof(FuncDecl) = 7 fields * 8 = 56
    Ptr<Byte> raw = alloc(56);
    Ptr<FuncDecl> f = cast<Ptr<FuncDecl>>(raw);
    (*f).return_ty = cast<Ptr<Type>>(null);
    (*f).name      = null;
    (*f).name_len  = 0;
    (*f).params    = cast<Ptr<PtrVec>>(null);
    (*f).body      = cast<Ptr<Stmt>>(null);
    (*f).is_extern = 0;
    (*f).line      = line;
    return f;
}

Ptr<Program> program_new() {
    // sizeof(Program) = 16
    Ptr<Byte> raw = alloc(16);
    Ptr<Program> pg = cast<Ptr<Program>>(raw);
    // Heap-allocate the PtrVec for funcs.
    Ptr<Byte> raw_funcs = alloc(24);
    Ptr<PtrVec> funcs = cast<Ptr<PtrVec>>(raw_funcs);
    ptrvec_init(funcs);
    Ptr<Byte> raw_structs = alloc(24);
    Ptr<PtrVec> structs = cast<Ptr<PtrVec>>(raw_structs);
    ptrvec_init(structs);
    (*pg).funcs   = funcs;
    (*pg).structs = structs;
    return pg;
}
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
// lazyc/compiler/parse_stmt.ml
//
// Statement, function, and (in 21g) struct declaration parser.
// Builds on parse.ml (which has parse_expr, parse_type, struct registry).
// Output: Ptr<Program> with lists of Ptr<FuncDecl> and Ptr<StructDef>.

// ---- Type-decoration helper ----
//
// In a variable or field declaration, after the name we may see `[N]` to
// turn the base type into a fixed-size array. Mirrors the C parser's
// wrap_with_array_suffix.
Ptr<Type> wrap_with_array_suffix(Ptr<Parser> p, Ptr<Type> base) {
    if (!parser_match(p, TOK_LBRACKET())) { return base; }
    if (!parser_check(p, TOK_NUMBER())) {
        parse_error(p, cast<Ptr<Byte>>("expected integer literal in array size"));
    }
    Ptr<Token> size_tok = parser_cur(p);
    Long n = (*size_tok).int_value;
    if (n <= 0) {
        parse_error(p, cast<Ptr<Byte>>("array size must be positive"));
    }
    if (n > 1000000) {
        parse_error(p, cast<Ptr<Byte>>("array size too large"));
    }
    parser_advance(p);
    parser_expect(p, TOK_RBRACKET(), cast<Ptr<Byte>>("expected ']' after array size"));
    return type_array(base, n);
}

// ---- Per-kind statement parsers ----

// Parse a variable declaration: TYPE NAME [= EXPR];
// Caller has verified that the current token starts a type.
Ptr<Stmt> parse_var_decl(Ptr<Parser> p) {
    Ptr<Token> first = parser_cur(p);
    Long line = (*first).line;
    Ptr<Stmt> s = parse_var_decl_no_semi(p);
    parser_expect(p, TOK_SEMI(), cast<Ptr<Byte>>("expected ';' after variable declaration"));
    // line was already set by no_semi version; keep as-is
    return s;
}

// Parse a variable declaration without trailing ';'. Used by `for` init.
Ptr<Stmt> parse_var_decl_no_semi(Ptr<Parser> p) {
    Ptr<Token> first = parser_cur(p);
    Long line = (*first).line;
    Ptr<Type> ty = parse_type(p);
    Ptr<Token> name_tok = parser_expect(p, TOK_IDENT(),
        cast<Ptr<Byte>>("expected variable name"));
    // After the name, accept an optional `[N]` array suffix to turn the
    // base type into a fixed-size array.
    ty = wrap_with_array_suffix(p, ty);
    Ptr<Stmt> s = stmt_new(ST_VAR_DECL(), line);
    (*s).var_ty       = ty;
    (*s).var_name     = (*name_tok).text;
    (*s).var_name_len = (*name_tok).text_len;
    if (parser_match(p, TOK_ASSIGN())) {
        (*s).var_init = parse_expr(p);
    }
    return s;
}

// Parse `name = expr` (used by for-init and for-update). No semicolon
// is consumed here; caller decides.
Ptr<Stmt> parse_assign_no_semi(Ptr<Parser> p) {
    Ptr<Token> name_tok = parser_expect(p, TOK_IDENT(),
        cast<Ptr<Byte>>("expected identifier on left of '='"));
    Long line = (*name_tok).line;
    parser_expect(p, TOK_ASSIGN(), cast<Ptr<Byte>>("expected '='"));
    Ptr<Expr> value = parse_expr(p);
    Ptr<Stmt> s = stmt_new(ST_ASSIGN(), line);
    (*s).var_name     = (*name_tok).text;
    (*s).var_name_len = (*name_tok).text_len;
    (*s).assign_value = value;
    return s;
}

// Parse a brace-delimited block.
Ptr<Stmt> parse_block(Ptr<Parser> p) {
    Ptr<Token> open = parser_expect(p, TOK_LBRACE(),
        cast<Ptr<Byte>>("expected '{' to begin block"));
    Long line = (*open).line;
    Ptr<Stmt> s = stmt_new(ST_BLOCK(), line);
    Ptr<Byte> raw = alloc(24);
    Ptr<PtrVec> stmts = cast<Ptr<PtrVec>>(raw);
    ptrvec_init(stmts);
    while (true) {
        if (parser_check(p, TOK_RBRACE())) { break; }
        if (parser_check(p, TOK_EOF())) {
            parse_error(p, cast<Ptr<Byte>>("unexpected EOF inside block"));
        }
        Ptr<Stmt> child = parse_stmt(p);
        ptrvec_push(stmts, cast<Ptr<Byte>>(child));
    }
    parser_expect(p, TOK_RBRACE(), cast<Ptr<Byte>>("expected '}' to close block"));
    (*s).block_stmts = stmts;
    return s;
}

// Parse a single statement.
Ptr<Stmt> parse_stmt(Ptr<Parser> p) {
    Ptr<Token> first = parser_cur(p);
    Long line = (*first).line;

    // Variable declaration: starts with a type-name token.
    if (is_type_start(p)) { return parse_var_decl(p); }

    // Block.
    if (parser_check(p, TOK_LBRACE())) { return parse_block(p); }

    // if (cond) { ... } [else { ... } | else if ...]
    if (parser_match(p, TOK_IF())) {
        parser_expect(p, TOK_LPAREN(), cast<Ptr<Byte>>("expected '(' after 'if'"));
        Ptr<Expr> if_cond = parse_expr(p);
        parser_expect(p, TOK_RPAREN(), cast<Ptr<Byte>>("expected ')'"));
        Ptr<Stmt> then_blk = parse_block(p);
        Ptr<Stmt> else_blk = cast<Ptr<Stmt>>(null);
        if (parser_match(p, TOK_ELSE())) {
            if (parser_check(p, TOK_IF())) { else_blk = parse_stmt(p); }
            else                            { else_blk = parse_block(p); }
        }
        Ptr<Stmt> s_if = stmt_new(ST_IF(), line);
        (*s_if).cond   = if_cond;
        (*s_if).then_b = then_blk;
        (*s_if).else_b = else_blk;
        return s_if;
    }

    // while (cond) { ... }
    if (parser_match(p, TOK_WHILE())) {
        parser_expect(p, TOK_LPAREN(), cast<Ptr<Byte>>("expected '(' after 'while'"));
        Ptr<Expr> while_cond = parse_expr(p);
        parser_expect(p, TOK_RPAREN(), cast<Ptr<Byte>>("expected ')'"));
        Ptr<Stmt> while_body = parse_block(p);
        Ptr<Stmt> s_while = stmt_new(ST_WHILE(), line);
        (*s_while).cond = while_cond;
        (*s_while).body = while_body;
        return s_while;
    }

    // for (init; cond; update) { ... }
    if (parser_match(p, TOK_FOR())) {
        parser_expect(p, TOK_LPAREN(), cast<Ptr<Byte>>("expected '('"));
        Ptr<Stmt> for_init_s = cast<Ptr<Stmt>>(null);
        if (!parser_check(p, TOK_SEMI())) {
            if (is_type_start(p)) { for_init_s = parse_var_decl_no_semi(p); }
            else                  { for_init_s = parse_assign_no_semi(p); }
        }
        parser_expect(p, TOK_SEMI(), cast<Ptr<Byte>>("expected ';' in for"));
        Ptr<Expr> for_cond = cast<Ptr<Expr>>(null);
        if (!parser_check(p, TOK_SEMI())) { for_cond = parse_expr(p); }
        parser_expect(p, TOK_SEMI(), cast<Ptr<Byte>>("expected ';' in for"));
        Ptr<Stmt> for_update_s = cast<Ptr<Stmt>>(null);
        if (!parser_check(p, TOK_RPAREN())) { for_update_s = parse_assign_no_semi(p); }
        parser_expect(p, TOK_RPAREN(), cast<Ptr<Byte>>("expected ')'"));
        Ptr<Stmt> for_body = parse_block(p);
        Ptr<Stmt> s_for = stmt_new(ST_FOR(), line);
        (*s_for).for_init   = for_init_s;
        (*s_for).cond       = for_cond;
        (*s_for).for_update = for_update_s;
        (*s_for).body       = for_body;
        return s_for;
    }

    // return [expr];
    if (parser_match(p, TOK_RETURN())) {
        Ptr<Expr> v = cast<Ptr<Expr>>(null);
        if (!parser_check(p, TOK_SEMI())) { v = parse_expr(p); }
        parser_expect(p, TOK_SEMI(), cast<Ptr<Byte>>("expected ';' after return"));
        Ptr<Stmt> s_ret = stmt_new(ST_RETURN(), line);
        (*s_ret).ret_value = v;
        return s_ret;
    }

    // break;
    if (parser_match(p, TOK_BREAK())) {
        parser_expect(p, TOK_SEMI(), cast<Ptr<Byte>>("expected ';' after 'break'"));
        return stmt_new(ST_BREAK(), line);
    }

    // continue;
    if (parser_match(p, TOK_CONTINUE())) {
        parser_expect(p, TOK_SEMI(), cast<Ptr<Byte>>("expected ';' after 'continue'"));
        return stmt_new(ST_CONTINUE(), line);
    }

    // Lookahead: if `IDENT =` we have an assign.
    if (parser_check(p, TOK_IDENT())) {
        Ptr<Token> nxt = parser_peek_next(p);
        if ((*nxt).kind == TOK_ASSIGN()) {
            Ptr<Stmt> s_asn = parse_assign_no_semi(p);
            parser_expect(p, TOK_SEMI(), cast<Ptr<Byte>>("expected ';'"));
            return s_asn;
        }
    }

    // Otherwise, parse an expression and decide between:
    //   *p = e;       -- pointer store
    //   s.f = e;      -- field store
    //   arr[i] = e;   -- index store
    //   foo();        -- expression statement
    Ptr<Expr> e = parse_expr(p);
    if (parser_check(p, TOK_ASSIGN())) {
        parser_advance(p);
        Ptr<Expr> value = parse_expr(p);
        parser_expect(p, TOK_SEMI(), cast<Ptr<Byte>>("expected ';'"));
        Long ek = (*e).kind;
        Long sk = -1;
        if (ek == EX_DEREF()) { sk = ST_PTR_STORE(); }
        if (ek == EX_FIELD()) { sk = ST_FIELD_STORE(); }
        if (ek == EX_INDEX()) { sk = ST_INDEX_STORE(); }
        if (sk < 0) {
            parse_error(p, cast<Ptr<Byte>>("left side of '=' must be a variable, '*pointer', 'struct.field', or 'arr[index]'"));
        }
        Ptr<Stmt> s_store = stmt_new(sk, line);
        (*s_store).store_target = e;
        (*s_store).store_value  = value;
        return s_store;
    }
    parser_expect(p, TOK_SEMI(), cast<Ptr<Byte>>("expected ';'"));
    Ptr<Stmt> s_expr = stmt_new(ST_EXPR(), line);
    (*s_expr).expr = e;
    return s_expr;
}

// ---- Function declarations ----

// Parse one function: `RetType name(Type p1, Type p2, ...) { body }`.
Ptr<FuncDecl> parse_func(Ptr<Parser> p) {
    Ptr<Token> first = parser_cur(p);
    Long line = (*first).line;
    Long is_ext = 0;
    if (parser_check(p, TOK_EXTERN())) {
        is_ext = 1;
        parser_advance(p);
    }
    Ptr<Type> ret = parse_type(p);
    Ptr<Token> name_tok = parser_expect(p, TOK_IDENT(),
        cast<Ptr<Byte>>("expected function name"));
    parser_expect(p, TOK_LPAREN(), cast<Ptr<Byte>>("expected '('"));

    Ptr<Byte> raw_pv = alloc(24);
    Ptr<PtrVec> params = cast<Ptr<PtrVec>>(raw_pv);
    ptrvec_init(params);

    if (!parser_check(p, TOK_RPAREN())) {
        while (true) {
            Ptr<Type> pty = parse_type(p);
            Ptr<Token> pname = parser_expect(p, TOK_IDENT(),
                cast<Ptr<Byte>>("expected parameter name"));
            Ptr<Param> param = param_new(pty, (*pname).text, (*pname).text_len);
            ptrvec_push(params, cast<Ptr<Byte>>(param));
            if (!parser_match(p, TOK_COMMA())) { break; }
        }
    }
    parser_expect(p, TOK_RPAREN(), cast<Ptr<Byte>>("expected ')'"));

    Ptr<Stmt> body = cast<Ptr<Stmt>>(null);
    if (is_ext != 0) {
        parser_expect(p, TOK_SEMI(),
            cast<Ptr<Byte>>("expected ';' after extern declaration"));
    } else {
        body = parse_block(p);
    }

    Ptr<FuncDecl> f = funcdecl_new(line);
    (*f).return_ty = ret;
    (*f).name      = (*name_tok).text;
    (*f).name_len  = (*name_tok).text_len;
    (*f).params    = params;
    (*f).body      = body;
    (*f).is_extern = is_ext;
    return f;
}

// ---- Top-level program parser ----

// Parse a whole program: zero or more struct or function declarations,
// in any order, followed by EOF.
Ptr<Program> parse_program(Ptr<TokenList> tl) {
    Ptr<Program> pg = program_new();
    Parser p;
    parser_init(&p, tl);
    while (true) {
        if (parser_check(&p, TOK_EOF())) { break; }
        if (parser_check(&p, TOK_STRUCT())) {
            Ptr<StructDef> sd = parse_struct_decl(&p);
            ptrvec_push((*pg).structs, cast<Ptr<Byte>>(sd));
        } else {
            Ptr<FuncDecl> f = parse_func(&p);
            ptrvec_push((*pg).funcs, cast<Ptr<Byte>>(f));
        }
    }
    return pg;
}
// lazyc/compiler/ast_print.ml
//
// Print AST nodes in the same text format as src/ast_print.c, so that
// AST dumps can be diffed across compilers for cross-validation.
//
// Step 21e: expression printing only. Statements come in 21f.

// Print n levels of indentation (2 spaces each).
Long ast_print_indent(Long d) {
    Long i = 0;
    while (i < d) {
        print("  ");
        i = i + 1;
    }
    return 0;
}

// Print a Ptr<Type> as the type name. Mirrors src/ast_print.c::type_name
// — note this prints the SHORT form ("Ptr" not "Ptr<...>") to match.
Long ast_print_type_short(Ptr<Type> t) {
    if (t == cast<Ptr<Type>>(null)) {
        print("?");
        return 0;
    }
    Long k = (*t).kind;
    if (k == TY_BOOLEAN())  { print("Boolean");  return 0; }
    if (k == TY_CHAR())     { print("Char");     return 0; }
    if (k == TY_BYTE())     { print("Byte");     return 0; }
    if (k == TY_INTEGER())  { print("Integer");  return 0; }
    if (k == TY_UINTEGER()) { print("uInteger"); return 0; }
    if (k == TY_WHOLE())    { print("Whole");    return 0; }
    if (k == TY_UWHOLE())   { print("uWhole");   return 0; }
    if (k == TY_LONG())     { print("Long");     return 0; }
    if (k == TY_ULONG())    { print("uLong");    return 0; }
    if (k == TY_STRING())   { print("String");   return 0; }
    if (k == TY_PTR())      { print("Ptr");      return 0; }
    if (k == TY_STRUCT())   { print("struct");   return 0; }
    if (k == TY_VOID())     { print("void");     return 0; }
    print("?");
    return 0;
}

// If e->ety is set (typechecker has run), print " :TypeName". Otherwise
// nothing. Mirrors C ast_print.c::ty_suffix exactly.
Long ast_ty_suffix(Ptr<Expr> e) {
    Ptr<Type> t = (*e).ety;
    if (t == cast<Ptr<Type>>(null)) { return 0; }
    if ((*t).kind == TY_UNKNOWN()) { return 0; }
    print(" :");
    ast_print_type_short(t);
    return 0;
}

// Print one expression node and its children, recursively, indented.
Long ast_print_expr(Ptr<Expr> e, Long d) {
    ast_print_indent(d);
    Long k = (*e).kind;

    if (k == EX_NUMBER()) {
        print("Number ");
        // We need to print a Long without %l format... use println? Actually
        // we have buf_push_long for buffers, but here we're streaming to
        // stdout. Use println but suppress its newline by streaming pieces.
        // Easiest: build into a Buf, then write_bytes. But we don't have
        // raw write_bytes exposed. Use println to emit the number alone.
        // The C compiler prints "Number %lld" then ty_suffix then '\n'.
        // We approximate with println("%l", ...) which adds a newline, so
        // we need a no-newline version. lazyc has only print/println; the
        // print function does NOT add a newline. Use it.
        print("%l", (*e).num);
        ast_ty_suffix(e);
        println("");
        return 0;
    }
    if (k == EX_CHAR_LIT()) {
        print("Char '%c'", cast<Char>((*e).char_val));
        ast_ty_suffix(e);
        println("");
        return 0;
    }
    if (k == EX_STRING_LIT()) {
        // C uses printf("%.*s") to print the slice without the
        // surrounding quotes added by lazyc. For us, str_data is the
        // raw inner content already.
        print("String \"%s\"", cast<String>((*e).str_data));
        ast_ty_suffix(e);
        println("");
        return 0;
    }
    if (k == EX_BOOL_LIT()) {
        if ((*e).bool_val == 1) { print("Bool true"); }
        else                    { print("Bool false"); }
        ast_ty_suffix(e);
        println("");
        return 0;
    }
    if (k == EX_NULL()) {
        print("Null");
        ast_ty_suffix(e);
        println("");
        return 0;
    }
    if (k == EX_IDENT()) {
        print("Ident %s", cast<String>((*e).name));
        ast_ty_suffix(e);
        println("");
        return 0;
    }
    if (k == EX_BINARY()) {
        print("Binary %s", cast<String>(op_name((*e).op)));
        ast_ty_suffix(e);
        println("");
        ast_print_expr((*e).child0, d + 1);
        ast_print_expr((*e).child1, d + 1);
        return 0;
    }
    if (k == EX_UNARY()) {
        print("Unary %s", cast<String>(op_name((*e).op)));
        ast_ty_suffix(e);
        println("");
        ast_print_expr((*e).child0, d + 1);
        return 0;
    }
    if (k == EX_CALL()) {
        print("Call %s", cast<String>((*e).name));
        ast_ty_suffix(e);
        println("");
        Ptr<PtrVec> args = (*e).call_args;
        if (args != cast<Ptr<PtrVec>>(null)) {
            Long n = (*args).count;
            Long i = 0;
            while (i < n) {
                Ptr<Expr> a = cast<Ptr<Expr>>(ptrvec_get(args, i));
                ast_print_expr(a, d + 1);
                i = i + 1;
            }
        }
        return 0;
    }
    if (k == EX_CAST()) {
        print("Cast<");
        ast_print_type_short((*e).cast_target);
        print(">");
        ast_ty_suffix(e);
        println("");
        ast_print_expr((*e).child0, d + 1);
        return 0;
    }
    if (k == EX_ADDR_OF()) {
        print("AddrOf");
        ast_ty_suffix(e);
        println("");
        ast_print_expr((*e).child0, d + 1);
        return 0;
    }
    if (k == EX_DEREF()) {
        print("Deref");
        ast_ty_suffix(e);
        println("");
        ast_print_expr((*e).child0, d + 1);
        return 0;
    }
    if (k == EX_FIELD()) {
        print("Field .%s", cast<String>((*e).name));
        ast_ty_suffix(e);
        println("");
        ast_print_expr((*e).child0, d + 1);
        return 0;
    }
    if (k == EX_INDEX()) {
        print("Index");
        ast_ty_suffix(e);
        println("");
        ast_print_expr((*e).child0, d + 1);
        ast_print_expr((*e).child1, d + 1);
        return 0;
    }
    println("?Expr kind=%l", k);
    return 0;
}
// lazyc/compiler/ast_print_stmt.ml
//
// Statement and program AST printer. Matches the format of
// src/ast_print.c::print_stmt and print_program.

Long ast_print_stmt(Ptr<Stmt> s, Long d) {
    ast_print_indent(d);
    Long k = (*s).kind;

    if (k == ST_VAR_DECL()) {
        print("VarDecl ");
        ast_print_type_short((*s).var_ty);
        println(" %s", cast<String>((*s).var_name));
        if ((*s).var_init != cast<Ptr<Expr>>(null)) {
            ast_print_expr((*s).var_init, d + 1);
        }
        return 0;
    }
    if (k == ST_ASSIGN()) {
        println("Assign %s", cast<String>((*s).var_name));
        ast_print_expr((*s).assign_value, d + 1);
        return 0;
    }
    if (k == ST_PTR_STORE()) {
        println("PtrStore");
        ast_print_expr((*s).store_target, d + 1);
        ast_print_expr((*s).store_value, d + 1);
        return 0;
    }
    if (k == ST_FIELD_STORE()) {
        println("FieldStore");
        ast_print_expr((*s).store_target, d + 1);
        ast_print_expr((*s).store_value, d + 1);
        return 0;
    }
    if (k == ST_INDEX_STORE()) {
        println("IndexStore");
        ast_print_expr((*s).store_target, d + 1);
        ast_print_expr((*s).store_value, d + 1);
        return 0;
    }
    if (k == ST_IF()) {
        println("If");
        ast_print_expr((*s).cond, d + 1);
        ast_print_indent(d);
        println("Then:");
        ast_print_stmt((*s).then_b, d + 1);
        if ((*s).else_b != cast<Ptr<Stmt>>(null)) {
            ast_print_indent(d);
            println("Else:");
            ast_print_stmt((*s).else_b, d + 1);
        }
        return 0;
    }
    if (k == ST_WHILE()) {
        println("While");
        ast_print_expr((*s).cond, d + 1);
        ast_print_stmt((*s).body, d + 1);
        return 0;
    }
    if (k == ST_FOR()) {
        println("For");
        if ((*s).for_init != cast<Ptr<Stmt>>(null)) {
            ast_print_indent(d + 1);
            println("Init:");
            ast_print_stmt((*s).for_init, d + 2);
        }
        if ((*s).cond != cast<Ptr<Expr>>(null)) {
            ast_print_indent(d + 1);
            println("Cond:");
            ast_print_expr((*s).cond, d + 2);
        }
        if ((*s).for_update != cast<Ptr<Stmt>>(null)) {
            ast_print_indent(d + 1);
            println("Update:");
            ast_print_stmt((*s).for_update, d + 2);
        }
        ast_print_stmt((*s).body, d + 1);
        return 0;
    }
    if (k == ST_RETURN()) {
        println("Return");
        if ((*s).ret_value != cast<Ptr<Expr>>(null)) {
            ast_print_expr((*s).ret_value, d + 1);
        }
        return 0;
    }
    if (k == ST_BREAK()) {
        println("Break");
        return 0;
    }
    if (k == ST_CONTINUE()) {
        println("Continue");
        return 0;
    }
    if (k == ST_BLOCK()) {
        println("Block");
        Ptr<PtrVec> stmts = (*s).block_stmts;
        if (stmts != cast<Ptr<PtrVec>>(null)) {
            Long n = (*stmts).count;
            Long i = 0;
            while (i < n) {
                Ptr<Stmt> child = cast<Ptr<Stmt>>(ptrvec_get(stmts, i));
                ast_print_stmt(child, d + 1);
                i = i + 1;
            }
        }
        return 0;
    }
    if (k == ST_EXPR()) {
        println("ExprStmt");
        ast_print_expr((*s).expr, d + 1);
        return 0;
    }
    println("?Stmt kind=%l", k);
    return 0;
}

// Print one function declaration, matching the C compiler's
// "Func RetType name(P1Ty p1, P2Ty p2, ...)" header line. For extern
// declarations the header reads "Extern RetType name(...)" and no body
// follows.
Long ast_print_func(Ptr<FuncDecl> f) {
    if ((*f).is_extern != 0) {
        print("Extern ");
    } else {
        print("Func ");
    }
    ast_print_type_short((*f).return_ty);
    print(" %s(", cast<String>((*f).name));

    Ptr<PtrVec> params = (*f).params;
    if (params != cast<Ptr<PtrVec>>(null)) {
        Long n = (*params).count;
        Long i = 0;
        while (i < n) {
            if (i > 0) { print(", "); }
            Ptr<Param> param = cast<Ptr<Param>>(ptrvec_get(params, i));
            ast_print_type_short((*param).ty);
            print(" %s", cast<String>((*param).name));
            i = i + 1;
        }
    }
    println(")");
    if ((*f).is_extern == 0) {
        ast_print_stmt((*f).body, 1);
    }
    return 0;
}

// Print the whole program: every function in declaration order.
// Structs are NOT printed (matches the C compiler's --ast-raw output).
Long ast_print_program(Ptr<Program> pg) {
    Ptr<PtrVec> funcs = (*pg).funcs;
    Long n = (*funcs).count;
    Long i = 0;
    while (i < n) {
        Ptr<FuncDecl> f = cast<Ptr<FuncDecl>>(ptrvec_get(funcs, i));
        ast_print_func(f);
        i = i + 1;
    }
    return 0;
}
// lazyc/compiler/typecheck.ml
//
// Typechecker for lazyc. Step 21h.
//
// Mirrors src/typecheck.c. The post-condition of typecheck_program is
// that every Expr node has its `ety` field set, EX_FIELD nodes have
// `field_resolved` filled in, and the program has been validated for
// type errors. Typed nulls and typed integer literals lose their
// "untyped" flag once coerced to a concrete type.
//
// Implementation notes:
//   * Symbol table = TcCtx with a PtrVec of Ptr<TcSym>. One per function.
//   * Function table = a PtrVec of Ptr<FuncSig>. Built once at program start.
//   * Loop depth tracked on TcCtx so break/continue can be validated.
//   * tc_error prints to stdout and exits 1 (matching the C compiler's
//     behavior, just routed through stdout instead of stderr — lazyc's
//     println goes to stdout).

// ---- Type predicates ----

Boolean is_signed_numeric_kind(Long k) {
    if (k == TY_INTEGER()) { return true; }
    if (k == TY_WHOLE())   { return true; }
    if (k == TY_LONG())    { return true; }
    return false;
}

Boolean is_unsigned_numeric_kind(Long k) {
    if (k == TY_UINTEGER()) { return true; }
    if (k == TY_UWHOLE())   { return true; }
    if (k == TY_ULONG())    { return true; }
    return false;
}

Boolean is_numeric_kind(Long k) {
    if (is_signed_numeric_kind(k))   { return true; }
    if (is_unsigned_numeric_kind(k)) { return true; }
    return false;
}

// type_size in BYTES for a given TypeKind. Used by promote_numeric and
// implicitly_assignable. Different from types.ml's type_size which works
// on Ptr<Type> and handles structs/arrays. This one mirrors the C
// typechecker's static type_size which is purely for numeric size compare.
Long tc_type_size_kind(Long k) {
    if (k == TY_BOOLEAN())  { return 1; }
    if (k == TY_CHAR())     { return 1; }
    if (k == TY_BYTE())     { return 1; }
    if (k == TY_INTEGER())  { return 2; }
    if (k == TY_UINTEGER()) { return 2; }
    if (k == TY_WHOLE())    { return 4; }
    if (k == TY_UWHOLE())   { return 4; }
    if (k == TY_LONG())     { return 8; }
    if (k == TY_ULONG())    { return 8; }
    if (k == TY_STRING())   { return 8; }
    if (k == TY_PTR())      { return 8; }
    return 0;
}

// Print a type-kind's name. Used by tc_error messages.
Ptr<Byte> tc_type_name_kind(Long k) {
    if (k == TY_BOOLEAN())  { return cast<Ptr<Byte>>("Boolean");  }
    if (k == TY_CHAR())     { return cast<Ptr<Byte>>("Char");     }
    if (k == TY_BYTE())     { return cast<Ptr<Byte>>("Byte");     }
    if (k == TY_INTEGER())  { return cast<Ptr<Byte>>("Integer");  }
    if (k == TY_UINTEGER()) { return cast<Ptr<Byte>>("uInteger"); }
    if (k == TY_WHOLE())    { return cast<Ptr<Byte>>("Whole");    }
    if (k == TY_UWHOLE())   { return cast<Ptr<Byte>>("uWhole");   }
    if (k == TY_LONG())     { return cast<Ptr<Byte>>("Long");     }
    if (k == TY_ULONG())    { return cast<Ptr<Byte>>("uLong");    }
    if (k == TY_STRING())   { return cast<Ptr<Byte>>("String");   }
    if (k == TY_PTR())      { return cast<Ptr<Byte>>("Ptr");      }
    if (k == TY_STRUCT())   { return cast<Ptr<Byte>>("struct");   }
    if (k == TY_VOID())     { return cast<Ptr<Byte>>("void");     }
    return cast<Ptr<Byte>>("?");
}

// True if the integer value v fits in a destination of kind k. Mirrors
// the C compiler's literal_fits range check.
Boolean literal_fits(Long v, Long k) {
    if (k == TY_BOOLEAN()) {
        if (v == 0) { return true; }
        if (v == 1) { return true; }
        return false;
    }
    if (k == TY_CHAR()) {
        if (v < 0)   { return false; }
        if (v > 127) { return false; }
        return true;
    }
    if (k == TY_BYTE()) {
        if (v < 0)   { return false; }
        if (v > 255) { return false; }
        return true;
    }
    if (k == TY_INTEGER()) {
        if (v < -32768) { return false; }
        if (v > 32767)  { return false; }
        return true;
    }
    if (k == TY_UINTEGER()) {
        if (v < 0)     { return false; }
        if (v > 65535) { return false; }
        return true;
    }
    if (k == TY_WHOLE()) {
        if (v < -2147483648) { return false; }
        if (v > 2147483647)  { return false; }
        return true;
    }
    if (k == TY_UWHOLE()) {
        if (v < 0)         { return false; }
        if (v > 4294967295){ return false; }
        return true;
    }
    if (k == TY_LONG())  { return true; }
    if (k == TY_ULONG()) {
        if (v < 0) { return false; }
        return true;
    }
    return false;
}

// ---- Type-error reporter ----
// Format strings here are kept simple (one or two %s/%l interpolations).
// The C version supports varargs; we don't, so we accept a fixed set of
// shapes and use overloading by suffix.
Long tc_error_simple(Long line, Ptr<Byte> msg) {
    println("type error at line %l: %s", line, cast<String>(msg));
    exit(1);
    return 0;
}
Long tc_error_one(Long line, Ptr<Byte> prefix, Ptr<Byte> a) {
    println("type error at line %l: %s %s", line,
            cast<String>(prefix), cast<String>(a));
    exit(1);
    return 0;
}
Long tc_error_two(Long line, Ptr<Byte> prefix, Ptr<Byte> a,
                  Ptr<Byte> mid, Ptr<Byte> b) {
    println("type error at line %l: %s %s %s %s", line,
            cast<String>(prefix), cast<String>(a),
            cast<String>(mid), cast<String>(b));
    exit(1);
    return 0;
}

// ---- Symbol table ----
//
// One entry per (name -> Type) binding. Linear search; ~dozens of
// entries per function in practice.
struct TcSym {
    Ptr<Byte> name;          // null-terminated
    Ptr<Type> ty;
}

Ptr<TcSym> tcsym_new(Ptr<Byte> name, Ptr<Type> ty) {
    Ptr<Byte> raw = alloc(16);
    Ptr<TcSym> s = cast<Ptr<TcSym>>(raw);
    (*s).name = name;
    (*s).ty   = ty;
    return s;
}

// TcCtx is the per-function typechecking context. `func_return_ty` is
// the declared return type; `loop_depth` tracks nesting so break/continue
// can be validated. `funcs` is a borrowed pointer to the program-level
// function table.
struct TcCtx {
    Ptr<PtrVec> items;            // PtrVec of Ptr<TcSym>
    Ptr<Type>   func_return_ty;
    Ptr<PtrVec> funcs;            // PtrVec of Ptr<FuncSig>
    Long        loop_depth;
}

Long ctx_init(Ptr<TcCtx> c, Ptr<Type> ret, Ptr<PtrVec> funcs) {
    Ptr<Byte> raw = alloc(24);
    Ptr<PtrVec> items = cast<Ptr<PtrVec>>(raw);
    ptrvec_init(items);
    (*c).items          = items;
    (*c).func_return_ty = ret;
    (*c).funcs          = funcs;
    (*c).loop_depth     = 0;
    return 0;
}

// Linear lookup. Returns null if not found. Names are compared via
// lex_slice_eq (slice vs null-terminated).
Ptr<TcSym> ctx_find(Ptr<TcCtx> c, Ptr<Byte> name, Long name_len) {
    Ptr<PtrVec> items = (*c).items;
    Long n = (*items).count;
    Long i = 0;
    while (i < n) {
        Ptr<TcSym> s = cast<Ptr<TcSym>>(ptrvec_get(items, i));
        if (lex_slice_eq(name, name_len, (*s).name)) { return s; }
        i = i + 1;
    }
    return cast<Ptr<TcSym>>(null);
}

// Add a binding. Errors if `name` is already declared in this context.
// `name` is a slice (start + length). We need a null-terminated buffer
// for storage; lex_intern_slice would be ideal, but we don't have it —
// instead we rely on the fact that lazyc interns identifier text in
// the Token (null-terminated, lives forever) so we can reuse the source
// pointer. The tokens come from Token.text which IS null-terminated by
// the lexer.
Long ctx_add(Ptr<TcCtx> c, Ptr<Byte> name, Long name_len, Ptr<Type> ty, Long line) {
    Ptr<TcSym> existing = ctx_find(c, name, name_len);
    if (existing != cast<Ptr<TcSym>>(null)) {
        tc_error_one(line, cast<Ptr<Byte>>("redeclaration of"), name);
    }
    Ptr<TcSym> s = tcsym_new(name, ty);
    ptrvec_push((*c).items, cast<Ptr<Byte>>(s));
    return 0;
}

// ---- Function signatures ----
//
// Built once at program start from FuncDecls. Calls look up signatures
// to validate argument counts/types and resolve the call's return type.
struct FuncSig {
    Ptr<Byte>   name;
    Ptr<Type>   return_ty;
    Ptr<PtrVec> params;     // PtrVec of Ptr<Param>
}

Ptr<FuncSig> funcsig_new(Ptr<Byte> name, Ptr<Type> ret, Ptr<PtrVec> params) {
    Ptr<Byte> raw = alloc(24);
    Ptr<FuncSig> s = cast<Ptr<FuncSig>>(raw);
    (*s).name      = name;
    (*s).return_ty = ret;
    (*s).params    = params;
    return s;
}

Ptr<FuncSig> funcs_find(Ptr<PtrVec> ft, Ptr<Byte> name, Long name_len) {
    Long n = (*ft).count;
    Long i = 0;
    while (i < n) {
        Ptr<FuncSig> sig = cast<Ptr<FuncSig>>(ptrvec_get(ft, i));
        if (lex_slice_eq(name, name_len, (*sig).name)) { return sig; }
        i = i + 1;
    }
    return cast<Ptr<FuncSig>>(null);
}

Long funcs_add(Ptr<PtrVec> ft, Ptr<FuncDecl> f) {
    Ptr<FuncSig> existing = funcs_find(ft, (*f).name, (*f).name_len);
    if (existing != cast<Ptr<FuncSig>>(null)) {
        tc_error_one((*f).line, cast<Ptr<Byte>>("redefinition of function"), (*f).name);
    }
    Ptr<FuncSig> sig = funcsig_new((*f).name, (*f).return_ty, (*f).params);
    ptrvec_push(ft, cast<Ptr<Byte>>(sig));
    return 0;
}

// ---- Implicit assignability ----
//
// True if expression e can be implicitly converted to type `to`. Side
// effects: when an untyped literal or null is coerced, this function
// updates e's `ety` to the target type. To match the C compiler's
// observable behavior exactly, the `is_untyped_int` and
// `is_untyped_null` flags are NOT cleared here — the binary-op pre-
// pass clears them explicitly when it does its own coercion. Mirrors
// the C implicitly_assignable.
Boolean implicitly_assignable(Ptr<Expr> e, Ptr<Type> to) {
    if ((*e).is_untyped_null != 0) {
        if ((*to).kind == TY_PTR()) {
            (*e).ety = to;
            return true;
        }
        return false;
    }
    if ((*e).is_untyped_int != 0) {
        Long k = (*to).kind;
        Boolean can_coerce = false;
        if (is_numeric_kind(k))   { can_coerce = true; }
        if (k == TY_BYTE())       { can_coerce = true; }
        if (k == TY_CHAR())       { can_coerce = true; }
        if (can_coerce) {
            if (literal_fits((*e).num, k)) {
                (*e).ety = to;
                // NOTE: matching the C compiler, we DO NOT clear
                // is_untyped_int here. The binary-op pre-pass clears it
                // explicitly when it does its own coercion. Leaving the
                // flag set everywhere else has no observable effect on
                // accepted programs (codegen and the AST printer don't
                // consult it), but matters for byte-level fidelity at
                // the fixed-point test (21m).
                return true;
            }
            return false;
        }
    }
    if ((*e).ety == cast<Ptr<Type>>(null)) { return false; }
    if (types_equal((*e).ety, to)) { return true; }
    Long ek = (*(*e).ety).kind;
    Long tk = (*to).kind;
    if (is_numeric_kind(ek)) {
        if (is_numeric_kind(tk)) {
            Boolean from_signed = is_signed_numeric_kind(ek);
            Boolean to_signed   = is_signed_numeric_kind(tk);
            if (from_signed != to_signed) { return false; }
            if (tc_type_size_kind(ek) <= tc_type_size_kind(tk)) { return true; }
            return false;
        }
    }
    return false;
}

// Numeric promotion. Returns the wider of two same-signed numeric types,
// or a TY_UNKNOWN type if the operands aren't compatible. Mirrors the C
// promote_numeric.
Ptr<Type> promote_numeric(Ptr<Type> a, Ptr<Type> b) {
    Long ak = (*a).kind;
    Long bk = (*b).kind;
    if (!is_numeric_kind(ak)) { return type_simple(TY_UNKNOWN()); }
    if (!is_numeric_kind(bk)) { return type_simple(TY_UNKNOWN()); }
    if (is_signed_numeric_kind(ak) != is_signed_numeric_kind(bk)) {
        return type_simple(TY_UNKNOWN());
    }
    if (tc_type_size_kind(ak) >= tc_type_size_kind(bk)) { return a; }
    return b;
}

// ---- Expression typechecker ----
//
// Walks one Expr, sets ety, recursively descends. Errors on type
// problems by calling tc_error_*.
//
// Forward-declared in lecture order; lazyc resolves cross-function
// names globally so the forward declaration is implicit.

// Validate an EX_INDEX node: typecheck base and index, return the
// element type. Caller decides whether to enforce the
// "elem must not be aggregate" rule (yes for value-context, no for
// `&arr[i]` addr-of).
Ptr<Type> tc_index_resolve(Ptr<Expr> e, Ptr<TcCtx> ctx) {
    Ptr<Expr> base = (*e).child0;
    Ptr<Type> elem_ty = type_simple(TY_UNKNOWN());

    if ((*base).kind == EX_IDENT()) {
        Ptr<TcSym> s = ctx_find(ctx, (*base).name, (*base).name_len);
        if (s == cast<Ptr<TcSym>>(null)) {
            tc_error_one((*e).line, cast<Ptr<Byte>>("undefined variable"), (*base).name);
        }
        Long sk = (*(*s).ty).kind;
        if (sk == TY_ARRAY()) {
            (*base).ety = (*s).ty;
            elem_ty = (*(*s).ty).elem;
        } else {
            if (sk == TY_PTR()) {
                (*base).ety = (*s).ty;
                elem_ty = (*(*s).ty).pointee;
            } else {
                tc_error_one((*e).line,
                    cast<Ptr<Byte>>("cannot index; expected array or Ptr<T>, got"),
                    tc_type_name_kind(sk));
            }
        }
    } else {
        tc_expr(base, ctx);
        Long bk = (*(*base).ety).kind;
        if (bk == TY_PTR()) {
            elem_ty = (*(*base).ety).pointee;
        } else {
            if (bk == TY_ARRAY()) {
                elem_ty = (*(*base).ety).elem;
            } else {
                tc_error_one((*e).line,
                    cast<Ptr<Byte>>("cannot index; expected array or Ptr<T>, got"),
                    tc_type_name_kind(bk));
            }
        }
    }

    tc_expr((*e).child1, ctx);
    Ptr<Type> long_ty = type_simple(TY_LONG());
    if (!implicitly_assignable((*e).child1, long_ty)) {
        Long ik = TY_UNKNOWN();
        if ((*(*e).child1).ety != cast<Ptr<Type>>(null)) {
            ik = (*(*(*e).child1).ety).kind;
        }
        tc_error_one((*e).line,
            cast<Ptr<Byte>>("array index must be integer-shaped, got"),
            tc_type_name_kind(ik));
    }

    return elem_ty;
}

// The big one: typecheck one Expr node.
Long tc_expr(Ptr<Expr> e, Ptr<TcCtx> ctx) {
    Long k = (*e).kind;

    if (k == EX_NUMBER()) {
        (*e).ety = type_simple(TY_LONG());
        return 0;
    }
    if (k == EX_NULL()) {
        // Default null type: Ptr<Byte>. is_untyped_null stays set so
        // implicitly_assignable can re-coerce later.
        (*e).ety = type_ptr(type_simple(TY_BYTE()));
        return 0;
    }
    if (k == EX_BOOL_LIT()) {
        (*e).ety = type_simple(TY_BOOLEAN());
        return 0;
    }
    if (k == EX_CHAR_LIT()) {
        (*e).ety = type_simple(TY_CHAR());
        return 0;
    }
    if (k == EX_STRING_LIT()) {
        (*e).ety = type_simple(TY_STRING());
        return 0;
    }

    if (k == EX_IDENT()) {
        Ptr<TcSym> sy_id = ctx_find(ctx, (*e).name, (*e).name_len);
        if (sy_id == cast<Ptr<TcSym>>(null)) {
            tc_error_one((*e).line, cast<Ptr<Byte>>("undefined variable"), (*e).name);
        }
        Long sk = (*(*sy_id).ty).kind;
        if (sk == TY_STRUCT()) {
            tc_error_one((*e).line,
                cast<Ptr<Byte>>("cannot use struct value in an expression:"),
                (*e).name);
        }
        if (sk == TY_ARRAY()) {
            tc_error_one((*e).line,
                cast<Ptr<Byte>>("cannot use array value as a value:"),
                (*e).name);
        }
        (*e).ety = (*sy_id).ty;
        return 0;
    }

    if (k == EX_CAST()) {
        tc_expr((*e).child0, ctx);
        Long target_k = (*(*e).cast_target).kind;
        Ptr<Type> from = (*(*e).child0).ety;
        Long from_k = (*from).kind;

        if (target_k == TY_STRING()) {
            // Only Ptr<Byte> -> String is allowed.
            Boolean ok_to_str = false;
            if (from_k == TY_PTR()) {
                if ((*from).pointee != cast<Ptr<Type>>(null)) {
                    if ((*(*from).pointee).kind == TY_BYTE()) { ok_to_str = true; }
                }
            }
            if (!ok_to_str) {
                tc_error_one((*e).line,
                    cast<Ptr<Byte>>("cannot cast to String (only Ptr<Byte> -> String allowed); from"),
                    tc_type_name_kind(from_k));
            }
        } else {
            if (target_k == TY_VOID()) {
                tc_error_simple((*e).line, cast<Ptr<Byte>>("cannot cast to void"));
            }
        }
        // Cast FROM String: only allowed to Ptr<Byte>.
        if (from_k == TY_STRING()) {
            Boolean ok_from_str = false;
            if (target_k == TY_PTR()) {
                if ((*(*e).cast_target).pointee != cast<Ptr<Type>>(null)) {
                    if ((*(*(*e).cast_target).pointee).kind == TY_BYTE()) { ok_from_str = true; }
                }
            }
            if (!ok_from_str) {
                tc_error_simple((*e).line,
                    cast<Ptr<Byte>>("cannot cast from String (only String -> Ptr<Byte> allowed)"));
            }
        }
        (*e).ety = (*e).cast_target;
        return 0;
    }

    if (k == EX_ADDR_OF()) {
        Ptr<Expr> t = (*e).child0;
        Long tk = (*t).kind;
        if (tk == EX_IDENT()) {
            Ptr<TcSym> sy_addr = ctx_find(ctx, (*t).name, (*t).name_len);
            if (sy_addr == cast<Ptr<TcSym>>(null)) {
                tc_error_one((*e).line, cast<Ptr<Byte>>("undefined variable"), (*t).name);
            }
            (*t).ety = (*sy_addr).ty;
            (*e).ety = type_ptr((*sy_addr).ty);
            return 0;
        }
        if (tk == EX_FIELD()) {
            tc_expr(t, ctx);
            (*e).ety = type_ptr((*t).ety);
            return 0;
        }
        if (tk == EX_INDEX()) {
            Ptr<Type> addr_elem_ty = tc_index_resolve(t, ctx);
            (*t).ety = addr_elem_ty;
            (*e).ety = type_ptr(addr_elem_ty);
            return 0;
        }
        tc_error_simple((*e).line,
            cast<Ptr<Byte>>("'&' requires a variable, 'struct.field', or 'arr[index]' (lvalue)"));
        return 0;
    }

    if (k == EX_DEREF()) {
        tc_expr((*e).child0, ctx);
        Ptr<Type> pt = (*(*e).child0).ety;
        if ((*pt).kind != TY_PTR()) {
            tc_error_one((*e).line,
                cast<Ptr<Byte>>("'*' requires a pointer, got"),
                tc_type_name_kind((*pt).kind));
        }
        (*e).ety = (*pt).pointee;
        return 0;
    }

    if (k == EX_FIELD()) {
        Ptr<Expr> f_op = (*e).child0;
        Ptr<StructDef> sd = cast<Ptr<StructDef>>(null);
        Long opk = (*f_op).kind;
        if (opk == EX_IDENT()) {
            Ptr<TcSym> sy_fld = ctx_find(ctx, (*f_op).name, (*f_op).name_len);
            if (sy_fld == cast<Ptr<TcSym>>(null)) {
                tc_error_one((*e).line, cast<Ptr<Byte>>("undefined variable"), (*f_op).name);
            }
            if ((*(*sy_fld).ty).kind != TY_STRUCT()) {
                tc_error_one((*e).line,
                    cast<Ptr<Byte>>("'.field' requires a struct value, got"),
                    tc_type_name_kind((*(*sy_fld).ty).kind));
            }
            (*f_op).ety = (*sy_fld).ty;
            sd = cast<Ptr<StructDef>>((*(*sy_fld).ty).sdef);
        } else {
            if (opk == EX_DEREF()) {
                tc_expr(f_op, ctx);
                if ((*(*f_op).ety).kind != TY_STRUCT()) {
                    tc_error_one((*e).line,
                        cast<Ptr<Byte>>("'.field' through pointer requires Ptr<struct>, pointee is"),
                        tc_type_name_kind((*(*f_op).ety).kind));
                }
                sd = cast<Ptr<StructDef>>((*(*f_op).ety).sdef);
            } else {
                tc_error_simple((*e).line,
                    cast<Ptr<Byte>>("field access requires a struct variable or '*ptr-to-struct' on the left"));
            }
        }
        // Resolve the field by name.
        Ptr<Field> resolved = find_field((*sd).fields, (*e).name, (*e).name_len);
        if (resolved == cast<Ptr<Field>>(null)) {
            tc_error_two((*e).line,
                cast<Ptr<Byte>>("struct"), (*sd).name,
                cast<Ptr<Byte>>("has no field"), (*e).name);
        }
        (*e).field_resolved = cast<Ptr<Byte>>(resolved);
        (*e).ety = cast<Ptr<Type>>((*resolved).ty);
        return 0;
    }

    if (k == EX_INDEX()) {
        Ptr<Type> elem_ty = tc_index_resolve(e, ctx);
        Long ek = (*elem_ty).kind;
        if (ek == TY_STRUCT()) {
            tc_error_one((*e).line,
                cast<Ptr<Byte>>("indexing yields aggregate; use &arr[i] to get a pointer:"),
                tc_type_name_kind(ek));
        }
        if (ek == TY_ARRAY()) {
            tc_error_one((*e).line,
                cast<Ptr<Byte>>("indexing yields aggregate; use &arr[i] to get a pointer:"),
                tc_type_name_kind(ek));
        }
        (*e).ety = elem_ty;
        return 0;
    }

    if (k == EX_UNARY()) {
        tc_expr((*e).child0, ctx);
        Long u_op = (*e).op;
        Ptr<Type> ot = (*(*e).child0).ety;
        if (u_op == OP_NOT()) {
            if ((*ot).kind != TY_BOOLEAN()) {
                tc_error_one((*e).line,
                    cast<Ptr<Byte>>("operator '!' requires Boolean, got"),
                    tc_type_name_kind((*ot).kind));
            }
            (*e).ety = type_simple(TY_BOOLEAN());
            return 0;
        }
        // OP_NEG
        if (!is_signed_numeric_kind((*ot).kind)) {
            tc_error_one((*e).line,
                cast<Ptr<Byte>>("unary '-' requires a signed numeric type, got"),
                tc_type_name_kind((*ot).kind));
        }
        (*e).ety = ot;
        // Constant-fold -<literal>.
        if ((*(*e).child0).is_untyped_int != 0) {
            Long u_folded = 0 - (*(*e).child0).num;
            (*e).kind = EX_NUMBER();
            (*e).is_untyped_int = 1;
            (*e).num = u_folded;
        }
        return 0;
    }

    if (k == EX_BINARY()) {
        tc_expr((*e).child0, ctx);
        tc_expr((*e).child1, ctx);

        // Untyped-int coercion to the typed sibling.
        if ((*(*e).child0).is_untyped_int != 0) {
            if ((*(*e).child1).is_untyped_int == 0) {
                if (is_numeric_kind((*(*(*e).child1).ety).kind)) {
                    if (literal_fits((*(*e).child0).num, (*(*(*e).child1).ety).kind)) {
                        (*(*e).child0).ety = (*(*e).child1).ety;
                        (*(*e).child0).is_untyped_int = 0;
                    }
                }
            }
        }
        if ((*(*e).child1).is_untyped_int != 0) {
            if ((*(*e).child0).is_untyped_int == 0) {
                if (is_numeric_kind((*(*(*e).child0).ety).kind)) {
                    if (literal_fits((*(*e).child1).num, (*(*(*e).child0).ety).kind)) {
                        (*(*e).child1).ety = (*(*e).child0).ety;
                        (*(*e).child1).is_untyped_int = 0;
                    }
                }
            }
        }
        // Untyped-null coercion to typed-pointer sibling.
        if ((*(*e).child0).is_untyped_null != 0) {
            if ((*(*(*e).child1).ety).kind == TY_PTR()) {
                (*(*e).child0).ety = (*(*e).child1).ety;
                (*(*e).child0).is_untyped_null = 0;
            }
        }
        if ((*(*e).child1).is_untyped_null != 0) {
            if ((*(*(*e).child0).ety).kind == TY_PTR()) {
                (*(*e).child1).ety = (*(*e).child0).ety;
                (*(*e).child1).is_untyped_null = 0;
            }
        }

        Ptr<Type> L = (*(*e).child0).ety;
        Ptr<Type> R = (*(*e).child1).ety;
        Long Lk = (*L).kind;
        Long Rk = (*R).kind;
        Long b_op = (*e).op;

        // Pointer arithmetic and pointer comparisons.
        Boolean any_ptr = false;
        if (Lk == TY_PTR()) { any_ptr = true; }
        if (Rk == TY_PTR()) { any_ptr = true; }
        if (any_ptr) {
            Boolean is_muldivmod = false;
            if (b_op == OP_MUL()) { is_muldivmod = true; }
            if (b_op == OP_DIV()) { is_muldivmod = true; }
            if (b_op == OP_MOD()) { is_muldivmod = true; }
            if (is_muldivmod) {
                tc_error_simple((*e).line,
                    cast<Ptr<Byte>>("cannot apply '*' '/' or '%' to pointers"));
            }
            if (b_op == OP_ADD()) {
                Ptr<Type> long_ty = type_simple(TY_LONG());
                if (Lk == TY_PTR()) {
                    if (implicitly_assignable((*e).child1, long_ty)) {
                        (*e).ety = L; return 0;
                    }
                }
                if (Rk == TY_PTR()) {
                    if (implicitly_assignable((*e).child0, long_ty)) {
                        (*e).ety = R; return 0;
                    }
                }
                tc_error_simple((*e).line,
                    cast<Ptr<Byte>>("pointer addition needs Ptr<T> + Long"));
            }
            if (b_op == OP_SUB()) {
                if (Lk == TY_PTR()) {
                    if (Rk == TY_PTR()) {
                        if (!types_equal(L, R)) {
                            tc_error_simple((*e).line,
                                cast<Ptr<Byte>>("pointer subtraction requires same pointee type"));
                        }
                        (*e).ety = type_simple(TY_LONG());
                        return 0;
                    }
                }
                Ptr<Type> long_ty_sub = type_simple(TY_LONG());
                if (Lk == TY_PTR()) {
                    if (implicitly_assignable((*e).child1, long_ty_sub)) {
                        (*e).ety = L; return 0;
                    }
                }
                tc_error_simple((*e).line,
                    cast<Ptr<Byte>>("pointer subtraction needs Ptr<T> - Long or Ptr<T> - Ptr<T>"));
            }
            Boolean is_eq = false;
            if (b_op == OP_EQ())  { is_eq = true; }
            if (b_op == OP_NEQ()) { is_eq = true; }
            if (is_eq) {
                if (!types_equal(L, R)) {
                    tc_error_simple((*e).line,
                        cast<Ptr<Byte>>("pointer comparison requires same pointee type"));
                }
                (*e).ety = type_simple(TY_BOOLEAN());
                return 0;
            }
            Boolean is_ord = false;
            if (b_op == OP_LT()) { is_ord = true; }
            if (b_op == OP_GT()) { is_ord = true; }
            if (b_op == OP_LE()) { is_ord = true; }
            if (b_op == OP_GE()) { is_ord = true; }
            if (is_ord) {
                if (!types_equal(L, R)) {
                    tc_error_simple((*e).line,
                        cast<Ptr<Byte>>("pointer ordering requires same pointee type"));
                }
                (*e).ety = type_simple(TY_BOOLEAN());
                return 0;
            }
        }

        Boolean is_arith = false;
        if (b_op == OP_ADD()) { is_arith = true; }
        if (b_op == OP_SUB()) { is_arith = true; }
        if (b_op == OP_MUL()) { is_arith = true; }
        if (b_op == OP_DIV()) { is_arith = true; }
        if (b_op == OP_MOD()) { is_arith = true; }
        if (is_arith) {
            Ptr<Type> r_ar = promote_numeric(L, R);
            if ((*r_ar).kind == TY_UNKNOWN()) {
                tc_error_two((*e).line,
                    cast<Ptr<Byte>>("arithmetic on incompatible types:"),
                    tc_type_name_kind(Lk),
                    cast<Ptr<Byte>>("and"),
                    tc_type_name_kind(Rk));
            }
            (*e).ety = r_ar;
            // Constant-fold both-untyped-int.
            if ((*(*e).child0).is_untyped_int != 0) {
                if ((*(*e).child1).is_untyped_int != 0) {
                    Long fa = (*(*e).child0).num;
                    Long fb = (*(*e).child1).num;
                    Long folded = 0;
                    if (b_op == OP_ADD()) { folded = fa + fb; }
                    if (b_op == OP_SUB()) { folded = fa - fb; }
                    if (b_op == OP_MUL()) { folded = fa * fb; }
                    if (b_op == OP_DIV()) {
                        if (fb != 0) { folded = fa / fb; }
                    }
                    if (b_op == OP_MOD()) {
                        if (fb != 0) { folded = fa - (fa / fb) * fb; }
                    }
                    (*e).kind = EX_NUMBER();
                    (*e).is_untyped_int = 1;
                    (*e).num = folded;
                }
            }
            return 0;
        }
        Boolean is_eq2 = false;
        if (b_op == OP_EQ())  { is_eq2 = true; }
        if (b_op == OP_NEQ()) { is_eq2 = true; }
        if (is_eq2) {
            if (types_equal(L, R)) {
                (*e).ety = type_simple(TY_BOOLEAN()); return 0;
            }
            Ptr<Type> r_eq = promote_numeric(L, R);
            if ((*r_eq).kind == TY_UNKNOWN()) {
                tc_error_two((*e).line,
                    cast<Ptr<Byte>>("cannot compare for equality:"),
                    tc_type_name_kind(Lk),
                    cast<Ptr<Byte>>("and"),
                    tc_type_name_kind(Rk));
            }
            (*e).ety = type_simple(TY_BOOLEAN());
            return 0;
        }
        Boolean is_ord2 = false;
        if (b_op == OP_LT()) { is_ord2 = true; }
        if (b_op == OP_GT()) { is_ord2 = true; }
        if (b_op == OP_LE()) { is_ord2 = true; }
        if (b_op == OP_GE()) { is_ord2 = true; }
        if (is_ord2) {
            Ptr<Type> r_ord = promote_numeric(L, R);
            if ((*r_ord).kind == TY_UNKNOWN()) {
                tc_error_two((*e).line,
                    cast<Ptr<Byte>>("ordering requires numeric same-signed operands:"),
                    tc_type_name_kind(Lk),
                    cast<Ptr<Byte>>("and"),
                    tc_type_name_kind(Rk));
            }
            (*e).ety = type_simple(TY_BOOLEAN());
            return 0;
        }
        tc_error_simple((*e).line, cast<Ptr<Byte>>("internal: unknown binary op"));
        return 0;
    }

    if (k == EX_CALL()) {
        // Built-ins first: print/println/alloc/free/exit/readf/writef/argc/argv.
        Ptr<Byte> nm = (*e).name;
        Ptr<PtrVec> args = (*e).call_args;
        Long nargs = 0;
        if (args != cast<Ptr<PtrVec>>(null)) { nargs = (*args).count; }

        Boolean is_print   = ml_streq(nm, cast<Ptr<Byte>>("print"));
        Boolean is_println = ml_streq(nm, cast<Ptr<Byte>>("println"));
        Boolean is_pr = false;
        if (is_print)   { is_pr = true; }
        if (is_println) { is_pr = true; }
        if (is_pr) {
            return tc_call_print(e, ctx, is_println);
        }
        if (ml_streq(nm, cast<Ptr<Byte>>("alloc"))) {
            return tc_call_alloc(e, ctx);
        }
        if (ml_streq(nm, cast<Ptr<Byte>>("free"))) {
            return tc_call_free(e, ctx);
        }
        if (ml_streq(nm, cast<Ptr<Byte>>("exit"))) {
            return tc_call_exit(e, ctx);
        }
        if (ml_streq(nm, cast<Ptr<Byte>>("readf"))) {
            return tc_call_readf(e, ctx);
        }
        if (ml_streq(nm, cast<Ptr<Byte>>("writef"))) {
            return tc_call_writef(e, ctx);
        }
        if (ml_streq(nm, cast<Ptr<Byte>>("argc"))) {
            return tc_call_argc(e, ctx);
        }
        if (ml_streq(nm, cast<Ptr<Byte>>("argv"))) {
            return tc_call_argv(e, ctx);
        }
        // User-defined function.
        Ptr<FuncSig> sig = funcs_find((*ctx).funcs, nm, (*e).name_len);
        if (sig == cast<Ptr<FuncSig>>(null)) {
            tc_error_one((*e).line, cast<Ptr<Byte>>("call to undefined function"), nm);
        }
        Long want = (*(*sig).params).count;
        if (nargs != want) {
            tc_error_one((*e).line, cast<Ptr<Byte>>("argument count mismatch for"), nm);
        }
        Long i = 0;
        while (i < nargs) {
            Ptr<Expr> a = cast<Ptr<Expr>>(ptrvec_get(args, i));
            tc_expr(a, ctx);
            Ptr<Param> p = cast<Ptr<Param>>(ptrvec_get((*sig).params, i));
            if (!implicitly_assignable(a, (*p).ty)) {
                tc_error_one((*e).line,
                    cast<Ptr<Byte>>("argument type mismatch in call to"), nm);
            }
            i = i + 1;
        }
        (*e).ety = (*sig).return_ty;
        return 0;
    }

    println("type error at line %l: internal: unknown expr kind %l", (*e).line, k);
    exit(1);
    return 0;
}

// ---- Built-in calls (split out to avoid huge tc_expr) ----

// Helper: returns the argument count for a call. Treats null call_args
// as 0 (the parser allocates a PtrVec even for f() with no args, but
// being defensive here is harmless).
Long call_nargs(Ptr<Expr> e) {
    Ptr<PtrVec> args = (*e).call_args;
    if (args == cast<Ptr<PtrVec>>(null)) { return 0; }
    return (*args).count;
}

Long tc_call_alloc(Ptr<Expr> e, Ptr<TcCtx> ctx) {
    if (call_nargs(e) != 1) {
        tc_error_simple((*e).line, cast<Ptr<Byte>>("alloc expects exactly 1 argument"));
    }
    Ptr<PtrVec> args = (*e).call_args;
    Ptr<Expr> a0 = cast<Ptr<Expr>>(ptrvec_get(args, 0));
    tc_expr(a0, ctx);
    Ptr<Type> long_ty = type_simple(TY_LONG());
    if (!implicitly_assignable(a0, long_ty)) {
        tc_error_one((*e).line,
            cast<Ptr<Byte>>("alloc expects a Long size, got"),
            tc_type_name_kind((*(*a0).ety).kind));
    }
    (*e).ety = type_ptr(type_simple(TY_BYTE()));
    return 0;
}

Long tc_call_free(Ptr<Expr> e, Ptr<TcCtx> ctx) {
    if (call_nargs(e) != 1) {
        tc_error_simple((*e).line, cast<Ptr<Byte>>("free expects exactly 1 argument"));
    }
    Ptr<PtrVec> args = (*e).call_args;
    Ptr<Expr> a0 = cast<Ptr<Expr>>(ptrvec_get(args, 0));
    tc_expr(a0, ctx);
    Ptr<Type> byte_ptr = type_ptr(type_simple(TY_BYTE()));
    if (!implicitly_assignable(a0, byte_ptr)) {
        tc_error_one((*e).line,
            cast<Ptr<Byte>>("free expects Ptr<Byte>, got"),
            tc_type_name_kind((*(*a0).ety).kind));
    }
    (*e).ety = type_simple(TY_BOOLEAN());
    return 0;
}

Long tc_call_exit(Ptr<Expr> e, Ptr<TcCtx> ctx) {
    if (call_nargs(e) != 1) {
        tc_error_simple((*e).line, cast<Ptr<Byte>>("exit expects exactly 1 argument"));
    }
    Ptr<PtrVec> args = (*e).call_args;
    Ptr<Expr> a0 = cast<Ptr<Expr>>(ptrvec_get(args, 0));
    tc_expr(a0, ctx);
    Ptr<Type> long_ty = type_simple(TY_LONG());
    if (!implicitly_assignable(a0, long_ty)) {
        tc_error_one((*e).line,
            cast<Ptr<Byte>>("exit expects a Long code, got"),
            tc_type_name_kind((*(*a0).ety).kind));
    }
    (*e).ety = type_simple(TY_LONG());
    return 0;
}

Long tc_call_readf(Ptr<Expr> e, Ptr<TcCtx> ctx) {
    if (call_nargs(e) != 1) {
        tc_error_simple((*e).line, cast<Ptr<Byte>>("readf expects exactly 1 argument"));
    }
    Ptr<PtrVec> args = (*e).call_args;
    Ptr<Expr> a0 = cast<Ptr<Expr>>(ptrvec_get(args, 0));
    tc_expr(a0, ctx);
    Ptr<Type> str_ty = type_simple(TY_STRING());
    if (!implicitly_assignable(a0, str_ty)) {
        tc_error_one((*e).line,
            cast<Ptr<Byte>>("readf expects a String path, got"),
            tc_type_name_kind((*(*a0).ety).kind));
    }
    (*e).ety = type_ptr(type_simple(TY_BYTE()));
    return 0;
}

Long tc_call_writef(Ptr<Expr> e, Ptr<TcCtx> ctx) {
    if (call_nargs(e) != 2) {
        tc_error_simple((*e).line, cast<Ptr<Byte>>("writef expects exactly 2 arguments"));
    }
    Ptr<PtrVec> args = (*e).call_args;
    Ptr<Expr> a0 = cast<Ptr<Expr>>(ptrvec_get(args, 0));
    Ptr<Expr> a1 = cast<Ptr<Expr>>(ptrvec_get(args, 1));
    tc_expr(a0, ctx);
    tc_expr(a1, ctx);
    Ptr<Type> str_ty = type_simple(TY_STRING());
    Ptr<Type> byte_ptr = type_ptr(type_simple(TY_BYTE()));
    if (!implicitly_assignable(a0, str_ty)) {
        tc_error_one((*e).line,
            cast<Ptr<Byte>>("writef expects String path, got"),
            tc_type_name_kind((*(*a0).ety).kind));
    }
    if (!implicitly_assignable(a1, byte_ptr)) {
        tc_error_one((*e).line,
            cast<Ptr<Byte>>("writef expects Ptr<Byte> contents, got"),
            tc_type_name_kind((*(*a1).ety).kind));
    }
    (*e).ety = type_simple(TY_BOOLEAN());
    return 0;
}

Long tc_call_argc(Ptr<Expr> e, Ptr<TcCtx> ctx) {
    Ptr<PtrVec> args = (*e).call_args;
    Long n = 0;
    if (args != cast<Ptr<PtrVec>>(null)) { n = (*args).count; }
    if (n != 0) {
        tc_error_simple((*e).line, cast<Ptr<Byte>>("argc expects 0 arguments"));
    }
    (*e).ety = type_simple(TY_LONG());
    return 0;
}

Long tc_call_argv(Ptr<Expr> e, Ptr<TcCtx> ctx) {
    if (call_nargs(e) != 1) {
        tc_error_simple((*e).line, cast<Ptr<Byte>>("argv expects exactly 1 argument"));
    }
    Ptr<PtrVec> args = (*e).call_args;
    Ptr<Expr> a0 = cast<Ptr<Expr>>(ptrvec_get(args, 0));
    tc_expr(a0, ctx);
    Ptr<Type> long_ty = type_simple(TY_LONG());
    if (!implicitly_assignable(a0, long_ty)) {
        tc_error_one((*e).line,
            cast<Ptr<Byte>>("argv expects a Long index, got"),
            tc_type_name_kind((*(*a0).ety).kind));
    }
    (*e).ety = type_ptr(type_simple(TY_BYTE()));
    return 0;
}

// Format-string check for print/println. Validates that every %X in
// the format string is matched with a same-typed argument, and that
// no extras appear on either side. Sets the call's type to LONG (the
// C version uses TY_VOID, but our AST printer treats unknown-with-
// kind=LONG identically; double-check below).
Long tc_call_print(Ptr<Expr> e, Ptr<TcCtx> ctx, Boolean is_println) {
    Ptr<PtrVec> args = (*e).call_args;
    Long nargs = 0;
    if (args != cast<Ptr<PtrVec>>(null)) { nargs = (*args).count; }
    if (nargs < 1) {
        tc_error_simple((*e).line,
            cast<Ptr<Byte>>("print/println requires at least a format string"));
    }
    Ptr<Expr> fmt = cast<Ptr<Expr>>(ptrvec_get(args, 0));
    if ((*fmt).kind != EX_STRING_LIT()) {
        tc_error_simple((*e).line,
            cast<Ptr<Byte>>("print/println format must be a string literal"));
    }
    (*fmt).ety = type_simple(TY_STRING());

    Ptr<Byte> data = (*fmt).str_data;
    Long len = (*fmt).str_len;
    Long arg_idx = 1;
    Long i = 0;
    while (i < len) {
        Long c = cast<Long>(data[i]);
        if (c != 37) {     // '%' == 37
            i = i + 1;
            continue;
        }
        if (i + 1 >= len) {
            tc_error_simple((*e).line,
                cast<Ptr<Byte>>("trailing '%' in format string"));
        }
        Long spec = cast<Long>(data[i + 1]);
        i = i + 2;
        if (spec == 37) { continue; }   // '%%'

        Long want_kind = TY_UNKNOWN();
        if (spec == 99) { want_kind = TY_CHAR(); }      // 'c'
        if (spec == 105){ want_kind = TY_INTEGER(); }   // 'i'
        if (spec == 108){ want_kind = TY_LONG(); }      // 'l'
        if (spec == 115){ want_kind = TY_STRING(); }    // 's'
        if (want_kind == TY_UNKNOWN()) {
            tc_error_simple((*e).line,
                cast<Ptr<Byte>>("unknown format specifier (use %c %i %l %s or %%)"));
        }
        if (arg_idx >= nargs) {
            tc_error_simple((*e).line,
                cast<Ptr<Byte>>("format string has more specifiers than arguments"));
        }
        Ptr<Expr> a = cast<Ptr<Expr>>(ptrvec_get(args, arg_idx));
        arg_idx = arg_idx + 1;
        tc_expr(a, ctx);
        Ptr<Type> want = type_simple(want_kind);
        if (!implicitly_assignable(a, want)) {
            tc_error_one((*e).line,
                cast<Ptr<Byte>>("format argument type mismatch; expected"),
                tc_type_name_kind(want_kind));
        }
    }
    if (arg_idx != nargs) {
        tc_error_simple((*e).line,
            cast<Ptr<Byte>>("format string has fewer specifiers than arguments"));
    }
    (*e).ety = type_simple(TY_VOID());
    return 0;
}

// ---- Statement typechecker ----

Long tc_stmt(Ptr<Stmt> s, Ptr<TcCtx> ctx) {
    Long k = (*s).kind;

    if (k == ST_VAR_DECL()) {
        Long vk = (*(*s).var_ty).kind;
        Boolean is_bad = false;
        if (vk == TY_VOID())    { is_bad = true; }
        if (vk == TY_UNKNOWN()) { is_bad = true; }
        if (is_bad) {
            tc_error_simple((*s).line, cast<Ptr<Byte>>("invalid variable type"));
        }
        Ptr<Expr> init = (*s).var_init;
        if (vk == TY_STRUCT()) {
            if (init != cast<Ptr<Expr>>(null)) {
                tc_error_simple((*s).line,
                    cast<Ptr<Byte>>("struct variables cannot be initialized"));
            }
        }
        if (vk == TY_ARRAY()) {
            if (init != cast<Ptr<Expr>>(null)) {
                tc_error_simple((*s).line,
                    cast<Ptr<Byte>>("array variables cannot be initialized"));
            }
        }
        if (init != cast<Ptr<Expr>>(null)) {
            tc_expr(init, ctx);
            if (!implicitly_assignable(init, (*s).var_ty)) {
                tc_error_two((*s).line,
                    cast<Ptr<Byte>>("cannot initialize"),
                    tc_type_name_kind(vk),
                    cast<Ptr<Byte>>("with value of type"),
                    tc_type_name_kind((*(*init).ety).kind));
            }
        }
        ctx_add(ctx, (*s).var_name, (*s).var_name_len, (*s).var_ty, (*s).line);
        return 0;
    }

    if (k == ST_ASSIGN()) {
        Ptr<TcSym> sy = ctx_find(ctx, (*s).var_name, (*s).var_name_len);
        if (sy == cast<Ptr<TcSym>>(null)) {
            tc_error_one((*s).line,
                cast<Ptr<Byte>>("assignment to undefined variable"),
                (*s).var_name);
        }
        tc_expr((*s).assign_value, ctx);
        if (!implicitly_assignable((*s).assign_value, (*sy).ty)) {
            tc_error_two((*s).line,
                cast<Ptr<Byte>>("cannot assign"),
                tc_type_name_kind((*(*(*s).assign_value).ety).kind),
                cast<Ptr<Byte>>("to variable of type"),
                tc_type_name_kind((*(*sy).ty).kind));
        }
        return 0;
    }

    if (k == ST_PTR_STORE()) {
        tc_expr((*s).store_target, ctx);
        Ptr<Type> pointee_ty = (*(*s).store_target).ety;
        tc_expr((*s).store_value, ctx);
        if (!implicitly_assignable((*s).store_value, pointee_ty)) {
            tc_error_two((*s).line,
                cast<Ptr<Byte>>("cannot store"),
                tc_type_name_kind((*(*(*s).store_value).ety).kind),
                cast<Ptr<Byte>>("through pointer to"),
                tc_type_name_kind((*pointee_ty).kind));
        }
        return 0;
    }

    if (k == ST_FIELD_STORE()) {
        tc_expr((*s).store_target, ctx);
        Ptr<Type> field_ty = (*(*s).store_target).ety;
        tc_expr((*s).store_value, ctx);
        if (!implicitly_assignable((*s).store_value, field_ty)) {
            tc_error_two((*s).line,
                cast<Ptr<Byte>>("cannot store"),
                tc_type_name_kind((*(*(*s).store_value).ety).kind),
                cast<Ptr<Byte>>("into field of type"),
                tc_type_name_kind((*field_ty).kind));
        }
        return 0;
    }

    if (k == ST_INDEX_STORE()) {
        tc_expr((*s).store_target, ctx);
        Ptr<Type> elem_ty = (*(*s).store_target).ety;
        tc_expr((*s).store_value, ctx);
        if (!implicitly_assignable((*s).store_value, elem_ty)) {
            tc_error_two((*s).line,
                cast<Ptr<Byte>>("cannot store"),
                tc_type_name_kind((*(*(*s).store_value).ety).kind),
                cast<Ptr<Byte>>("into element of type"),
                tc_type_name_kind((*elem_ty).kind));
        }
        return 0;
    }

    if (k == ST_RETURN()) {
        Ptr<Expr> v = (*s).ret_value;
        if (v != cast<Ptr<Expr>>(null)) {
            tc_expr(v, ctx);
            if (!implicitly_assignable(v, (*ctx).func_return_ty)) {
                tc_error_two((*s).line,
                    cast<Ptr<Byte>>("cannot return"),
                    tc_type_name_kind((*(*v).ety).kind),
                    cast<Ptr<Byte>>("from function declared to return"),
                    tc_type_name_kind((*(*ctx).func_return_ty).kind));
            }
        } else {
            if ((*(*ctx).func_return_ty).kind != TY_VOID()) {
                tc_error_one((*s).line,
                    cast<Ptr<Byte>>("missing return value (function returns)"),
                    tc_type_name_kind((*(*ctx).func_return_ty).kind));
            }
        }
        return 0;
    }

    if (k == ST_IF()) {
        tc_expr((*s).cond, ctx);
        if ((*(*(*s).cond).ety).kind != TY_BOOLEAN()) {
            tc_error_one((*s).line,
                cast<Ptr<Byte>>("if-condition must be Boolean, got"),
                tc_type_name_kind((*(*(*s).cond).ety).kind));
        }
        tc_stmt((*s).then_b, ctx);
        if ((*s).else_b != cast<Ptr<Stmt>>(null)) {
            tc_stmt((*s).else_b, ctx);
        }
        return 0;
    }

    if (k == ST_WHILE()) {
        tc_expr((*s).cond, ctx);
        if ((*(*(*s).cond).ety).kind != TY_BOOLEAN()) {
            tc_error_one((*s).line,
                cast<Ptr<Byte>>("while-condition must be Boolean, got"),
                tc_type_name_kind((*(*(*s).cond).ety).kind));
        }
        (*ctx).loop_depth = (*ctx).loop_depth + 1;
        tc_stmt((*s).body, ctx);
        (*ctx).loop_depth = (*ctx).loop_depth - 1;
        return 0;
    }

    if (k == ST_FOR()) {
        if ((*s).for_init != cast<Ptr<Stmt>>(null)) {
            tc_stmt((*s).for_init, ctx);
        }
        if ((*s).cond != cast<Ptr<Expr>>(null)) {
            tc_expr((*s).cond, ctx);
            if ((*(*(*s).cond).ety).kind != TY_BOOLEAN()) {
                tc_error_one((*s).line,
                    cast<Ptr<Byte>>("for-condition must be Boolean, got"),
                    tc_type_name_kind((*(*(*s).cond).ety).kind));
            }
        }
        (*ctx).loop_depth = (*ctx).loop_depth + 1;
        tc_stmt((*s).body, ctx);
        (*ctx).loop_depth = (*ctx).loop_depth - 1;
        if ((*s).for_update != cast<Ptr<Stmt>>(null)) {
            tc_stmt((*s).for_update, ctx);
        }
        return 0;
    }

    if (k == ST_BREAK()) {
        if ((*ctx).loop_depth == 0) {
            tc_error_simple((*s).line,
                cast<Ptr<Byte>>("'break' is only valid inside a loop"));
        }
        return 0;
    }
    if (k == ST_CONTINUE()) {
        if ((*ctx).loop_depth == 0) {
            tc_error_simple((*s).line,
                cast<Ptr<Byte>>("'continue' is only valid inside a loop"));
        }
        return 0;
    }
    if (k == ST_BLOCK()) {
        Ptr<PtrVec> stmts = (*s).block_stmts;
        if (stmts != cast<Ptr<PtrVec>>(null)) {
            Long n = (*stmts).count;
            Long i = 0;
            while (i < n) {
                Ptr<Stmt> child = cast<Ptr<Stmt>>(ptrvec_get(stmts, i));
                tc_stmt(child, ctx);
                i = i + 1;
            }
        }
        return 0;
    }
    if (k == ST_EXPR()) {
        tc_expr((*s).expr, ctx);
        return 0;
    }
    println("type error at line %l: internal: unknown stmt kind %l", (*s).line, k);
    exit(1);
    return 0;
}

// ---- Program-level entry ----

Long typecheck_program(Ptr<Program> pg) {
    // Build the function table.
    Ptr<Byte> raw = alloc(24);
    Ptr<PtrVec> ft = cast<Ptr<PtrVec>>(raw);
    ptrvec_init(ft);

    Ptr<PtrVec> funcs = (*pg).funcs;
    Long nf = (*funcs).count;
    Long i = 0;
    while (i < nf) {
        Ptr<FuncDecl> fa = cast<Ptr<FuncDecl>>(ptrvec_get(funcs, i));
        funcs_add(ft, fa);
        i = i + 1;
    }

    // Typecheck each body. Externs have no body to check.
    Long fi = 0;
    while (fi < nf) {
        Ptr<FuncDecl> fb = cast<Ptr<FuncDecl>>(ptrvec_get(funcs, fi));
        if ((*fb).is_extern != 0) {
            fi = fi + 1;
            continue;
        }
        TcCtx ctx;
        ctx_init(&ctx, (*fb).return_ty, ft);
        // Add parameters as locals.
        Ptr<PtrVec> params = (*fb).params;
        if (params != cast<Ptr<PtrVec>>(null)) {
            Long pn = (*params).count;
            Long pi = 0;
            while (pi < pn) {
                Ptr<Param> p = cast<Ptr<Param>>(ptrvec_get(params, pi));
                ctx_add(&ctx, (*p).name, (*p).name_len, (*p).ty, (*fb).line);
                pi = pi + 1;
            }
        }
        tc_stmt((*fb).body, &ctx);
        fi = fi + 1;
    }
    return 1;
}
// lazyc/compiler/codegen.ml
//
// Codegen for lazyc. Step 21j+k+l in one file.
//
// Mirrors src/codegen.c. Walks a typechecked Program and emits NASM
// x86-64 assembly to a Ptr<Buf>. Stack-machine evaluation strategy: every
// expression pushes its result on the runtime stack; statements pop and
// consume. Local variables live in stack slots negative-indexed from rbp.
//
// The codegen output must be byte-identical to the C codegen's output
// for the same input program — that's required for the fixed-point test
// at 21m. So we mirror the C version's emit order and label numbering
// EXACTLY.

// ---- Codegen context ----
//
// Holds all the state the C version uses module-globals for:
//   * out: the Buf we're appending asm to
//   * label_counter: monotonically increasing integer for .L<N> labels
//   * loop stack: nested break/continue targets
//   * string-literal pool (intern_strlit)
//   * cooked-string pool (intern_cooked) for format-string fragments
//   * symbol table for the current function (set per gen_func)
struct Symbol {
    Ptr<Byte> name;
    Long      name_len;
    Long      offset;          // bytes below rbp
    Ptr<Type> ty;
}

struct SymTab {
    Ptr<PtrVec> items;         // PtrVec of Ptr<Symbol>
    Long        next_offset;
}

struct LoopFrame {
    Long break_lbl;
    Long continue_lbl;
}

struct StrLit {
    Long      label_id;
    Ptr<Byte> data;            // raw inner bytes (escapes NOT yet processed)
    Long      len;
}

struct CookedStr {
    Long      label_id;
    Ptr<Byte> bytes;           // already-decoded bytes
    Long      len;
}

struct CgCtx {
    Ptr<Buf>    out;
    Long        label_counter;
    Ptr<PtrVec> loop_stack;    // PtrVec of Ptr<LoopFrame>
    Ptr<PtrVec> strlits;       // PtrVec of Ptr<StrLit>
    Ptr<PtrVec> cooked;        // PtrVec of Ptr<CookedStr>
    Ptr<SymTab> sym;           // current function's symbol table (or null)
}

// ---- Constructors ----

Ptr<Symbol> sym_new(Ptr<Byte> name, Long name_len, Long offset, Ptr<Type> ty) {
    Ptr<Byte> raw = alloc(32);
    Ptr<Symbol> s = cast<Ptr<Symbol>>(raw);
    (*s).name     = name;
    (*s).name_len = name_len;
    (*s).offset   = offset;
    (*s).ty       = ty;
    return s;
}

Ptr<SymTab> symtab_new() {
    Ptr<Byte> raw = alloc(16);
    Ptr<SymTab> st = cast<Ptr<SymTab>>(raw);
    Ptr<Byte> raw_pv = alloc(24);
    Ptr<PtrVec> items = cast<Ptr<PtrVec>>(raw_pv);
    ptrvec_init(items);
    (*st).items = items;
    (*st).next_offset = 0;
    return st;
}

Ptr<Symbol> symtab_find(Ptr<SymTab> st, Ptr<Byte> name, Long name_len) {
    Ptr<PtrVec> items = (*st).items;
    Long n = (*items).count;
    Long i = 0;
    while (i < n) {
        Ptr<Symbol> sy = cast<Ptr<Symbol>>(ptrvec_get(items, i));
        if (lex_slice_eq(name, name_len, (*sy).name)) { return sy; }
        i = i + 1;
    }
    return cast<Ptr<Symbol>>(null);
}

// Compute byte size for a type (matches C codegen's type_total_bytes,
// not the typechecker's tc_type_size_kind which only knows numerics).
Long cg_type_size(Ptr<Type> ty) {
    Long k = (*ty).kind;
    if (k == TY_BOOLEAN()) { return 1; }
    if (k == TY_CHAR())    { return 1; }
    if (k == TY_BYTE())    { return 1; }
    if (k == TY_INTEGER()) { return 2; }
    if (k == TY_UINTEGER()){ return 2; }
    if (k == TY_WHOLE())   { return 4; }
    if (k == TY_UWHOLE())  { return 4; }
    if (k == TY_LONG())    { return 8; }
    if (k == TY_ULONG())   { return 8; }
    if (k == TY_STRING())  { return 8; }
    if (k == TY_PTR())     { return 8; }
    if (k == TY_STRUCT()) {
        Ptr<StructDef> sd = cast<Ptr<StructDef>>((*ty).sdef);
        if (sd == cast<Ptr<StructDef>>(null)) { return 0; }
        return (*sd).size;
    }
    if (k == TY_ARRAY()) {
        if ((*ty).elem == cast<Ptr<Type>>(null)) { return 0; }
        return cg_type_size((*ty).elem) * (*ty).nelems;
    }
    return 0;
}

// type_size for "loadable" types only (matches C codegen's static
// type_size which only handles the leaf types). For struct/array this
// is meaningless so we return 8 as a fallback (matches default branch).
Long cg_type_size_kind(Long k) {
    if (k == TY_BOOLEAN()) { return 1; }
    if (k == TY_CHAR())    { return 1; }
    if (k == TY_BYTE())    { return 1; }
    if (k == TY_INTEGER()) { return 2; }
    if (k == TY_UINTEGER()){ return 2; }
    if (k == TY_WHOLE())   { return 4; }
    if (k == TY_UWHOLE())  { return 4; }
    if (k == TY_LONG())    { return 8; }
    if (k == TY_ULONG())   { return 8; }
    if (k == TY_STRING())  { return 8; }
    if (k == TY_PTR())     { return 8; }
    return 8;
}

Long cg_type_align(Ptr<Type> ty) {
    Long k = (*ty).kind;
    if (k == TY_STRUCT()) {
        Ptr<StructDef> sd = cast<Ptr<StructDef>>((*ty).sdef);
        if (sd == cast<Ptr<StructDef>>(null)) { return 1; }
        return (*sd).align;
    }
    if (k == TY_ARRAY()) {
        if ((*ty).elem == cast<Ptr<Type>>(null)) { return 1; }
        return cg_type_align((*ty).elem);
    }
    return cg_type_size_kind(k);
}

Boolean cg_is_signed_kind(Long k) {
    if (k == TY_INTEGER()) { return true; }
    if (k == TY_WHOLE())   { return true; }
    if (k == TY_LONG())    { return true; }
    return false;
}

// Add a binding to the symbol table, computing its stack offset with
// proper alignment. Mirrors symtab_add in C.
Long symtab_add(Ptr<SymTab> st, Ptr<Byte> name, Long name_len, Ptr<Type> ty, Long line) {
    Ptr<Symbol> existing = symtab_find(st, name, name_len);
    if (existing != cast<Ptr<Symbol>>(null)) {
        println("error at line %l: redeclaration of '%s'", line, cast<String>(name));
        exit(1);
    }
    Long sz = cg_type_size(ty);
    Long al = cg_type_align(ty);
    if (al < 1) { al = 1; }
    Long off = (*st).next_offset + sz;
    Long rem = off - (off / al) * al;
    if (rem != 0) { off = off + (al - rem); }
    (*st).next_offset = off;
    Ptr<Symbol> sy = sym_new(name, name_len, off, ty);
    ptrvec_push((*st).items, cast<Ptr<Byte>>(sy));
    return off;
}

Long symtab_stack_size_aligned(Ptr<SymTab> st) {
    Long n = (*st).next_offset;
    Long rem = n - (n / 16) * 16;
    if (rem != 0) { n = n + (16 - rem); }
    return n;
}

// ---- Cgctx ----

Ptr<CgCtx> cgctx_new(Ptr<Buf> out) {
    Ptr<Byte> raw = alloc(48);
    Ptr<CgCtx> c = cast<Ptr<CgCtx>>(raw);
    (*c).out = out;
    (*c).label_counter = 0;

    Ptr<Byte> r1 = alloc(24);
    Ptr<PtrVec> ls = cast<Ptr<PtrVec>>(r1);
    ptrvec_init(ls);
    (*c).loop_stack = ls;

    Ptr<Byte> r2 = alloc(24);
    Ptr<PtrVec> sl = cast<Ptr<PtrVec>>(r2);
    ptrvec_init(sl);
    (*c).strlits = sl;

    Ptr<Byte> r3 = alloc(24);
    Ptr<PtrVec> ck = cast<Ptr<PtrVec>>(r3);
    ptrvec_init(ck);
    (*c).cooked = ck;

    (*c).sym = cast<Ptr<SymTab>>(null);
    return c;
}

Long new_label(Ptr<CgCtx> ctx) {
    Long id = (*ctx).label_counter;
    (*ctx).label_counter = id + 1;
    return id;
}

Long loop_push(Ptr<CgCtx> ctx, Long break_lbl, Long continue_lbl) {
    Ptr<Byte> raw = alloc(16);
    Ptr<LoopFrame> lf = cast<Ptr<LoopFrame>>(raw);
    (*lf).break_lbl = break_lbl;
    (*lf).continue_lbl = continue_lbl;
    ptrvec_push((*ctx).loop_stack, cast<Ptr<Byte>>(lf));
    return 0;
}

Long loop_pop(Ptr<CgCtx> ctx) {
    Ptr<PtrVec> ls = (*ctx).loop_stack;
    (*ls).count = (*ls).count - 1;
    return 0;
}

Long loop_break_lbl(Ptr<CgCtx> ctx) {
    Ptr<PtrVec> ls = (*ctx).loop_stack;
    Ptr<LoopFrame> lf = cast<Ptr<LoopFrame>>(ptrvec_get(ls, (*ls).count - 1));
    return (*lf).break_lbl;
}

Long loop_continue_lbl(Ptr<CgCtx> ctx) {
    Ptr<PtrVec> ls = (*ctx).loop_stack;
    Ptr<LoopFrame> lf = cast<Ptr<LoopFrame>>(ptrvec_get(ls, (*ls).count - 1));
    return (*lf).continue_lbl;
}

Long loop_depth_now(Ptr<CgCtx> ctx) {
    return (*(*ctx).loop_stack).count;
}

// ---- String literal interning ----

Long intern_strlit(Ptr<CgCtx> ctx, Ptr<Byte> data, Long len) {
    Ptr<PtrVec> sl = (*ctx).strlits;
    Long id = (*sl).count;
    Ptr<Byte> raw = alloc(24);
    Ptr<StrLit> s = cast<Ptr<StrLit>>(raw);
    (*s).label_id = id;
    (*s).data     = data;
    (*s).len      = len;
    ptrvec_push(sl, cast<Ptr<Byte>>(s));
    return id;
}

// Process backslash escapes in `src[0..len)`, returning a fresh
// null-terminated buffer. Length of output written to (*out_len).
Ptr<Byte> cook_escapes(Ptr<Byte> src, Long len, Ptr<Long> out_len) {
    Ptr<Byte> buf = alloc(len + 1);
    Long out = 0;
    Long i = 0;
    while (i < len) {
        Long c = cast<Long>(src[i]);
        Boolean did_esc = false;
        if (c == 92) {                       // '\'
            if (i + 1 < len) {
                Long esc = cast<Long>(src[i + 1]);
                if (esc == 120) {                  // 'x' -> \xHH hex escape
                    if (i + 3 < len) {
                        Long h1 = cast<Long>(src[i + 2]);
                        Long h2 = cast<Long>(src[i + 3]);
                        Long d1 = -1;
                        Long d2 = -1;
                        if (h1 >= 48) { if (h1 <= 57) { d1 = h1 - 48; } }   // 0..9
                        if (h1 >= 97) { if (h1 <= 102){ d1 = h1 - 97 + 10; } } // a..f
                        if (h1 >= 65) { if (h1 <= 70) { d1 = h1 - 65 + 10; } } // A..F
                        if (h2 >= 48) { if (h2 <= 57) { d2 = h2 - 48; } }
                        if (h2 >= 97) { if (h2 <= 102){ d2 = h2 - 97 + 10; } }
                        if (h2 >= 65) { if (h2 <= 70) { d2 = h2 - 65 + 10; } }
                        Boolean both_ok = false;
                        if (d1 >= 0) { if (d2 >= 0) { both_ok = true; } }
                        if (both_ok) {
                            buf[out] = cast<Byte>(d1 * 16 + d2);
                            out = out + 1;
                            i = i + 4;
                            did_esc = true;
                        }
                    }
                }
                if (!did_esc) {
                    Long resolved = esc;
                    if (esc == 110) { resolved = 10;  }   // n -> \n
                    if (esc == 116) { resolved = 9;   }   // t -> \t
                    if (esc == 114) { resolved = 13;  }   // r -> \r
                    if (esc == 48)  { resolved = 0;   }   // 0 -> \0
                    if (esc == 92)  { resolved = 92;  }   // \ -> \\
                    if (esc == 39)  { resolved = 39;  }   // ' -> '
                    if (esc == 34)  { resolved = 34;  }   // " -> "
                    buf[out] = cast<Byte>(resolved);
                    out = out + 1;
                    i = i + 2;
                    did_esc = true;
                }
            }
        }
        if (!did_esc) {
            buf[out] = cast<Byte>(c);
            out = out + 1;
            i = i + 1;
        }
    }
    buf[out] = cast<Byte>(0);
    *out_len = out;
    return buf;
}

Long intern_cooked(Ptr<CgCtx> ctx, Ptr<Byte> src, Long len) {
    Long out_len = 0;
    Ptr<Byte> bytes = cook_escapes(src, len, &out_len);
    Ptr<PtrVec> ck = (*ctx).cooked;
    Long id = (*ck).count;
    Ptr<Byte> raw = alloc(24);
    Ptr<CookedStr> cs = cast<Ptr<CookedStr>>(raw);
    (*cs).label_id = id;
    (*cs).bytes    = bytes;
    (*cs).len      = out_len;
    ptrvec_push(ck, cast<Ptr<Byte>>(cs));
    return id;
}

// ---- emit helpers ----

Long emit_str(Ptr<CgCtx> ctx, Ptr<Byte> s) {
    buf_push_str((*ctx).out, s);
    return 0;
}

Long emit_long(Ptr<CgCtx> ctx, Long n) {
    buf_push_long((*ctx).out, n);
    return 0;
}

Long emit_nl(Ptr<CgCtx> ctx) {
    buf_push_byte((*ctx).out, cast<Byte>(10));
    return 0;
}

// `    mov rax, <n>\n`
Long emit_mov_rax_imm(Ptr<CgCtx> ctx, Long n) {
    emit_str(ctx, cast<Ptr<Byte>>("    mov rax, "));
    emit_long(ctx, n);
    emit_nl(ctx);
    return 0;
}

// `    push rax\n`
Long emit_push_rax(Ptr<CgCtx> ctx) {
    emit_str(ctx, cast<Ptr<Byte>>("    push rax\n"));
    return 0;
}

Long emit_pop_rax(Ptr<CgCtx> ctx) {
    emit_str(ctx, cast<Ptr<Byte>>("    pop rax\n"));
    return 0;
}

Long emit_pop_rcx(Ptr<CgCtx> ctx) {
    emit_str(ctx, cast<Ptr<Byte>>("    pop rcx\n"));
    return 0;
}

// Emit `<prefix><offset>]<suffix>\n` for things like
// `    mov qword [rbp-<offset>], <reg>\n`
Long emit_mem_op(Ptr<CgCtx> ctx, Ptr<Byte> prefix, Long offset, Ptr<Byte> suffix) {
    emit_str(ctx, prefix);
    emit_long(ctx, offset);
    emit_str(ctx, suffix);
    return 0;
}

// Emit `.L<N>:\n`
Long emit_label_def(Ptr<CgCtx> ctx, Long n) {
    emit_str(ctx, cast<Ptr<Byte>>(".L"));
    emit_long(ctx, n);
    emit_str(ctx, cast<Ptr<Byte>>(":\n"));
    return 0;
}

// Emit `    jmp .L<N>\n`
Long emit_jmp(Ptr<CgCtx> ctx, Ptr<Byte> jmp_op, Long n) {
    emit_str(ctx, cast<Ptr<Byte>>("    "));
    emit_str(ctx, jmp_op);
    emit_str(ctx, cast<Ptr<Byte>>(" .L"));
    emit_long(ctx, n);
    emit_nl(ctx);
    return 0;
}

// Emit `    <op> rax, <imm>\n` for things like `add rax, 5`
Long emit_op_rax_imm(Ptr<CgCtx> ctx, Ptr<Byte> op, Long imm) {
    emit_str(ctx, cast<Ptr<Byte>>("    "));
    emit_str(ctx, op);
    emit_str(ctx, cast<Ptr<Byte>>(" rax, "));
    emit_long(ctx, imm);
    emit_nl(ctx);
    return 0;
}

// ---- Sized load/store helpers ----

// Load a value from [rbp-offset] into rax with proper width and signedness.
Long emit_load_var(Ptr<CgCtx> ctx, Ptr<Type> ty, Long offset) {
    Long sz = cg_type_size_kind((*ty).kind);
    Boolean sgn = cg_is_signed_kind((*ty).kind);
    if (sz == 1) {
        if (sgn) { emit_mem_op(ctx, cast<Ptr<Byte>>("    movsx rax, byte [rbp-"), offset, cast<Ptr<Byte>>("]\n")); }
        else     { emit_mem_op(ctx, cast<Ptr<Byte>>("    movzx rax, byte [rbp-"), offset, cast<Ptr<Byte>>("]\n")); }
        return 0;
    }
    if (sz == 2) {
        if (sgn) { emit_mem_op(ctx, cast<Ptr<Byte>>("    movsx rax, word [rbp-"), offset, cast<Ptr<Byte>>("]\n")); }
        else     { emit_mem_op(ctx, cast<Ptr<Byte>>("    movzx rax, word [rbp-"), offset, cast<Ptr<Byte>>("]\n")); }
        return 0;
    }
    if (sz == 4) {
        if (sgn) { emit_mem_op(ctx, cast<Ptr<Byte>>("    movsxd rax, dword [rbp-"), offset, cast<Ptr<Byte>>("]\n")); }
        else     { emit_mem_op(ctx, cast<Ptr<Byte>>("    mov eax, dword [rbp-"), offset, cast<Ptr<Byte>>("]\n")); }
        return 0;
    }
    emit_mem_op(ctx, cast<Ptr<Byte>>("    mov rax, [rbp-"), offset, cast<Ptr<Byte>>("]\n"));
    return 0;
}

// Store rax into [rbp-offset] with the right width.
Long emit_store_var(Ptr<CgCtx> ctx, Ptr<Type> ty, Long offset) {
    Long sz = cg_type_size_kind((*ty).kind);
    if (sz == 1) {
        emit_mem_op(ctx, cast<Ptr<Byte>>("    mov byte  [rbp-"), offset, cast<Ptr<Byte>>("], al\n"));
        return 0;
    }
    if (sz == 2) {
        emit_mem_op(ctx, cast<Ptr<Byte>>("    mov word  [rbp-"), offset, cast<Ptr<Byte>>("], ax\n"));
        return 0;
    }
    if (sz == 4) {
        emit_mem_op(ctx, cast<Ptr<Byte>>("    mov dword [rbp-"), offset, cast<Ptr<Byte>>("], eax\n"));
        return 0;
    }
    emit_mem_op(ctx, cast<Ptr<Byte>>("    mov qword [rbp-"), offset, cast<Ptr<Byte>>("], rax\n"));
    return 0;
}

// Zero a possibly-multi-byte stack slot in 8/4/2/1-byte chunks.
// Mirrors zero_slot.
Long emit_zero_slot(Ptr<CgCtx> ctx, Long offset, Long sz) {
    Long pos = 0;
    while (pos + 8 <= sz) {
        emit_mem_op(ctx, cast<Ptr<Byte>>("    mov qword [rbp-"), offset - pos, cast<Ptr<Byte>>("], 0\n"));
        pos = pos + 8;
    }
    while (pos + 4 <= sz) {
        emit_mem_op(ctx, cast<Ptr<Byte>>("    mov dword [rbp-"), offset - pos, cast<Ptr<Byte>>("], 0\n"));
        pos = pos + 4;
    }
    while (pos + 2 <= sz) {
        emit_mem_op(ctx, cast<Ptr<Byte>>("    mov word  [rbp-"), offset - pos, cast<Ptr<Byte>>("], 0\n"));
        pos = pos + 2;
    }
    while (pos + 1 <= sz) {
        emit_mem_op(ctx, cast<Ptr<Byte>>("    mov byte  [rbp-"), offset - pos, cast<Ptr<Byte>>("], 0\n"));
        pos = pos + 1;
    }
    return 0;
}

// Zero a variable (any type).
Long emit_zero_var(Ptr<CgCtx> ctx, Ptr<Type> ty, Long offset) {
    Long k = (*ty).kind;
    if (k == TY_STRUCT()) {
        emit_zero_slot(ctx, offset, cg_type_size(ty));
        return 0;
    }
    if (k == TY_ARRAY()) {
        emit_zero_slot(ctx, offset, cg_type_size(ty));
        return 0;
    }
    Long sz = cg_type_size_kind(k);
    if (sz == 1) {
        emit_mem_op(ctx, cast<Ptr<Byte>>("    mov byte  [rbp-"), offset, cast<Ptr<Byte>>("], 0\n"));
        return 0;
    }
    if (sz == 2) {
        emit_mem_op(ctx, cast<Ptr<Byte>>("    mov word  [rbp-"), offset, cast<Ptr<Byte>>("], 0\n"));
        return 0;
    }
    if (sz == 4) {
        emit_mem_op(ctx, cast<Ptr<Byte>>("    mov dword [rbp-"), offset, cast<Ptr<Byte>>("], 0\n"));
        return 0;
    }
    emit_mem_op(ctx, cast<Ptr<Byte>>("    mov qword [rbp-"), offset, cast<Ptr<Byte>>("], 0\n"));
    return 0;
}

// Argument register for parameter index i, sized.
Ptr<Byte> arg_reg_for(Long i, Long sz) {
    if (sz == 1) {
        if (i == 0) { return cast<Ptr<Byte>>("dil"); }
        if (i == 1) { return cast<Ptr<Byte>>("sil"); }
        if (i == 2) { return cast<Ptr<Byte>>("dl");  }
        if (i == 3) { return cast<Ptr<Byte>>("cl");  }
        if (i == 4) { return cast<Ptr<Byte>>("r8b"); }
        return cast<Ptr<Byte>>("r9b");
    }
    if (sz == 2) {
        if (i == 0) { return cast<Ptr<Byte>>("di");  }
        if (i == 1) { return cast<Ptr<Byte>>("si");  }
        if (i == 2) { return cast<Ptr<Byte>>("dx");  }
        if (i == 3) { return cast<Ptr<Byte>>("cx");  }
        if (i == 4) { return cast<Ptr<Byte>>("r8w"); }
        return cast<Ptr<Byte>>("r9w");
    }
    if (sz == 4) {
        if (i == 0) { return cast<Ptr<Byte>>("edi"); }
        if (i == 1) { return cast<Ptr<Byte>>("esi"); }
        if (i == 2) { return cast<Ptr<Byte>>("edx"); }
        if (i == 3) { return cast<Ptr<Byte>>("ecx"); }
        if (i == 4) { return cast<Ptr<Byte>>("r8d"); }
        return cast<Ptr<Byte>>("r9d");
    }
    if (i == 0) { return cast<Ptr<Byte>>("rdi"); }
    if (i == 1) { return cast<Ptr<Byte>>("rsi"); }
    if (i == 2) { return cast<Ptr<Byte>>("rdx"); }
    if (i == 3) { return cast<Ptr<Byte>>("rcx"); }
    if (i == 4) { return cast<Ptr<Byte>>("r8");  }
    return cast<Ptr<Byte>>("r9");
}

// ---- Pass 1: collect locals from a Stmt subtree ----

Long collect_locals_stmt(Ptr<Stmt> s, Ptr<SymTab> st) {
    if (s == cast<Ptr<Stmt>>(null)) { return 0; }
    Long k = (*s).kind;
    if (k == ST_VAR_DECL()) {
        symtab_add(st, (*s).var_name, (*s).var_name_len, (*s).var_ty, (*s).line);
        return 0;
    }
    if (k == ST_BLOCK()) {
        Ptr<PtrVec> ss = (*s).block_stmts;
        if (ss != cast<Ptr<PtrVec>>(null)) {
            Long n = (*ss).count;
            Long i = 0;
            while (i < n) {
                Ptr<Stmt> child = cast<Ptr<Stmt>>(ptrvec_get(ss, i));
                collect_locals_stmt(child, st);
                i = i + 1;
            }
        }
        return 0;
    }
    if (k == ST_IF()) {
        collect_locals_stmt((*s).then_b, st);
        if ((*s).else_b != cast<Ptr<Stmt>>(null)) {
            collect_locals_stmt((*s).else_b, st);
        }
        return 0;
    }
    if (k == ST_WHILE()) {
        collect_locals_stmt((*s).body, st);
        return 0;
    }
    if (k == ST_FOR()) {
        if ((*s).for_init != cast<Ptr<Stmt>>(null)) {
            collect_locals_stmt((*s).for_init, st);
        }
        collect_locals_stmt((*s).body, st);
        return 0;
    }
    return 0;
}

// ---- Codegen error ----
Long cg_error_at(Long line, Ptr<Byte> msg) {
    println("codegen error at line %l: %s", line, cast<String>(msg));
    exit(1);
    return 0;
}

// ---- gen_expr: dispatch ----
//
// Each case appends asm to ctx.out and ends with the result on the
// stack (i.e., emit_push_rax was called).

// gen_expr, gen_binary, gen_unary, gen_cast, gen_call, gen_format_call,
// gen_lvalue_address, gen_index_addr, gen_stmt: defined below. lazyc
// resolves names globally so no forward declarations needed.

// Emit a sized load from [rax] into rax, given the pointee type.
Long emit_load_via_rax(Ptr<CgCtx> ctx, Ptr<Type> pointee) {
    Long sz = cg_type_size_kind((*pointee).kind);
    Boolean sgn = cg_is_signed_kind((*pointee).kind);
    if (sz == 1) {
        if (sgn) { emit_str(ctx, cast<Ptr<Byte>>("    movsx rax, byte [rax]\n")); }
        else     { emit_str(ctx, cast<Ptr<Byte>>("    movzx rax, byte [rax]\n")); }
        return 0;
    }
    if (sz == 2) {
        if (sgn) { emit_str(ctx, cast<Ptr<Byte>>("    movsx rax, word [rax]\n")); }
        else     { emit_str(ctx, cast<Ptr<Byte>>("    movzx rax, word [rax]\n")); }
        return 0;
    }
    if (sz == 4) {
        if (sgn) { emit_str(ctx, cast<Ptr<Byte>>("    movsxd rax, dword [rax]\n")); }
        else     { emit_str(ctx, cast<Ptr<Byte>>("    mov eax, dword [rax]\n")); }
        return 0;
    }
    emit_str(ctx, cast<Ptr<Byte>>("    mov rax, [rax]\n"));
    return 0;
}

// Emit a sized store of rax through rcx (for ptr/field/index stores).
Long emit_store_via_rcx(Ptr<CgCtx> ctx, Long sz) {
    if (sz == 1) {
        emit_str(ctx, cast<Ptr<Byte>>("    mov byte  [rcx], al\n"));
        return 0;
    }
    if (sz == 2) {
        emit_str(ctx, cast<Ptr<Byte>>("    mov word  [rcx], ax\n"));
        return 0;
    }
    if (sz == 4) {
        emit_str(ctx, cast<Ptr<Byte>>("    mov dword [rcx], eax\n"));
        return 0;
    }
    emit_str(ctx, cast<Ptr<Byte>>("    mov qword [rcx], rax\n"));
    return 0;
}

// gen_expr: walk an expression and push its value on the stack.
Long gen_expr(Ptr<Expr> e, Ptr<CgCtx> ctx) {
    Long ek = (*e).kind;

    if (ek == EX_NUMBER()) {
        emit_mov_rax_imm(ctx, (*e).num);
        emit_push_rax(ctx);
        return 0;
    }
    if (ek == EX_BOOL_LIT()) {
        Long bv = 0;
        if ((*e).bool_val == 1) { bv = 1; }
        emit_mov_rax_imm(ctx, bv);
        emit_push_rax(ctx);
        return 0;
    }
    if (ek == EX_NULL()) {
        emit_str(ctx, cast<Ptr<Byte>>("    xor rax, rax\n"));
        emit_push_rax(ctx);
        return 0;
    }
    if (ek == EX_CHAR_LIT()) {
        // Mask to 0..255 for the literal value (matches C unsigned-char cast).
        Long cv = (*e).char_val;
        if (cv < 0) { cv = cv + 256; }
        emit_mov_rax_imm(ctx, cv);
        emit_push_rax(ctx);
        return 0;
    }
    if (ek == EX_STRING_LIT()) {
        Long sid = intern_strlit(ctx, (*e).str_data, (*e).str_len);
        emit_str(ctx, cast<Ptr<Byte>>("    lea rax, [rel Lstr_"));
        emit_long(ctx, sid);
        emit_str(ctx, cast<Ptr<Byte>>("]\n"));
        emit_push_rax(ctx);
        return 0;
    }
    if (ek == EX_IDENT()) {
        Ptr<Symbol> sy_id = symtab_find((*ctx).sym, (*e).name, (*e).name_len);
        if (sy_id == cast<Ptr<Symbol>>(null)) {
            cg_error_at((*e).line, cast<Ptr<Byte>>("internal: variable not in symtab"));
        }
        emit_load_var(ctx, (*sy_id).ty, (*sy_id).offset);
        emit_push_rax(ctx);
        return 0;
    }
    if (ek == EX_CAST())   { return gen_cast(e, ctx);   }
    if (ek == EX_BINARY()) { return gen_binary(e, ctx); }
    if (ek == EX_UNARY())  { return gen_unary(e, ctx);  }
    if (ek == EX_CALL())   { return gen_call(e, ctx);   }

    if (ek == EX_ADDR_OF()) {
        Ptr<Expr> ta = (*e).child0;
        Long tk = (*ta).kind;
        if (tk == EX_IDENT()) {
            Ptr<Symbol> sy_a = symtab_find((*ctx).sym, (*ta).name, (*ta).name_len);
            if (sy_a == cast<Ptr<Symbol>>(null)) {
                cg_error_at((*e).line, cast<Ptr<Byte>>("internal: addr-of unknown var"));
            }
            emit_mem_op(ctx, cast<Ptr<Byte>>("    lea rax, [rbp-"), (*sy_a).offset, cast<Ptr<Byte>>("]\n"));
            emit_push_rax(ctx);
            return 0;
        }
        if (tk == EX_FIELD()) {
            Ptr<Expr> op_a = (*ta).child0;
            Ptr<Field> f_a = cast<Ptr<Field>>((*ta).field_resolved);
            if (f_a == cast<Ptr<Field>>(null)) {
                cg_error_at((*e).line, cast<Ptr<Byte>>("internal: field not resolved"));
            }
            if ((*op_a).kind == EX_IDENT()) {
                Ptr<Symbol> sy_b = symtab_find((*ctx).sym, (*op_a).name, (*op_a).name_len);
                if (sy_b == cast<Ptr<Symbol>>(null)) {
                    cg_error_at((*e).line, cast<Ptr<Byte>>("internal: addr-of field on unknown var"));
                }
                Long addr_a = (*sy_b).offset - (*f_a).offset;
                emit_mem_op(ctx, cast<Ptr<Byte>>("    lea rax, [rbp-"), addr_a, cast<Ptr<Byte>>("]\n"));
                emit_push_rax(ctx);
                return 0;
            }
            if ((*op_a).kind == EX_DEREF()) {
                gen_expr((*op_a).child0, ctx);
                emit_pop_rax(ctx);
                if ((*f_a).offset != 0) {
                    emit_op_rax_imm(ctx, cast<Ptr<Byte>>("add"), (*f_a).offset);
                }
                emit_push_rax(ctx);
                return 0;
            }
            cg_error_at((*e).line, cast<Ptr<Byte>>("internal: addr-of field with unexpected operand"));
        }
        if (tk == EX_INDEX()) {
            Long idx_sz = cg_type_size((*ta).ety);
            gen_index_addr((*ta).child0, (*ta).child1, idx_sz, ctx);
            return 0;
        }
        cg_error_at((*e).line, cast<Ptr<Byte>>("internal: unsupported addr-of operand"));
    }

    if (ek == EX_DEREF()) {
        gen_expr((*e).child0, ctx);
        emit_pop_rax(ctx);
        Ptr<Type> pty_d = (*(*e).child0).ety;
        Ptr<Type> pointee_d = (*pty_d).pointee;
        emit_load_via_rax(ctx, pointee_d);
        emit_push_rax(ctx);
        return 0;
    }

    if (ek == EX_FIELD()) {
        Ptr<Expr> op_f = (*e).child0;
        Ptr<Field> f_f = cast<Ptr<Field>>((*e).field_resolved);
        if (f_f == cast<Ptr<Field>>(null)) {
            cg_error_at((*e).line, cast<Ptr<Byte>>("internal: field not resolved by typechecker"));
        }
        Ptr<Type> fty_f = cast<Ptr<Type>>((*f_f).ty);
        Long fsz_f = cg_type_size_kind((*fty_f).kind);
        Boolean fsgn_f = cg_is_signed_kind((*fty_f).kind);
        if ((*op_f).kind == EX_IDENT()) {
            Ptr<Symbol> sy_f = symtab_find((*ctx).sym, (*op_f).name, (*op_f).name_len);
            if (sy_f == cast<Ptr<Symbol>>(null)) {
                cg_error_at((*e).line, cast<Ptr<Byte>>("internal: field access on unknown var"));
            }
            Long addr_f = (*sy_f).offset - (*f_f).offset;
            if (fsz_f == 1) {
                if (fsgn_f) { emit_mem_op(ctx, cast<Ptr<Byte>>("    movsx rax, byte [rbp-"), addr_f, cast<Ptr<Byte>>("]\n")); }
                else        { emit_mem_op(ctx, cast<Ptr<Byte>>("    movzx rax, byte [rbp-"), addr_f, cast<Ptr<Byte>>("]\n")); }
            } else {
                if (fsz_f == 2) {
                    if (fsgn_f) { emit_mem_op(ctx, cast<Ptr<Byte>>("    movsx rax, word [rbp-"), addr_f, cast<Ptr<Byte>>("]\n")); }
                    else        { emit_mem_op(ctx, cast<Ptr<Byte>>("    movzx rax, word [rbp-"), addr_f, cast<Ptr<Byte>>("]\n")); }
                } else {
                    if (fsz_f == 4) {
                        if (fsgn_f) { emit_mem_op(ctx, cast<Ptr<Byte>>("    movsxd rax, dword [rbp-"), addr_f, cast<Ptr<Byte>>("]\n")); }
                        else        { emit_mem_op(ctx, cast<Ptr<Byte>>("    mov eax, dword [rbp-"), addr_f, cast<Ptr<Byte>>("]\n")); }
                    } else {
                        emit_mem_op(ctx, cast<Ptr<Byte>>("    mov rax, [rbp-"), addr_f, cast<Ptr<Byte>>("]\n"));
                    }
                }
            }
            emit_push_rax(ctx);
            return 0;
        }
        // op_f is EX_DEREF: evaluate the pointer (operand of deref), add field offset, load.
        gen_expr((*op_f).child0, ctx);
        emit_pop_rax(ctx);
        if ((*f_f).offset != 0) {
            emit_op_rax_imm(ctx, cast<Ptr<Byte>>("add"), (*f_f).offset);
        }
        emit_load_via_rax(ctx, fty_f);
        emit_push_rax(ctx);
        return 0;
    }

    if (ek == EX_INDEX()) {
        Long isz = cg_type_size_kind((*(*e).ety).kind);
        Long iek = (*(*e).ety).kind;
        if (iek == TY_STRUCT()) {
            cg_error_at((*e).line, cast<Ptr<Byte>>("internal: indexed read of aggregate not supported"));
        }
        if (iek == TY_ARRAY()) {
            cg_error_at((*e).line, cast<Ptr<Byte>>("internal: indexed read of aggregate not supported"));
        }
        gen_index_addr((*e).child0, (*e).child1, isz, ctx);
        emit_pop_rax(ctx);
        emit_load_via_rax(ctx, (*e).ety);
        emit_push_rax(ctx);
        return 0;
    }

    cg_error_at((*e).line, cast<Ptr<Byte>>("internal: unknown expr kind in codegen"));
    return 0;
}

// ---- gen_binary ----

Long gen_binary(Ptr<Expr> e, Ptr<CgCtx> ctx) {
    Ptr<Type> Lt = (*(*e).child0).ety;
    Ptr<Type> Rt = (*(*e).child1).ety;
    Boolean lhs_is_ptr = false;
    if ((*Lt).kind == TY_PTR()) { lhs_is_ptr = true; }
    Boolean rhs_is_ptr = false;
    if ((*Rt).kind == TY_PTR()) { rhs_is_ptr = true; }
    Long bop = (*e).op;

    Boolean any_ptr = false;
    if (lhs_is_ptr) { any_ptr = true; }
    if (rhs_is_ptr) { any_ptr = true; }

    Boolean is_addsub = false;
    if (bop == OP_ADD()) { is_addsub = true; }
    if (bop == OP_SUB()) { is_addsub = true; }

    if (any_ptr) {
        if (is_addsub) {
            Ptr<Type> ptr_ty = Lt;
            if (!lhs_is_ptr) { ptr_ty = Rt; }
            // Use cg_type_size (which handles struct/array fully) so
            // that Ptr<struct> and Ptr<T[N]> scale by the correct full
            // size, not the leaf-only size.
            Long psz = cg_type_size((*ptr_ty).pointee);

            gen_expr((*e).child0, ctx);
            gen_expr((*e).child1, ctx);
            emit_pop_rcx(ctx);
            emit_pop_rax(ctx);

            if (bop == OP_ADD()) {
                if (lhs_is_ptr) {
                    if (psz != 1) {
                        emit_str(ctx, cast<Ptr<Byte>>("    imul rcx, rcx, "));
                        emit_long(ctx, psz);
                        emit_nl(ctx);
                    }
                    emit_str(ctx, cast<Ptr<Byte>>("    add rax, rcx\n"));
                } else {
                    if (psz != 1) {
                        emit_str(ctx, cast<Ptr<Byte>>("    imul rax, rax, "));
                        emit_long(ctx, psz);
                        emit_nl(ctx);
                    }
                    emit_str(ctx, cast<Ptr<Byte>>("    add rax, rcx\n"));
                }
                emit_push_rax(ctx);
                return 0;
            }
            // OP_SUB
            if (lhs_is_ptr) {
                if (rhs_is_ptr) {
                    emit_str(ctx, cast<Ptr<Byte>>("    sub rax, rcx\n"));
                    if (psz != 1) {
                        emit_str(ctx, cast<Ptr<Byte>>("    cqo\n"));
                        emit_str(ctx, cast<Ptr<Byte>>("    mov r10, "));
                        emit_long(ctx, psz);
                        emit_nl(ctx);
                        emit_str(ctx, cast<Ptr<Byte>>("    idiv r10\n"));
                    }
                    emit_push_rax(ctx);
                    return 0;
                }
            }
            // ptr - Long
            if (psz != 1) {
                emit_str(ctx, cast<Ptr<Byte>>("    imul rcx, rcx, "));
                emit_long(ctx, psz);
                emit_nl(ctx);
            }
            emit_str(ctx, cast<Ptr<Byte>>("    sub rax, rcx\n"));
            emit_push_rax(ctx);
            return 0;
        }
    }

    // Default path.
    gen_expr((*e).child0, ctx);
    gen_expr((*e).child1, ctx);
    emit_pop_rcx(ctx);
    emit_pop_rax(ctx);

    if (bop == OP_ADD()) { emit_str(ctx, cast<Ptr<Byte>>("    add rax, rcx\n"));  emit_push_rax(ctx); return 0; }
    if (bop == OP_SUB()) { emit_str(ctx, cast<Ptr<Byte>>("    sub rax, rcx\n"));  emit_push_rax(ctx); return 0; }
    if (bop == OP_MUL()) { emit_str(ctx, cast<Ptr<Byte>>("    imul rax, rcx\n")); emit_push_rax(ctx); return 0; }
    if (bop == OP_DIV()) {
        emit_str(ctx, cast<Ptr<Byte>>("    cqo\n"));
        emit_str(ctx, cast<Ptr<Byte>>("    idiv rcx\n"));
        emit_push_rax(ctx);
        return 0;
    }
    if (bop == OP_MOD()) {
        emit_str(ctx, cast<Ptr<Byte>>("    cqo\n"));
        emit_str(ctx, cast<Ptr<Byte>>("    idiv rcx\n"));
        emit_str(ctx, cast<Ptr<Byte>>("    mov rax, rdx\n"));
        emit_push_rax(ctx);
        return 0;
    }
    // Comparisons.
    Boolean is_cmp = false;
    if (bop == OP_EQ())  { is_cmp = true; }
    if (bop == OP_NEQ()) { is_cmp = true; }
    if (bop == OP_LT())  { is_cmp = true; }
    if (bop == OP_GT())  { is_cmp = true; }
    if (bop == OP_LE())  { is_cmp = true; }
    if (bop == OP_GE())  { is_cmp = true; }
    if (is_cmp) {
        emit_str(ctx, cast<Ptr<Byte>>("    cmp rax, rcx\n"));
        Boolean unsigned_cmp = false;
        if (any_ptr) {
            unsigned_cmp = true;
        } else {
            if (!cg_is_signed_kind((*Lt).kind)) { unsigned_cmp = true; }
        }
        Ptr<Byte> setcc = cast<Ptr<Byte>>("sete");
        if (bop == OP_EQ())  { setcc = cast<Ptr<Byte>>("sete");  }
        if (bop == OP_NEQ()) { setcc = cast<Ptr<Byte>>("setne"); }
        if (bop == OP_LT())  {
            if (unsigned_cmp) { setcc = cast<Ptr<Byte>>("setb"); }
            else              { setcc = cast<Ptr<Byte>>("setl"); }
        }
        if (bop == OP_GT())  {
            if (unsigned_cmp) { setcc = cast<Ptr<Byte>>("seta"); }
            else              { setcc = cast<Ptr<Byte>>("setg"); }
        }
        if (bop == OP_LE())  {
            if (unsigned_cmp) { setcc = cast<Ptr<Byte>>("setbe"); }
            else              { setcc = cast<Ptr<Byte>>("setle"); }
        }
        if (bop == OP_GE())  {
            if (unsigned_cmp) { setcc = cast<Ptr<Byte>>("setae"); }
            else              { setcc = cast<Ptr<Byte>>("setge"); }
        }
        emit_str(ctx, cast<Ptr<Byte>>("    "));
        emit_str(ctx, setcc);
        emit_str(ctx, cast<Ptr<Byte>>(" al\n"));
        emit_str(ctx, cast<Ptr<Byte>>("    movzx rax, al\n"));
        emit_push_rax(ctx);
        return 0;
    }
    cg_error_at((*e).line, cast<Ptr<Byte>>("unknown binary op"));
    return 0;
}

// ---- gen_unary ----

Long gen_unary(Ptr<Expr> e, Ptr<CgCtx> ctx) {
    gen_expr((*e).child0, ctx);
    emit_pop_rax(ctx);
    Long uop = (*e).op;
    if (uop == OP_NEG()) {
        emit_str(ctx, cast<Ptr<Byte>>("    neg rax\n"));
        emit_push_rax(ctx);
        return 0;
    }
    if (uop == OP_NOT()) {
        emit_str(ctx, cast<Ptr<Byte>>("    cmp rax, 0\n"));
        emit_str(ctx, cast<Ptr<Byte>>("    sete al\n"));
        emit_str(ctx, cast<Ptr<Byte>>("    movzx rax, al\n"));
        emit_push_rax(ctx);
        return 0;
    }
    cg_error_at((*e).line, cast<Ptr<Byte>>("unknown unary op"));
    return 0;
}

// ---- gen_cast ----

Long gen_cast(Ptr<Expr> e, Ptr<CgCtx> ctx) {
    gen_expr((*e).child0, ctx);
    emit_pop_rax(ctx);
    Ptr<Type> from = (*(*e).child0).ety;
    Ptr<Type> to_t = (*e).cast_target;
    Long fk = (*from).kind;
    Long tk = (*to_t).kind;

    if (tk == TY_BOOLEAN()) {
        emit_str(ctx, cast<Ptr<Byte>>("    cmp rax, 0\n"));
        emit_str(ctx, cast<Ptr<Byte>>("    setne al\n"));
        emit_str(ctx, cast<Ptr<Byte>>("    movzx rax, al\n"));
        emit_push_rax(ctx);
        return 0;
    }
    Long from_sz = cg_type_size_kind(fk);
    Long to_sz = cg_type_size_kind(tk);
    Boolean from_sgn = cg_is_signed_kind(fk);
    if (fk == TY_BOOLEAN()) { from_sgn = false; }
    if (fk == TY_CHAR())    { from_sgn = false; }
    if (fk == TY_BYTE())    { from_sgn = false; }

    if (to_sz > from_sz) {
        if (from_sz == 1) {
            if (from_sgn) { emit_str(ctx, cast<Ptr<Byte>>("    movsx rax, al\n")); }
            else          { emit_str(ctx, cast<Ptr<Byte>>("    movzx rax, al\n")); }
        }
        if (from_sz == 2) {
            if (from_sgn) { emit_str(ctx, cast<Ptr<Byte>>("    movsx rax, ax\n")); }
            else          { emit_str(ctx, cast<Ptr<Byte>>("    movzx rax, ax\n")); }
        }
        if (from_sz == 4) {
            if (from_sgn) { emit_str(ctx, cast<Ptr<Byte>>("    movsxd rax, eax\n")); }
            else          { emit_str(ctx, cast<Ptr<Byte>>("    mov eax, eax\n")); }
        }
    } else {
        if (to_sz < from_sz) {
            Boolean to_sgn = false;
            if (tk == TY_INTEGER()) { to_sgn = true; }
            if (tk == TY_WHOLE())   { to_sgn = true; }
            if (tk == TY_LONG())    { to_sgn = true; }
            if (to_sz == 1) {
                if (to_sgn) { emit_str(ctx, cast<Ptr<Byte>>("    movsx rax, al\n")); }
                else        { emit_str(ctx, cast<Ptr<Byte>>("    movzx rax, al\n")); }
            }
            if (to_sz == 2) {
                if (to_sgn) { emit_str(ctx, cast<Ptr<Byte>>("    movsx rax, ax\n")); }
                else        { emit_str(ctx, cast<Ptr<Byte>>("    movzx rax, ax\n")); }
            }
            if (to_sz == 4) {
                if (to_sgn) { emit_str(ctx, cast<Ptr<Byte>>("    movsxd rax, eax\n")); }
                else        { emit_str(ctx, cast<Ptr<Byte>>("    mov eax, eax\n")); }
            }
        }
    }
    emit_push_rax(ctx);
    return 0;
}

// ---- gen_format_call: print/println ----

Long gen_format_call(Ptr<Expr> e, Ptr<CgCtx> ctx, Boolean append_newline) {
    Ptr<PtrVec> args_f = (*e).call_args;
    Ptr<Expr> fmt = cast<Ptr<Expr>>(ptrvec_get(args_f, 0));
    Ptr<Byte> src = (*fmt).str_data;
    Long len_f = (*fmt).str_len;

    Long i_f = 0;
    Long arg_idx = 1;

    while (i_f < len_f) {
        Long start_f = i_f;
        while (i_f < len_f) {
            if (cast<Long>(src[i_f]) == 37) { break; }    // '%'
            i_f = i_f + 1;
        }
        if (i_f > start_f) {
            Long cid = intern_cooked(ctx, src + start_f, i_f - start_f);
            Ptr<PtrVec> ck = (*ctx).cooked;
            Ptr<CookedStr> cs = cast<Ptr<CookedStr>>(ptrvec_get(ck, (*ck).count - 1));
            Long cooked_len = (*cs).len;
            emit_str(ctx, cast<Ptr<Byte>>("    lea rdi, [rel Lcstr_"));
            emit_long(ctx, cid);
            emit_str(ctx, cast<Ptr<Byte>>("]\n"));
            emit_str(ctx, cast<Ptr<Byte>>("    mov rsi, "));
            emit_long(ctx, cooked_len);
            emit_nl(ctx);
            emit_str(ctx, cast<Ptr<Byte>>("    call lazyc_write_bytes\n"));
        }
        if (i_f >= len_f) { break; }
        i_f = i_f + 1;     // consume '%'
        Long spec = cast<Long>(src[i_f]);
        i_f = i_f + 1;

        if (spec == 37) {       // '%%'
            Long pid = intern_cooked(ctx, cast<Ptr<Byte>>("%"), 1);
            emit_str(ctx, cast<Ptr<Byte>>("    lea rdi, [rel Lcstr_"));
            emit_long(ctx, pid);
            emit_str(ctx, cast<Ptr<Byte>>("]\n"));
            emit_str(ctx, cast<Ptr<Byte>>("    mov rsi, 1\n"));
            emit_str(ctx, cast<Ptr<Byte>>("    call lazyc_write_bytes\n"));
            continue;
        }

        Ptr<Expr> a_f = cast<Ptr<Expr>>(ptrvec_get(args_f, arg_idx));
        arg_idx = arg_idx + 1;
        gen_expr(a_f, ctx);
        emit_str(ctx, cast<Ptr<Byte>>("    pop rdi\n"));

        if (spec == 99)  { emit_str(ctx, cast<Ptr<Byte>>("    call lazyc_print_char\n"));   }
        if (spec == 105) { emit_str(ctx, cast<Ptr<Byte>>("    call lazyc_print_int16\n"));  }
        if (spec == 108) { emit_str(ctx, cast<Ptr<Byte>>("    call lazyc_print_long\n"));   }
        if (spec == 115) { emit_str(ctx, cast<Ptr<Byte>>("    call lazyc_print_string\n")); }
    }
    if (append_newline) {
        emit_str(ctx, cast<Ptr<Byte>>("    call lazyc_print_newline\n"));
    }
    return 0;
}

// ---- gen_call ----

Long gen_call(Ptr<Expr> e, Ptr<CgCtx> ctx) {
    Ptr<Byte> nm = (*e).name;
    Ptr<PtrVec> args_c = (*e).call_args;
    Long nargs = 0;
    if (args_c != cast<Ptr<PtrVec>>(null)) { nargs = (*args_c).count; }

    Boolean is_print   = ml_streq(nm, cast<Ptr<Byte>>("print"));
    Boolean is_println = ml_streq(nm, cast<Ptr<Byte>>("println"));
    Boolean is_pr = false;
    if (is_print)   { is_pr = true; }
    if (is_println) { is_pr = true; }
    if (is_pr) {
        gen_format_call(e, ctx, is_println);
        emit_str(ctx, cast<Ptr<Byte>>("    push 0\n"));
        return 0;
    }

    Boolean is_alloc = ml_streq(nm, cast<Ptr<Byte>>("alloc"));
    Boolean is_free  = ml_streq(nm, cast<Ptr<Byte>>("free"));
    Boolean is_exit  = ml_streq(nm, cast<Ptr<Byte>>("exit"));
    Boolean is_one_arg_builtin = false;
    if (is_alloc) { is_one_arg_builtin = true; }
    if (is_free)  { is_one_arg_builtin = true; }
    if (is_exit)  { is_one_arg_builtin = true; }
    if (is_one_arg_builtin) {
        Ptr<Expr> a0_b = cast<Ptr<Expr>>(ptrvec_get(args_c, 0));
        gen_expr(a0_b, ctx);
        emit_str(ctx, cast<Ptr<Byte>>("    pop rdi\n"));
        if (is_alloc)     { emit_str(ctx, cast<Ptr<Byte>>("    call lazyc_alloc\n")); }
        if (is_free)      { emit_str(ctx, cast<Ptr<Byte>>("    call lazyc_free\n")); }
        if (is_exit)      { emit_str(ctx, cast<Ptr<Byte>>("    call lazyc_exit\n")); }
        emit_push_rax(ctx);
        return 0;
    }

    Boolean is_readf  = ml_streq(nm, cast<Ptr<Byte>>("readf"));
    Boolean is_writef = ml_streq(nm, cast<Ptr<Byte>>("writef"));
    if (is_readf) {
        Ptr<Expr> a0_r = cast<Ptr<Expr>>(ptrvec_get(args_c, 0));
        gen_expr(a0_r, ctx);
        emit_str(ctx, cast<Ptr<Byte>>("    pop rdi\n"));
        emit_str(ctx, cast<Ptr<Byte>>("    call lazyc_readf\n"));
        emit_push_rax(ctx);
        return 0;
    }
    if (is_writef) {
        Ptr<Expr> a0_w = cast<Ptr<Expr>>(ptrvec_get(args_c, 0));
        Ptr<Expr> a1_w = cast<Ptr<Expr>>(ptrvec_get(args_c, 1));
        gen_expr(a0_w, ctx);
        gen_expr(a1_w, ctx);
        emit_str(ctx, cast<Ptr<Byte>>("    pop rsi\n"));
        emit_str(ctx, cast<Ptr<Byte>>("    pop rdi\n"));
        emit_str(ctx, cast<Ptr<Byte>>("    call lazyc_writef\n"));
        emit_push_rax(ctx);
        return 0;
    }

    Boolean is_argc = ml_streq(nm, cast<Ptr<Byte>>("argc"));
    Boolean is_argv = ml_streq(nm, cast<Ptr<Byte>>("argv"));
    if (is_argc) {
        emit_str(ctx, cast<Ptr<Byte>>("    call lazyc_argc\n"));
        emit_push_rax(ctx);
        return 0;
    }
    if (is_argv) {
        Ptr<Expr> a0_v = cast<Ptr<Expr>>(ptrvec_get(args_c, 0));
        gen_expr(a0_v, ctx);
        emit_str(ctx, cast<Ptr<Byte>>("    pop rdi\n"));
        emit_str(ctx, cast<Ptr<Byte>>("    call lazyc_argv\n"));
        emit_push_rax(ctx);
        return 0;
    }

    if (nargs > 6) {
        cg_error_at((*e).line, cast<Ptr<Byte>>("calls with more than 6 arguments are not supported"));
    }
    Long ci = 0;
    while (ci < nargs) {
        Ptr<Expr> ai = cast<Ptr<Expr>>(ptrvec_get(args_c, ci));
        gen_expr(ai, ctx);
        ci = ci + 1;
    }
    Long pi = nargs;
    while (pi > 0) {
        pi = pi - 1;
        Ptr<Byte> reg = arg_reg_for(pi, 8);
        emit_str(ctx, cast<Ptr<Byte>>("    pop "));
        emit_str(ctx, reg);
        emit_nl(ctx);
    }
    emit_str(ctx, cast<Ptr<Byte>>("    call "));
    emit_str(ctx, nm);
    emit_nl(ctx);
    emit_push_rax(ctx);
    return 0;
}

// ---- Lvalue address (for &x, &s.f, &arr[i]) ----

Long gen_lvalue_address(Ptr<Expr> e, Ptr<CgCtx> ctx) {
    Long lk = (*e).kind;
    if (lk == EX_IDENT()) {
        Ptr<Symbol> sy_l = symtab_find((*ctx).sym, (*e).name, (*e).name_len);
        if (sy_l == cast<Ptr<Symbol>>(null)) {
            cg_error_at((*e).line, cast<Ptr<Byte>>("internal: addr of unknown var"));
        }
        emit_mem_op(ctx, cast<Ptr<Byte>>("    lea rax, [rbp-"), (*sy_l).offset, cast<Ptr<Byte>>("]\n"));
        emit_push_rax(ctx);
        return 0;
    }
    if (lk == EX_DEREF()) {
        gen_expr((*e).child0, ctx);
        return 0;
    }
    if (lk == EX_FIELD()) {
        Ptr<Expr> op_l = (*e).child0;
        Ptr<Field> f_l = cast<Ptr<Field>>((*e).field_resolved);
        if (f_l == cast<Ptr<Field>>(null)) {
            cg_error_at((*e).line, cast<Ptr<Byte>>("internal: field not resolved"));
        }
        Long opk = (*op_l).kind;
        Boolean op_is_struct_ident = false;
        if (opk == EX_IDENT()) {
            if ((*(*op_l).ety).kind == TY_STRUCT()) { op_is_struct_ident = true; }
        }
        if (op_is_struct_ident) {
            Ptr<Symbol> sy_lf = symtab_find((*ctx).sym, (*op_l).name, (*op_l).name_len);
            if (sy_lf == cast<Ptr<Symbol>>(null)) {
                cg_error_at((*e).line, cast<Ptr<Byte>>("internal: addr-of field on unknown var"));
            }
            Long addr_l = (*sy_lf).offset - (*f_l).offset;
            emit_mem_op(ctx, cast<Ptr<Byte>>("    lea rax, [rbp-"), addr_l, cast<Ptr<Byte>>("]\n"));
            emit_push_rax(ctx);
            return 0;
        }
        if (opk == EX_DEREF()) {
            gen_expr((*op_l).child0, ctx);
            emit_pop_rax(ctx);
            if ((*f_l).offset != 0) {
                emit_op_rax_imm(ctx, cast<Ptr<Byte>>("add"), (*f_l).offset);
            }
            emit_push_rax(ctx);
            return 0;
        }
        cg_error_at((*e).line, cast<Ptr<Byte>>("internal: addr-of field with unexpected operand"));
    }
    if (lk == EX_INDEX()) {
        Long sz_l = cg_type_size((*e).ety);
        Ptr<Expr> base_l = (*e).child0;
        if ((*(*base_l).ety).kind == TY_ARRAY()) {
            gen_lvalue_address(base_l, ctx);
        } else {
            if ((*(*base_l).ety).kind == TY_PTR()) {
                gen_expr(base_l, ctx);
            } else {
                cg_error_at((*e).line, cast<Ptr<Byte>>("internal: index base has wrong type"));
            }
        }
        gen_expr((*e).child1, ctx);
        emit_pop_rax(ctx);
        if (sz_l != 1) {
            emit_str(ctx, cast<Ptr<Byte>>("    imul rax, rax, "));
            emit_long(ctx, sz_l);
            emit_nl(ctx);
        }
        emit_pop_rcx(ctx);
        emit_str(ctx, cast<Ptr<Byte>>("    add rax, rcx\n"));
        emit_push_rax(ctx);
        return 0;
    }
    cg_error_at((*e).line, cast<Ptr<Byte>>("internal: not an lvalue"));
    return 0;
}

// Push base[index] address with the given element size.
Long gen_index_addr(Ptr<Expr> base, Ptr<Expr> index, Long elem_size, Ptr<CgCtx> ctx) {
    if ((*(*base).ety).kind == TY_ARRAY()) {
        gen_lvalue_address(base, ctx);
    } else {
        if ((*(*base).ety).kind == TY_PTR()) {
            gen_expr(base, ctx);
        } else {
            cg_error_at((*base).line, cast<Ptr<Byte>>("internal: index on non-array, non-pointer"));
        }
    }
    gen_expr(index, ctx);
    emit_pop_rax(ctx);
    if (elem_size != 1) {
        emit_str(ctx, cast<Ptr<Byte>>("    imul rax, rax, "));
        emit_long(ctx, elem_size);
        emit_nl(ctx);
    }
    emit_pop_rcx(ctx);
    emit_str(ctx, cast<Ptr<Byte>>("    add rax, rcx\n"));
    emit_push_rax(ctx);
    return 0;
}

// ---- gen_stmt ----

Long gen_stmt(Ptr<Stmt> s, Ptr<CgCtx> ctx) {
    Long sk = (*s).kind;
    if (sk == ST_VAR_DECL()) {
        Ptr<Symbol> sy_v = symtab_find((*ctx).sym, (*s).var_name, (*s).var_name_len);
        if (sy_v == cast<Ptr<Symbol>>(null)) {
            cg_error_at((*s).line, cast<Ptr<Byte>>("internal: var not in symtab"));
        }
        if ((*s).var_init != cast<Ptr<Expr>>(null)) {
            gen_expr((*s).var_init, ctx);
            emit_pop_rax(ctx);
            emit_store_var(ctx, (*sy_v).ty, (*sy_v).offset);
        } else {
            emit_zero_var(ctx, (*sy_v).ty, (*sy_v).offset);
        }
        return 0;
    }
    if (sk == ST_ASSIGN()) {
        Ptr<Symbol> sy_a = symtab_find((*ctx).sym, (*s).var_name, (*s).var_name_len);
        if (sy_a == cast<Ptr<Symbol>>(null)) {
            cg_error_at((*s).line, cast<Ptr<Byte>>("internal: assignment to unknown var"));
        }
        gen_expr((*s).assign_value, ctx);
        emit_pop_rax(ctx);
        emit_store_var(ctx, (*sy_a).ty, (*sy_a).offset);
        return 0;
    }
    if (sk == ST_PTR_STORE()) {
        Ptr<Expr> deref_e = (*s).store_target;
        Ptr<Expr> pexpr = (*deref_e).child0;
        Ptr<Type> pointee_t = (*deref_e).ety;
        gen_expr(pexpr, ctx);
        gen_expr((*s).store_value, ctx);
        emit_pop_rax(ctx);
        emit_pop_rcx(ctx);
        Long sz_p = cg_type_size_kind((*pointee_t).kind);
        emit_store_via_rcx(ctx, sz_p);
        return 0;
    }
    if (sk == ST_FIELD_STORE()) {
        Ptr<Expr> fld_e = (*s).store_target;
        Ptr<Expr> op_fs = (*fld_e).child0;
        Ptr<Field> f_fs = cast<Ptr<Field>>((*fld_e).field_resolved);
        if (f_fs == cast<Ptr<Field>>(null)) {
            cg_error_at((*s).line, cast<Ptr<Byte>>("internal: field not resolved"));
        }
        Ptr<Type> fty_fs = cast<Ptr<Type>>((*f_fs).ty);
        Long sz_fs = cg_type_size_kind((*fty_fs).kind);
        if ((*op_fs).kind == EX_IDENT()) {
            Ptr<Symbol> sy_fs = symtab_find((*ctx).sym, (*op_fs).name, (*op_fs).name_len);
            if (sy_fs == cast<Ptr<Symbol>>(null)) {
                cg_error_at((*s).line, cast<Ptr<Byte>>("internal: field-store on unknown var"));
            }
            Long addr_fs = (*sy_fs).offset - (*f_fs).offset;
            gen_expr((*s).store_value, ctx);
            emit_pop_rax(ctx);
            if (sz_fs == 1) {
                emit_mem_op(ctx, cast<Ptr<Byte>>("    mov byte  [rbp-"), addr_fs, cast<Ptr<Byte>>("], al\n"));
            } else {
                if (sz_fs == 2) {
                    emit_mem_op(ctx, cast<Ptr<Byte>>("    mov word  [rbp-"), addr_fs, cast<Ptr<Byte>>("], ax\n"));
                } else {
                    if (sz_fs == 4) {
                        emit_mem_op(ctx, cast<Ptr<Byte>>("    mov dword [rbp-"), addr_fs, cast<Ptr<Byte>>("], eax\n"));
                    } else {
                        emit_mem_op(ctx, cast<Ptr<Byte>>("    mov qword [rbp-"), addr_fs, cast<Ptr<Byte>>("], rax\n"));
                    }
                }
            }
            return 0;
        }
        // EX_DEREF case
        gen_expr((*op_fs).child0, ctx);
        gen_expr((*s).store_value, ctx);
        emit_pop_rax(ctx);
        emit_pop_rcx(ctx);
        if ((*f_fs).offset != 0) {
            emit_str(ctx, cast<Ptr<Byte>>("    add rcx, "));
            emit_long(ctx, (*f_fs).offset);
            emit_nl(ctx);
        }
        emit_store_via_rcx(ctx, sz_fs);
        return 0;
    }
    if (sk == ST_INDEX_STORE()) {
        Ptr<Expr> idx_e = (*s).store_target;
        Long sz_is = cg_type_size_kind((*(*idx_e).ety).kind);
        gen_index_addr((*idx_e).child0, (*idx_e).child1, sz_is, ctx);
        gen_expr((*s).store_value, ctx);
        emit_pop_rax(ctx);
        emit_pop_rcx(ctx);
        emit_store_via_rcx(ctx, sz_is);
        return 0;
    }
    if (sk == ST_RETURN()) {
        if ((*s).ret_value != cast<Ptr<Expr>>(null)) {
            gen_expr((*s).ret_value, ctx);
            emit_pop_rax(ctx);
        } else {
            emit_str(ctx, cast<Ptr<Byte>>("    xor rax, rax\n"));
        }
        emit_str(ctx, cast<Ptr<Byte>>("    leave\n"));
        emit_str(ctx, cast<Ptr<Byte>>("    ret\n"));
        return 0;
    }
    if (sk == ST_BLOCK()) {
        Ptr<PtrVec> ss = (*s).block_stmts;
        if (ss != cast<Ptr<PtrVec>>(null)) {
            Long n = (*ss).count;
            Long bi = 0;
            while (bi < n) {
                Ptr<Stmt> child = cast<Ptr<Stmt>>(ptrvec_get(ss, bi));
                gen_stmt(child, ctx);
                bi = bi + 1;
            }
        }
        return 0;
    }
    if (sk == ST_EXPR()) {
        gen_expr((*s).expr, ctx);
        emit_str(ctx, cast<Ptr<Byte>>("    add rsp, 8\n"));
        return 0;
    }
    if (sk == ST_IF()) {
        Long if_else_lbl = new_label(ctx);
        Long if_end_lbl = if_else_lbl;
        Boolean has_else = false;
        if ((*s).else_b != cast<Ptr<Stmt>>(null)) {
            has_else = true;
            if_end_lbl = new_label(ctx);
        }
        gen_expr((*s).cond, ctx);
        emit_pop_rax(ctx);
        emit_str(ctx, cast<Ptr<Byte>>("    cmp rax, 0\n"));
        emit_jmp(ctx, cast<Ptr<Byte>>("je"), if_else_lbl);
        gen_stmt((*s).then_b, ctx);
        if (has_else) {
            emit_jmp(ctx, cast<Ptr<Byte>>("jmp"), if_end_lbl);
            emit_label_def(ctx, if_else_lbl);
            gen_stmt((*s).else_b, ctx);
        }
        emit_label_def(ctx, if_end_lbl);
        return 0;
    }
    if (sk == ST_WHILE()) {
        Long wh_top_lbl = new_label(ctx);
        Long wh_end_lbl = new_label(ctx);
        emit_label_def(ctx, wh_top_lbl);
        gen_expr((*s).cond, ctx);
        emit_pop_rax(ctx);
        emit_str(ctx, cast<Ptr<Byte>>("    cmp rax, 0\n"));
        emit_jmp(ctx, cast<Ptr<Byte>>("je"), wh_end_lbl);
        loop_push(ctx, wh_end_lbl, wh_top_lbl);
        gen_stmt((*s).body, ctx);
        loop_pop(ctx);
        emit_jmp(ctx, cast<Ptr<Byte>>("jmp"), wh_top_lbl);
        emit_label_def(ctx, wh_end_lbl);
        return 0;
    }
    if (sk == ST_FOR()) {
        Long for_top_lbl  = new_label(ctx);
        Long for_step_lbl = new_label(ctx);
        Long for_end_lbl  = new_label(ctx);
        if ((*s).for_init != cast<Ptr<Stmt>>(null)) { gen_stmt((*s).for_init, ctx); }
        emit_label_def(ctx, for_top_lbl);
        if ((*s).cond != cast<Ptr<Expr>>(null)) {
            gen_expr((*s).cond, ctx);
            emit_pop_rax(ctx);
            emit_str(ctx, cast<Ptr<Byte>>("    cmp rax, 0\n"));
            emit_jmp(ctx, cast<Ptr<Byte>>("je"), for_end_lbl);
        }
        loop_push(ctx, for_end_lbl, for_step_lbl);
        gen_stmt((*s).body, ctx);
        loop_pop(ctx);
        emit_label_def(ctx, for_step_lbl);
        if ((*s).for_update != cast<Ptr<Stmt>>(null)) { gen_stmt((*s).for_update, ctx); }
        emit_jmp(ctx, cast<Ptr<Byte>>("jmp"), for_top_lbl);
        emit_label_def(ctx, for_end_lbl);
        return 0;
    }
    if (sk == ST_BREAK()) {
        if (loop_depth_now(ctx) == 0) {
            cg_error_at((*s).line, cast<Ptr<Byte>>("internal: 'break' outside loop reached codegen"));
        }
        emit_jmp(ctx, cast<Ptr<Byte>>("jmp"), loop_break_lbl(ctx));
        return 0;
    }
    if (sk == ST_CONTINUE()) {
        if (loop_depth_now(ctx) == 0) {
            cg_error_at((*s).line, cast<Ptr<Byte>>("internal: 'continue' outside loop reached codegen"));
        }
        emit_jmp(ctx, cast<Ptr<Byte>>("jmp"), loop_continue_lbl(ctx));
        return 0;
    }
    cg_error_at((*s).line, cast<Ptr<Byte>>("statement not supported"));
    return 0;
}

// ---- gen_func ----

Long gen_func(Ptr<FuncDecl> f, Ptr<CgCtx> ctx) {
    Ptr<PtrVec> params = (*f).params;
    Long nparams = 0;
    if (params != cast<Ptr<PtrVec>>(null)) { nparams = (*params).count; }
    if (nparams > 6) {
        cg_error_at((*f).line, cast<Ptr<Byte>>("functions with more than 6 parameters are not supported"));
    }
    // Reset loop stack at function entry/exit.
    Ptr<PtrVec> ls = (*ctx).loop_stack;
    (*ls).count = 0;

    Ptr<SymTab> st = symtab_new();
    (*ctx).sym = st;
    // Add parameters first.
    Long pi_a = 0;
    while (pi_a < nparams) {
        Ptr<Param> pa = cast<Ptr<Param>>(ptrvec_get(params, pi_a));
        symtab_add(st, (*pa).name, (*pa).name_len, (*pa).ty, (*f).line);
        pi_a = pi_a + 1;
    }
    collect_locals_stmt((*f).body, st);
    Long frame = symtab_stack_size_aligned(st);

    emit_str(ctx, cast<Ptr<Byte>>("global "));
    emit_str(ctx, (*f).name);
    emit_nl(ctx);
    emit_str(ctx, (*f).name);
    emit_str(ctx, cast<Ptr<Byte>>(":\n"));
    emit_str(ctx, cast<Ptr<Byte>>("    push rbp\n"));
    emit_str(ctx, cast<Ptr<Byte>>("    mov rbp, rsp\n"));
    if (frame > 0) {
        emit_str(ctx, cast<Ptr<Byte>>("    sub rsp, "));
        emit_long(ctx, frame);
        emit_nl(ctx);
    }

    // Spill parameter registers.
    Long pi_s = 0;
    while (pi_s < nparams) {
        Ptr<Param> ps = cast<Ptr<Param>>(ptrvec_get(params, pi_s));
        Ptr<Symbol> sy_sp = symtab_find(st, (*ps).name, (*ps).name_len);
        Long sz_sp = cg_type_size_kind((*(*sy_sp).ty).kind);
        Ptr<Byte> reg = arg_reg_for(pi_s, sz_sp);
        if (sz_sp == 1) {
            emit_str(ctx, cast<Ptr<Byte>>("    mov byte  [rbp-"));
        } else {
            if (sz_sp == 2) {
                emit_str(ctx, cast<Ptr<Byte>>("    mov word  [rbp-"));
            } else {
                if (sz_sp == 4) {
                    emit_str(ctx, cast<Ptr<Byte>>("    mov dword [rbp-"));
                } else {
                    emit_str(ctx, cast<Ptr<Byte>>("    mov qword [rbp-"));
                }
            }
        }
        emit_long(ctx, (*sy_sp).offset);
        emit_str(ctx, cast<Ptr<Byte>>("], "));
        emit_str(ctx, reg);
        emit_nl(ctx);
        pi_s = pi_s + 1;
    }

    gen_stmt((*f).body, ctx);

    // Default epilogue.
    emit_str(ctx, cast<Ptr<Byte>>("    xor rax, rax\n"));
    emit_str(ctx, cast<Ptr<Byte>>("    leave\n"));
    emit_str(ctx, cast<Ptr<Byte>>("    ret\n"));

    return 0;
}

// ---- codegen_program ----

// Emit one StrLit's data in `db ...,0` form. The bytes go through escape
// processing on the fly (matches the C compiler's emit-time decoding for
// strlits, distinct from the cooked-pool which decoded earlier).
Long emit_strlit_data(Ptr<CgCtx> ctx, Ptr<StrLit> s) {
    emit_str(ctx, cast<Ptr<Byte>>("Lstr_"));
    emit_long(ctx, (*s).label_id);
    emit_str(ctx, cast<Ptr<Byte>>(": db "));
    Long len_s = (*s).len;
    Ptr<Byte> data_s = (*s).data;
    Boolean first = true;
    Long j = 0;
    while (j < len_s) {
        Long c = cast<Long>(data_s[j]);
        Boolean did_esc = false;
        if (c == 92) {                 // '\'
            if (j + 1 < len_s) {
                Long esc = cast<Long>(data_s[j + 1]);
                if (esc == 120) {                // 'x' -> \xHH
                    if (j + 3 < len_s) {
                        Long h1 = cast<Long>(data_s[j + 2]);
                        Long h2 = cast<Long>(data_s[j + 3]);
                        Long d1 = -1;
                        Long d2 = -1;
                        if (h1 >= 48) { if (h1 <= 57) { d1 = h1 - 48; } }
                        if (h1 >= 97) { if (h1 <= 102){ d1 = h1 - 97 + 10; } }
                        if (h1 >= 65) { if (h1 <= 70) { d1 = h1 - 65 + 10; } }
                        if (h2 >= 48) { if (h2 <= 57) { d2 = h2 - 48; } }
                        if (h2 >= 97) { if (h2 <= 102){ d2 = h2 - 97 + 10; } }
                        if (h2 >= 65) { if (h2 <= 70) { d2 = h2 - 65 + 10; } }
                        Boolean both_ok = false;
                        if (d1 >= 0) { if (d2 >= 0) { both_ok = true; } }
                        if (both_ok) {
                            c = d1 * 16 + d2;
                            j = j + 4;
                            did_esc = true;
                        }
                    }
                }
                if (!did_esc) {
                    Long resolved = esc;
                    if (esc == 110) { resolved = 10;  }
                    if (esc == 116) { resolved = 9;   }
                    if (esc == 114) { resolved = 13;  }
                    if (esc == 48)  { resolved = 0;   }
                    if (esc == 92)  { resolved = 92;  }
                    if (esc == 39)  { resolved = 39;  }
                    if (esc == 34)  { resolved = 34;  }
                    c = resolved;
                    j = j + 2;
                    did_esc = true;
                }
            }
        }
        if (!did_esc) { j = j + 1; }
        if (!first) {
            emit_str(ctx, cast<Ptr<Byte>>(","));
        }
        emit_long(ctx, c);
        first = false;
    }
    if (!first) {
        emit_str(ctx, cast<Ptr<Byte>>(","));
    }
    emit_str(ctx, cast<Ptr<Byte>>("0\n"));
    return 0;
}

Long emit_cooked_data(Ptr<CgCtx> ctx, Ptr<CookedStr> cs) {
    emit_str(ctx, cast<Ptr<Byte>>("Lcstr_"));
    emit_long(ctx, (*cs).label_id);
    emit_str(ctx, cast<Ptr<Byte>>(": db "));
    Long ln = (*cs).len;
    if (ln == 0) {
        emit_str(ctx, cast<Ptr<Byte>>("0\n"));
        return 0;
    }
    Long j = 0;
    while (j < ln) {
        if (j != 0) { emit_str(ctx, cast<Ptr<Byte>>(",")); }
        emit_long(ctx, cast<Long>((*cs).bytes[j]));
        j = j + 1;
    }
    emit_nl(ctx);
    return 0;
}

Long codegen_program(Ptr<Program> pg, Ptr<Buf> out) {
    Ptr<CgCtx> ctx = cgctx_new(out);

    emit_str(ctx, cast<Ptr<Byte>>("; auto-generated by lazyc\n"));

    // Builtin externs: emitted by default so user code doesn't need to
    // declare them. But if the current program defines one of these
    // names as a non-extern function (e.g. when compiling runtime.ml
    // itself), skip the `extern` to avoid nasm's "label inconsistently
    // redefined" error.
    Ptr<PtrVec> pg_funcs = (*pg).funcs;
    Long pg_nf = (*pg_funcs).count;

    // Walk through the 13 builtin names; for each, scan the program's
    // funcs for a matching non-extern definition and only emit the
    // `extern` if no match is found.
    Long bi = 0;
    while (bi < 13) {
        Ptr<Byte> bname = cast<Ptr<Byte>>(null);
        if (bi == 0)  { bname = cast<Ptr<Byte>>("lazyc_write_bytes"); }
        if (bi == 1)  { bname = cast<Ptr<Byte>>("lazyc_print_char"); }
        if (bi == 2)  { bname = cast<Ptr<Byte>>("lazyc_print_int16"); }
        if (bi == 3)  { bname = cast<Ptr<Byte>>("lazyc_print_long"); }
        if (bi == 4)  { bname = cast<Ptr<Byte>>("lazyc_print_string"); }
        if (bi == 5)  { bname = cast<Ptr<Byte>>("lazyc_print_newline"); }
        if (bi == 6)  { bname = cast<Ptr<Byte>>("lazyc_alloc"); }
        if (bi == 7)  { bname = cast<Ptr<Byte>>("lazyc_free"); }
        if (bi == 8)  { bname = cast<Ptr<Byte>>("lazyc_exit"); }
        if (bi == 9)  { bname = cast<Ptr<Byte>>("lazyc_readf"); }
        if (bi == 10) { bname = cast<Ptr<Byte>>("lazyc_writef"); }
        if (bi == 11) { bname = cast<Ptr<Byte>>("lazyc_argc"); }
        if (bi == 12) { bname = cast<Ptr<Byte>>("lazyc_argv"); }

        Boolean defined_locally = false;
        Long pi = 0;
        while (pi < pg_nf) {
            Ptr<FuncDecl> pf = cast<Ptr<FuncDecl>>(ptrvec_get(pg_funcs, pi));
            if ((*pf).is_extern == 0) {
                if (ml_streq((*pf).name, bname)) {
                    defined_locally = true;
                }
            }
            pi = pi + 1;
        }

        if (!defined_locally) {
            emit_str(ctx, cast<Ptr<Byte>>("extern "));
            emit_str(ctx, bname);
            emit_nl(ctx);
        }
        bi = bi + 1;
    }

    // User-declared externs (e.g. syscall trampolines): emit one
    // `extern <name>` per is_extern function so the linker can resolve
    // calls to it.
    Ptr<PtrVec> all_funcs_for_extern = (*pg).funcs;
    Long n_for_extern = (*all_funcs_for_extern).count;
    Long fxi = 0;
    while (fxi < n_for_extern) {
        Ptr<FuncDecl> fx = cast<Ptr<FuncDecl>>(ptrvec_get(all_funcs_for_extern, fxi));
        if ((*fx).is_extern != 0) {
            emit_str(ctx, cast<Ptr<Byte>>("extern "));
            emit_str(ctx, (*fx).name);
            emit_nl(ctx);
        }
        fxi = fxi + 1;
    }
    emit_str(ctx, cast<Ptr<Byte>>("section .text\n"));

    Ptr<PtrVec> funcs = (*pg).funcs;
    Long nf = (*funcs).count;
    Long fi = 0;
    while (fi < nf) {
        Ptr<FuncDecl> fd = cast<Ptr<FuncDecl>>(ptrvec_get(funcs, fi));
        if ((*fd).is_extern == 0) {
            gen_func(fd, ctx);
        }
        fi = fi + 1;
    }

    Ptr<PtrVec> sl = (*ctx).strlits;
    Ptr<PtrVec> ck = (*ctx).cooked;
    Boolean has_rodata = false;
    if ((*sl).count > 0) { has_rodata = true; }
    if ((*ck).count > 0) { has_rodata = true; }

    if (has_rodata) {
        emit_str(ctx, cast<Ptr<Byte>>("section .rodata\n"));
        Long si = 0;
        while (si < (*sl).count) {
            Ptr<StrLit> s = cast<Ptr<StrLit>>(ptrvec_get(sl, si));
            emit_strlit_data(ctx, s);
            si = si + 1;
        }
        Long ci = 0;
        while (ci < (*ck).count) {
            Ptr<CookedStr> cs = cast<Ptr<CookedStr>>(ptrvec_get(ck, ci));
            emit_cooked_data(ctx, cs);
            ci = ci + 1;
        }
    }
    return 0;
}
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
