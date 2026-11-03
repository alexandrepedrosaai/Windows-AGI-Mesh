; =============================================================================
; gradient_compress_avx512.asm
; AVX-512 accelerated gradient compression for federated learning
; Implements Top-K sparsification, quantization, and error feedback
; Target: x86-64 with AVX-512F, AVX-512BW, AVX-512DQ, AVX-512VBMI
; Assembler: NASM 2.15+
; =============================================================================

BITS 64

SECTION .data ALIGN=64

; Quantization levels for 8-bit gradient quantization
align 64
quant_levels_8bit:
    times 8 dq 0x4060000000000000   ; 128.0 (scale factor)

; Sign bit mask for double
align 8
sign_mask_double:   dq 0x8000000000000000

; Absolute value mask for double
align 8
abs_mask_double:    dq 0x7FFFFFFFFFFFFFFF

; Compression statistics
align 8
total_gradients_in:     dq 0
total_gradients_out:    dq 0
total_bytes_saved:      dq 0
compression_ratio:      dq 0x3FF0000000000000   ; 1.0

; Top-K selection constants
align 8
topk_default_ratio:     dq 0x3FB999999999999A   ; 0.1 (10%)

; Error feedback accumulator size
align 8
error_buffer_size:      dq 0

SECTION .bss ALIGN=64

; Error feedback buffer (for error correction between rounds)
align 64
error_feedback:     resq 65536      ; 512KB for error feedback

; Temporary sort buffer
align 64
sort_buffer:        resq 8192

; Index buffer for Top-K selection
align 64
topk_indices:       resq 8192

; Magnitude buffer for sorting
align 64
magnitude_buffer:   resq 8192

SECTION .text

global gradient_topk_select
global gradient_quantize_8bit
global gradient_dequantize_8bit
global gradient_quantize_4bit
global gradient_dequantize_4bit
global gradient_compress_topk
global gradient_decompress_topk
global gradient_error_feedback_apply
global gradient_error_feedback_update
global gradient_sign_compress
global gradient_sign_decompress
global gradient_abs_values
global gradient_find_threshold
global gradient_apply_mask
global gradient_pack_sparse
global gradient_unpack_sparse
global gradient_compute_sparsity
global gradient_random_sparsify
global gradient_magnitude_sort
global gradient_compression_stats

; =============================================================================
; gradient_abs_values
; Compute absolute values of gradient vector
; Input:  rdi = input gradient (double*), rsi = output abs (double*), rdx = length
; =============================================================================
gradient_abs_values:
    push    rbx
    mov     rbx, rdx

    vmovdqu64   zmm15, [abs_mask_double - 56]   ; broadcast abs mask
    ; Broadcast abs mask properly
    mov     rax, 0x7FFFFFFFFFFFFFFF
    movq    xmm14, rax
    vbroadcastsd    zmm15, xmm14

.abs_loop:
    cmp     rbx, 8
    jl      .abs_scalar

    vmovdqu64   zmm0, [rdi]
    vandpd      zmm1, zmm0, zmm15   ; clear sign bit
    vmovdqu64   [rsi], zmm1

    add     rdi, 64
    add     rsi, 64
    sub     rbx, 8
    jmp     .abs_loop

.abs_scalar:
    test    rbx, rbx
    jz      .abs_done

    movsd   xmm0, [rdi]
    andpd   xmm0, xmm14
    movsd   [rsi], xmm0

    add     rdi, 8
    add     rsi, 8
    dec     rbx
    jmp     .abs_scalar

.abs_done:
    xor     eax, eax
    pop     rbx
    ret

; =============================================================================
; gradient_find_threshold
; Find the K-th largest absolute value (threshold for Top-K)
; Uses partial quickselect algorithm
; Input:  rdi = magnitude array (double*), rsi = length, rdx = K
; Output: xmm0 = threshold value
; =============================================================================
gradient_find_threshold:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15

    mov     r12, rdi        ; magnitudes
    mov     r13, rsi        ; length
    mov     r14, rdx        ; K

    ; Copy magnitudes to sort buffer for in-place selection
    xor     rbx, rbx
