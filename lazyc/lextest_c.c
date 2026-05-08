// C-side lextest for cross-checking against the mylang lexer.
// Build:  gcc -Iinclude -o /tmp/lextest_c lextest_c.c src/lexer.c
// Usage:  /tmp/lextest_c <source.ml>
//
// Output format mimics the mylang lextest so diffs are easy.

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include "src/lexer.h"

static char *slurp(const char *path) {
    FILE *f = fopen(path, "rb");
    if (!f) { perror(path); exit(1); }
    struct stat st;
    fstat(fileno(f), &st);
    char *buf = malloc(st.st_size + 1);
    fread(buf, 1, st.st_size, f);
    buf[st.st_size] = '\0';
    fclose(f);
    return buf;
}

int main(int argc, char **argv) {
    if (argc < 2) { fprintf(stderr, "usage: %s <src>\n", argv[0]); return 1; }
    char *src = slurp(argv[1]);
    Lexer l;
    lexer_init(&l, src);
    for (;;) {
        Token t = lexer_next(&l);
        // Build a printable version of the token text.
        // For identifiers/numbers/strings/chars, the text is t.start[0..t.length).
        // To match the mylang lexer's STRING_LIT (raw inner without quotes):
        //   - If kind == STRING_LIT, slice off leading and trailing '"'.
        // Otherwise just use start+length.
        const char *text = t.start;
        size_t len = t.length;
        if (t.kind == TOK_STRING_LIT) {
            if (len >= 2) { text = t.start + 1; len = t.length - 2; }
        }
        // For tokens with no meaningful text (EOF, ERROR), emit empty.
        printf("L%d %s [%.*s] num=%lld ch=%d\n",
               t.line, token_kind_name(t.kind),
               (int)len, text,
               (long long)t.int_value,
               (int)(unsigned char)t.char_value);
        if (t.kind == TOK_EOF || t.kind == TOK_ERROR) break;
    }
    free(src);
    return 0;
}
