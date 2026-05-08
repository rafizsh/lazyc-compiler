#ifndef LEXER_H
#define LEXER_H

#include <stddef.h>

typedef enum {
    TOK_NUMBER, TOK_CHAR_LIT, TOK_STRING_LIT, TOK_IDENT,

    TOK_BOOLEAN, TOK_CHAR, TOK_BYTE,
    TOK_INTEGER, TOK_UINTEGER,
    TOK_WHOLE,   TOK_UWHOLE,
    TOK_LONG,    TOK_ULONG,
    TOK_STRING,
    TOK_PTR,

    TOK_TRUE, TOK_FALSE,
    TOK_NULL,
    TOK_IF, TOK_ELSE,
    TOK_WHILE, TOK_FOR,
    TOK_RETURN,
    TOK_CAST,
    TOK_STRUCT,
    TOK_BREAK,
    TOK_CONTINUE,
    TOK_EXTERN,

    TOK_PLUS, TOK_MINUS, TOK_STAR, TOK_SLASH, TOK_PERCENT,
    TOK_ASSIGN,
    TOK_EQ, TOK_NEQ,
    TOK_LT, TOK_GT, TOK_LE, TOK_GE,
    TOK_BANG,
    TOK_AMP,
    TOK_LPAREN, TOK_RPAREN,
    TOK_LBRACE, TOK_RBRACE,
    TOK_LBRACKET, TOK_RBRACKET,
    TOK_SEMI, TOK_COMMA,
    TOK_DOT,

    TOK_EOF, TOK_ERROR
} TokenKind;

typedef struct {
    TokenKind kind;
    const char *start;
    size_t length;
    int line;
    long long int_value;
    char char_value;
} Token;

typedef struct {
    const char *src;
    const char *cur;
    int line;
} Lexer;

void   lexer_init(Lexer *l, const char *src);
Token  lexer_next(Lexer *l);
const char *token_kind_name(TokenKind k);

#endif
