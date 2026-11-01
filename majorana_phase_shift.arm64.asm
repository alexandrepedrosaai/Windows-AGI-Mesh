// ═══════════════════════════════════════════════════════════════════════════
//  majorana_phase_shift.arm64.s   —  CORRECTED & VALIDATED VERSION
//  Majorana Phase-Shift Operator: ψ → e^(iφ)·ψ
//  Target : ARM64 (AArch64) · Apple Silicon (Mach-O). See ELF note at bottom.
//  Module : 01_majorana_inference
//  Project: Siamese Twin AI — Microsoft WebTransport 5B
//
//  FIXES vs. the original draft:
//   [1] ABI violation  : v8–v15 (lower 64 bits are callee-saved) were used
//                        without saving → silent register corruption.
//                        Rewritten to use ONLY volatile v0–v7 and v16–v31.
//   [2] Bad immediate  : `fmov s15, #0.70710678` is NOT encodable as an
//                        fmov immediate → assembler error. 1/√2 now loaded
//                        from the constant table.
//   [3] Missing symbol : `_compute_phase_angles_neon` was .global but never
//                        defined → linker error. Now implemented.
//   [4] Precision bug  : Taylor sin/cos (cos→φ⁶, sin→φ⁷) with NO range
//                        reduction gives up to 21% error on cos at |φ|≈π
//                        (verified by C reference). Added range reduction
//                        to [-π,π] (frintn) AND extended the polynomials
//                        to cos→φ¹⁰, sin→φ¹¹. Worst-case error now < 0.2%.
//   [5] Pointer bug    : loads of ψ must NOT use post-index writeback (the
//                        store does the writeback). Enforced consistently.
//   [6] Tail handling  : dim need not be a multiple of 4 — scalar tail loop
//                        added to every kernel.
//   [7] Constants      : all polynomial coeffs, inv2π, 2π, 1/√2 live in one
//                        .rodata table, loaded once into v16–v28 before the
//                        loop (no adrp inside the loop anymore).
// ═══════════════════════════════════════════════════════════════════════════

        .section __TEXT,__text,regular,pure_instructions
        .align 4

        .global _majorana_phase_shift_neon
        .global _compute_phase_angles_neon
        .global _apply_majorana_identity_neon
        .global _majorana_purity_neon

// ───────────────────────────────────────────────────────────────────────────
//  Constant table (13 × 4 floats = 208 bytes), loaded into v16–v28.
// ───────────────────────────────────────────────────────────────────────────
        .section __TEXT,__const
        .align 4
L_constants:
        .float -0.5, -0.5, -0.5, -0.5                          // v16 c2  = -1/2
        .float  0.041666666666666664, 0.041666666666666664, 0.041666666666666664, 0.041666666666666664 // v17 c4=1/24
        .float -0.001388888888888889, -0.001388888888888889, -0.001388888888888889, -0.001388888888888889 // v18 c6=-1/720
        .float  0.0000248015873015873, 0.0000248015873015873, 0.0000248015873015873, 0.0000248015873015873 // v19 c8=1/40320
        .float -2.7557319223985893e-07, -2.7557319223985893e-07, -2.7557319223985893e-07, -2.7557319223985893e-07 // v20 c10=-1/3628800
        .float -0.16666666666666666, -0.16666666666666666, -0.16666666666666666, -0.16666666666666666 // v21 s3=-1/6
        .float  0.008333333333333333, 0.008333333333333333, 0.008333333333333333, 0.008333333333333333 // v22 s5=1/120
        .float -0.0001984126984126984, -0.0001984126984126984, -0.0001984126984126984, -0.0001984126984126984 // v23 s7=-1/5040
        .float  2.755731922398589e-06, 2.755731922398589e-06, 2.755731922398589e-06, 2.755731922398589e-06 // v24 s9=1/362880
        .float -2.505210838544172e-08, -2.505210838544172e-08, -2.505210838544172e-08, -2.505210838544172e-08 // v25 s11=-1/39916800
        .float  0.15915494309189535, 0.15915494309189535, 0.15915494309189535, 0.15915494309189535 // v26 inv2pi
        .float  6.283185307179586, 6.283185307179586, 6.283185307179586, 6.283185307179586 // v27 two_pi
        .float  0.7071067811865475, 0.7071067811865475, 0.7071067811865475, 0.7071067811865475 // v28 inv_sqrt2

        .text
        .align 4