.copy_loop:
    cmp     rbx, r13
    jge     .copy_done
    mov     rax, [r12 + rbx*8]
    mov     [sort_buffer + rbx*8], rax
    inc     rbx
    jmp     .copy_loop
.copy_done:

    ; Simple partial sort: find K-th largest using insertion sort on top-K
    ; For production, use AVX-512 bitonic sort
    ; Here: simplified O(N*K) selection

    xor     rbx, rbx        ; outer loop: find K largest

.select_outer:
    cmp     rbx, r14
    jge     .select_done

    ; Find max in remaining [rbx, N)
    mov     r15, rbx        ; max index
    movsd   xmm14, [sort_buffer + rbx*8]

    mov     rcx, rbx
    inc     rcx

.select_inner:
    cmp     rcx, r13
    jge     .select_swap

    movsd   xmm0, [sort_buffer + rcx*8]
    ucomisd xmm0, xmm14
    jbe     .select_inner_next

    movsd   xmm14, xmm0
    mov     r15, rcx

.select_inner_next:
    inc     rcx
    jmp     .select_inner

.select_swap:
    ; Swap sort_buffer[rbx] and sort_buffer[r15]
    mov     rax, [sort_buffer + rbx*8]
    mov     rcx, [sort_buffer + r15*8]
    mov     [sort_buffer + rbx*8], rcx
    mov     [sort_buffer + r15*8], rax

    inc     rbx
    jmp     .select_outer

.select_done:
    ; Threshold = sort_buffer[K-1] (K-th largest)
    dec     r14
    movsd   xmm0, [sort_buffer + r14*8]

    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; =============================================================================
; gradient_topk_select
; Select Top-K gradients by magnitude
; Input:  rdi = gradient vector (double*)
;         rsi = length N
;         rdx = K (number to keep)
;         rcx = output sparse values (double*)
;         r8  = output sparse indices (uint32*)
; Output: rax = actual K selected
; =============================================================================
gradient_topk_select:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    push    rbp

    mov     r12, rdi        ; gradient
    mov     r13, rsi        ; N
    mov     r14, rdx        ; K
    mov     r15, rcx        ; output values
    mov     rbp, r8         ; output indices

    ; Validate and bound N/K for fixed scratch buffers (8192 doubles)
    test    r13, r13
    jle     .topk_return_zero
    cmp     r13, 8192
    jle     .topk_n_bounded
    mov     r13, 8192

.topk_n_bounded:
    test    r14, r14
    jle     .topk_return_zero
    cmp     r14, r13
    jle     .topk_k_bounded
    mov     r14, r13

.topk_k_bounded:
    ; Step 1: Compute absolute values into magnitude_buffer
    mov     rdi, r12
    lea     rsi, [magnitude_buffer]
    mov     rdx, r13
    call    gradient_abs_values

    ; Step 2: Find threshold (K-th largest magnitude)
    lea     rdi, [magnitude_buffer]
    mov     rsi, r13
    mov     rdx, r14
    call    gradient_find_threshold
    ; xmm0 = threshold

    ; Step 3: Select gradients above threshold
    xor     rbx, rbx        ; input index
    xor     rax, rax        ; output count

.topk_select_loop:
    cmp     rbx, r13
    jge     .topk_select_done

    movsd   xmm1, [magnitude_buffer + rbx*8]
    ucomisd xmm1, xmm0
    jb      .topk_skip

    ; Above threshold: include this gradient
    movsd   xmm2, [r12 + rbx*8]
    movsd   [r15 + rax*8], xmm2
    mov     ecx, ebx
    mov     [rbp + rax*4], ecx
    inc     rax

    ; Stop if we have K
    cmp     rax, r14
    jge     .topk_select_done

.topk_skip:

.topk_return_zero:
    xor     rax, rax
    inc     rbx
    jmp     .topk_select_loop

.topk_select_done:
    ; rax = actual count selected

    pop     rbp
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; =============================================================================
; gradient_quantize_8bit
; Quantize double gradients to 8-bit integers
; Input:  rdi = input gradients (double*)
;         rsi = output quantized (int8_t*)
;         rdx = length
;         xmm0 = scale factor
; Output: rax = 0, xmm0 = actual scale used
; =============================================================================
gradient_quantize_8bit:
    push    rbx
    push    r12
    push    r13

    mov     r12, rdi
    mov     r13, rsi
    mov     rbx, rdx
    movsd   xmm15, xmm0        ; scale factor

    ; If scale = 0, compute from max abs value
    xorpd   xmm1, xmm1
    ucomisd xmm15, xmm1
    jne     .quant8_have_scale

    ; Find max absolute value
    vpxorq  zmm14, zmm14, zmm14
    xor     rcx, rcx
