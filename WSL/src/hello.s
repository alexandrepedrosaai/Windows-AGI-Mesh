// =============================================================================
// Windows AGI Benchmark Lab — ARM64 (AArch64) Assembly Hello World
// Copyright (c) 2026 Microsoft Corporation. All Rights Reserved.
// =============================================================================
// Target: AArch64 Linux (ELF64)
// Assembler: GNU as (aarch64-linux-gnu-as)
// Build:
//   aarch64-linux-gnu-as hello.s -o hello_arm64.o
//   aarch64-linux-gnu-ld hello_arm64.o -o hello_arm64
// QEMU test:
//   qemu-aarch64 ./hello_arm64
// =============================================================================

.section .data

msg:
    .ascii "Windows AGI Benchmark Lab — ARM64 AArch64\n"
    .equ msg_len, . - msg

banner:
    .ascii "Microsoft Corporation — Exclusive License\n"
    .equ banner_len, . - banner

arch_msg:
    .ascii "Architecture: ARM64 / AArch64 / NEON / SVE\n"
    .equ arch_msg_len, . - arch_msg

.section .bss
    .align 8
    buf:    .skip 256

.section .text
.global _start

// =============================================================================
// _start — Entry point
// =============================================================================
_start:
    // Print main message
    mov     x0, #1              // fd = stdout
    adr     x1, msg             // buffer address
    mov     x2, #msg_len        // length
    mov     x8, #64             // sys_write
    svc     #0

    // Print banner
    mov     x0, #1
    adr     x1, banner
    mov     x2, #banner_len
    mov     x8, #64
    svc     #0

    // Print architecture info
    mov     x0, #1
    adr     x1, arch_msg
    mov     x2, #arch_msg_len
    mov     x8, #64
    svc     #0

    // Run benchmarks
    bl      bench_integer
    bl      bench_memory
    bl      bench_neon_fp32
    bl      bench_branch
    bl      bench_load_store

    // Exit
    mov     x0, #0              // exit code
    mov     x8, #93             // sys_exit
    svc     #0


// =============================================================================
// bench_integer — Integer arithmetic benchmark
// ARM64 has 31 general-purpose 64-bit registers (x0-x30)
// =============================================================================
bench_integer:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    mov     x0, #1000000        // iteration count
    mov     x1, #0x1234         // accumulator
    movk    x1, #0x5678, lsl #16
    movk    x1, #0x9ABC, lsl #32
    movk    x1, #0xDEF0, lsl #48

    mov     x2, #0xCAFE         // multiplier
    movk    x2, #0xBABE, lsl #16
    movk    x2, #0xDEAD, lsl #32
    movk    x2, #0xBEEF, lsl #48

    mov     x3, #0x0123         // addend
    movk    x3, #0x4567, lsl #16
    movk    x3, #0x89AB, lsl #32
    movk    x3, #0xCDEF, lsl #48

bench_integer_loop:
    // Multiply-add chain using ARM64 MUL/MADD
    mul     x4, x1, x2          // x4 = x1 * x2
    add     x4, x4, x3          // x4 += x3
    eor     x1, x4, x2          // x1 = x4 XOR x2
    ror     x1, x1, #7          // rotate right 7

    mul     x5, x2, x1
    add     x5, x5, x3
    eor     x2, x5, x1
    ror     x2, x2, #13

    // MADD: x6 = x3 * x1 + x2
    madd    x6, x3, x1, x2
    eor     x3, x6, x1

    subs    x0, x0, #1
    b.ne    bench_integer_loop

    ldp     x29, x30, [sp], #16
    ret


// =============================================================================
// bench_memory — Memory access benchmark
// Tests L1/L2 cache performance
// =============================================================================
bench_memory:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Sequential write
    adr     x0, buf
    mov     x1, #32             // 32 iterations (256 bytes / 8)
    mov     x2, #0

bench_mem_write:
    str     x2, [x0], #8       // store and post-increment
    add     x2, x2, #1
    subs    x1, x1, #1
    b.ne    bench_mem_write

    // Sequential read
    adr     x0, buf
    mov     x1, #32
    mov     x3, #0