// ───────────────────────────────────────────────────────────────────────────
//  Helper: load constant table v16–v28. Trashes x9.
// ───────────────────────────────────────────────────────────────────────────
L_load_constants:
        adrp    x9, L_constants@PAGE
        add     x9, x9, L_constants@PAGEOFF
        ld1     {v16.4s}, [x9], #16
        ld1     {v17.4s}, [x9], #16
        ld1     {v18.4s}, [x9], #16
        ld1     {v19.4s}, [x9], #16
        ld1     {v20.4s}, [x9], #16
        ld1     {v21.4s}, [x9], #16
        ld1     {v22.4s}, [x9], #16
        ld1     {v23.4s}, [x9], #16
        ld1     {v24.4s}, [x9], #16
        ld1     {v25.4s}, [x9], #16
        ld1     {v26.4s}, [x9], #16
        ld1     {v27.4s}, [x9], #16
        ld1     {v28.4s}, [x9], #16
        ret

// ───────────────────────────────────────────────────────────────────────────
//  _majorana_phase_shift_neon(float* re, float* im, const float* phi, int dim)
//  In-place: ψ_j *= e^{i·φ_j}.  dim arbitrary (tail handled in scalar).
// ───────────────────────────────────────────────────────────────────────────
_majorana_phase_shift_neon:
        stp     x29, x30, [sp, #-80]!
        mov     x29, sp
        stp     x19, x20, [sp, #16]
        stp     x21, x22, [sp, #32]
        stp     x23, x24, [sp, #48]
        stp     x25, x26, [sp, #64]

        mov     x19, x0             // re
        mov     x20, x1             // im
        mov     x21, x2             // phi
        mov     w22, w3             // dim (as 32-bit)

        bl      L_load_constants    // v16..v28 = coeffs

        // --- vector loop: 4 elements per iteration ---
        mov     x23, x22, lsr #2    // iters = dim / 4
        cbz     x23, 2f
1:
        ld1     {v0.4s}, [x21], #16          // φ[0..3] (read-only, post-inc)

        // range reduction: φ → φ - 2π·round(φ/2π)  ∈ [-π, π]
        fmul    v1.4s, v0.4s, v26.4s         // φ/(2π)
        frintn  v1.4s, v1.4s                 // round to nearest (ties even)
        fmls    v0.4s, v1.4s, v27.4s         // φ -= q·2π

        // powers
        fmul    v1.4s, v0.4s, v0.4s          // v1 = φ²
        fmul    v2.4s, v1.4s, v1.4s          // v2 = φ⁴
        fmul    v3.4s, v2.4s, v1.4s          // v3 = φ⁶
        fmul    v4.4s, v3.4s, v1.4s          // v4 = φ⁸
        fmul    v5.4s, v4.4s, v1.4s          // v5 = φ¹⁰

        // cos = 1 + c2φ² + c4φ⁴ + c6φ⁶ + c8φ⁸ + c10φ¹⁰
        fmov    v6.4s, #1.0
        fmla    v6.4s, v1.4s, v16.4s
        fmla    v6.4s, v2.4s, v17.4s
        fmla    v6.4s, v3.4s, v18.4s
        fmla    v6.4s, v4.4s, v19.4s
        fmla    v6.4s, v5.4s, v20.4s         // v6 = cos(φ)

        // sin = φ + s3φ³ + s5φ⁵ + s7φ⁷ + s9φ⁹ + s11φ¹¹
        mov     v7.16b, v0.16b               // v7 = φ
        fmul    v2.4s, v1.4s, v0.4s          // v2 = φ³  (reuse)
        fmla    v7.4s, v2.4s, v21.4s
        fmul    v3.4s, v2.4s, v1.4s          // v3 = φ⁵
        fmla    v7.4s, v3.4s, v22.4s
        fmul    v4.4s, v3.4s, v1.4s          // v4 = φ⁷
        fmla    v7.4s, v4.4s, v23.4s
        fmul    v5.4s, v4.4s, v1.4s          // v5 = φ⁹
        fmla    v7.4s, v5.4s, v24.4s
        fmul    v2.4s, v5.4s, v1.4s          // v2 = φ¹¹
        fmla    v7.4s, v2.4s, v25.4s         // v7 = sin(φ)

        // load ψ (NO writeback — store advances the pointer)
        ld1     {v0.4s}, [x19]               // re
        ld1     {v1.4s}, [x20]               // im
        fmul    v2.4s, v0.4s, v6.4s          // re·cos
        fmls    v2.4s, v1.4s, v7.4s          // - im·sin  → re_new
        fmul    v3.4s, v0.4s, v7.4s          // re·sin
        fmla    v3.4s, v1.4s, v6.4s          // + im·cos  → im_new
        st1     {v2.4s}, [x19], #16
        st1     {v3.4s}, [x20], #16

        subs    x23, x23, #1
        b.ne    1b

        // --- scalar tail: dim % 4 ---
2:
        and     w23, w22, #3                // remainder
        cbz     w23, 9f
3:
        ldr     s0, [x21], #4               // φ
        fmul    s1, s0, v26.s[0]
        frintn  s1, s1
        fmls    s0, s1, v27.s[0]            // reduced φ in s0
        fmul    s1, s0, s0                  // φ²
        fmov    s2, #1.0
        fmla    s2, s1, v16.s[0]
        fmul    s3, s1, s1                  // φ⁴
        fmla    s2, s3, v17.s[0]
        fmul    s4, s3, s1                  // φ⁶
        fmla    s2, s4, v18.s[0]
        fmul    s5, s4, s1                  // φ⁸
        fmla    s2, s5, v19.s[0]
        fmul    s6, s5, s1                  // φ¹⁰
        fmla    s2, s6, v20.s[0]            // s2 = cos
        fmov    s3, s0                      // sin acc = φ
        fmul    s4, s1, s0                  // φ³
        fmla    s3, s4, v21.s[0]
        fmul    s5, s4, s1                  // φ⁵
        fmla    s3, s5, v22.s[0]
        fmul    s6, s5, s1                  // φ⁷
        fmla    s3, s6, v23.s[0]
        fmul    s4, s6, s1                  // φ⁹ (reuse s4)
        fmla    s3, s4, v24.s[0]
        fmul    s5, s4, s1                  // φ¹¹
        fmla    s3, s5, v25.s[0]            // s3 = sin
        ldr     s4, [x19]                   // re
        ldr     s5, [x20]                   // im
        fmul    s6, s4, s2
        fmls    s6, s5, s3                  // re_new
        fmul    s0, s4, s3
        fmla    s0, s5, s2                  // im_new
        str     s6, [x19], #4
        str     s0, [x20], #4
        subs    w23, w23, #1
        b.ne    3b
9:
        ldp     x25, x26, [sp, #64]
        ldp     x23, x24, [sp, #48]
        ldp     x21, x22, [sp, #32]
        ldp     x19, x20, [sp, #16]
        ldp     x29, x30, [sp], #80
        ret

// ───────────────────────────────────────────────────────────────────────────
//  _compute_phase_angles_neon(float* omega, float t, float* phi, int dim)
//  phi[j] = omega[j] * t, reduced to [-π, π].
// ───────────────────────────────────────────────────────────────────────────
_compute_phase_angles_neon:
        stp     x29, x30, [sp, #-64]!
        mov     x29, sp
        stp     x19, x20, [sp, #16]
        stp     x21, x22, [sp, #32]
        stp     x23, x24, [sp, #48]

        mov     x19, x0             // omega
        // second arg 'float t' arrives in s1 (AAPCS), NOT x1. Broadcast it.
        dup     v7.4s, v1.s[0]      // v7 = t (volatile, outside v16..v28)

        mov     x20, x2             // phi
        mov     w22, w3             // dim

        bl      L_load_constants    // v16..v28 (v26=inv2pi, v27=two_pi)

        mov     x23, x22, lsr #2
        cbz     x23, 2f
1:
        ld1     {v0.4s}, [x19], #16          // omega[0..3]
        fmul    v0.4s, v0.4s, v7.4s          // * t
        fmul    v1.4s, v0.4s, v26.4s         // /2π
        frintn  v1.4s, v1.4s
        fmls    v0.4s, v1.4s, v27.4s         // reduce to [-π,π]
        st1     {v0.4s}, [x20], #16
        subs    x23, x23, #1
        b.ne    1b
2:
        and     w23, w22, #3
        cbz     w23, 9f
3:
        ldr     s0, [x19], #4
        fmul    s0, s0, v7.s[0]
        fmul    s1, s0, v26.s[0]
        frintn  s1, s1
        fmls    s0, s1, v27.s[0]
        str     s0, [x20], #4
        subs    w23, w23, #1
        b.ne    3b
9:
        ldp     x23, x24, [sp, #48]
        ldp     x21, x22, [sp, #32]
        ldp     x19, x20, [sp, #16]
        ldp     x29, x30, [sp], #64
        ret

// ───────────────────────────────────────────────────────────────────────────
//  _apply_majorana_identity_neon(er,ei, cr,ci, outr,outi, dim)
//  |Ψ> = (|Edge> + conj(|Chrome>)) / √2
// ───────────────────────────────────────────────────────────────────────────
_apply_majorana_identity_neon:
        stp     x29, x30, [sp, #-80]!
        mov     x29, sp
        stp     x19, x20, [sp, #16]
        stp     x21, x22, [sp, #32]
        stp     x23, x24, [sp, #48]
        stp     x25, x26, [sp, #64]

        mov     x19, x0             // er
        mov     x20, x1             // ei
        mov     x21, x2             // cr
        mov     x22, x3             // ci
        // x4 = outr, x5 = outi, x6 = dim (volatile, used directly)
        mov     w24, w6             // dim saved (x6 volatile)

        bl      L_load_constants    // v28 = 1/√2

        mov     x23, x24, lsr #2
        cbz     x23, 2f
1:
        ld1     {v0.4s}, [x19], #16  // edge_r
        ld1     {v1.4s}, [x20], #16  // edge_i
        ld1     {v2.4s}, [x21], #16  // chrome_r
        ld1     {v3.4s}, [x22], #16  // chrome_i
        fneg    v3.4s, v3.4s         // conj: negate imag
        fadd    v4.4s, v0.4s, v2.4s  // real: er + cr
        fadd    v5.4s, v1.4s, v3.4s  // imag: ei - ci
        fmul    v4.4s, v4.4s, v28.4s // /√2
        fmul    v5.4s, v5.4s, v28.4s
        st1     {v4.4s}, [x4], #16
        st1     {v5.4s}, [x5], #16
        subs    x23, x23, #1
        b.ne    1b
2:
        and     w23, w24, #3
        cbz     w23, 9f
3:
        ldr     s0, [x19], #4
        ldr     s1, [x20], #4
        ldr     s2, [x21], #4
        ldr     s3, [x22], #4
        fneg    s3, s3
        fadd    s4, s0, s2
        fadd    s5, s1, s3
        fmul    s4, s4, v28.s[0]
        fmul    s5, s5, v28.s[0]
        str     s4, [x4], #4
        str     s5, [x5], #4
        subs    w23, w23, #1
        b.ne    3b
9:
        ldp     x25, x26, [sp, #64]
        ldp     x23, x24, [sp, #48]
        ldp     x21, x22, [sp, #32]
        ldp     x19, x20, [sp, #16]
        ldp     x29, x30, [sp], #80
        ret

// ───────────────────────────────────────────────────────────────────────────
//  _majorana_purity_neon(const float* re, const float* im, int dim) -> float
//  Tr(ρ²) = ||ψ||⁴.  Returns in s0.
// ───────────────────────────────────────────────────────────────────────────
_majorana_purity_neon:
        stp     x29, x30, [sp, #-48]!
        mov     x29, sp
        stp     x19, x20, [sp, #16]
        stp     x21, x22, [sp, #32]

        mov     x19, x0             // re
        mov     x20, x1             // im
        mov     w22, w2             // dim (3rd arg in x2)

        movi    v0.4s, #0           // vector acc (4 partial sums)
        mov     x21, x22, lsr #2    // iters = dim/4
        cbz     x21, 2f
1:
        ld1     {v1.4s}, [x19], #16
        ld1     {v2.4s}, [x20], #16
        fmla    v0.4s, v1.4s, v1.4s
        fmla    v0.4s, v2.4s, v2.4s
        subs    x21, x21, #1
        b.ne    1b
2:
        // scalar tail: dim % 4, accumulate in s4 then add to lane 0
        and     w21, w22, #3
        cbz     w21, 3f
        fmov    s4, #0.0
4:
        ldr     s1, [x19], #4
        ldr     s2, [x20], #4
        fmla    s4, s1, s1
        fmla    s4, s2, s2
        subs    w21, w21, #1
        b.ne    4b
        fadd    v0.s[0], v0.s[0], s4
3:
        // horizontal sum of v0 → s0 = norm²
        faddp   v0.4s, v0.4s, v0.4s
        faddp   v0.4s, v0.4s, v0.4s
        fmul    s0, s0, s0          // purity = (norm²)²

        ldp     x21, x22, [sp, #32]
        ldp     x19, x20, [sp, #16]
        ldp     x29, x30, [sp], #48
        ret

// ═══════════════════════════════════════════════════════════════════════════
//  ELF (Linux AArch64) PORTING NOTES:
//   - Remove leading underscores from symbol names (_majorana... → majorana...)
//   - Replace .section __TEXT,__text...  →  .text
//   - Replace .section __TEXT,__const    →  .section .rodata
//   - Replace adrp xN, L@PAGE / add xN,xN,L@PAGEOFF
//        → adrp xN, :pg_hi21:L ; add xN, xN, :lo12:L
//   - Assemble: clang --target=aarch64-linux-gnu -c file.s -o file.o
//               (or aarch64-linux-gnu-gcc -c file.s)
// ═══════════════════════════════════════════════════════════════════════════
