; lazyc runtime: System V AMD64 / Linux x86-64.
;
; Provides the entry point _start and the per-type helpers that
; format-string codegen calls into.

section .rodata
lazyc_newline: db 10

section .bss
; Captured at _start entry, exposed via lazyc_argc/lazyc_argv.
lazyc_saved_argc: resq 1
lazyc_saved_argv: resq 1

section .text
global _start
global lazyc_write_bytes
global lazyc_print_newline
global lazyc_print_char
global lazyc_print_string
global lazyc_print_int16
global lazyc_print_long
global lazyc_alloc
global lazyc_free
global lazyc_exit
global lazyc_readf
global lazyc_writef
global lazyc_argc
global lazyc_argv
extern main

; On entry to _start (per System V x86-64):
;   [rsp]      = argc (8 bytes)
;   [rsp+8..]  = argv[0], argv[1], ..., argv[argc-1], NULL
;   then envp[], aux vector
; We capture argc and the address of argv[0] before calling main.
_start:
    mov  rax, [rsp]               ; argc
    mov  [rel lazyc_saved_argc], rax
    lea  rax, [rsp + 8]           ; address of argv[0]
    mov  [rel lazyc_saved_argv], rax
    call main
    mov  rdi, rax
    mov  rax, 60
    syscall

; lazyc_argc() -> Long
lazyc_argc:
    mov  rax, [rel lazyc_saved_argc]
    ret

; lazyc_argv(Long i) -> Ptr<Byte>
; Returns null if i is out of range (negative or >= argc).
lazyc_argv:
    test rdi, rdi
    js   .out_of_range            ; i < 0
    mov  rax, [rel lazyc_saved_argc]
    cmp  rdi, rax
    jge  .out_of_range            ; i >= argc
    mov  rax, [rel lazyc_saved_argv]
    mov  rax, [rax + rdi*8]       ; argv[i]
    ret
.out_of_range:
    xor  rax, rax
    ret

; lazyc_write_bytes(const char *buf, size_t len)  rdi=buf, rsi=len
lazyc_write_bytes:
    mov  rdx, rsi
    mov  rsi, rdi
    mov  rdi, 1
    mov  rax, 1
    syscall
    ret

lazyc_print_newline:
    mov  rdi, 1
    lea  rsi, [rel lazyc_newline]
    mov  rdx, 1
    mov  rax, 1
    syscall
    ret

; lazyc_print_char(Char c)   rdi (low byte) = value
lazyc_print_char:
    push rbp
    mov  rbp, rsp
    sub  rsp, 16
    mov  byte [rsp], dil
    mov  rdi, 1
    lea  rsi, [rsp]
    mov  rdx, 1
    mov  rax, 1
    syscall
    leave
    ret

lazyc_strlen:
    xor  rax, rax
.l:
    cmp  byte [rdi + rax], 0
    je   .d
    inc  rax
    jmp  .l
.d:
    ret

; lazyc_print_string(String s)   rdi = ptr
lazyc_print_string:
    push rbp
    mov  rbp, rsp
    push rdi
    sub  rsp, 8
    call lazyc_strlen
    add  rsp, 8
    pop  rsi
    mov  rdx, rax
    mov  rdi, 1
    mov  rax, 1
    syscall
    leave
    ret

; lazyc_print_int16(Integer n)  -- codegen sign-extends to rdi via movsx,
; so this just delegates to the Long helper.
lazyc_print_int16:
    jmp lazyc_print_long

; lazyc_print_long(Long n)   rdi = signed 64-bit
lazyc_print_long:
    push rbp
    mov  rbp, rsp
    sub  rsp, 32

    mov  r9, 0
    mov  rax, rdi
    cmp  rax, 0
    jge  .nn
    mov  r9, 1
    neg  rax
.nn:
    lea  r8, [rbp]

    cmp  rax, 0
    jne  .dl
    dec  r8
    mov  byte [r8], '0'
    jmp  .wr