.quant8_max_loop:
    cmp     rcx, rbx
    jge     .quant8_max_done
    movsd   xmm0, [r12 + rcx*8]
    andpd   xmm0, [abs_mask_double]
    ucomisd xmm0, xmm15
    jbe     .quant8_max_next
    movsd   xmm15, xmm0
.quant8_max_next:
    inc     rcx
    jmp     .quant8_max_loop
.quant8_max_done:
    ; scale = 127.0 / max_abs
    xorpd   xmm0, xmm0
    ucomisd xmm15, xmm0
    jne     .quant8_nonzero_scale
    mov     rax, 0x3FF0000000000000
    movq    xmm15, rax
    jmp     .quant8_have_scale
.quant8_nonzero_scale:
    mov     rax, 0x405FC00000000000  ; 127.0
    movq    xmm0, rax
    divsd   xmm0, xmm15
    movsd   xmm15, xmm0

.quant8_have_scale:
    vbroadcastsd    zmm15, xmm15

    xor     rcx, rcx

.quant8_loop:
    cmp     rcx, rbx
    jge     .quant8_done

    movsd   xmm0, [r12 + rcx*8]
    mulsd   xmm0, xmm15
    cvtsd2si    eax, xmm0

    ; Clamp to [-127, 127]
    cmp     eax, 127
    jle     .quant8_clamp_low
    mov     eax, 127
    jmp     .quant8_store
.quant8_clamp_low:
    cmp     eax, -127
    jge     .quant8_store
    mov     eax, -127

.quant8_store:
    mov     [r13 + rcx], al
    inc     rcx
    jmp     .quant8_loop

.quant8_done:
    ; Return scale in xmm0
    vextractf64x2   xmm0, zmm15, 0

    xor     eax, eax
    pop     r13
    pop     r12
    pop     rbx
    ret

; =============================================================================
; gradient_dequantize_8bit
; Dequantize 8-bit integers back to double gradients
; Input:  rdi = quantized (int8_t*), rsi = output (double*), rdx = length
;         xmm0 = scale factor (same as used in quantize)
; Output: rax = 0
; =============================================================================
gradient_dequantize_8bit:
    push    rbx
    push    r12
    push    r13

    mov     r12, rdi
    mov     r13, rsi
    mov     rbx, rdx

    ; inv_scale = 1.0 / scale
    movsd   xmm1, [broadcast_one + 0]
    mov     rax, 0x3FF0000000000000
    movq    xmm1, rax
    divsd   xmm1, xmm0
    movsd   xmm15, xmm1

    xor     rcx, rcx

.dequant8_loop:
    cmp     rcx, rbx
    jge     .dequant8_done

    movsx   eax, byte [r12 + rcx]
    cvtsi2sd    xmm0, eax
    mulsd   xmm0, xmm15
    movsd   [r13 + rcx*8], xmm0

    inc     rcx
    jmp     .dequant8_loop

.dequant8_done:
    xor     eax, eax
    pop     r13
    pop     r12
    pop     rbx
    ret

; =============================================================================
; gradient_quantize_4bit
; Quantize double gradients to 4-bit (packed 2 per byte)
; Input:  rdi = input (double*), rsi = output (uint8_t*), rdx = length (must be even)
;         xmm0 = scale factor
; Output: rax = 0
; =============================================================================
gradient_quantize_4bit:
    push    rbx
    push    r12
    push    r13

    mov     r12, rdi
    mov     r13, rsi
    mov     rbx, rdx
    movsd   xmm15, xmm0

    xor     rcx, rcx

.quant4_loop:
    cmp     rcx, rbx
    jge     .quant4_done

    ; Quantize first value (low nibble)
    movsd   xmm0, [r12 + rcx*8]
    mulsd   xmm0, xmm15
    cvtsd2si    eax, xmm0
    ; Clamp to [-7, 7]
    cmp     eax, 7
    jle     .q4_clamp_low1
    mov     eax, 7
    jmp     .q4_ok1
