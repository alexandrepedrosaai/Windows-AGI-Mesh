; =============================================================================
; Windows AGI Benchmark Lab — x86_64 Assembly Hello World
; Copyright (c) 2026 Microsoft Corporation. All Rights Reserved.
; =============================================================================
; Target: x86_64 Linux (ELF64)
; Assembler: NASM
; Build: nasm -f elf64 hello.asm -o hello.o && ld hello.o -o hello
; =============================================================================

global _start

section .data
    msg     db  "Windows AGI Benchmark Lab — x86_64 Assembly", 0x0A
    msg_len equ $ - msg

    banner  db  "Microsoft Corporation — Exclusive License", 0x0A
    ban_len equ $ - banner

section .bss
    ; Reserved space for benchmark data
    buf     resb 256

section .text

; =============================================================================
; _start — Entry point
; =============================================================================
_start:
    ; Write banner to stdout
    mov     rax, 1          ; sys_write
    mov     rdi, 1          ; fd = stdout
    mov     rsi, msg        ; buffer
    mov     rdx, msg_len    ; length
    syscall

    mov     rax, 1
    mov     rdi, 1
    mov     rsi, banner
    mov     rdx, ban_len
    syscall

    ; Run integer benchmark
    call    bench_integer

    ; Run memory benchmark
    call    bench_memory

    ; Exit cleanly
    mov     rax, 60         ; sys_exit
    xor     rdi, rdi        ; exit code 0
    syscall


; =============================================================================
; bench_integer — Integer arithmetic benchmark
; Performs 1,000,000 iterations of multiply-add-xor operations
; =============================================================================
bench_integer:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15

    mov     rcx, 1000000    ; iteration count
    xor     rax, rax        ; accumulator = 0
    mov     rbx, 0x1234567890ABCDEF  ; seed value
    mov     r12, 0xDEADBEEFCAFEBABE  ; multiplier
    mov     r13, 0x0123456789ABCDEF  ; addend

.loop:
    ; Multiply-add chain
    imul    rax, rbx
    add     rax, r13
    xor     rax, r12
    ror     rax, 7

    imul    rbx, rax
    add     rbx, r12
    xor     rbx, r13
    rol     rbx, 13

    ; Decrement and loop
    dec     rcx
    jnz     .loop

    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret


; =============================================================================
; bench_memory — Memory access benchmark
; Sequential and strided memory access patterns
; =============================================================================
bench_memory:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13

    ; Sequential write to buffer
    lea     rdi, [buf]
    mov     rcx, 32         ; 32 qwords = 256 bytes
    xor     rax, rax

.write_loop:
    mov     [rdi], rax
    add     rdi, 8
    inc     rax
    dec     rcx
    jnz     .write_loop

    ; Sequential read from buffer
    lea     rsi, [buf]
    mov     rcx, 32
    xor     rbx, rbx

.read_loop:
    mov     rax, [rsi]
    add     rbx, rax
    add     rsi, 8
    dec     rcx
    jnz     .read_loop

    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret


; =============================================================================
; bench_simd_sse2 — SSE2 SIMD benchmark (128-bit vectors)
; Packed double-precision floating point operations
; =============================================================================
section .data
    align 16
    vec_a   dq  1.0, 2.0
    vec_b   dq  3.0, 4.0
    vec_c   dq  0.0, 0.0

section .text

bench_simd_sse2:
    push    rbp
    mov     rbp, rsp

    ; Load 128-bit vectors
    movapd  xmm0, [vec_a]
    movapd  xmm1, [vec_b]

    mov     rcx, 100000

.simd_loop:
    ; Packed double multiply-add
    mulpd   xmm0, xmm1
    addpd   xmm0, xmm1
    subpd   xmm0, xmm1
    mulpd   xmm1, xmm0

    dec     rcx
    jnz     .simd_loop

    ; Store result
    movapd  [vec_c], xmm0

    pop     rbp
    ret


; =============================================================================
; bench_avx2 — AVX2 SIMD benchmark (256-bit vectors)
; Packed single-precision floating point operations
; =============================================================================
section .data
    align 32
    avx_a   times 8 dd 1.0
    avx_b   times 8 dd 2.0
    avx_c   times 8 dd 0.0

section .text

bench_avx2:
    push    rbp
    mov     rbp, rsp

    ; Load 256-bit vectors (8x float32)
    vmovaps ymm0, [avx_a]
    vmovaps ymm1, [avx_b]

    mov     rcx, 100000

.avx_loop:
    ; Fused multiply-add (FMA)
    vfmadd213ps ymm0, ymm1, ymm1   ; ymm0 = ymm0*ymm1 + ymm1
    vfmadd213ps ymm1, ymm0, ymm0   ; ymm1 = ymm1*ymm0 + ymm0

    dec     rcx
    jnz     .avx_loop

    vmovaps [avx_c], ymm0
    vzeroupper

    pop     rbp
    ret


; =============================================================================
; bench_branch — Branch prediction benchmark
; Tests branch predictor with alternating patterns
; =============================================================================
bench_branch:
    push    rbp
    mov     rbp, rsp

    mov     rcx, 1000000
    xor     rax, rax
    xor     rbx, rbx

.branch_loop:
    ; Alternating branch pattern
    test    rcx, 1
    jz      .even
    inc     rax
    jmp     .next
.even:
    inc     rbx
.next:
    dec     rcx
    jnz     .branch_loop

    pop     rbp
    ret


; =============================================================================
; bench_syscall — System call overhead benchmark
; Measures raw syscall latency
; =============================================================================
bench_syscall:
    push    rbp
    mov     rbp, rsp

    mov     rcx, 10000

.syscall_loop:
    ; getpid syscall (fast, no side effects)
    mov     rax, 39         ; sys_getpid
    syscall

    dec     rcx
    jnz     .syscall_loop

    pop     rbp
    ret
