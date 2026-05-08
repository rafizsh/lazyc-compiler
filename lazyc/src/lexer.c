#include "lexer.h"
#include <ctype.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>

void lexer_init(Lexer *l, const char *src) {
    l->src = src; l->cur = src; l->line = 1;
}

static int at_end(Lexer *l) { return *l->cur == '\0'; }
static char peek(Lexer *l)  { return *l->cur; }
static char peek2(Lexer *l) { return l->cur[0] ? l->cur[1] : '\0'; }
static char advance(Lexer *l) {
    char c = *l->cur++;
    if (c == '\n') l->line++;
    return c;
}
static int match(Lexer *l, char c) {
    if (peek(l) != c) return 0;
    l->cur++;
    return 1;
}

static void skip_whitespace_and_comments(Lexer *l) {
    for (;;) {
        char c = peek(l);
        if (c == ' ' || c == '\t' || c == '\r' || c == '\n') {
            advance(l);
        } else if (c == '/' && peek2(l) == '/') {
            while (!at_end(l) && peek(l) != '\n') advance(l);
        } else if (c == '/' && peek2(l) == '*') {
            advance(l); advance(l);
            while (!at_end(l) && !(peek(l) == '*' && peek2(l) == '/')) advance(l);
            if (!at_end(l)) { advance(l); advance(l); }
        } else {
            break;
        }
    }
}

static Token make_tok(Lexer *l, TokenKind k, const char *start) {
    Token t;
    t.kind = k;
    t.start = start;
    t.length = (size_t)(l->cur - start);
    t.line = l->line;
    t.int_value = 0;
    t.char_value = 0;
    return t;
}

static Token error_tok(Lexer *l, const char *msg) {
    Token t;
    t.kind = TOK_ERROR;
    t.start = msg;
    t.length = strlen(msg);
    t.line = l->line;
    t.int_value = 0;
    t.char_value = 0;
    return t;
}

static TokenKind ident_kind(const char *s, size_t n) {
    #define KW(kw, tok) if (n == sizeof(kw)-1 && memcmp(s, kw, n) == 0) return tok
    KW("Boolean",  TOK_BOOLEAN);
    KW("Char",     TOK_CHAR);
    KW("Byte",     TOK_BYTE);
    KW("Integer",  TOK_INTEGER);
    KW("uInteger", TOK_UINTEGER);
    KW("Whole",    TOK_WHOLE);
    KW("uWhole",   TOK_UWHOLE);
    KW("Long",     TOK_LONG);
    KW("uLong",    TOK_ULONG);
    KW("String",   TOK_STRING);
    KW("Ptr",      TOK_PTR);
    KW("true",     TOK_TRUE);
    KW("false",    TOK_FALSE);
    KW("null",     TOK_NULL);
    KW("if",       TOK_IF);
    KW("else",     TOK_ELSE);
    KW("while",    TOK_WHILE);
    KW("for",      TOK_FOR);
    KW("return",   TOK_RETURN);
    KW("cast",     TOK_CAST);
    KW("struct",   TOK_STRUCT);
    KW("break",    TOK_BREAK);
    KW("continue", TOK_CONTINUE);
    KW("extern",   TOK_EXTERN);
    #undef KW
    return TOK_IDENT;
}

static Token lex_ident(Lexer *l, const char *start) {
    while (isalnum((unsigned char)peek(l)) || peek(l) == '_') advance(l);
    Token t = make_tok(l, TOK_IDENT, start);
    t.kind = ident_kind(start, t.length);
    return t;
}

static Token lex_number(Lexer *l, const char *start) {
    while (isdigit((unsigned char)peek(l))) advance(l);
    Token t = make_tok(l, TOK_NUMBER, start);
    char buf[32];
    size_t n = t.length < 31 ? t.length : 31;
    memcpy(buf, start, n);
    buf[n] = '\0';
    t.int_value = strtoll(buf, NULL, 10);
    return t;
}

static Token lex_char(Lexer *l, const char *start) {
    char c = advance(l);
    if (c == '\\') {
        char esc = advance(l);
        switch (esc) {
            case 'n':  c = '\n'; break;
            case 't':  c = '\t'; break;
            case 'r':  c = '\r'; break;
            case '0':  c = '\0'; break;
            case '\\': c = '\\'; break;
            case '\'': c = '\''; break;
            case '"':  c = '"';  break;
            default: return error_tok(l, "unknown escape in char literal");
        }
    }
    if (peek(l) != '\'') return error_tok(l, "unterminated char literal");
    advance(l);
    Token t = make_tok(l, TOK_CHAR_LIT, start);
    t.char_value = c;
    return t;
}

static Token lex_string(Lexer *l, const char *start) {
    while (!at_end(l) && peek(l) != '"') {
        if (peek(l) == '\\') advance(l);
        advance(l);
    }
    if (at_end(l)) return error_tok(l, "unterminated string literal");
    advance(l);
    return make_tok(l, TOK_STRING_LIT, start);
}

Token lexer_next(Lexer *l) {
    skip_whitespace_and_comments(l);
    const char *start = l->cur;
    if (at_end(l)) return make_tok(l, TOK_EOF, start);

    char c = advance(l);

    if (isalpha((unsigned char)c) || c == '_') return lex_ident(l, start);
    if (isdigit((unsigned char)c))             return lex_number(l, start);
    if (c == '\'')                              return lex_char(l, start + 1);
    if (c == '"')                               return lex_string(l, start);

    switch (c) {
        case '+': return make_tok(l, TOK_PLUS,    start);
        case '-': return make_tok(l, TOK_MINUS,   start);
        case '*': return make_tok(l, TOK_STAR,    start);
        case '/': return make_tok(l, TOK_SLASH,   start);
        case '%': return make_tok(l, TOK_PERCENT, start);
        case '(': return make_tok(l, TOK_LPAREN,  start);
        case ')': return make_tok(l, TOK_RPAREN,  start);
        case '{': return make_tok(l, TOK_LBRACE,  start);
        case '}': return make_tok(l, TOK_RBRACE,  start);
        case '[': return make_tok(l, TOK_LBRACKET, start);
        case ']': return make_tok(l, TOK_RBRACKET, start);
        case ';': return make_tok(l, TOK_SEMI,    start);
        case ',': return make_tok(l, TOK_COMMA,   start);
        case '.': return make_tok(l, TOK_DOT,     start);
        case '=': return make_tok(l, match(l, '=') ? TOK_EQ  : TOK_ASSIGN, start);
        case '!': return make_tok(l, match(l, '=') ? TOK_NEQ : TOK_BANG,   start);
        case '<': return make_tok(l, match(l, '=') ? TOK_LE  : TOK_LT,     start);
        case '>': return make_tok(l, match(l, '=') ? TOK_GE  : TOK_GT,     start);
        case '&': return make_tok(l, TOK_AMP, start);
    }
    return error_tok(l, "unexpected character");
}

const char *token_kind_name(TokenKind k) {
    static const char *names[] = {
        "NUMBER","CHAR_LIT","STRING_LIT","IDENT",
        "Boolean","Char","Byte","Integer","uInteger","Whole","uWhole","Long","uLong","String","Ptr",
        "true","false","null","if","else","while","for","return","cast","struct","break","continue","extern",
        "+","-","*","/","%",
        "=","==","!=","<",">","<=",">=","!","&",
        "(",")","{","}","[","]",";",",",".",
        "EOF","ERROR"
    };
    return names[k];
}
