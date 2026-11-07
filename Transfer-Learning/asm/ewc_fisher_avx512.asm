; =============================================================================
; ewc_fisher_avx512.asm
; AVX-512 accelerated Fisher Information Matrix computation for EWC
; Computes diagonal Fisher approximation for continual learning
; Target: x86-64 with AVX-512F, AVX-512BW, AVX-512DQ
; Assembler: NASM 2.15+
; =============================================================================

BITS 64

SECTION .data ALIGN=64

; EWC regularization constants
align 8
ewc_lambda_default:     dq 0x4079000000000000   ; 400.0 as double
ewc_lambda_min:         dq 0x4059000000000000   ; 100.0
ewc_lambda_max:         dq 0x4089000000000000   ; 800.0

; Gradient clipping threshold
align 8
grad_clip_threshold:    dq 0x4014000000000000   ; 5.0

; Small epsilon for numerical stability
align 8


; Normalization constant (1/N)
align 8
fisher_norm_scale:      dq 0x3F50624DD2F1A9FC   ; 1/1000 approx

; Broadcast constants for AVX-512
align 64
broadcast_one:          times 8 dq 0x3FF0000000000000   ; 1.0
broadcast_zero:         times 8 dq 0x0000000000000000   ; 0.0
broadcast_half:         times 8 dq 0x3FE0000000000000   ; 0.5
broadcast_two:          times 8 dq 0x4000000000000000   ; 2.0

; Fisher accumulation statistics
align 8
fisher_samples_seen:    dq 0
fisher_total_norm:      dq 0x0000000000000000
fisher_max_value:       dq 0x0000000000000000
fisher_min_value:       dq 0x7FF0000000000000   ; +inf

SECTION .bss ALIGN=64

; Temporary gradient buffer (64KB)
align 64
grad_temp_buffer:   resq 8192

; Fisher accumulation buffer (64KB)
align 64
fisher_accum:       resq 8192

SECTION .text

global fisher_compute_diagonal
global fisher_accumulate_gradient
global fisher_normalize
global fisher_apply_ewc
global fisher_compute_penalty
global fisher_clip_gradients
global fisher_merge_tasks
global fisher_scale
global fisher_dot_product
global fisher_l2_norm
global fisher_element_multiply
global fisher_element_add
global fisher_threshold_mask
global fisher_importance_weight
global fisher_reset_accumulator
global fisher_get_stats
global fisher_compute_batch
global fisher_online_update
global fisher_ewc_gradient

; =============================================================================
; fisher_reset_accumulator
; Zero the Fisher accumulation buffer
; Input:  rdi = pointer to Fisher buffer (double*)
;         rsi = length (number of doubles)
; Output: rax = 0
; =============================================================================
fisher_reset_accumulator:
    push    rbx
    mov     rbx, rsi
    vpxorq  zmm0, zmm0, zmm0

.reset_loop:
    cmp     rbx, 8
    jl      .reset_scalar


    add     rdi, 64
    sub     rbx, 8
    jmp     .reset_loop

.reset_scalar:
    test    rbx, rbx
    jz      .reset_done
    mov     qword [rdi], 0
    add     rdi, 8
    dec     rbx
    jmp     .reset_scalar

.reset_done:
    xor     eax, eax
    pop     rbx
    ret

; =============================================================================
; fisher_accumulate_gradient
; Accumulate squared gradients into Fisher diagonal estimate
; F_i += g_i^2 for each parameter i
; Input:  rdi = pointer to gradient vector (double*)
;         rsi = pointer to Fisher accumulator (double*)
;         rdx = length (number of parameters)
; Output: rax = 0
; =============================================================================
fisher_accumulate_gradient:
    push    rbx
    push    r12
    push    r13

    mov     r12, rdi        ; gradient
    mov     r13, rsi        ; Fisher accumulator
    mov     rbx, rdx        ; length

.accum_loop:
    cmp     rbx, 8
    jl      .accum_scalar

    ; Load 8 gradients
    vmovdqu64   zmm0, [r12]

    ; Square: g^2
    vmulpd      zmm1, zmm0, zmm0

    ; Load current Fisher values
    vmovdqu64   zmm2, [r13]

    ; Accumulate: F += g^2
    vaddpd      zmm3, zmm2, zmm1

    ; Store
    vmovdqu64   [r13], zmm3

    add     r12, 64
    add     r13, 64
    sub     rbx, 8
    jmp     .accum_loop

