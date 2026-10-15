// ═══════════════════════════════════════════════════════════════════════════════
// majorana_phase_shift.arm64.asm
// Majorana Phase-Shift Operator: ψ → e^(iφ) · ψ
// Target:  ARM64 (AArch64) · NEON SIMD
// Module:  01_majorana_inference
// Project: Siamese Twin AI — Microsoft WebTransport 5B
// ═══════════════════════════════════════════════════════════════════════════════

.section __TEXT,__text,regular,pure_instructions
.align 4

.global _majorana_phase_shift_neon
.global _compute_phase_angles_neon
.global _apply_majorana_identity_neon
.global _majorana_purity_neon

// ─────────────────────────────────────────────────────────────────────────────
// _majorana_phase_shift_neon(
//     float* psi_real,   x0 — input/output real
//     float* psi_imag,   x1 — input/output imag
//     float* phi,        x2 — phase angles
//     int    dim         x3 — dimension (multiple of 4)
// )
// Applies U(φ) = diag(e^{iφⱼ}) using NEON 128-bit vectors (4 floats/cycle)
// ─────────────────────────────────────────────────────────────────────────────
_majorana_phase_shift_neon:
    stp     x29, x30, [sp, #-64]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]

    mov     x19, x0             // psi_real
    mov     x20, x1             // psi_imag
    mov     x21, x2             // phi
    mov     x22, x3             // dim

    // Polynomial constants (loaded into NEON)
    adrp    x23, .Lcos_c2@PAGE
    add     x23, x23, .Lcos_c2@PAGEOFF

    mov     x24, #0             // idx = 0
    lsr     x22, x22, #2        // iterations = dim / 4

.Lphase_loop:
    cbz     x22, .Lphase_done

    // Load 4 phase angles
    ld1     {v0.4s}, [x21], #16     // φ[0..3]

    // cos(φ) polynomial: 1 - φ²/2 + φ⁴/24 - φ⁶/720
    fmul    v1.4s, v0.4s, v0.4s    // φ²
    fmov    v2.4s, #1.0             // c0 = 1.0
    ld1     {v8.4s}, [x23]          // c2 = -0.5
    fmla    v2.4s, v1.4s, v8.4s    // 1 + φ²·(-0.5)
    fmul    v3.4s, v1.4s, v1.4s    // φ⁴
    adrp    x0, .Lcos_c4@PAGE
    add     x0, x0, .Lcos_c4@PAGEOFF
    ld1     {v9.4s}, [x0]
    fmla    v2.4s, v3.4s, v9.4s    // + φ⁴·(1/24)
    fmul    v4.4s, v3.4s, v1.4s    // φ⁶
    adrp    x0, .Lcos_c6@PAGE
    add     x0, x0, .Lcos_c6@PAGEOFF
    ld1     {v10.4s}, [x0]
    fmla    v2.4s, v4.4s, v10.4s   // + φ⁶·(-1/720)
    // v2 = cos(φ)

    // sin(φ) polynomial: φ - φ³/6 + φ⁵/120 - φ⁷/5040
    mov     v5.16b, v0.16b          // φ
    fmul    v6.4s, v1.4s, v0.4s    // φ³
    adrp    x0, .Lsin_c3@PAGE
    add     x0, x0, .Lsin_c3@PAGEOFF
    ld1     {v11.4s}, [x0]
    fmla    v5.4s, v6.4s, v11.4s   // φ + φ³·(-1/6)
    fmul    v7.4s, v3.4s, v0.4s    // φ⁵
    adrp    x0, .Lsin_c5@PAGE
    add     x0, x0, .Lsin_c5@PAGEOFF
    ld1     {v12.4s}, [x0]
    fmla    v5.4s, v7.4s, v12.4s   // + φ⁵·(1/120)
    fmul    v8.4s, v4.4s, v0.4s    // φ⁷
    adrp    x0, .Lsin_c7@PAGE
    add     x0, x0, .Lsin_c7@PAGEOFF
    ld1     {v13.4s}, [x0]
    fmla    v5.4s, v8.4s, v13.4s   // + φ⁷·(-1/5040)
    // v5 = sin(φ)

    // Load ψ
    ld1     {v14.4s}, [x19]         // re[0..3]
    ld1     {v15.4s}, [x20]         // im[0..3]

    // re_new = re·cos - im·sin
    fmul    v16.4s, v14.4s, v2.4s  // re·cos
    fmls    v16.4s, v15.4s, v5.4s  // - im·sin

    // im_new = re·sin + im·cos
    fmul    v17.4s, v14.4s, v5.4s  // re·sin
    fmla    v17.4s, v15.4s, v2.4s  // + im·cos

    // Store
    st1     {v16.4s}, [x19], #16
    st1     {v17.4s}, [x20], #16

    subs    x22, x22, #1
    b.ne    .Lphase_loop

.Lphase_done:
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #64
    ret

// ─────────────────────────────────────────────────────────────────────────────
// _majorana_purity_neon(float* psi_real, float* psi_imag, int dim) -> float
// Computes Tr(ρ²) = ||ψ||⁴ for pure state purity measurement
// Returns purity in s0
// ─────────────────────────────────────────────────────────────────────────────
_majorana_purity_neon:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]

    mov     x19, x0             // psi_real
    mov     x20, x1             // psi_imag
    // x2 = dim

    movi    v0.4s, #0           // norm_acc = 0
    lsr     x3, x2, #2          // dim / 4