.q4_clamp_low1:
    cmp     eax, -7
    jge     .q4_ok1
    mov     eax, -7
.q4_ok1:
    and     eax, 0x0F          ; keep low 4 bits (sign-magnitude in 4 bits)
    mov     r8d, eax

    inc     rcx
    cmp     rcx, rbx
    jge     .quant4_store_last

    ; Quantize second value (high nibble)
    movsd   xmm0, [r12 + rcx*8]
    mulsd   xmm0, xmm15
    cvtsd2si    eax, xmm0
    cmp     eax, 7
    jle     .q4_clamp_low2
    mov     eax, 7
    jmp     .q4_ok2
.q4_clamp_low2:
    cmp     eax, -7
    jge     .q4_ok2
    mov     eax, -7
.q4_ok2:
    shl     eax, 4
    or      eax, r8d
    mov     [r13], al
    add     r13, 1
    inc     rcx
    jmp     .quant4_loop

.quant4_store_last:
    mov     [r13], r8b
    add     r13, 1

.quant4_done:
    xor     eax, eax
    pop     r13
    pop     r12
    pop     rbx
    ret

; =============================================================================
; gradient_dequantize_4bit
; Dequantize 4-bit packed gradients back to double
; Input:  rdi = quantized (uint8_t*), rsi = output (double*), rdx = length
;         xmm0 = scale factor
; Output: rax = 0
; =============================================================================
gradient_dequantize_4bit:
    push    rbx
    push    r12
    push    r13

    mov     r12, rdi
    mov     r13, rsi
    mov     rbx, rdx

    movsd   xmm1, [broadcast_one + 0]
    mov     rax, 0x3FF0000000000000
    movq    xmm1, rax
    divsd   xmm1, xmm0
    movsd   xmm15, xmm1

    xor     rcx, rcx
    xor     r8, r8          ; byte index

.dequant4_loop:
    cmp     rcx, rbx
    jge     .dequant4_done

    movzx   eax, byte [r12 + r8]

    ; Low nibble
    mov     edx, eax
    and     edx, 0x0F
    ; Sign extend from 4 bits
    test    edx, 0x08
    jz      .dq4_pos1
    or      edx, 0xFFFFFFF0
.dq4_pos1:
    cvtsi2sd    xmm0, edx
    mulsd   xmm0, xmm15
    movsd   [r13 + rcx*8], xmm0
    inc     rcx

    cmp     rcx, rbx
    jge     .dequant4_done

    ; High nibble
    shr     eax, 4
    and     eax, 0x0F
    test    eax, 0x08
    jz      .dq4_pos2
    or      eax, 0xFFFFFFF0
.dq4_pos2:
    cvtsi2sd    xmm0, eax
    mulsd   xmm0, xmm15
    movsd   [r13 + rcx*8], xmm0
    inc     rcx

    inc     r8
    jmp     .dequant4_loop

.dequant4_done:
    xor     eax, eax
    pop     r13
    pop     r12
    pop     rbx
    ret

; =============================================================================
; gradient_compress_topk
; Full Top-K compression pipeline with error feedback
; Input:  rdi = gradient (double*), rsi = error_accum (double*)
;         rdx = length, rcx = K
;         r8  = output values (double*), r9 = output indices (uint32*)
; Output: rax = actual K selected
; =============================================================================
gradient_compress_topk:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    push    rbp

    mov     r12, rdi        ; gradient
    mov     r13, rsi        ; error accumulator
    mov     r14, rdx        ; length
    mov     r15, rcx        ; K
    mov     rbp, r8         ; output values
    ; r9 = output indices (save on stack)
    push    r9

    ; Step 1: Add error feedback to gradient
    ; grad_corrected = grad + error_accum
    xor     rbx, rbx
.add_error_loop:
    cmp     rbx, r14
    jge     .add_error_done
    movsd   xmm0, [r12 + rbx*8]
    addsd   xmm0, [r13 + rbx*8]
    movsd   [r12 + rbx*8], xmm0
    inc     rbx
    jmp     .add_error_loop
