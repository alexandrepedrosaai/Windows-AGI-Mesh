; =============================================================================
; hamming_avx512.asm
; AVX-512 accelerated Hamming distance computation for SafaSensor 5K pipeline
; Target: x86-64 with AVX-512BW, AVX-512VPOPCNTDQ extensions
; Assembler: NASM 2.15+
; ABI: System V AMD64 (Linux) / Microsoft x64 (Windows)
; =============================================================================

BITS 64

; =============================================================================
; SECTION: .data — constants and lookup tables
; =============================================================================
SECTION .data ALIGN=64

; Popcount nibble lookup table (16 bytes, broadcast to ZMM)
align 64
popcount_nibble_lut:
    db 0, 1, 1, 2, 1, 2, 2, 3, 1, 2, 2, 3, 2, 3, 3, 4
    db 0, 1, 1, 2, 1, 2, 2, 3, 1, 2, 2, 3, 2, 3, 3, 4
    db 0, 1, 1, 2, 1, 2, 2, 3, 1, 2, 2, 3, 2, 3, 3, 4
    db 0, 1, 1, 2, 1, 2, 2, 3, 1, 2, 2, 3, 2, 3, 3, 4

; Low nibble mask (0x0F repeated 64 times)
align 64
low_nibble_mask:
    times 64 db 0x0F

; Zero vector for comparisons
align 64
zero_vector:
    times 64 db 0x00

; Threshold constants for adaptive clustering
align 8
default_threshold:   dq 24
min_threshold:       dq 4
max_threshold:       dq 64

; Performance counters
align 8
total_pairs_computed: dq 0
total_cycles_spent:   dq 0

; =============================================================================
; SECTION: .bss — uninitialized data
; =============================================================================
SECTION .bss ALIGN=64

; Temporary accumulation buffer (512 bytes = 64 uint64 accumulators)
align 64
hamming_accum: resq 64

; Batch result buffer (up to 1024 results)
align 64
batch_results: resq 1024

; =============================================================================
; SECTION: .text — executable code
; =============================================================================
SECTION .text

; Export symbols
global hamming_distance_u64
global hamming_distance_avx512
global hamming_batch_avx512
global hamming_matrix_avx512
global hamming_threshold_filter
global hamming_centroid_distance
global hamming_nearest_cluster
global hamming_novelty_score
global hamming_distance_u8_array
global hamming_popcount_zmm
global hamming_distance_512bit
global hamming_distance_1024bit
global hamming_distance_2048bit
global hamming_distance_4096bit
global hamming_simd_init
global hamming_simd_cleanup
global hamming_get_stats

; =============================================================================
; hamming_simd_init
; Initialize AVX-512 state, verify CPU features
; Input:  none
; Output: rax = 0 (success), -1 (AVX-512 not supported)
; =============================================================================
hamming_simd_init:
    push    rbx
    push    rcx
    push    rdx

    ; Check CPUID for AVX-512BW support
    mov     eax, 7
    xor     ecx, ecx
    cpuid

    ; Check bit 30 of EBX (AVX-512BW)
    bt      ebx, 30
    jnc     .no_avx512

    ; Check bit 14 of ECX (AVX-512VPOPCNTDQ)
    bt      ecx, 14
    jnc     .no_vpopcnt

    ; Zero all ZMM registers to avoid AVX-512 transition penalty
    vzeroall

    ; Initialize performance counters
    mov     qword [total_pairs_computed], 0
    mov     qword [total_cycles_spent], 0

    xor     eax, eax        ; return 0 = success
    jmp     .done

.no_avx512:
    mov     eax, -1
    jmp     .done

.no_vpopcnt:
    mov     eax, -2

.done:
    pop     rdx
    pop     rcx
    pop     rbx
    ret

; =============================================================================
; hamming_simd_cleanup
; Clean up AVX-512 state (zero registers to avoid transition penalty)
; =============================================================================
hamming_simd_cleanup:
    vzeroall
    ret

; =============================================================================
; hamming_distance_u64
; Compute Hamming distance between two 64-bit integers
; Input:  rdi = a (uint64), rsi = b (uint64)
; Output: rax = popcount(a XOR b)
; =============================================================================
hamming_distance_u64:
    xor     rdi, rsi        ; a XOR b
    popcnt  rax, rdi        ; popcount
    ret