bench_mem_read:
    ldr     x2, [x0], #8       // load and post-increment
    add     x3, x3, x2
    subs    x1, x1, #1
    b.ne    bench_mem_read

    // Strided access (cache line = 64 bytes)
    adr     x0, buf
    mov     x1, #4
    mov     x4, #0

bench_mem_stride:
    ldr     x2, [x0]
    add     x4, x4, x2
    add     x0, x0, #64        // stride = 64 bytes (1 cache line)
    subs    x1, x1, #1
    b.ne    bench_mem_stride

    ldp     x29, x30, [sp], #16
    ret


// =============================================================================
// bench_neon_fp32 — ARM NEON SIMD benchmark (128-bit vectors)
// Processes 4x float32 per instruction
// =============================================================================
bench_neon_fp32:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Load constants into NEON registers
    // v0-v7: 128-bit NEON registers (4x float32 each)
    fmov    s0, #1.0
    dup     v0.4s, v0.s[0]     // v0 = {1.0, 1.0, 1.0, 1.0}

    fmov    s1, #2.0
    dup     v1.4s, v1.s[0]     // v1 = {2.0, 2.0, 2.0, 2.0}

    fmov    s2, #0.5
    dup     v2.4s, v2.s[0]     // v2 = {0.5, 0.5, 0.5, 0.5}

    fmov    s3, #3.0
    dup     v3.4s, v3.s[0]     // v3 = {3.0, 3.0, 3.0, 3.0}

    mov     x0, #500000

bench_neon_loop:
    // NEON FMA: v0 = v0 * v1 + v2
    fmla    v0.4s, v1.4s, v2.4s
    fmla    v1.4s, v0.4s, v3.4s
    fmla    v2.4s, v3.4s, v0.4s
    fmla    v3.4s, v2.4s, v1.4s

    // NEON multiply
    fmul    v4.4s, v0.4s, v1.4s
    fmul    v5.4s, v2.4s, v3.4s

    // NEON add
    fadd    v0.4s, v4.4s, v5.4s
    fadd    v1.4s, v0.4s, v2.4s

    subs    x0, x0, #1
    b.ne    bench_neon_loop

    ldp     x29, x30, [sp], #16
    ret


// =============================================================================
// bench_neon_fp64 — ARM NEON SIMD benchmark (FP64)
// Processes 2x float64 per instruction
// =============================================================================
bench_neon_fp64:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    fmov    d0, #1.0
    dup     v0.2d, v0.d[0]     // v0 = {1.0, 1.0}

    fmov    d1, #2.0
    dup     v1.2d, v1.d[0]

    fmov    d2, #0.5
    dup     v2.2d, v2.d[0]

    mov     x0, #500000

bench_neon_fp64_loop:
    fmla    v0.2d, v1.2d, v2.2d
    fmla    v1.2d, v0.2d, v2.2d
    fmul    v2.2d, v0.2d, v1.2d
    fadd    v0.2d, v1.2d, v2.2d

    subs    x0, x0, #1
    b.ne    bench_neon_fp64_loop

    ldp     x29, x30, [sp], #16
    ret


// =============================================================================
// bench_neon_int — ARM NEON Integer SIMD
// 16x int8, 8x int16, 4x int32, 2x int64
// =============================================================================
bench_neon_int:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Initialize integer vectors
    movi    v0.16b, #1          // 16x int8 = 1
    movi    v1.16b, #2          // 16x int8 = 2
    movi    v2.8h, #3           // 8x int16 = 3
    movi    v3.4s, #4           // 4x int32 = 4

    mov     x0, #500000

bench_neon_int_loop:
    // 16x int8 operations
    add     v0.16b, v0.16b, v1.16b
    mul     v4.16b, v0.16b, v1.16b

    // 8x int16 operations
    add     v2.8h, v2.8h, v3.4h
    mul     v5.8h, v2.8h, v2.8h

    // 4x int32 operations
    add     v3.4s, v3.4s, v0.4s
    mul     v6.4s, v3.4s, v3.4s

    // 2x int64 operations
    add     v7.2d, v0.2d, v1.2d

    subs    x0, x0, #1
    b.ne    bench_neon_int_loop

    ldp     x29, x30, [sp], #16
    ret


