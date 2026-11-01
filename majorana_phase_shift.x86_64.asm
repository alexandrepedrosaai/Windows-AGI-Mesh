; ═══════════════════════════════════════════════════════════════════════════════
; majorana_phase_shift.x86_64.asm
; Majorana Phase-Shift Operator: ψ → e^(iφ) · ψ
; Target:  x86-64 · AVX-512 · FMA3
; Module:  01_majorana_inference
; Project: Siamese Twin AI — Microsoft WebTransport 5B
; Author:  Alexandre Pedrosa (EVP Microsoft)
; ═══════════════════════════════════════════════════════════════════════════════

section .data
    align 64
    .pi:        dq 3.14159265358979323846
    .two_pi:    dq 6.28318530717958647692
    .one:       dd 1.0
    .zero:      dd 0.0
    ; Polynomial coefficients for cos/sin (Chebyshev, degree 7)
    .cos_c0:    times 16 dd  1.0
    .cos_c2:    times 16 dd -0.49999997
    .cos_c4:    times 16 dd  0.04166642
    .cos_c6:    times 16 dd -0.00138873
    .sin_c1:    times 16 dd  1.0
    .sin_c3:    times 16 dd -0.16666667
    .sin_c5:    times 16 dd  0.00833333
    .sin_c7:    times 16 dd -0.00019841

section .bss
    align 64
    .psi_real_out:  resb 512 * 4    ; output real part  (512 floats)
    .psi_imag_out:  resb 512 * 4    ; output imag part

section .text
    global majorana_phase_shift_avx512
    global majorana_phase_shift_scalar
    global compute_phase_angles
    global apply_majorana_identity

; ───────────────────────────────────────────────────────────────────────────────
; majorana_phase_shift_avx512(
;     float* psi_real,   ; rdi — input/output real part
;     float* psi_imag,   ; rsi — input/output imag part
;     float* phi,        ; rdx — phase angles array
;     int    dim         ; rcx — vector dimension (multiple of 16)
; )
; Applies U(φ) = diag(e^{iφⱼ}) to quantum state ψ
; e^{iφ}·ψ = (cos φ + i·sin φ)·(re + i·im)
;           = (re·cos φ - im·sin φ) + i·(re·sin φ + im·cos φ)
; ───────────────────────────────────────────────────────────────────────────────
majorana_phase_shift_avx512:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 128
    push    rbx
    push    r12
    push    r13
    push    r14

    mov     r12, rdi            ; psi_real
    mov     r13, rsi            ; psi_imag
    mov     r14, rdx            ; phi
    ; rcx = dim

    xor     rbx, rbx            ; idx = 0
    mov     rax, rcx
    shr     rax, 4              ; iterations = dim / 16

.loop:
    test    rax, rax
    jz      .done

    ; Load 16 phase angles
    vmovaps zmm0, [r14 + rbx*4]    ; φ[0..15]

    ; Compute cos(φ) via Chebyshev polynomial
    ; cos(x) ≈ 1 - x²/2 + x⁴/24 - x⁶/720
    vmulps  zmm1, zmm0, zmm0       ; x²
    vmovaps zmm2, [rel .cos_c0]    ; 1.0
    vfmadd231ps zmm2, zmm1, [rel .cos_c2]  ; + x²·(-0.5)
    vmulps  zmm3, zmm1, zmm1       ; x⁴
    vfmadd231ps zmm2, zmm3, [rel .cos_c4]  ; + x⁴·(1/24)
    vmulps  zmm4, zmm3, zmm1       ; x⁶
    vfmadd231ps zmm2, zmm4, [rel .cos_c6]  ; + x⁶·(-1/720)
    ; zmm2 = cos(φ)

    ; Compute sin(φ) via Chebyshev polynomial
    ; sin(x) ≈ x - x³/6 + x⁵/120 - x⁷/5040
    vmovaps zmm5, zmm0             ; x
    vmulps  zmm6, zmm1, zmm0       ; x³
    vfmadd231ps zmm5, zmm6, [rel .sin_c3]  ; + x³·(-1/6)
    vmulps  zmm7, zmm3, zmm0       ; x⁵
    vfmadd231ps zmm5, zmm7, [rel .sin_c5]  ; + x⁵·(1/120)
    vmulps  zmm8, zmm4, zmm0       ; x⁷
    vfmadd231ps zmm5, zmm8, [rel .sin_c7]  ; + x⁷·(-1/5040)
    ; zmm5 = sin(φ)

    ; Load ψ components
    vmovaps zmm9,  [r12 + rbx*4]   ; re[0..15]
    vmovaps zmm10, [r13 + rbx*4]   ; im[0..15]

    ; Apply rotation:
    ; re_new = re·cos(φ) - im·sin(φ)
    vmulps  zmm11, zmm9,  zmm2     ; re·cos
    vfnmadd231ps zmm11, zmm10, zmm5 ; - im·sin
    ; im_new = re·sin(φ) + im·cos(φ)
    vmulps  zmm12, zmm9,  zmm5     ; re·sin
    vfmadd231ps zmm12, zmm10, zmm2  ; + im·cos

    ; Store results
    vmovaps [r12 + rbx*4], zmm11
    vmovaps [r13 + rbx*4], zmm12

    add     rbx, 16
    dec     rax
    jmp     .loop

