CC=gcc
CFLAGS=-Wall -Wextra -g -std=c11
NASM=nasm
LD=ld

SRC=src/main.c src/lexer.c src/parser.c src/ast_print.c \
    src/codegen.c src/symtab.c src/typecheck.c src/desugar.c \
    src/funcs.c src/types.c

# The C reference compiler. The canonical lazyc binary is built via
# ./build.sh from the prebuilt asm; the C reference is only needed to
# rebuild the prebuilts from scratch or to cross-check the bootstrap.
lazyc-ref: $(SRC)
	$(CC) $(CFLAGS) -o $@ $^

# Convenience target: build a test program with the C reference.
# Usage: make test PROG=tests/arith1
test: lazyc-ref build/runtime.o
	./lazyc-ref $(PROG).ml
	$(NASM) -f elf64 $(PROG).ml.asm -o $(PROG).o
	$(LD) $(PROG).o build/runtime.o -o $(PROG)
	@echo "Built $(PROG). Run: ./$(PROG); echo \$$?"

clean:
	rm -f lazyc-ref tests/*.o tests/*.asm
	rm -rf build
	@find tests -maxdepth 1 -type f ! -name "*.ml" -exec rm -f {} +

.PHONY: test clean