.add_error_done:

    ; Step 2: Select Top-K
    pop     r9
    mov     rdi, r12
    mov     rsi, r14
    mov     rdx, r15
    mov     rcx, rbp
    mov     r8, r9
    call    gradient_topk_select
    ; rax = actual K

    pop     rbp
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; =============================================================================
; gradient_decompress_topk
; Decompress sparse Top-K gradient back to dense
; Input:  rdi = sparse values (double*), rsi = sparse indices (uint32*)
;         rdx = K, rcx = output dense (double*), r8 = N (full length)
; Output: rax = 0
; =============================================================================
gradient_decompress_topk:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15

    mov     r12, rdi        ; sparse values
    mov     r13, rsi        ; sparse indices
    mov     r14, rdx        ; K
    mov     r15, rcx        ; output dense
    ; r8 = N

    ; Zero output dense vector without depending on the EWC module
    xor     rbx, rbx
.decomp_zero_loop:
    cmp     rbx, r8
    jge     .decomp_zero_done
    mov     qword [r15 + rbx*8], 0
    inc     rbx
    jmp     .decomp_zero_loop
.decomp_zero_done:

    ; Fill in sparse values
    xor     rbx, rbx
.decomp_loop:
    cmp     rbx, r14
    jge     .decomp_done

    mov     ecx, [r13 + rbx*4]     ; index
    cmp     rcx, r8                 ; validate index < N
    jae     .decomp_skip_store      ; skip invalid/out-of-range index
    movsd   xmm0, [r12 + rbx*8]     ; value
    movsd   [r15 + rcx*8], xmm0

.decomp_skip_store:
    inc     rbx
    jmp     .decomp_loop

.decomp_done:
    xor     eax, eax

    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; =============================================================================
; gradient_error_feedback_update
; Update error feedback: error = grad_corrected - grad_reconstructed
; Input:  rdi = original gradient (double*)
;         rsi = reconstructed gradient (double*)
;         rdx = error accumulator (double*)
;         rcx = length
; Output: rax = 0
; =============================================================================
gradient_error_feedback_update:
    push    rbx
    mov     rbx, rcx

.efb_loop:
    cmp     rbx, 8
    jl      .efb_scalar

    vmovdqu64   zmm0, [rdi]
    vmovdqu64   zmm1, [rsi]
    vsubpd      zmm2, zmm0, zmm1    ; error = original - reconstructed
    vmovdqu64   [rdx], zmm2

    add     rdi, 64
    add     rsi, 64
    add     rdx, 64
    sub     rbx, 8
    jmp     .efb_loop

.efb_scalar:
    test    rbx, rbx
    jz      .efb_done

    movsd   xmm0, [rdi]
    subsd   xmm0, [rsi]
    movsd   [rdx], xmm0

    add     rdi, 8
    add     rsi, 8
    add     rdx, 8
    dec     rbx
    jmp     .efb_scalar

.efb_done:
    xor     eax, eax
    pop     rbx
    ret

; =============================================================================
; gradient_error_feedback_apply
; Apply error feedback: grad_corrected = grad + error_accum
; Input:  rdi = gradient (double*), rsi = error (double*), rdx = output (double*)
;         rcx = length
; Output: rax = 0
; =============================================================================
gradient_error_feedback_apply:
    push    rbx
    mov     rbx, rcx

.efa_loop:
    cmp     rbx, 8
    jl      .efa_scalar

    vmovdqu64   zmm0, [rdi]
    vmovdqu64   zmm1, [rsi]
    vaddpd      zmm2, zmm0, zmm1
    vmovdqu64   [rdx], zmm2

    add     rdi, 64
    add     rsi, 64
    add     rdx, 64
    sub     rbx, 8
    jmp     .efa_loop

.efa_scalar:
    test    rbx, rbx
    jz      .efa_done

    movsd   xmm0, [rdi]
    addsd   xmm0, [rsi]
    movsd   [rdx], xmm0

    add     rdi, 8
    add     rsi, 8
    add     rdx, 8
    dec     rbx
    jmp     .efa_scalar

.efa_done:
    xor     eax, eax
    pop     rbx
    ret