; =============================================================================
; hamming_distance_avx512
; Compute Hamming distance between two 512-bit vectors (8 x uint64)
; Input:  rdi = pointer to vector A (64 bytes, aligned 64)
;         rsi = pointer to vector B (64 bytes, aligned 64)
; Output: rax = total Hamming distance (sum of popcounts)
; =============================================================================
hamming_distance_avx512:
    ; Load 512-bit vectors
    vmovdqa64   zmm0, [rdi]
    vmovdqa64   zmm1, [rsi]

    ; XOR the vectors
    vpxorq      zmm2, zmm0, zmm1

    ; Popcount each 64-bit lane using VPOPCNTQ
    vpopcntq    zmm3, zmm2

    ; Horizontal sum of 8 x uint64 popcounts
    ; Reduce zmm3 to scalar
    vextracti64x4   ymm4, zmm3, 1       ; upper 256 bits
    vpaddq          ymm5, ymm4, ymm3    ; add upper + lower 256
    vextracti128    xmm6, ymm5, 1       ; upper 128 bits
    vpaddq          xmm7, xmm6, xmm5   ; add upper + lower 128
    vpextrq         rax, xmm7, 0        ; extract low 64
    vpextrq         rcx, xmm7, 1        ; extract high 64
    add             rax, rcx            ; final sum

    ; Update performance counter
    inc     qword [total_pairs_computed]

    ret

; =============================================================================
; hamming_distance_512bit
; Alias for hamming_distance_avx512 with explicit naming
; =============================================================================
hamming_distance_512bit:
    jmp     hamming_distance_avx512

; =============================================================================
; hamming_distance_1024bit
; Compute Hamming distance between two 1024-bit vectors (16 x uint64)
; Input:  rdi = pointer to vector A (128 bytes, aligned 64)
;         rsi = pointer to vector B (128 bytes, aligned 64)
; Output: rax = total Hamming distance
; =============================================================================
hamming_distance_1024bit:
    ; Load first 512 bits
    vmovdqa64   zmm0, [rdi]
    vmovdqa64   zmm1, [rsi]
    vpxorq      zmm2, zmm0, zmm1
    vpopcntq    zmm3, zmm2

    ; Load second 512 bits
    vmovdqa64   zmm4, [rdi + 64]
    vmovdqa64   zmm5, [rsi + 64]
    vpxorq      zmm6, zmm4, zmm5
    vpopcntq    zmm7, zmm6

    ; Accumulate
    vpaddq      zmm8, zmm3, zmm7

    ; Horizontal sum
    vextracti64x4   ymm9, zmm8, 1
    vpaddq          ymm10, ymm9, ymm8
    vextracti128    xmm11, ymm10, 1
    vpaddq          xmm12, xmm11, xmm10
    vpextrq         rax, xmm12, 0
    vpextrq         rcx, xmm12, 1
    add             rax, rcx

    inc     qword [total_pairs_computed]
    ret

; =============================================================================
; hamming_distance_2048bit
; Compute Hamming distance between two 2048-bit vectors (32 x uint64)
; Input:  rdi = pointer to vector A (256 bytes, aligned 64)
;         rsi = pointer to vector B (256 bytes, aligned 64)
; Output: rax = total Hamming distance
; =============================================================================
hamming_distance_2048bit:
    vpxorq      zmm16, zmm16, zmm16     ; accumulator = 0

    ; Process 4 x 512-bit blocks
    %assign offset 0
    %rep 4
        vmovdqa64   zmm0, [rdi + offset]
        vmovdqa64   zmm1, [rsi + offset]
        vpxorq      zmm2, zmm0, zmm1
        vpopcntq    zmm3, zmm2
        vpaddq      zmm16, zmm16, zmm3
    %assign offset offset+64
    %endrep

    ; Horizontal sum of zmm16
    vextracti64x4   ymm0, zmm16, 1
    vpaddq          ymm1, ymm0, ymm16
    vextracti128    xmm2, ymm1, 1
    vpaddq          xmm3, xmm2, xmm1
    vpextrq         rax, xmm3, 0
    vpextrq         rcx, xmm3, 1
    add             rax, rcx

    inc     qword [total_pairs_computed]
    ret

