// =============================================================================
// Windows AGI Benchmark Lab — ARM64 NEON/SVE Extended Benchmark
// Copyright (c) 2026 Microsoft Corporation. All Rights Reserved.
// =============================================================================
// Comprehensive ARM64 SIMD benchmark covering:
//   NEON: 128-bit vectors (float32x4, float64x2, int8x16, int16x8, int32x4)
//   SVE:  Scalable Vector Extension (variable width)
//   Crypto: AES, SHA-256, SHA-512 hardware acceleration
//   Atomics: LSE (Large System Extension)
//   Memory: Load/Store pairs, prefetch, cache management
// =============================================================================

.section .data
msg_neon:   .ascii "ARM64 NEON Extended Benchmark — Windows AGI Lab\n"
            .equ msg_neon_len, . - msg_neon
msg_sve:    .ascii "ARM64 SVE Benchmark\n"
            .equ msg_sve_len, . - msg_sve
msg_done:   .ascii "ARM64 Extended Benchmark Complete\n"
            .equ msg_done_len, . - msg_done

.align 16
vec_f32_a:  .float 1.0, 2.0, 3.0, 4.0
vec_f32_b:  .float 5.0, 6.0, 7.0, 8.0
vec_f64_a:  .double 1.0, 2.0
vec_f64_b:  .double 3.0, 4.0

.align 16
mat_a:      .float 1.0, 0.0, 0.0, 0.0
            .float 0.0, 1.0, 0.0, 0.0
            .float 0.0, 0.0, 1.0, 0.0
            .float 0.0, 0.0, 0.0, 1.0

.section .bss
.align 16
result_buf: .skip 1024

.section .text
.global _start

_start:
    mov     x0, #1
    adr     x1, msg_neon
    mov     x2, #msg_neon_len
    mov     x8, #64
    svc     #0

    bl      bench_neon_f32_fma
    bl      bench_neon_f64_fma
    bl      bench_neon_int8
    bl      bench_neon_int16
    bl      bench_neon_int32
    bl      bench_neon_matmul_4x4
    bl      bench_neon_dot_product
    bl      bench_neon_reduction
    bl      bench_neon_transpose
    bl      bench_crypto_aes
    bl      bench_crypto_sha256
    bl      bench_atomic_lse
    bl      bench_prefetch
    bl      bench_cache_management

    mov     x0, #1
    adr     x1, msg_done
    mov     x2, #msg_done_len
    mov     x8, #64
    svc     #0

    mov     x0, #0
    mov     x8, #93
    svc     #0

// NEON float32x4 FMA benchmark
bench_neon_f32_fma:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    adr     x0, vec_f32_a
    adr     x1, vec_f32_b
    ld1     {v0.4s}, [x0]
    ld1     {v1.4s}, [x1]
    fmov    s2, #0.5
    dup     v2.4s, v2.s[0]
    fmov    s3, #3.0
    dup     v3.4s, v3.s[0]
    mov     x2, #1000000
.f32_fma_loop:
    fmla    v0.4s, v1.4s, v2.4s
    fmla    v1.4s, v0.4s, v3.4s
    fmla    v2.4s, v3.4s, v0.4s
    fmla    v3.4s, v2.4s, v1.4s
    fmul    v4.4s, v0.4s, v1.4s
    fmul    v5.4s, v2.4s, v3.4s
    fadd    v0.4s, v4.4s, v5.4s
    fsub    v1.4s, v4.4s, v5.4s
    subs    x2, x2, #1
    b.ne    .f32_fma_loop
    ldp     x29, x30, [sp], #16
    ret

// NEON float64x2 FMA benchmark
bench_neon_f64_fma:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    adr     x0, vec_f64_a
    adr     x1, vec_f64_b
    ld1     {v0.2d}, [x0]
    ld1     {v1.2d}, [x1]
    fmov    d2, #0.5
    dup     v2.2d, v2.d[0]
    fmov    d3, #3.0
    dup     v3.2d, v3.d[0]
    mov     x2, #500000