.dl:
    cmp  rax, 0
    je   .dd
    xor  rdx, rdx
    mov  rcx, 10
    div  rcx
    add  dl, '0'
    dec  r8
    mov  byte [r8], dl
    jmp  .dl
.dd:
    cmp  r9, 0
    je   .wr
    dec  r8
    mov  byte [r8], '-'
.wr:
    mov  rdx, rbp
    sub  rdx, r8
    mov  rsi, r8
    mov  rdi, 1
    mov  rax, 1
    syscall
    leave
    ret

; ============================================================
; Heap allocator (step 14): mmap-backed, page-granular.
; Each allocation is rounded up to whole pages. An 8-byte header
; storing the total mapped size sits before the user pointer.
;
; Layout:    [8-byte total ][ user bytes... ]
;                          ^ returned pointer
; ============================================================

; lazyc_alloc(Long n) -> Ptr<Byte>
; rdi = n.  rax = pointer (or 0 on failure).
lazyc_alloc:
    push rbp
    mov  rbp, rsp
    sub  rsp, 16

    mov  [rbp-8], rdi              ; save n (unused but useful for debugging)

    ; total = round_up(n + 8, 4096)
    add  rdi, 8 + 4095
    and  rdi, -4096
    mov  [rbp-16], rdi

    mov  rax, 9                    ; sys_mmap
    xor  rdi, rdi                  ; addr = NULL
    mov  rsi, [rbp-16]             ; length
    mov  rdx, 3                    ; PROT_READ | PROT_WRITE
    mov  r10, 0x22                 ; MAP_PRIVATE | MAP_ANONYMOUS
    mov  r8, -1                    ; fd
    xor  r9, r9                    ; offset
    syscall

    ; mmap returns negative-ish errno on failure (~last 4096 bytes of address space).
    cmp  rax, -4096
    ja   .alloc_fail

    ; Write total at [rax]; return rax+8.
    mov  rcx, [rbp-16]
    mov  qword [rax], rcx
    add  rax, 8

    leave
    ret
.alloc_fail:
    xor  rax, rax
    leave
    ret

; lazyc_free(Ptr<Byte> p) -> Boolean
; rdi = user pointer.  rax = 1 success, 0 failure.
lazyc_free:
    push rbp
    mov  rbp, rsp

    test rdi, rdi
    jz   .free_fail                ; null pointer -> false

    sub  rdi, 8                    ; back up to header
    mov  rsi, [rdi]                ; total length

    mov  rax, 11                   ; sys_munmap
    syscall

    test rax, rax
    jnz  .free_fail

    mov  rax, 1
    leave
    ret
.free_fail:
    xor  rax, rax
    leave
    ret

; lazyc_exit(Long code) — never returns.
lazyc_exit:
    mov  rax, 60                   ; sys_exit
    syscall
    ; Should be unreachable. Just in case:
    xor  rax, rax
    ret

; ============================================================
; File I/O (step 15): readf and writef syscalls.
; readf does stat -> alloc -> open -> read-loop -> close -> null-terminate.
; writef does strlen -> open(create+trunc) -> write-loop -> close.
; ============================================================