; =============================================================================
; hamming_distance_4096bit
; Compute Hamming distance between two 4096-bit vectors (64 x uint64)
; This covers the full SafaSensor 5K hash vector
; Input:  rdi = pointer to vector A (512 bytes, aligned 64)
;         rsi = pointer to vector B (512 bytes, aligned 64)
; Output: rax = total Hamming distance
; =============================================================================
hamming_distance_4096bit:
    push    rbx
    push    r12
    push    r13

    vpxorq      zmm16, zmm16, zmm16     ; accumulator = 0
    mov         r12, rdi
    mov         r13, rsi
    mov         rbx, 8                  ; 8 x 512-bit blocks

.loop_4096:
    vmovdqa64   zmm0, [r12]
    vmovdqa64   zmm1, [r13]
    vpxorq      zmm2, zmm0, zmm1
    vpopcntq    zmm3, zmm2
    vpaddq      zmm16, zmm16, zmm3

    add         r12, 64
    add         r13, 64
    dec         rbx
    jnz         .loop_4096

    ; Horizontal sum
    vextracti64x4   ymm0, zmm16, 1
    vpaddq          ymm1, ymm0, ymm16
    vextracti128    xmm2, ymm1, 1
    vpaddq          xmm3, xmm2, xmm1
    vpextrq         rax, xmm3, 0
    vpextrq         rcx, xmm3, 1
    add             rax, rcx

    inc     qword [total_pairs_computed]

    pop     r13
    pop     r12
    pop     rbx
    ret

; =============================================================================
; hamming_batch_avx512
; Compute Hamming distances for a batch of vector pairs
; Input:  rdi = pointer to array of vector A pointers (uint64**)
;         rsi = pointer to array of vector B pointers (uint64**)
;         rdx = number of pairs (uint64)
;         rcx = vector length in uint64 words
;         r8  = pointer to output array (uint64*)
; Output: rax = number of pairs processed
; =============================================================================
hamming_batch_avx512:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    push    rbp

    mov     r12, rdi        ; array of A pointers
    mov     r13, rsi        ; array of B pointers
    mov     r14, rdx        ; pair count
    mov     r15, rcx        ; vector length
    mov     rbp, r8         ; output array

    xor     rbx, rbx        ; pair index

.batch_loop:
    cmp     rbx, r14
    jge     .batch_done

    ; Load pointers for this pair
    mov     rdi, [r12 + rbx*8]
    mov     rsi, [r13 + rbx*8]

    ; Dispatch based on vector length
    cmp     r15, 8
    je      .dispatch_512
    cmp     r15, 16
    je      .dispatch_1024
    cmp     r15, 32
    je      .dispatch_2048
    cmp     r15, 64
    je      .dispatch_4096

    ; Generic case: loop over 64-bit words
    xor     rax, rax
    xor     rcx, rcx
.generic_loop:
    cmp     rcx, r15
    jge     .generic_done
    mov     r8, [rdi + rcx*8]
    xor     r8, [rsi + rcx*8]
    popcnt  r9, r8
    add     rax, r9
    inc     rcx
    jmp     .generic_loop
.generic_done:
    jmp     .store_result

.dispatch_512:
    call    hamming_distance_avx512
    jmp     .store_result

.dispatch_1024:
    call    hamming_distance_1024bit
    jmp     .store_result

.dispatch_2048:
    call    hamming_distance_2048bit
    jmp     .store_result

.dispatch_4096:
    call    hamming_distance_4096bit

.store_result:
    mov     [rbp + rbx*8], rax
    inc     rbx
    jmp     .batch_loop

.batch_done:
    mov     rax, rbx        ; return count processed

    pop     rbp
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; =============================================================================
; hamming_matrix_avx512
; Compute full N×N Hamming distance matrix
; Input:  rdi = pointer to array of N vectors (uint64**)
;         rsi = N (number of vectors)
;         rdx = vector length in uint64 words
;         rcx = pointer to output matrix (uint64*, N×N row-major)
; Output: rax = N*N (total elements computed)
; =============================================================================
hamming_matrix_avx512:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    push    rbp

    mov     r12, rdi        ; vector array
    mov     r13, rsi        ; N
    mov     r14, rdx        ; vector length
    mov     r15, rcx        ; output matrix

    xor     rbx, rbx        ; row index i

.matrix_row:
    cmp     rbx, r13
    jge     .matrix_done

    xor     rbp, rbp        ; col index j