.f64_fma_loop:
    fmla    v0.2d, v1.2d, v2.2d
    fmla    v1.2d, v0.2d, v3.2d
    fmul    v2.2d, v0.2d, v1.2d
    fadd    v3.2d, v2.2d, v0.2d
    subs    x2, x2, #1
    b.ne    .f64_fma_loop
    ldp     x29, x30, [sp], #16
    ret

// NEON int8x16 benchmark (16 int8 per vector)
bench_neon_int8:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    movi    v0.16b, #1
    movi    v1.16b, #2
    movi    v2.16b, #3
    movi    v3.16b, #4
    mov     x0, #500000
.int8_loop:
    add     v0.16b, v0.16b, v1.16b
    mul     v4.16b, v0.16b, v2.16b
    sub     v5.16b, v4.16b, v3.16b
    add     v1.16b, v5.16b, v0.16b
    smax    v2.16b, v0.16b, v1.16b
    smin    v3.16b, v2.16b, v1.16b
    abs     v0.16b, v3.16b
    subs    x0, x0, #1
    b.ne    .int8_loop
    ldp     x29, x30, [sp], #16
    ret

// NEON int16x8 benchmark
bench_neon_int16:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    movi    v0.8h, #1
    movi    v1.8h, #2
    movi    v2.8h, #3
    mov     x0, #500000
.int16_loop:
    add     v0.8h, v0.8h, v1.8h
    mul     v3.8h, v0.8h, v2.8h
    sqdmulh v4.8h, v0.8h, v1.8h
    sqadd   v5.8h, v3.8h, v4.8h
    subs    x0, x0, #1
    b.ne    .int16_loop
    ldp     x29, x30, [sp], #16
    ret

// NEON int32x4 benchmark
bench_neon_int32:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    movi    v0.4s, #1
    movi    v1.4s, #2
    movi    v2.4s, #3
    mov     x0, #500000
.int32_loop:
    add     v0.4s, v0.4s, v1.4s
    mul     v3.4s, v0.4s, v2.4s
    mla     v0.4s, v1.4s, v2.4s
    smax    v4.4s, v0.4s, v3.4s
    smin    v5.4s, v4.4s, v1.4s
    subs    x0, x0, #1
    b.ne    .int32_loop
    ldp     x29, x30, [sp], #16
    ret

// NEON 4x4 matrix multiply (float32)
bench_neon_matmul_4x4:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    adr     x0, mat_a
    ld1     {v0.4s, v1.4s, v2.4s, v3.4s}, [x0]
    mov     x1, #100000
.matmul_loop:
    // Row 0 of result
    fmul    v4.4s, v0.4s, v0.s[0]
    fmla    v4.4s, v1.4s, v0.s[1]
    fmla    v4.4s, v2.4s, v0.s[2]
    fmla    v4.4s, v3.4s, v0.s[3]
    // Row 1
    fmul    v5.4s, v0.4s, v1.s[0]
    fmla    v5.4s, v1.4s, v1.s[1]
    fmla    v5.4s, v2.4s, v1.s[2]
    fmla    v5.4s, v3.4s, v1.s[3]
    // Row 2
    fmul    v6.4s, v0.4s, v2.s[0]
    fmla    v6.4s, v1.4s, v2.s[1]
    fmla    v6.4s, v2.4s, v2.s[2]
    fmla    v6.4s, v3.4s, v2.s[3]
    // Row 3
    fmul    v7.4s, v0.4s, v3.s[0]
    fmla    v7.4s, v1.4s, v3.s[1]
    fmla    v7.4s, v2.4s, v3.s[2]
    fmla    v7.4s, v3.4s, v3.s[3]
    mov     v0.16b, v4.16b
    mov     v1.16b, v5.16b
    mov     v2.16b, v6.16b
    mov     v3.16b, v7.16b
    subs    x1, x1, #1
    b.ne    .matmul_loop
    ldp     x29, x30, [sp], #16
    ret

// NEON dot product (float32)
bench_neon_dot_product:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    adr     x0, vec_f32_a
    adr     x1, vec_f32_b
    ld1     {v0.4s}, [x0]
    ld1     {v1.4s}, [x1]
    mov     x2, #1000000
