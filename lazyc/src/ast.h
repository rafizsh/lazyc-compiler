#ifndef AST_H
#define AST_H

#include "lexer.h"

typedef enum {
    TY_BOOLEAN, TY_CHAR, TY_BYTE,
    TY_INTEGER, TY_UINTEGER,
    TY_WHOLE,   TY_UWHOLE,
    TY_LONG,    TY_ULONG,
    TY_STRING,
    TY_PTR,
    TY_STRUCT,
    TY_ARRAY,
    TY_VOID,
    TY_UNKNOWN
} TypeKind;

typedef struct Type Type;
typedef struct StructDef StructDef;
typedef struct Field Field;
struct Type {
    TypeKind kind;
    Type *pointee;       // non-NULL only when kind == TY_PTR
    StructDef *sdef;     // non-NULL only when kind == TY_STRUCT
    Type *elem;          // non-NULL only when kind == TY_ARRAY
    int   nelems;        // valid only when kind == TY_ARRAY
};

typedef enum {
    EX_NUMBER, EX_CHAR_LIT, EX_STRING_LIT, EX_BOOL_LIT,
    EX_IDENT,
    EX_BINARY, EX_UNARY,
    EX_CALL,
    EX_CAST,
    EX_ADDR_OF,
    EX_DEREF,
    EX_NULL,
    EX_FIELD,
    EX_INDEX
} ExprKind;

typedef enum {
    OP_ADD, OP_SUB, OP_MUL, OP_DIV, OP_MOD,
    OP_EQ, OP_NEQ, OP_LT, OP_GT, OP_LE, OP_GE,
    OP_NEG, OP_NOT
} OpKind;

typedef struct Expr Expr;

struct Expr {
    ExprKind kind;
    Type type;
    int  is_untyped_int;
    int  is_untyped_null;
    int  line;
    union {
        long long  num;
        char       ch;
        struct { const char *data; size_t len; } str;
        int        boolean;
        struct { const char *name; size_t len; } ident;
        struct { OpKind op; Expr *lhs, *rhs; } bin;
        struct { OpKind op; Expr *operand; }    un;
        struct { const char *name; size_t name_len;
                 Expr **args; size_t nargs; }   call;
        struct { Type target; Expr *operand; }  cast;
        struct { Expr *target; }                addr;
        struct { Expr *operand; }               deref;
        struct {
            Expr *operand;          // must evaluate to a struct value
            const char *name;       // field name (slice into source)
            size_t name_len;
            Field *resolved;        // set by typechecker (NULL until tc)
        } field;
        struct {
            Expr *base;             // array (lvalue) or Ptr<T>
            Expr *index;            // integer-shaped index
        } index;
    };
};

typedef enum {
    ST_VAR_DECL,
    ST_ASSIGN,
    ST_PTR_STORE,
    ST_FIELD_STORE,
    ST_INDEX_STORE,
    ST_IF,
    ST_WHILE,
    ST_FOR,
    ST_RETURN,
    ST_BREAK,
    ST_CONTINUE,
    ST_BLOCK,
    ST_EXPR
} StmtKind;

typedef struct Stmt Stmt;

struct Stmt {
    StmtKind kind;
    int line;
    union {
        struct { Type ty; const char *name; size_t name_len; Expr *init; } var;
        struct { const char *name; size_t name_len; Expr *value; } assign;
        struct { Expr *target; Expr *value; } ptr_store;
        struct { Expr *target; Expr *value; } field_store;
        struct { Expr *target; Expr *value; } index_store;
        struct { Expr *cond; Stmt *then_b; Stmt *else_b; } if_s;
        struct { Expr *cond; Stmt *body; } while_s;
        struct { Stmt *init; Expr *cond; Stmt *update; Stmt *body; } for_s;
        struct { Expr *value; } ret;
        struct { Stmt **stmts; size_t n; } block;
        struct { Expr *expr; } expr_s;
    };
};

typedef struct {
    Type ty;
    const char *name;
    size_t name_len;
} Param;

struct Field {
    Type ty;
    const char *name;
    size_t name_len;
    int offset;
};

struct StructDef {
    const char *name;
    size_t name_len;
    Field *fields;
    size_t nfields;
    int size;
    int align;
    int line;
};

typedef struct {
    Type return_ty;
    const char *name;
    size_t name_len;
    Param *params;
    size_t nparams;
    Stmt *body;          // null if is_extern
    int is_extern;
    int line;
} FuncDecl;

typedef struct {
    FuncDecl **funcs;
    size_t nfuncs;
    StructDef **structs;
    size_t nstructs;
} Program;

void print_program(Program *p);

#endif
