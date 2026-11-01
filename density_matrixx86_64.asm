; ═══════════════════════════════════════════════════════════════════════════════
; density_matrix.x86_64.asm
; Density Matrix: ρ = |ψ⟩⟨ψ| · Purity Tr(ρ²) · Hilbert Correction
; Target:  x86-64 · AVX-512 · FMA3
; Module:  01_majorana_inference
; ═══════════════════════════════════════════════════════════════════════════════

section .data
    align 64
    .eps:           times 16 dd 1e-8
    .one:           times 16 dd 1.0
    .half:          times 16 dd 0.5
    .inv_sqrt2:     times 16 dd 0.70710678118

section .bss
    align 64
    ; Density matrix storage (dim × dim × 2 floats for complex)
    ; For dim=128: 128×128×8 = 131072 bytes
    .rho_real:  resb 128 * 128 * 4
    .rho_imag:  resb 128 * 128 * 4

section .text
    global density_matrix_outer_product
    global compute_purity_avx512
    global hilbert_project_pure_state
    global separate_decoherence
    global off_diagonal_coherence

; ───────────────────────────────────────────────────────────────────────────────
; density_matrix_outer_product(
;     float* psi_r, float* psi_i,   ; rdi, rsi — quantum state
;     float* rho_r, float* rho_i,   ; rdx, rcx — output density matrix
;     int dim                        ; r8
; )
; Computes ρ[i,j] = ψ[i] · conj(ψ[j]) = (re_i·re_j + im_i·im_j)
;                                       + i·(im_i·re_j - re_i·im_j)
; ───────────────────────────────────────────────────────────────────────────────
density_matrix_outer_product:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 64
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15

    mov     r12, rdi            ; psi_r
    mov     r13, rsi            ; psi_i
    mov     r14, rdx            ; rho_r
    mov     r15, rcx            ; rho_i
    ; r8 = dim

    ; Outer loop: row i
    xor     rbx, rbx
.row_loop:
    cmp     rbx, r8
    jge     .row_done

    ; Load ψ[i]
    vmovss  xmm14, [r12 + rbx*4]   ; re_i
    vmovss  xmm15, [r13 + rbx*4]   ; im_i
    vbroadcastss zmm14, xmm14       ; broadcast re_i
    vbroadcastss zmm15, xmm15       ; broadcast im_i

    ; Inner loop: col j (vectorized, 16 at a time)
    xor     r9, r9
    mov     r10, r8
    shr     r10, 4              ; dim / 16
.col_loop:
    test    r10, r10
    jz      .col_done

    ; Load ψ[j..j+15]
    vmovaps zmm0, [r12 + r9*4]     ; re_j
    vmovaps zmm1, [r13 + r9*4]     ; im_j

    ; ρ_real[i,j] = re_i·re_j + im_i·im_j
    vmulps  zmm2, zmm14, zmm0      ; re_i · re_j
    vfmadd231ps zmm2, zmm15, zmm1  ; + im_i · im_j

    ; ρ_imag[i,j] = im_i·re_j - re_i·im_j
    vmulps  zmm3, zmm15, zmm0      ; im_i · re_j
    vfnmadd231ps zmm3, zmm14, zmm1 ; - re_i · im_j

    ; Store at rho[i*dim + j]
    mov     rax, rbx
    imul    rax, r8
    add     rax, r9
    vmovaps [r14 + rax*4], zmm2
    vmovaps [r15 + rax*4], zmm3

    add     r9, 16
    dec     r10
    jmp     .col_loop
.col_done:

    inc     rbx
    jmp     .row_loop
.row_done:

    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    mov     rsp, rbp
    pop     rbp
    ret

; ───────────────────────────────────────────────────────────────────────────────
; compute_purity_avx512(float* rho_r, float* rho_i, int dim) -> float (xmm0)
; Tr(ρ²) = Σᵢ Σⱼ |ρ[i,j]|²  (for pure state = 1.0)
; ───────────────────────────────────────────────────────────────────────────────
compute_purity_avx512:
    push    rbp
    mov     rbp, rsp
    push    rbx

    ; rdi=rho_r, rsi=rho_i, rdx=dim
    ; Total elements = dim²
    mov     rax, rdx
    imul    rax, rdx            ; dim²
    shr     rax, 4              ; / 16

    vxorps  zmm0, zmm0, zmm0   ; acc = 0
    xor     rbx, rbx