.accum_scalar:
    test    rbx, rbx
    jz      .accum_done

    movsd   xmm0, [r12]
    mulsd   xmm0, xmm0          ; g^2
    addsd   xmm0, [r13]         ; F += g^2
    movsd   [r13], xmm0

    add     r12, 8
    add     r13, 8
    dec     rbx
    jmp     .accum_scalar

.accum_done:
    inc     qword [fisher_samples_seen]
    xor     eax, eax

    pop     r13
    pop     r12
    pop     rbx
    ret

; =============================================================================
; fisher_compute_diagonal
; Compute diagonal Fisher Information Matrix from a batch of gradients
; F_i = (1/N) * sum_n(g_i_n^2)
; Input:  rdi = pointer to gradient matrix (double*, N x P row-major)
;         rsi = N (number of samples)
;         rdx = P (number of parameters)
;         rcx = pointer to output Fisher diagonal (double*, P)
; Output: rax = 0 (success)
; =============================================================================
fisher_compute_diagonal:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    push    rbp

    mov     r12, rdi        ; gradient matrix
    mov     r13, rsi        ; N samples
    mov     r14, rdx        ; P parameters
    mov     r15, rcx        ; output Fisher

    ; Zero output Fisher
    mov     rdi, r15
    mov     rsi, r14
    call    fisher_reset_accumulator

    ; Accumulate squared gradients for each sample
    xor     rbx, rbx        ; sample index

.diag_sample_loop:
    cmp     rbx, r13
    jge     .diag_normalize

    ; Pointer to gradient row n
    mov     rdi, rbx
    imul    rdi, r14
    imul    rdi, 8          ; byte offset
    add     rdi, r12

    mov     rsi, r15        ; Fisher accumulator
    mov     rdx, r14        ; P parameters

    call    fisher_accumulate_gradient

    inc     rbx
    jmp     .diag_sample_loop

.diag_normalize:
    ; Normalize by N: F_i /= N
    mov     rdi, r15
    mov     rsi, r13
    mov     rdx, r14
    call    fisher_normalize

    xor     eax, eax

    pop     rbp
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; =============================================================================
; fisher_normalize
; Divide Fisher values by N (number of samples)
; Input:  rdi = pointer to Fisher vector (double*)
;         rsi = N (divisor, uint64)
;         rdx = length (number of parameters)
; Output: rax = 0
; =============================================================================
fisher_normalize:
    push    rbx
    push    r12

    mov     r12, rdi        ; Fisher vector
    mov     rbx, rdx        ; length

    ; Convert N to double and broadcast
    cvtsi2sd    xmm0, rsi
    vbroadcastsd    zmm1, xmm0  ; broadcast N to all lanes

.norm_loop:
    cmp     rbx, 8
    jl      .norm_scalar

    vmovdqu64   zmm0, [r12]
    vdivpd      zmm2, zmm0, zmm1
    vmovdqu64   [r12], zmm2

    add     r12, 64
    sub     rbx, 8
    jmp     .norm_loop

.norm_scalar:
    test    rbx, rbx
    jz      .norm_done

    movsd   xmm2, [r12]

    movsd   [r12], xmm2

    add     r12, 8
    dec     rbx
    jmp     .norm_scalar

.norm_done:
    xor     eax, eax
    pop     r12
    pop     rbx
    ret

; =============================================================================
; fisher_apply_ewc
; Apply EWC regularization: compute regularization gradient
; reg_grad_i = lambda * F_i * (theta_i - theta_star_i)
; Input:  rdi = pointer to current params theta (double*)
;         rsi = pointer to optimal params theta_star (double*)
;         rdx = pointer to Fisher diagonal F (double*)
;         rcx = pointer to output reg_grad (double*)
;         r8  = length (number of parameters)
;         xmm0 = lambda (EWC regularization strength)
; Output: rax = 0
; =============================================================================
fisher_apply_ewc:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15

    mov     r12, rdi        ; theta
    mov     r13, rsi        ; theta_star
    mov     r14, rdx        ; Fisher
    mov     r15, rcx        ; output reg_grad
    mov     rbx, r8         ; length

    ; Broadcast lambda
    vbroadcastsd    zmm15, xmm0

