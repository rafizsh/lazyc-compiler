#include "parser.h"
#include "desugar.h"
#include "typecheck.h"
#include "codegen.h"
#include "ast.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static char *read_file(const char *path) {
    FILE *f = fopen(path, "rb");
    if (!f) { perror(path); exit(1); }
    fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
    char *buf = malloc(n + 1);
    fread(buf, 1, n, f); buf[n] = '\0';
    fclose(f);
    return buf;
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: %s [--ast | --ast-raw] <file.ml>\n", argv[0]);
        return 1;
    }

    int show_ast = 0;
    int ast_raw  = 0;
    const char *path = NULL;
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--ast") == 0) show_ast = 1;
        else if (strcmp(argv[i], "--ast-raw") == 0) { show_ast = 1; ast_raw = 1; }
        else path = argv[i];
    }
    if (!path) { fprintf(stderr, "no input file\n"); return 1; }

    char *src = read_file(path);
    Program *prog = parse_program(src);

    if (show_ast && ast_raw) {
        print_program(prog);
        return 0;
    }

    desugar_program(prog);
    typecheck_program(prog);

    if (show_ast) {
        print_program(prog);
        return 0;
    }

    char asm_path[512];
    snprintf(asm_path, sizeof(asm_path), "%s.asm", path);

    FILE *o = fopen(asm_path, "w");
    if (!o) { perror(asm_path); return 1; }
    codegen_program(prog, o);
    fclose(o);

    printf("wrote %s\n", asm_path);
    return 0;
}