.Lpurity_loop:
    cbz     x3, .Lpurity_sum
    ld1     {v1.4s}, [x19], #16
    ld1     {v2.4s}, [x20], #16
    fmla    v0.4s, v1.4s, v1.4s // acc += re²
    fmla    v0.4s, v2.4s, v2.4s // acc += im²
    subs    x3, x3, #1
    b.ne    .Lpurity_loop

.Lpurity_sum:
    // Horizontal sum → norm²
    faddp   v0.4s, v0.4s, v0.4s
    faddp   v0.4s, v0.4s, v0.4s
    // purity = norm⁴ = (norm²)²
    fmul    s0, s0, s0

    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

// ─────────────────────────────────────────────────────────────────────────────
// _apply_majorana_identity_neon(
//     float* edge_r, float* edge_i,
//     float* chrome_r, float* chrome_i,
//     float* out_r, float* out_i, int dim
// )
// Joint Majorana state: |Ψ⟩ = (|Edge⟩ + conj(|Chrome⟩)) / √2
// ─────────────────────────────────────────────────────────────────────────────
_apply_majorana_identity_neon:
    stp     x29, x30, [sp, #-64]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]

    mov     x19, x0             // edge_r
    mov     x20, x1             // edge_i
    mov     x21, x2             // chrome_r
    mov     x22, x3             // chrome_i
    // x4=out_r, x5=out_i, x6=dim

    fmov    s15, #0.70710678    // 1/√2
    dup     v15.4s, v15.s[0]

    lsr     x6, x6, #2

.Lidentity_loop:
    cbz     x6, .Lidentity_done

    ld1     {v0.4s}, [x19], #16  // edge_real
    ld1     {v1.4s}, [x20], #16  // edge_imag
    ld1     {v2.4s}, [x21], #16  // chrome_real
    ld1     {v3.4s}, [x22], #16  // chrome_imag
    fneg    v3.4s, v3.4s         // conj: negate imag

    fadd    v4.4s, v0.4s, v2.4s  // real: edge_r + chrome_r
    fadd    v5.4s, v1.4s, v3.4s  // imag: edge_i - chrome_i
    fmul    v4.4s, v4.4s, v15.4s // / √2
    fmul    v5.4s, v5.4s, v15.4s

    st1     {v4.4s}, [x4], #16
    st1     {v5.4s}, [x5], #16

    subs    x6, x6, #1
    b.ne    .Lidentity_loop

.Lidentity_done:
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #64
    ret

.section __DATA,__data
.align 4
.Lcos_c2:   .float -0.49999997, -0.49999997, -0.49999997, -0.49999997
.Lcos_c4:   .float  0.04166642,  0.04166642,  0.04166642,  0.04166642
.Lcos_c6:   .float -0.00138873, -0.00138873, -0.00138873, -0.00138873
.Lsin_c3:   .float -0.16666667, -0.16666667, -0.16666667, -0.16666667
.Lsin_c5:   .float  0.00833333,  0.00833333,  0.00833333,  0.00833333
.Lsin_c7:   .float -0.00019841, -0.00019841, -0.00019841, -0.00019841
