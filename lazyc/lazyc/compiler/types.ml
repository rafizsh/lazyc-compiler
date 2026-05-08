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