; lazyc_readf(String path) -> Ptr<Byte>
; rdi = path. rax = heap pointer to null-terminated buffer (or 0 on fail).
lazyc_readf:
    push rbp
    mov  rbp, rsp
    sub  rsp, 192                  ; 144 stat buf, plus locals at low addresses
    ; Local layout (relative to rbp):
    ;   [rbp-8]    saved path (or, after we open, fd)
    ;   [rbp-16]   saved size
    ;   [rbp-24]   saved buf pointer
    ;   [rbp-32]   saved fd (if we use [-8] for total later)
    ;   [rbp-40]   total bytes read so far
    ;   [rbp-48..rbp-191]   stat buffer (144 bytes; st_size is at offset 48)

    mov  [rbp-8], rdi              ; save path

    ; stat(path, statbuf)
    mov  rax, 4
    mov  rdi, [rbp-8]
    lea  rsi, [rbp-192]
    syscall
    test rax, rax
    js   .readf_fail

    ; st_size lives at offset 48 within the stat struct.
    ; statbuf starts at [rbp-192], so st_size is at [rbp-192+48] = [rbp-144].
    mov  rax, [rbp-144]
    mov  [rbp-16], rax             ; size

    ; Allocate (size+1) bytes.
    mov  rdi, rax
    inc  rdi
    call lazyc_alloc
    test rax, rax
    jz   .readf_fail
    mov  [rbp-24], rax             ; buf

    ; open(path, O_RDONLY=0, 0)
    mov  rax, 2
    mov  rdi, [rbp-8]
    xor  rsi, rsi
    xor  rdx, rdx
    syscall
    test rax, rax
    js   .readf_fail_after_alloc
    mov  [rbp-32], rax             ; fd

    ; total = 0
    xor  rcx, rcx
    mov  [rbp-40], rcx

.readf_loop:
    mov  rax, [rbp-16]             ; size
    mov  rdx, rax
    sub  rdx, [rbp-40]             ; remaining
    test rdx, rdx
    jz   .readf_done

    ; read(fd, buf+total, remaining)
    mov  rax, 0
    mov  rdi, [rbp-32]
    mov  rsi, [rbp-24]
    add  rsi, [rbp-40]
    syscall
    test rax, rax
    js   .readf_fail_after_open
    jz   .readf_done               ; EOF
    add  [rbp-40], rax
    jmp  .readf_loop

.readf_done:
    ; close(fd)
    mov  rax, 3
    mov  rdi, [rbp-32]
    syscall

    ; Null-terminate: buf[size] = 0
    mov  rax, [rbp-24]             ; buf
    mov  rcx, [rbp-16]             ; size
    mov  byte [rax + rcx], 0

    leave
    ret

.readf_fail_after_open:
    mov  rax, 3
    mov  rdi, [rbp-32]
    syscall
.readf_fail_after_alloc:
    mov  rdi, [rbp-24]
    call lazyc_free
.readf_fail:
    xor  rax, rax
    leave
    ret

; lazyc_writef(String path, Ptr<Byte> contents) -> Boolean
; rdi = path. rsi = contents.  rax = 1 success, 0 failure.
lazyc_writef:
    push rbp
    mov  rbp, rsp
    sub  rsp, 48
    ; Locals:
    ;   [rbp-8]   path  (becomes "total" after open)
    ;   [rbp-16]  contents
    ;   [rbp-24]  len
    ;   [rbp-32]  fd

    mov  [rbp-8], rdi
    mov  [rbp-16], rsi

    ; len = strlen(contents)
    mov  rdi, [rbp-16]
    call lazyc_strlen
    mov  [rbp-24], rax

    ; open(path, O_WRONLY|O_CREAT|O_TRUNC=577, 0644 octal = 420 decimal)
    mov  rax, 2
    mov  rdi, [rbp-8]
    mov  rsi, 577
    mov  rdx, 420
    syscall
    test rax, rax
    js   .writef_fail
    mov  [rbp-32], rax

    ; total = 0  (reuse [rbp-8])
    xor  rcx, rcx
    mov  [rbp-8], rcx

.writef_loop:
    mov  rdx, [rbp-24]
    sub  rdx, [rbp-8]
    test rdx, rdx
    jz   .writef_done

    ; write(fd, contents+total, remaining)
    mov  rax, 1
    mov  rdi, [rbp-32]
    mov  rsi, [rbp-16]
    add  rsi, [rbp-8]
    syscall
    test rax, rax
    js   .writef_fail_after_open
    add  [rbp-8], rax
    jmp  .writef_loop

.writef_done:
    mov  rax, 3
    mov  rdi, [rbp-32]
    syscall
    mov  rax, 1
    leave
    ret

.writef_fail_after_open:
    mov  rax, 3
    mov  rdi, [rbp-32]
    syscall
.writef_fail:
    xor  rax, rax
    leave
    ret