.purity_loop:
    test    rax, rax
    jz      .purity_sum

    vmovaps zmm1, [rdi + rbx*4]    ; rho_r chunk
    vmovaps zmm2, [rsi + rbx*4]    ; rho_i chunk
    vfmadd231ps zmm0, zmm1, zmm1   ; acc += re²
    vfmadd231ps zmm0, zmm2, zmm2   ; acc += im²

    add     rbx, 16
    dec     rax
    jmp     .purity_loop

.purity_sum:
    ; Horizontal reduction
    vextractf64x4 ymm1, zmm0, 1
    vaddps  ymm0, ymm0, ymm1
    vextractf128 xmm1, ymm0, 1
    vaddps  xmm0, xmm0, xmm1
    vhaddps xmm0, xmm0, xmm0
    vhaddps xmm0, xmm0, xmm0
    ; xmm0 = Tr(ρ²) = purity

    pop     rbx
    mov     rsp, rbp
    pop     rbp
    ret

; ───────────────────────────────────────────────────────────────────────────────
; hilbert_project_pure_state(
;     float* rho_r, float* rho_i,   ; rdi, rsi — density matrix
;     float* psi_out_r,              ; rdx — output dominant eigenvector real
;     float* psi_out_i,              ; rcx — output dominant eigenvector imag
;     int dim                        ; r8
; )
; Projects ρ onto dominant pure state via power iteration
; Implements Hilbert correction: eliminates unnecessary decoherence
; ───────────────────────────────────────────────────────────────────────────────
hilbert_project_pure_state:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 256
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15

    mov     r12, rdi            ; rho_r
    mov     r13, rsi            ; rho_i
    mov     r14, rdx            ; psi_out_r
    mov     r15, rcx            ; psi_out_i
    ; r8 = dim

    ; Initialize v = [1, 0, 0, ..., 0] (starting vector)
    ; Store on stack
    lea     rdi, [rsp + 0]      ; v_real (dim floats)
    lea     rsi, [rsp + 128]    ; v_imag

    ; Zero v
    vxorps  zmm0, zmm0, zmm0
    xor     rax, rax
    mov     rcx, r8
    shr     rcx, 4
.zero_v:
    vmovaps [rdi + rax*4], zmm0
    vmovaps [rsi + rax*4], zmm0
    add     rax, 16
    dec     rcx
    jnz     .zero_v
    vmovss  xmm0, [rel .one]
    vmovss  [rdi], xmm0         ; v[0] = 1.0

    ; Power iteration: v ← ρ·v / ||ρ·v|| (10 iterations)
    mov     rbx, 10
.power_iter:
    test    rbx, rbx
    jz      .power_done

    ; w = ρ · v (matrix-vector multiply)
    ; w_r[i] = Σⱼ (rho_r[i,j]·v_r[j] - rho_i[i,j]·v_i[j])
    ; w_i[i] = Σⱼ (rho_r[i,j]·v_i[j] + rho_i[i,j]·v_r[j])
    xor     r9, r9
.matvec_i:
    cmp     r9, r8
    jge     .matvec_done

    vxorps  zmm1, zmm1, zmm1   ; w_r acc
    vxorps  zmm2, zmm2, zmm2   ; w_i acc
    xor     r10, r10
    mov     r11, r8
    shr     r11, 4
.matvec_j:
    test    r11, r11
    jz      .matvec_j_done

    ; rho row i, cols j..j+15
    mov     rax, r9
    imul    rax, r8
    add     rax, r10
    vmovaps zmm3, [r12 + rax*4]    ; rho_r[i,j..]
    vmovaps zmm4, [r13 + rax*4]    ; rho_i[i,j..]
    vmovaps zmm5, [rdi + r10*4]    ; v_r[j..]
    vmovaps zmm6, [rsi + r10*4]    ; v_i[j..]

    vfmadd231ps zmm1, zmm3, zmm5   ; w_r += rho_r·v_r
    vfnmadd231ps zmm1, zmm4, zmm6  ; w_r -= rho_i·v_i
    vfmadd231ps zmm2, zmm3, zmm6   ; w_i += rho_r·v_i
    vfmadd231ps zmm2, zmm4, zmm5   ; w_i += rho_i·v_r

    add     r10, 16
    dec     r11
    jmp     .matvec_j