; =============================================================================
; gradient_sign_compress
; Sign-based gradient compression (1-bit per gradient)
; Input:  rdi = gradient (double*), rsi = output bits (uint64*), rdx = length
; Output: rax = number of uint64 words written
; =============================================================================
gradient_sign_compress:
    push    rbx
    push    r12
    push    r13

    mov     r12, rdi
    mov     r13, rsi
    mov     rbx, rdx

    xor     rcx, rcx        ; bit position
    xor     r8, r8          ; current word
    xor     r9, r9          ; word count
    xor     r10, r10        ; input index

.sign_loop:
    cmp     r10, rbx
    jge     .sign_flush

    movsd   xmm0, [r12 + r10*8]
    xorpd   xmm1, xmm1
    ucomisd xmm0, xmm1
    jb      .sign_negative

    ; Positive: bit = 1
    mov     rax, 1
    shl     rax, cl
    or      r8, rax
    jmp     .sign_next

.sign_negative:
    ; Negative: bit = 0 (already 0)

.sign_next:
    inc     rcx
    inc     r10

    cmp     rcx, 64
    jl      .sign_loop

    ; Store word
    mov     [r13 + r9*8], r8
    inc     r9
    xor     r8, r8
    xor     rcx, rcx
    jmp     .sign_loop

.sign_flush:
    ; Store remaining bits
    test    rcx, rcx
    jz      .sign_done
    mov     [r13 + r9*8], r8
    inc     r9

.sign_done:
    mov     rax, r9

    pop     r13
    pop     r12
    pop     rbx
    ret

; =============================================================================
; gradient_sign_decompress
; Decompress sign-compressed gradients
; Input:  rdi = compressed bits (uint64*), rsi = output (double*), rdx = length
;         xmm0 = magnitude (all gradients get this magnitude with sign from bits)
; Output: rax = 0
; =============================================================================
gradient_sign_decompress:
    push    rbx
    push    r12
    push    r13

    mov     r12, rdi
    mov     r13, rsi
    mov     rbx, rdx
    movsd   xmm15, xmm0        ; magnitude

    ; Negative magnitude
    mov     rax, 0x8000000000000000
    movq    xmm14, rax
    xorpd   xmm14, xmm15       ; -magnitude

    xor     rcx, rcx        ; bit position
    xor     r8, r8          ; word index
    xor     r9, r9          ; output index

.decomp_sign_loop:
    cmp     r9, rbx
    jge     .decomp_sign_done

    ; Load word if needed
    test    rcx, rcx
    jnz     .decomp_sign_have_word
    mov     r10, [r12 + r8*8]
    inc     r8
.decomp_sign_have_word:

    ; Extract bit
    mov     rax, r10
    shr     rax, cl
    and     rax, 1

    test    rax, rax
    jz      .decomp_sign_neg

    movsd   [r13 + r9*8], xmm15
    jmp     .decomp_sign_next

.decomp_sign_neg:
    movsd   [r13 + r9*8], xmm14

.decomp_sign_next:
    inc     rcx
    and     rcx, 63
    inc     r9
    jmp     .decomp_sign_loop

.decomp_sign_done:
    xor     eax, eax
    pop     r13
    pop     r12
    pop     rbx
    ret

; =============================================================================
; gradient_apply_mask
; Apply binary mask to gradient (zero out masked elements)
; Input:  rdi = gradient (double*), rsi = mask (uint8_t*), rdx = output (double*)
;         rcx = length
; Output: rax = count of non-zero elements
; =============================================================================
gradient_apply_mask:
    push    rbx
    mov     rbx, rcx
    xor     rax, rax

.mask_loop:
    cmp     rbx, 0
    jle     .mask_done

    movzx   ecx, byte [rsi]
    test    ecx, ecx
    jz      .mask_zero

    movsd   xmm0, [rdi]
    movsd   [rdx], xmm0
    inc     rax
    jmp     .mask_next

.mask_zero:
    mov     qword [rdx], 0

.mask_next:
    add     rdi, 8
    add     rsi, 1
    add     rdx, 8
    dec     rbx
    jmp     .mask_loop

.mask_done:
    pop     rbx
    ret