.ewc_loop:
    cmp     rbx, 8
    jl      .ewc_scalar

    ; Load theta and theta_star
    vmovdqu64   zmm0, [r12]
    vmovdqu64   zmm1, [r13]

    ; delta = theta - theta_star
    vsubpd      zmm2, zmm0, zmm1

    ; Load Fisher diagonal
    vmovdqu64   zmm3, [r14]

    ; reg_grad = lambda * F * delta
    vmulpd      zmm4, zmm3, zmm2
    vmulpd      zmm5, zmm4, zmm15

    ; Store
    vmovdqu64   [r15], zmm5

    add     r12, 64
    add     r13, 64
    add     r14, 64
    add     r15, 64
    sub     rbx, 8
    jmp     .ewc_loop

.ewc_scalar:
    test    rbx, rbx
    jz      .ewc_done

    movsd   xmm1, [r12]
    subsd   xmm1, [r13]         ; delta
    mulsd   xmm1, [r14]         ; F * delta

    movsd   [r15], xmm1

    add     r12, 8
    add     r13, 8
    add     r14, 8
    add     r15, 8
    dec     rbx
    jmp     .ewc_scalar

.ewc_done:
    xor     eax, eax

    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; =============================================================================
; fisher_compute_penalty
; Compute EWC penalty: L_ewc = (lambda/2) * sum_i(F_i * (theta_i - theta*_i)^2)
; Input:  rdi = pointer to theta (double*)
;         rsi = pointer to theta_star (double*)
;         rdx = pointer to Fisher F (double*)
;         rcx = length
;         xmm0 = lambda
; Output: xmm0 = EWC penalty (double)
; =============================================================================
fisher_compute_penalty:
    push    rbx
    push    r12
    push    r13
    push    r14

    mov     r12, rdi
    mov     r13, rsi
    mov     r14, rdx
    mov     rbx, rcx

    ; Broadcast lambda/2
    movsd   xmm1, [broadcast_half]
    mulsd   xmm0, xmm1
    vbroadcastsd    zmm15, xmm0

    vpxorq  zmm14, zmm14, zmm14     ; accumulator = 0.0

.penalty_loop:
    cmp     rbx, 8
    jl      .penalty_scalar

    vmovdqu64   zmm0, [r12]
    vmovdqu64   zmm1, [r13]
    vsubpd      zmm2, zmm0, zmm1    ; delta
    vmulpd      zmm3, zmm2, zmm2    ; delta^2
    vmovdqu64   zmm4, [r14]
    vmulpd      zmm5, zmm4, zmm3    ; F * delta^2
    vaddpd      zmm14, zmm14, zmm5  ; accumulate

    add     r12, 64
    add     r13, 64
    add     r14, 64
    sub     rbx, 8
    jmp     .penalty_loop

.penalty_scalar:
    test    rbx, rbx
    jz      .penalty_reduce

    movsd   xmm1, [r12]
    subsd   xmm1, [r13]
    mulsd   xmm1, xmm1
    mulsd   xmm1, [r14]
    ; Add to zmm14 lane 0

    add     r12, 8
    add     r13, 8
    add     r14, 8
    dec     rbx
    jmp     .penalty_scalar

.penalty_reduce:
    ; Horizontal sum of zmm14
    vextractf64x4   ymm0, zmm14, 1
    vaddpd          ymm1, ymm0, ymm14
    vextractf128    xmm2, ymm1, 1
    vaddpd          xmm3, xmm2, xmm1
    vhaddpd         xmm4, xmm3, xmm3

    movsd   xmm0, xmm4

    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; =============================================================================
; fisher_clip_gradients
; Clip gradient vector to max norm
; Input:  rdi = pointer to gradient vector (double*)
;         rsi = length
;         xmm0 = max_norm threshold
; Output: rax = 0 (no clipping), 1 (clipped)
; =============================================================================
fisher_clip_gradients:
    push    rbx
    push    r12

    mov     r12, rdi
    mov     rbx, rsi
    movsd   xmm15, xmm0        ; save threshold

    ; Compute L2 norm
    mov     rdi, r12
    mov     rsi, rbx
    call    fisher_l2_norm      ; result in xmm0

    ; Compare norm to threshold
    ucomisd xmm0, xmm15
    jbe     .no_clip

    ; Compute scale = threshold / norm
    divsd   xmm15, xmm0
    vbroadcastsd    zmm14, xmm15

    ; Scale all gradients
    mov     r12, rdi
    ; (rdi was modified by fisher_l2_norm call, restore)
    ; Note: in real code, save/restore r12 properly
    mov     rbx, rsi