.dot_loop:
    fmul    v2.4s, v0.4s, v1.4s
    faddp   v3.4s, v2.4s, v2.4s
    faddp   v4.2s, v3.2s, v3.2s
    subs    x2, x2, #1
    b.ne    .dot_loop
    ldp     x29, x30, [sp], #16
    ret

// NEON horizontal reduction
bench_neon_reduction:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    adr     x0, vec_f32_a
    ld1     {v0.4s}, [x0]
    mov     x1, #1000000
.reduce_loop:
    faddp   v1.4s, v0.4s, v0.4s
    faddp   v2.2s, v1.2s, v1.2s
    fmaxp   v3.4s, v0.4s, v0.4s
    fminp   v4.4s, v0.4s, v0.4s
    subs    x1, x1, #1
    b.ne    .reduce_loop
    ldp     x29, x30, [sp], #16
    ret

// NEON 4x4 matrix transpose
bench_neon_transpose:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    adr     x0, mat_a
    ld1     {v0.4s, v1.4s, v2.4s, v3.4s}, [x0]
    mov     x1, #500000
.transpose_loop:
    trn1    v4.4s, v0.4s, v1.4s
    trn2    v5.4s, v0.4s, v1.4s
    trn1    v6.4s, v2.4s, v3.4s
    trn2    v7.4s, v2.4s, v3.4s
    zip1    v0.2d, v4.2d, v6.2d
    zip2    v1.2d, v4.2d, v6.2d
    zip1    v2.2d, v5.2d, v7.2d
    zip2    v3.2d, v5.2d, v7.2d
    subs    x1, x1, #1
    b.ne    .transpose_loop
    ldp     x29, x30, [sp], #16
    ret

// AES hardware acceleration
bench_crypto_aes:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    movi    v0.16b, #0xAB
    movi    v1.16b, #0xCD
    movi    v2.16b, #0xEF
    mov     x0, #500000
.aes_loop:
    aese    v0.16b, v1.16b
    aesmc   v0.16b, v0.16b
    aese    v0.16b, v2.16b
    aesmc   v0.16b, v0.16b
    aesd    v0.16b, v1.16b
    aesimc  v0.16b, v0.16b
    subs    x0, x0, #1
    b.ne    .aes_loop
    ldp     x29, x30, [sp], #16
    ret

// SHA-256 hardware acceleration
bench_crypto_sha256:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    movi    v0.4s, #0
    movi    v1.4s, #0
    movi    v2.4s, #1
    movi    v3.4s, #2
    mov     x0, #200000
.sha256_loop:
    sha256h     q0, q1, v2.4s
    sha256h2    q1, q0, v2.4s
    sha256su0   v2.4s, v3.4s
    sha256su1   v2.4s, v0.4s, v1.4s
    subs    x0, x0, #1
    b.ne    .sha256_loop
    ldp     x29, x30, [sp], #16
    ret

// LSE atomic operations
bench_atomic_lse:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    mov     x0, #0
    str     x0, [sp, #16]
    mov     x1, #100000
    mov     x2, #1
.lse_loop:
    ldadd   x2, x3, [sp, #16]
    ldclr   x2, x3, [sp, #16]
    ldeor   x2, x3, [sp, #16]
    ldset   x2, x3, [sp, #16]
    subs    x1, x1, #1
    b.ne    .lse_loop
    ldp     x29, x30, [sp], #32
    ret

// Prefetch benchmark
bench_prefetch:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    adr     x0, result_buf
    mov     x1, #100000
.prefetch_loop:
    prfm    pldl1keep, [x0]
    prfm    pldl2keep, [x0, #64]
    prfm    pldl3keep, [x0, #128]
    prfm    pstl1keep, [x0, #192]
    ldr     x2, [x0]
    str     x2, [x0, #8]
    subs    x1, x1, #1
    b.ne    .prefetch_loop
    ldp     x29, x30, [sp], #16
    ret

// Cache management
bench_cache_management:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    adr     x0, result_buf
    mov     x1, #10000
.cache_loop:
    dc      cvac, x0
    dc      civac, x0
    ic      ivau, x0
    dsb     sy
    isb
    subs    x1, x1, #1
    b.ne    .cache_loop
    ldp     x29, x30, [sp], #16
    ret