; =============================================================================
; gradient_compute_sparsity
; Compute sparsity ratio of gradient vector
; Input:  rdi = gradient (double*), rsi = length, xmm0 = zero_threshold
; Output: xmm0 = sparsity ratio [0.0, 1.0]
; =============================================================================
gradient_compute_sparsity:
    push    rbx
    push    r12

    mov     r12, rdi
    mov     rbx, rsi
    movsd   xmm15, xmm0

    xor     rcx, rcx        ; zero count
    xor     r8, r8          ; index

.sparsity_loop:
    cmp     r8, rbx
    jge     .sparsity_done

    movsd   xmm0, [r12 + r8*8]
    andpd   xmm0, [abs_mask_double]
    ucomisd xmm0, xmm15
    ja      .sparsity_next

    inc     rcx

.sparsity_next:
    inc     r8
    jmp     .sparsity_loop

.sparsity_done:
    test    rbx, rbx
    jz      .sparsity_empty
    cvtsi2sd    xmm0, rcx
    cvtsi2sd    xmm1, rbx
    divsd   xmm0, xmm1      ; sparsity = zeros / total
    jmp     .sparsity_return
.sparsity_empty:
    xorpd   xmm0, xmm0
.sparsity_return:

    pop     r12
    pop     rbx
    ret

; =============================================================================
; gradient_pack_sparse
; Pack sparse (index, value) pairs into compact binary format
; Format: [uint32 count][uint32 idx0][double val0][uint32 idx1][double val1]...
; Input:  rdi = values (double*), rsi = indices (uint32*), rdx = K
;         rcx = output buffer (uint8*)
; Output: rax = bytes written
; =============================================================================
gradient_pack_sparse:
    push    rbx
    push    r12
    push    r13
    push    r14

    mov     r12, rdi        ; values
    mov     r13, rsi        ; indices
    mov     r14, rdx        ; K
    ; rcx = output buffer

    ; Write count
    mov     [rcx], r14d
    add     rcx, 4

    xor     rbx, rbx

.pack_loop:
    cmp     rbx, r14
    jge     .pack_done

    ; Write index (4 bytes)
    mov     eax, [r13 + rbx*4]
    mov     [rcx], eax
    add     rcx, 4

    ; Write value (8 bytes)
    mov     rax, [r12 + rbx*8]
    mov     [rcx], rax
    add     rcx, 8

    inc     rbx
    jmp     .pack_loop

.pack_done:
    ; Return bytes written: 4 + K*(4+8) = 4 + K*12
    mov     rax, r14
    imul    rax, 12
    add     rax, 4

    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; =============================================================================
; gradient_unpack_sparse
; Unpack sparse binary format back to (values, indices)
; Input:  rdi = packed buffer (uint8*), rsi = output values (double*)
;         rdx = output indices (uint32*), rcx = input length in bytes
;         r8  = output capacity (max number of elements)
; Output: rax = K (number of elements unpacked), or 0 on invalid packet
; =============================================================================
gradient_unpack_sparse:
    push    rbx
    push    r12
    push    r13

    mov     r12, rsi        ; output values
    mov     r13, rdx        ; output indices

    ; Validate minimum header size
    cmp     rcx, 4
    jb      .unpack_invalid

    ; Read count
    mov     eax, [rdi]
    mov     rbx, rax

    ; Validate count <= output capacity
    cmp     rbx, r8
    ja      .unpack_invalid

    ; Validate packet size: 4 + count*12 <= input_len
    mov     rax, rbx
    imul    rax, 12
    jc      .unpack_invalid
    add     rax, 4
    jc      .unpack_invalid
    cmp     rax, rcx
    ja      .unpack_invalid

    add     rdi, 4
    xor     rcx, rcx

.unpack_loop:
    cmp     rcx, rbx
    jge     .unpack_done

    ; Read index
    mov     eax, [rdi]
    mov     [r13 + rcx*4], eax
    add     rdi, 4

    ; Read value
    mov     rax, [rdi]
    mov     [r12 + rcx*8], rax
    add     rdi, 8

    inc     rcx
    jmp     .unpack_loop

.unpack_done:
    mov     rax, rbx
    jmp     .unpack_exit

.unpack_invalid:
    xor     rax, rax

.unpack_exit:
    pop     r13
    pop     r12
    pop     rbx
    ret