.clip_loop:
    cmp     rbx, 8
    jl      .clip_scalar

    vmovdqu64   zmm0, [r12]
    vmulpd      zmm1, zmm0, zmm14
    vmovdqu64   [r12], zmm1

    add     r12, 64
    sub     rbx, 8
    jmp     .clip_loop

.clip_scalar:
    test    rbx, rbx
    jz      .clip_done

    movsd   xmm0, [r12]
    mulsd   xmm0, xmm15
    movsd   [r12], xmm0
    add     r12, 8
    dec     rbx
    jmp     .clip_scalar

.clip_done:
    mov     eax, 1
    jmp     .done

.no_clip:
    xor     eax, eax

.done:
    pop     r12
    pop     rbx
    ret

; =============================================================================
; fisher_l2_norm
; Compute L2 norm of a vector
; Input:  rdi = pointer to vector (double*)
;         rsi = length
; Output: xmm0 = L2 norm
; =============================================================================
fisher_l2_norm:
    push    rbx
    push    r12

    mov     r12, rdi
    mov     rbx, rsi

    vpxorq  zmm14, zmm14, zmm14     ; accumulator

.norm_loop:
    cmp     rbx, 8
    jl      .norm_scalar

    vmovdqu64   zmm0, [r12]
    vmulpd      zmm1, zmm0, zmm0
    vaddpd      zmm14, zmm14, zmm1

    add     r12, 64
    sub     rbx, 8
    jmp     .norm_loop

.norm_scalar:
    test    rbx, rbx
    jz      .norm_reduce

    movsd   xmm0, [r12]
    mulsd   xmm0, xmm0
    vextractf64x2   xmm1, zmm14, 0


    add     r12, 8
    dec     rbx
    jmp     .norm_scalar

.norm_reduce:
    vextractf64x4   ymm0, zmm14, 1
    vaddpd          ymm1, ymm0, ymm14
    vextractf128    xmm2, ymm1, 1
    vaddpd          xmm3, xmm2, xmm1
    vhaddpd         xmm4, xmm3, xmm3
    sqrtsd          xmm0, xmm4

    pop     r12
    pop     rbx
    ret

; =============================================================================
; fisher_dot_product
; Compute dot product of two vectors
; Input:  rdi = pointer to vector A (double*)
;         rsi = pointer to vector B (double*)
;         rdx = length
; Output: xmm0 = dot product
; =============================================================================
fisher_dot_product:
    push    rbx
    push    r12
    push    r13

    mov     r12, rdi
    mov     r13, rsi
    mov     rbx, rdx

    vpxorq  zmm14, zmm14, zmm14

.dot_loop:
    cmp     rbx, 8
    jl      .dot_scalar

    vmovdqu64   zmm0, [r12]
    vmovdqu64   zmm1, [r13]
    vfmadd231pd zmm14, zmm0, zmm1

    add     r12, 64
    add     r13, 64
    sub     rbx, 8
    jmp     .dot_loop

.dot_scalar:
    test    rbx, rbx
    jz      .dot_reduce

    movsd   xmm0, [r12]
    mulsd   xmm0, [r13]
    vextractf64x2   xmm1, zmm14, 0
    addsd   xmm1, xmm0

    add     r12, 8
    add     r13, 8
    dec     rbx
    jmp     .dot_scalar

.dot_reduce:
    vextractf64x4   ymm0, zmm14, 1
    vaddpd          ymm1, ymm0, ymm14
    vextractf128    xmm2, ymm1, 1
    vaddpd          xmm3, xmm2, xmm1
    vhaddpd         xmm0, xmm3, xmm3

    pop     r13
    pop     r12
    pop     rbx
    ret

; =============================================================================
; fisher_element_multiply
; Element-wise multiply: C = A * B
; Input:  rdi = A (double*), rsi = B (double*), rdx = C (double*), rcx = length
; =============================================================================
fisher_element_multiply:
    push    rbx
    mov     rbx, rcx