// =============================================================================
// bench_branch — Branch prediction benchmark
// Tests conditional branches and indirect branches
// =============================================================================
bench_branch:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    mov     x0, #1000000
    mov     x1, #0              // even counter
    mov     x2, #0              // odd counter

bench_branch_loop:
    // Test LSB for even/odd
    tst     x0, #1
    b.eq    bench_branch_even
    add     x2, x2, #1
    b       bench_branch_next
bench_branch_even:
    add     x1, x1, #1
bench_branch_next:
    subs    x0, x0, #1
    b.ne    bench_branch_loop

    ldp     x29, x30, [sp], #16
    ret


// =============================================================================
// bench_load_store — Load/Store benchmark
// Tests ARM64 load-store pair instructions
// =============================================================================
bench_load_store:
    stp     x29, x30, [sp, #-64]!
    mov     x29, sp

    mov     x0, #100000
    mov     x1, #0x1111111111111111
    mov     x2, #0x2222222222222222
    mov     x3, #0x3333333333333333
    mov     x4, #0x4444444444444444

bench_ls_loop:
    // Store pairs (2 registers at once)
    stp     x1, x2, [sp, #16]
    stp     x3, x4, [sp, #32]

    // Load pairs
    ldp     x5, x6, [sp, #16]
    ldp     x7, x8, [sp, #32]

    // Process loaded values
    add     x1, x5, x7
    add     x2, x6, x8
    eor     x3, x1, x2
    eor     x4, x2, x3

    subs    x0, x0, #1
    b.ne    bench_ls_loop

    ldp     x29, x30, [sp], #64
    ret


// =============================================================================
// bench_crypto — ARM64 Cryptographic Extensions
// AES and SHA acceleration (if available)
// =============================================================================
bench_crypto_aes:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Initialize AES key and data
    movi    v0.16b, #0xAB       // plaintext
    movi    v1.16b, #0xCD       // round key

    mov     x0, #100000

bench_aes_loop:
    // AES encryption round
    aese    v0.16b, v1.16b      // AES single round encryption
    aesmc   v0.16b, v0.16b      // AES mix columns

    // AES decryption round
    aesd    v0.16b, v1.16b      // AES single round decryption
    aesimc  v0.16b, v0.16b      // AES inverse mix columns

    subs    x0, x0, #1
    b.ne    bench_aes_loop

    ldp     x29, x30, [sp], #16
    ret


// =============================================================================
// bench_sha256 — ARM64 SHA-256 Hardware Acceleration
// =============================================================================
bench_sha256:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Initialize SHA state
    movi    v0.4s, #0           // SHA state 0-3
    movi    v1.4s, #0           // SHA state 4-7
    movi    v2.4s, #1           // message schedule
    movi    v3.4s, #2

    mov     x0, #100000

bench_sha256_loop:
    // SHA-256 rounds
    sha256h     q0, q1, v2.4s
    sha256h2    q1, q0, v2.4s
    sha256su0   v2.4s, v3.4s
    sha256su1   v2.4s, v0.4s, v1.4s

    subs    x0, x0, #1
    b.ne    bench_sha256_loop

    ldp     x29, x30, [sp], #16
    ret


// =============================================================================
// bench_atomic — ARM64 Atomic Operations (LSE)
// Load-Store Exclusive and Large System Extension
// =============================================================================
bench_atomic:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp

    // Allocate atomic counter on stack
    mov     x0, #0
    str     x0, [sp, #16]       // counter = 0

    mov     x1, #100000

bench_atomic_loop:
    // Load-exclusive / Store-exclusive
    ldxr    x2, [sp, #16]       // load exclusive
    add     x2, x2, #1          // increment
    stxr    w3, x2, [sp, #16]   // store exclusive
    cbnz    w3, bench_atomic_loop  // retry if failed

    subs    x1, x1, #1
    b.ne    bench_atomic_loop

    ldp     x29, x30, [sp], #32
    ret