.matrix_col:
    cmp     rbp, r13
    jge     .matrix_next_row

    ; Compute distance between vector[i] and vector[j]
    mov     rdi, [r12 + rbx*8]
    mov     rsi, [r12 + rbp*8]

    ; Use the 512-bit version only for exactly 8 words
    cmp     r14, 8
    jne     .matrix_scalar

    call    hamming_distance_avx512
    jmp     .matrix_store

.matrix_scalar:
    xor     rax, rax
    xor     rcx, rcx
.matrix_scalar_loop:
    cmp     rcx, r14
    jge     .matrix_store
    mov     r8, [rdi + rcx*8]
    xor     r8, [rsi + rcx*8]
    popcnt  r9, r8
    add     rax, r9
    inc     rcx
    jmp     .matrix_scalar_loop

.matrix_store:
    ; Store at matrix[i*N + j]
    mov     rcx, rbx
    imul    rcx, r13
    add     rcx, rbp
    mov     [r15 + rcx*8], rax

    inc     rbp
    jmp     .matrix_col

.matrix_next_row:
    inc     rbx
    jmp     .matrix_row

.matrix_done:
    ; Return N*N
    mov     rax, r13
    imul    rax, r13

    pop     rbp
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; =============================================================================
; hamming_threshold_filter
; Filter a batch of distances against a threshold
; Input:  rdi = pointer to distance array (uint64*)
;         rsi = count
;         rdx = threshold
;         rcx = pointer to output index array (uint64*)
; Output: rax = number of distances below threshold
; =============================================================================
hamming_threshold_filter:
    push    rbx
    push    r12
    push    r13
    push    r14

    mov     r12, rdi        ; distance array
    mov     r13, rsi        ; count
    mov     r14, rdx        ; threshold
    ; rcx = output index array

    xor     rbx, rbx        ; input index
    xor     rax, rax        ; output count

.filter_loop:
    cmp     rbx, r13
    jge     .filter_done

    mov     r8, [r12 + rbx*8]
    cmp     r8, r14
    jge     .filter_skip

    ; Below threshold: store index
    mov     [rcx + rax*8], rbx
    inc     rax

.filter_skip:
    inc     rbx
    jmp     .filter_loop

.filter_done:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; =============================================================================
; hamming_centroid_distance
; Compute distance from a sample to a cluster centroid
; Input:  rdi = pointer to sample vector (uint64*, 8 words = 512 bits)
;         rsi = pointer to centroid vector (uint64*, 8 words = 512 bits)
; Output: rax = Hamming distance
; =============================================================================
hamming_centroid_distance:
    jmp     hamming_distance_avx512

; =============================================================================
; hamming_nearest_cluster
; Find the nearest cluster centroid for a sample
; Input:  rdi = pointer to sample vector (uint64*, 8 words)
;         rsi = pointer to centroid array (uint64**, N centroids)
;         rdx = N (number of clusters)
; Output: rax = index of nearest cluster
;         rdx = distance to nearest cluster
; =============================================================================
hamming_nearest_cluster:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15

    mov     r12, rdi        ; sample
    mov     r13, rsi        ; centroid array
    mov     r14, rdx        ; N clusters

    mov     r15, 0xFFFFFFFFFFFFFFFF  ; best distance = MAX
    xor     rbx, rbx                 ; best cluster index
    xor     r8, r8                   ; current index

.nearest_loop:
    cmp     r8, r14
    jge     .nearest_done

    ; Load centroid pointer
    mov     rsi, [r13 + r8*8]
    mov     rdi, r12

    call    hamming_distance_avx512

    jae     .nearest_next

    mov     r15, rax        ; update best distance
    mov     rbx, r8         ; update best index

.nearest_next:
    inc     r8
    jmp     .nearest_loop

.nearest_done:
    mov     rax, rbx        ; return best cluster index
    mov     rdx, r15        ; return best distance

    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; =============================================================================