.matvec_j_done:

    ; Reduce w[i]
    vextractf64x4 ymm7, zmm1, 1
    vaddps  ymm1, ymm1, ymm7
    vextractf128 xmm7, ymm1, 1
    vaddps  xmm1, xmm1, xmm7
    vhaddps xmm1, xmm1, xmm1
    vhaddps xmm1, xmm1, xmm1
    vmovss  [r14 + r9*4], xmm1     ; store w_r[i]

    vextractf64x4 ymm7, zmm2, 1
    vaddps  ymm2, ymm2, ymm7
    vextractf128 xmm7, ymm2, 1
    vaddps  xmm2, xmm2, xmm7
    vhaddps xmm2, xmm2, xmm2
    vhaddps xmm2, xmm2, xmm2
    vmovss  [r15 + r9*4], xmm2     ; store w_i[i]

    inc     r9
    jmp     .matvec_i
.matvec_done:

    ; Normalize w → v
    vxorps  zmm0, zmm0, zmm0
    xor     rax, rax
    mov     rcx, r8
    shr     rcx, 4
.norm_acc:
    vmovaps zmm1, [r14 + rax*4]
    vmovaps zmm2, [r15 + rax*4]
    vfmadd231ps zmm0, zmm1, zmm1
    vfmadd231ps zmm0, zmm2, zmm2
    add     rax, 16
    dec     rcx
    jnz     .norm_acc

    vextractf64x4 ymm1, zmm0, 1
    vaddps  ymm0, ymm0, ymm1
    vextractf128 xmm1, ymm0, 1
    vaddps  xmm0, xmm0, xmm1
    vhaddps xmm0, xmm0, xmm0
    vhaddps xmm0, xmm0, xmm0
    vsqrtss xmm0, xmm0, xmm0
    vbroadcastss zmm0, xmm0

    xor     rax, rax
    mov     rcx, r8
    shr     rcx, 4
.normalize:
    vmovaps zmm1, [r14 + rax*4]
    vmovaps zmm2, [r15 + rax*4]
    vdivps  zmm1, zmm1, zmm0
    vdivps  zmm2, zmm2, zmm0
    vmovaps [r14 + rax*4], zmm1
    vmovaps [r15 + rax*4], zmm2
    ; Copy back to v
    vmovaps [rdi + rax*4], zmm1
    vmovaps [rsi + rax*4], zmm2
    add     rax, 16
    dec     rcx
    jnz     .normalize

    dec     rbx
    jmp     .power_iter
.power_done:

    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    mov     rsp, rbp
    pop     rbp
    ret

; ───────────────────────────────────────────────────────────────────────────────
; off_diagonal_coherence(float* rho_r, float* rho_i, int dim) -> float (xmm0)
; Measures Σᵢ≠ⱼ |ρ[i,j]|² — quantum coherence (hidden state indicator)
; ───────────────────────────────────────────────────────────────────────────────
off_diagonal_coherence:
    push    rbp
    mov     rbp, rsp
    push    rbx

    ; Total coherence = Tr(ρ²) - Σᵢ |ρ[i,i]|²
    ; Step 1: compute total Tr(ρ²)
    push    rdx
    call    compute_purity_avx512
    pop     rdx
    vmovss  xmm10, xmm0         ; save total

    ; Step 2: subtract diagonal contribution
    vxorps  xmm11, xmm11, xmm11
    xor     rbx, rbx
.diag_loop:
    cmp     rbx, rdx
    jge     .diag_done
    ; diagonal index: i*dim + i
    mov     rax, rbx
    imul    rax, rdx
    add     rax, rbx
    vmovss  xmm0, [rdi + rax*4]
    vmovss  xmm1, [rsi + rax*4]
    vfmadd231ss xmm11, xmm0, xmm0
    vfmadd231ss xmm11, xmm1, xmm1
    inc     rbx
    jmp     .diag_loop
.diag_done:

    vsubss  xmm0, xmm10, xmm11  ; off-diagonal = total - diagonal

    pop     rbx
    mov     rsp, rbp
    pop     rbp
    ret
}