.emul_loop:
    cmp     rbx, 8
    jl      .emul_scalar

    vmovdqu64   zmm0, [rdi]
    vmovdqu64   zmm1, [rsi]
    vmulpd      zmm2, zmm0, zmm1
    vmovdqu64   [rdx], zmm2

    add     rdi, 64
    add     rsi, 64
    add     rdx, 64
    sub     rbx, 8
    jmp     .emul_loop

.emul_scalar:
    test    rbx, rbx
    jz      .emul_done

    movsd   xmm0, [rdi]
    mulsd   xmm0, [rsi]
    movsd   [rdx], xmm0

    add     rdi, 8
    add     rsi, 8
    add     rdx, 8
    dec     rbx
    jmp     .emul_scalar

.emul_done:
    xor     eax, eax
    pop     rbx
    ret

; =============================================================================
; fisher_element_add
; Element-wise add: C = A + B
; Input:  rdi = A (double*), rsi = B (double*), rdx = C (double*), rcx = length
; =============================================================================
fisher_element_add:
    push    rbx
    mov     rbx, rcx

.eadd_loop:
    cmp     rbx, 8
    jl      .eadd_scalar

    vmovdqu64   zmm0, [rdi]
    vmovdqu64   zmm1, [rsi]
    vaddpd      zmm2, zmm0, zmm1
    vmovdqu64   [rdx], zmm2

    add     rdi, 64
    add     rsi, 64
    add     rdx, 64
    sub     rbx, 8
    jmp     .eadd_loop

.eadd_scalar:
    test    rbx, rbx
    jz      .eadd_done

    movsd   xmm0, [rdi]
    addsd   xmm0, [rsi]
    movsd   [rdx], xmm0

    add     rdi, 8
    add     rsi, 8
    add     rdx, 8
    dec     rbx
    jmp     .eadd_scalar

.eadd_done:
    xor     eax, eax
    pop     rbx
    ret

; =============================================================================
; fisher_scale
; Scale vector by scalar: B = alpha * A
; Input:  rdi = A (double*), rsi = B (double*), rdx = length, xmm0 = alpha
; =============================================================================
fisher_scale:
    push    rbx
    mov     rbx, rdx
    vbroadcastsd    zmm15, xmm0

.scale_loop:
    cmp     rbx, 8
    jl      .scale_scalar

    vmovdqu64   zmm0, [rdi]
    vmulpd      zmm1, zmm0, zmm15
    vmovdqu64   [rsi], zmm1

    add     rdi, 64
    add     rsi, 64
    sub     rbx, 8
    jmp     .scale_loop

.scale_scalar:
    test    rbx, rbx
    jz      .scale_done

    movsd   xmm1, [rdi]
    mulsd   xmm1, xmm0
    movsd   [rsi], xmm1

    add     rdi, 8
    add     rsi, 8
    dec     rbx
    jmp     .scale_scalar

.scale_done:
    xor     eax, eax
    pop     rbx
    ret

; =============================================================================
; fisher_merge_tasks
; Merge Fisher matrices from multiple tasks: F_merged = max(F_1, F_2, ..., F_K)
; Input:  rdi = pointer to array of Fisher pointers (double**)
;         rsi = K (number of tasks)
;         rdx = P (number of parameters)
;         rcx = pointer to output merged Fisher (double*)
; Output: rax = 0
; =============================================================================
fisher_merge_tasks:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15

    mov     r12, rdi        ; Fisher pointer array
    mov     r13, rsi        ; K tasks
    mov     r14, rdx        ; P parameters
    mov     r15, rcx        ; output

    ; Initialize output with first Fisher
    mov     rdi, [r12]
    mov     rsi, r15
    mov     rdx, r14
    imul    rdx, 8
    ; memcpy first Fisher to output
    xor     rbx, rbx
.init_copy:
    cmp     rbx, r14
    jge     .merge_loop_start
    mov     rax, [rdi + rbx*8]
    mov     [r15 + rbx*8], rax
    inc     rbx
    jmp     .init_copy

.merge_loop_start:
    mov     rbx, 1          ; start from task 1

.merge_task_loop:
    cmp     rbx, r13
    jge     .merge_done

    mov     rdi, [r12 + rbx*8]     ; Fisher_k pointer
    xor     rcx, rcx