; hamming_novelty_score
; Compute novelty score as min distance to all existing centroids
; Input:  rdi = pointer to sample vector (uint64*, 8 words)
;         rsi = pointer to centroid array (uint64**, N centroids)
;         rdx = N (number of clusters)
; Output: rax = novelty score (min Hamming distance, higher = more novel)
; =============================================================================
hamming_novelty_score:
    push    rbx
    push    r12
    push    r13
    push    r14

    mov     r12, rdi
    mov     r13, rsi
    mov     r14, rdx

    ; Call nearest cluster to get min distance
    call    hamming_nearest_cluster

    ; rax = cluster index, rdx = min distance
    ; Novelty = min distance (higher distance = more novel)
    mov     rax, rdx

    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; =============================================================================
; hamming_distance_u8_array
; Compute Hamming distance between two byte arrays using AVX-512 popcount
; Input:  rdi = pointer to array A (uint8_t*, must be multiple of 64 bytes)
;         rsi = pointer to array B (uint8_t*, must be multiple of 64 bytes)
;         rdx = length in bytes (multiple of 64)
; Output: rax = total Hamming distance (bit-level)
; =============================================================================
hamming_distance_u8_array:
    push    rbx
    push    r12
    push    r13

    mov     r12, rdi
    mov     r13, rsi
    mov     rbx, rdx        ; byte count

    ; Load nibble LUT into zmm31
    vmovdqa64   zmm31, [popcount_nibble_lut]

    ; Load low nibble mask into zmm30
    vmovdqa64   zmm30, [low_nibble_mask]

    vpxorq      zmm16, zmm16, zmm16     ; accumulator

.u8_loop:
    cmp     rbx, 64
    jl      .u8_done

    ; Load 64 bytes from each array
    vmovdqu8    zmm0, [r12]
    vmovdqu8    zmm1, [r13]

    ; XOR
    vpxorq      zmm2, zmm0, zmm1

    ; Popcount via nibble LUT
    ; Low nibbles
    vpandq      zmm3, zmm2, zmm30
    vpshufb     zmm4, zmm31, zmm3

    ; High nibbles
    vpsrlw      zmm5, zmm2, 4
    vpandq      zmm5, zmm5, zmm30
    vpshufb     zmm6, zmm31, zmm5

    ; Sum low + high nibble popcounts
    vpaddb      zmm7, zmm4, zmm6

    ; Accumulate byte-level popcounts into 64-bit accumulators
    ; Use VPSADBW against zero to sum bytes within 64-bit groups
    vpxorq      zmm8, zmm8, zmm8
    vpsadbw     zmm9, zmm7, zmm8
    vpaddq      zmm16, zmm16, zmm9

    add     r12, 64
    add     r13, 64
    sub     rbx, 64
    jmp     .u8_loop

.u8_done:
    ; Horizontal sum of zmm16
    vextracti64x4   ymm0, zmm16, 1
    vpaddq          ymm1, ymm0, ymm16
    vextracti128    xmm2, ymm1, 1
    vpaddq          xmm3, xmm2, xmm1
    vpextrq         rax, xmm3, 0
    vpextrq         rcx, xmm3, 1
    add             rax, rcx

    pop     r13
    pop     r12
    pop     rbx
    ret

; =============================================================================
; hamming_popcount_zmm
; Count total set bits in a 512-bit ZMM register
; Input:  zmm0 = input vector
; Output: rax = total popcount
; Note: Caller must load zmm0 before calling
; =============================================================================
hamming_popcount_zmm:
    vpopcntq    zmm1, zmm0

    ; Horizontal sum
    vextracti64x4   ymm2, zmm1, 1
    vpaddq          ymm3, ymm2, ymm1
    vextracti128    xmm4, ymm3, 1
    vpaddq          xmm5, xmm4, xmm3
    vpextrq         rax, xmm5, 0
    vpextrq         rcx, xmm5, 1
    add             rax, rcx
    ret

; =============================================================================
; hamming_get_stats
; Return performance statistics
; Input:  rdi = pointer to output struct {uint64 pairs, uint64 cycles}
; Output: rax = 0 (success)
; =============================================================================
hamming_get_stats:
    mov     rax, [total_pairs_computed]
    mov     [rdi], rax
    mov     rax, [total_cycles_spent]
    mov     [rdi + 8], rax
    xor     eax, eax
    ret

; =============================================================================
; SECTION: .note — build metadata
; =============================================================================
SECTION .note

db "Windows-AGI-Mesh hamming_avx512.asm", 0
db "AVX-512BW + VPOPCNTDQ implementation", 0
db "Version 1.0.0", 0
