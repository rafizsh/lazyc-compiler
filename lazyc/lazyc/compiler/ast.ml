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