.merge_param_loop:
    cmp     rcx, r14
    jge     .merge_next_task

    movsd   xmm0, [rdi + rcx*8]
    movsd   xmm1, [r15 + rcx*8]
    maxsd   xmm0, xmm1
    movsd   [r15 + rcx*8], xmm0

    inc     rcx
    jmp     .merge_param_loop

.merge_next_task:
    inc     rbx
    jmp     .merge_task_loop

.merge_done:
    xor     eax, eax

    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; =============================================================================
; fisher_threshold_mask
; Create binary mask where Fisher > threshold
; Input:  rdi = Fisher vector (double*), rsi = length, rdx = mask output (uint8*)
;         xmm0 = threshold
; Output: rax = count of parameters above threshold
; =============================================================================
fisher_threshold_mask:
    push    rbx
    push    r12
    push    r13

    mov     r12, rdi
    mov     r13, rsi
    ; rdx = mask output

    vbroadcastsd    zmm15, xmm0
    xor     rbx, rbx        ; index
    xor     rax, rax        ; count above threshold

.mask_loop:
    cmp     rbx, r13
    jge     .mask_done

    movsd   xmm1, [r12 + rbx*8]
    ucomisd xmm1, xmm0
    jbe     .mask_zero

    mov     byte [rdx + rbx], 1
    inc     rax
    jmp     .mask_next

.mask_zero:
    mov     byte [rdx + rbx], 0

.mask_next:
    inc     rbx
    jmp     .mask_loop

.mask_done:
    pop     r13
    pop     r12
    pop     rbx
    ret

; =============================================================================
; fisher_importance_weight
; Compute importance weights: w_i = F_i / (F_i + epsilon)
; Input:  rdi = Fisher vector (double*), rsi = output weights (double*), rdx = length
; =============================================================================
fisher_importance_weight:
    push    rbx
    mov     rbx, rdx

    movsd   xmm15, [fisher_epsilon]
    vbroadcastsd    zmm15, xmm15

.iw_loop:
    cmp     rbx, 8
    jl      .iw_scalar

    vmovdqu64   zmm0, [rdi]
    vaddpd      zmm1, zmm0, zmm15    ; F + eps
    vdivpd      zmm2, zmm0, zmm1    ; F / (F + eps)
    vmovdqu64   [rsi], zmm2

    add     rdi, 64
    add     rsi, 64
    sub     rbx, 8
    jmp     .iw_loop

.iw_scalar:
    test    rbx, rbx
    jz      .iw_done

    movsd   xmm0, [rdi]
    movsd   xmm1, xmm0
    addsd   xmm1, [fisher_epsilon]
    divsd   xmm0, xmm1
    movsd   [rsi], xmm0

    add     rdi, 8
    add     rsi, 8
    dec     rbx
    jmp     .iw_scalar

.iw_done:
    xor     eax, eax
    pop     rbx
    ret

; =============================================================================
; fisher_online_update
; Online Fisher update: F = (1-alpha)*F + alpha*g^2
; Input:  rdi = Fisher (double*), rsi = gradient (double*), rdx = length
;         xmm0 = alpha (update rate)
; =============================================================================
fisher_online_update:
    push    rbx
    push    r12
    push    r13

    mov     r12, rdi
    mov     r13, rsi
    mov     rbx, rdx

    ; alpha in xmm0, (1-alpha) in xmm1
    movsd   xmm1, [broadcast_one]
    subsd   xmm1, xmm0

    vbroadcastsd    zmm14, xmm0     ; alpha
    vbroadcastsd    zmm15, xmm1     ; 1-alpha

.online_loop:
    cmp     rbx, 8
    jl      .online_scalar

    vmovdqu64   zmm0, [r12]         ; F
    vmovdqu64   zmm1, [r13]         ; g
    vmulpd      zmm2, zmm1, zmm1    ; g^2
    vmulpd      zmm3, zmm0, zmm15   ; (1-alpha)*F
    vfmadd231pd zmm3, zmm2, zmm14   ; + alpha*g^2
    vmovdqu64   [r12], zmm3

    add     r12, 64
    add     r13, 64
    sub     rbx, 8
    jmp     .online_loop

