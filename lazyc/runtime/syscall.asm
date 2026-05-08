; runtime/syscall.asm — minimal assembly stub for the lazyc runtime.
;
; Everything else (allocation, formatting, file I/O) lives in runtime.ml
; and gets compiled by lazyc itself. This file only contains:
;
;   * _start: capture argc/argv off the entry stack, call main, exit
;   * lazyc_argc/lazyc_argv: read the saved-by-_start values
;   * lazyc_sys_*: thin trampolines around Linux syscalls. These take
;     System V calling-convention args (rdi, rsi, rdx, rcx, r8, r9),
;     load the syscall number into rax, issue `syscall`, and return.
;
; Exposed names (the lazyc runtime uses these via `extern`-style calls):
;   lazyc_sys_read   (fd, buf, n)              -> ssize_t        [syscall 0]
;   lazyc_sys_write  (fd, buf, n)              -> ssize_t        [syscall 1]
;   lazyc_sys_open   (path, flags, mode)       -> fd             [syscall 2]
;   lazyc_sys_close  (fd)                      -> int            [syscall 3]
;   lazyc_sys_stat   (path, statbuf)           -> int            [syscall 4]
;   lazyc_sys_mmap   (addr, len, prot, flags, fd, off) -> ptr    [syscall 9]
;   lazyc_sys_munmap (addr, len)               -> int            [syscall 11]
;   lazyc_sys_exit   (code)                    -> noreturn       [syscall 60]
;   lazyc_sys_ioctl  (fd, request, argp)       -> int            [syscall 16]

section .bss
; Captured at _start entry, exposed via lazyc_argc/lazyc_argv.
lazyc_saved_argc: resq 1
lazyc_saved_argv: resq 1

section .text
global _start
global lazyc_argc
global lazyc_argv
global lazyc_sys_read
global lazyc_sys_write
global lazyc_sys_open
global lazyc_sys_close
global lazyc_sys_stat
global lazyc_sys_mmap
global lazyc_sys_munmap
global lazyc_sys_exit
global lazyc_sys_ioctl
extern main

; On entry to _start (per System V x86-64):
;   [rsp]      = argc (8 bytes)
;   [rsp+8..]  = argv[0], argv[1], ..., argv[argc-1], NULL
; We capture argc and the address of argv[0] before calling main.
_start:
    mov  rax, [rsp]
    mov  [rel lazyc_saved_argc], rax
    lea  rax, [rsp + 8]
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
;   rdi = i
;   returns argv[i] for i in [0, argc), null otherwise.
lazyc_argv:
    test rdi, rdi
    js   .argv_oor                ; i < 0
    mov  rax, [rel lazyc_saved_argc]
    cmp  rdi, rax
    jge  .argv_oor                ; i >= argc
    mov  rax, [rel lazyc_saved_argv]
    mov  rax, [rax + rdi*8]
    ret
.argv_oor:
    xor  rax, rax
    ret

; ---- syscall trampolines ----
;
; Each trampoline shifts the syscall args to match the kernel ABI:
;   user (System V): rdi rsi rdx rcx r8  r9
;   kernel:          rdi rsi rdx r10 r8  r9
; So for syscalls with >=4 args we move rcx -> r10. For mmap (6 args)
; we also relay r8/r9 unchanged.

lazyc_sys_read:
    mov  rax, 0
    syscall
    ret

lazyc_sys_write:
    mov  rax, 1
    syscall
    ret

lazyc_sys_open:
    mov  rax, 2
    syscall
    ret

lazyc_sys_close:
    mov  rax, 3
    syscall
    ret

lazyc_sys_stat:
    mov  rax, 4
    syscall
    ret

; mmap takes 6 args; the 4th moves rcx -> r10 per the kernel ABI.
lazyc_sys_mmap:
    mov  rax, 9
    mov  r10, rcx
    syscall
    ret

lazyc_sys_munmap:
    mov  rax, 11
    syscall
    ret

lazyc_sys_exit:
    mov  rax, 60
    syscall
    ; unreachable
    xor  rax, rax
    ret

; lazyc_sys_ioctl(fd, request, argp) -> int  [syscall 16]
; Used to manipulate terminal state (TCGETS, TCSETS, TIOCGWINSZ, ...).
lazyc_sys_ioctl:
    mov  rax, 16
    syscall
    ret
