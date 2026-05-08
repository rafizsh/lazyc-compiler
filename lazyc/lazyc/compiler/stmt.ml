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