.online_scalar:
    test    rbx, rbx
    jz      .online_done

    movsd   xmm2, [r12]
    movsd   xmm3, [r13]
    mulsd   xmm3, xmm3              ; g^2

    addsd   xmm2, xmm3
    movsd   [r12], xmm2

    add     r12, 8
    add     r13, 8
    dec     rbx
    jmp     .online_scalar

.online_done:
    xor     eax, eax
    pop     r13
    pop     r12
    pop     rbx
    ret

; =============================================================================
; fisher_ewc_gradient
; Compute full EWC gradient: grad_total = grad_task + lambda * F * (theta - theta*)
; Input:  rdi = task gradient (double*)
;         rsi = theta (double*)
;         rdx = theta_star (double*)
;         rcx = Fisher (double*)
;         r8  = output gradient (double*)
;         r9  = length
;         xmm0 = lambda
; Output: rax = 0
; =============================================================================
fisher_ewc_gradient:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    push    rbp

    mov     r12, rdi        ; task gradient
    mov     r13, rsi        ; theta
    mov     r14, rdx        ; theta_star
    mov     r15, rcx        ; Fisher
    mov     rbp, r8         ; output
    mov     rbx, r9         ; length

    vbroadcastsd    zmm15, xmm0     ; lambda

.ewc_grad_loop:
    cmp     rbx, 8
    jl      .ewc_grad_scalar

    vmovdqu64   zmm0, [r12]         ; task grad
    vmovdqu64   zmm1, [r13]         ; theta
    vmovdqu64   zmm2, [r14]         ; theta_star
    vmovdqu64   zmm3, [r15]         ; Fisher

    vsubpd      zmm4, zmm1, zmm2    ; theta - theta_star
    vmulpd      zmm5, zmm3, zmm4    ; F * delta
    vmulpd      zmm6, zmm5, zmm15   ; lambda * F * delta
    vaddpd      zmm7, zmm0, zmm6    ; task_grad + ewc_grad
    vmovdqu64   [rbp], zmm7

    add     r12, 64
    add     r13, 64
    add     r14, 64
    add     r15, 64
    add     rbp, 64
    sub     rbx, 8
    jmp     .ewc_grad_loop

.ewc_grad_scalar:
    test    rbx, rbx
    jz      .ewc_grad_done

    movsd   xmm1, [r12]
    movsd   xmm2, [r13]
    subsd   xmm2, [r14]
    mulsd   xmm2, [r15]
    mulsd   xmm2, xmm0
    addsd   xmm1, xmm2
    movsd   [rbp], xmm1

    add     r12, 8
    add     r13, 8
    add     r14, 8
    add     r15, 8
    add     rbp, 8
    dec     rbx
    jmp     .ewc_grad_scalar

.ewc_grad_done:
    xor     eax, eax

    pop     rbp
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; =============================================================================
; fisher_compute_batch
; Compute Fisher for a batch using online updates
; Input:  rdi = gradient batch (double*, N x P)
;         rsi = Fisher accumulator (double*, P)
;         rdx = N samples
;         rcx = P parameters
;         xmm0 = alpha (online update rate)
; Output: rax = 0
; =============================================================================
fisher_compute_batch:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15

    mov     r12, rdi        ; gradient batch
    mov     r13, rsi        ; Fisher accumulator
    mov     r14, rdx        ; N
    mov     r15, rcx        ; P
    movsd   [grad_temp_buffer], xmm0    ; save alpha

    xor     rbx, rbx        ; sample index

.batch_fisher_loop:
    cmp     rbx, r14
    jge     .batch_fisher_done

    ; Pointer to gradient row
    mov     rdi, rbx
    imul    rdi, r15
    imul    rdi, 8
    add     rdi, r12



    inc     rbx
    jmp     .batch_fisher_loop

.batch_fisher_done:
    xor     eax, eax

    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; =============================================================================
; fisher_get_stats
; Return Fisher computation statistics
; Input:  rdi = pointer to stats struct
; Output: rax = 0
; =============================================================================
fisher_get_stats:
    mov     rax, [fisher_samples_seen]
    mov     [rdi], rax
    movsd   xmm0, [fisher_total_norm]
    movsd   [rdi + 8], xmm0
    movsd   xmm1, [fisher_max_value]
    movsd   [rdi + 16], xmm1
    movsd   xmm2, [fisher_min_value]
    movsd   [rdi + 24], xmm2
    xor     eax, eax
    ret