.done:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    mov     rsp, rbp
    pop     rbp
    ret

; ───────────────────────────────────────────────────────────────────────────────
; compute_phase_angles(float* psi_real, float* psi_imag, float* phi_out, int dim)
; Computes φⱼ = angle(ψⱼ) = atan2(imag, real) for Hilbert correction
; ───────────────────────────────────────────────────────────────────────────────
compute_phase_angles:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14

    mov     r12, rdi            ; psi_real
    mov     r13, rsi            ; psi_imag
    mov     r14, rdx            ; phi_out
    ; rcx = dim

    xor     rbx, rbx
.angle_loop:
    cmp     rbx, rcx
    jge     .angle_done

    ; atan2(y, x) approximation:
    ; atan2(y,x) ≈ atan(y/x) for x > 0
    ; atan(t) ≈ t·(π/4) / (1 + |t|) — fast approximation
    vmovss  xmm0, [r12 + rbx*4]   ; real
    vmovss  xmm1, [r13 + rbx*4]   ; imag

    ; Handle x=0 case
    vxorps  xmm2, xmm2, xmm2
    vucomiss xmm0, xmm2
    je      .handle_zero

    vdivss  xmm2, xmm1, xmm0      ; t = imag/real
    ; |t|
    vandps  xmm3, xmm2, [rel .abs_mask]
    vaddss  xmm3, xmm3, [rel .one]
    vdivss  xmm2, xmm2, xmm3      ; t / (1 + |t|)
    vmulss  xmm2, xmm2, [rel .pi_over4]
    jmp     .store_angle

.handle_zero:
    ; x=0: angle = π/2 if y>0, -π/2 if y<0
    vmovss  xmm2, [rel .pi_over2]
    vxorps  xmm3, xmm3, xmm3
    vucomiss xmm1, xmm3
    jae     .store_angle
    vxorps  xmm2, xmm2, [rel .sign_mask]

.store_angle:
    vmovss  [r14 + rbx*4], xmm2
    inc     rbx
    jmp     .angle_loop

.angle_done:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    mov     rsp, rbp
    pop     rbp
    ret

; ───────────────────────────────────────────────────────────────────────────────
; apply_majorana_identity(float* psi_edge_r, float* psi_edge_i,
;                         float* psi_chrome_r, float* psi_chrome_i,
;                         float* psi_out_r, float* psi_out_i, int dim)
; Majorana identity: γ = γ†
; Computes joint state: |Ψ⟩ = (|Edge⟩ + conj(|Chrome⟩)) / √2
; ───────────────────────────────────────────────────────────────────────────────
apply_majorana_identity:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 64
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15

    mov     r12, rdi            ; psi_edge_r
    mov     r13, rsi            ; psi_edge_i
    mov     r14, rdx            ; psi_chrome_r
    mov     r15, rcx            ; psi_chrome_i
    ; r8 = psi_out_r, r9 = psi_out_i, [rbp+16] = dim

    vmovaps zmm15, [rel .inv_sqrt2_zmm]  ; 1/√2

    xor     rbx, rbx
    mov     rax, [rbp + 16]     ; dim
    shr     rax, 4

.identity_loop:
    test    rax, rax
    jz      .identity_done

    ; Load Edge state
    vmovaps zmm0, [r12 + rbx*4]   ; edge_real
    vmovaps zmm1, [r13 + rbx*4]   ; edge_imag

    ; Load Chrome conjugate: conj(Chrome) = (chrome_r, -chrome_i)
    vmovaps zmm2, [r14 + rbx*4]   ; chrome_real
    vmovaps zmm3, [r15 + rbx*4]   ; chrome_imag
    vxorps  zmm3, zmm3, [rel .sign_zmm]  ; negate imag → conjugate

    ; Joint state: (Edge + conj(Chrome)) / √2
    vaddps  zmm4, zmm0, zmm2       ; real: edge_r + chrome_r
    vaddps  zmm5, zmm1, zmm3       ; imag: edge_i + (-chrome_i)
    vmulps  zmm4, zmm4, zmm15      ; / √2
    vmulps  zmm5, zmm5, zmm15

    vmovaps [r8 + rbx*4], zmm4
    vmovaps [r9 + rbx*4], zmm5

    add     rbx, 16
    dec     rax
    jmp     .identity_loop

.identity_done:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    mov     rsp, rbp
    pop     rbp
    ret

    align 64
.abs_mask:      times 16 dd 0x7FFFFFFF
.sign_mask:     times 16 dd 0x80000000
.pi_over4:      times 16 dd 0.78539816
.pi_over2:      times 16 dd 1.57079633
.inv_sqrt2_zmm: times 16 dd 0.70710678
.sign_zmm:      times 16 dd 0x80000000