; =============================================================================
; gradient_magnitude_sort
; Sort gradient indices by magnitude (descending)
; Input:  rdi = magnitudes (double*), rsi = indices (uint32*), rdx = length
; Output: rax = 0 (indices sorted by descending magnitude)
; =============================================================================
gradient_magnitude_sort:
    push    rbx
    push    r12
    push    r13
    push    r14

    mov     r12, rdi        ; magnitudes
    mov     r13, rsi        ; indices
    mov     r14, rdx        ; length

    ; Initialize indices 0..N-1
    xor     rbx, rbx
.init_idx:
    cmp     rbx, r14
    jge     .sort_start
    mov     [r13 + rbx*4], ebx
    inc     rbx
    jmp     .init_idx

.sort_start:
    ; Insertion sort (simple, for small N; use bitonic for large N)
    mov     rbx, 1

.sort_outer:
    cmp     rbx, r14
    jge     .sort_done

    mov     ecx, [r13 + rbx*4]     ; key index
    movsd   xmm0, [r12 + rcx*8]   ; key magnitude

    mov     rdx, rbx
    dec     rdx

.sort_inner:
    cmp     rdx, 0
    jl      .sort_insert

    mov     eax, [r13 + rdx*4]
    movsd   xmm1, [r12 + rax*8]
    ucomisd xmm1, xmm0
    jae     .sort_insert

    ; Shift right
    mov     r8d, [r13 + rdx*4]
    mov     [r13 + rdx*4 + 4], r8d
    dec     rdx
    jmp     .sort_inner

.sort_insert:
    mov     [r13 + rdx*4 + 4], ecx

    inc     rbx
    jmp     .sort_outer

.sort_done:
    xor     eax, eax

    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; =============================================================================
; gradient_random_sparsify
; Randomly sparsify gradient (keep each element with probability p)
; Input:  rdi = gradient (double*), rsi = output (double*), rdx = length
;         xmm0 = keep_probability [0.0, 1.0], rcx = random_seed
; Output: rax = count kept
; =============================================================================
gradient_random_sparsify:
    push    rbx
    push    r12
    push    r13
    push    r14

    mov     r12, rdi
    mov     r13, rsi
    mov     r14, rdx
    movsd   xmm15, xmm0
    mov     rbx, rcx        ; seed

    xor     rax, rax        ; count kept
    xor     rcx, rcx        ; index

.random_loop:
    cmp     rcx, r14
    jge     .random_done

    ; LCG random: seed = seed * 6364136223846793005 + 1442695040888963407
    mov     r10, 0x5851F42D4C957F2D
    imul    rbx, r10
    mov     r10, 0x14057B7EF767814F
    add     rbx, r10

    ; Convert to [0.0, 1.0)
    mov     rdx, rbx
    shr     rdx, 11
    or      rdx, 0x3FF0000000000000  ; set exponent to 1023
    movq    xmm0, rdx
    subsd   xmm0, [broadcast_one + 0]
    ; xmm0 is already normalized to [0.0, 1.0); no second subtraction is needed
    ; xmm0 now in [0.0, 1.0) approximately

    ; Compare with keep_probability
    ucomisd xmm0, xmm15
    ja      .random_zero

    ; Keep this gradient
    movsd   xmm1, [r12 + rcx*8]
    movsd   [r13 + rcx*8], xmm1
    inc     rax
    jmp     .random_next

.random_zero:
    mov     qword [r13 + rcx*8], 0

.random_next:
    inc     rcx
    jmp     .random_loop

.random_done:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; =============================================================================
; gradient_compression_stats
; Return compression statistics
; Input:  rdi = pointer to stats struct
; Output: rax = 0
; =============================================================================
gradient_compression_stats:
    mov     rax, [total_gradients_in]
    mov     [rdi], rax
    mov     rax, [total_gradients_out]
    mov     [rdi + 8], rax
    mov     rax, [total_bytes_saved]
    mov     [rdi + 16], rax
    movsd   xmm0, [compression_ratio]
    movsd   [rdi + 24], xmm0
    xor     eax, eax
    ret

; Placeholder reference to avoid linker error
broadcast_one:
    dq 0x3FF0000000000000
    times 7 dq 0x3FF0000000000000
