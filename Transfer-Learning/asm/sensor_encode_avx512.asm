; =============================================================================
; sensor_encode_avx512.asm
; AVX-512 accelerated SafaSensor 5K data encoding pipeline
; Converts raw ADC samples to 512-bit Hamming-compatible binary hashes
; Target: x86-64 with AVX-512BW, AVX-512DQ, AVX-512F
; Assembler: NASM 2.15+
; =============================================================================

BITS 64

; =============================================================================
; SECTION: .data
; =============================================================================
SECTION .data ALIGN=64

; Quantization thresholds for ADC → binary encoding
; 16 thresholds broadcast across ZMM for SIMD comparison
align 64
quant_thresholds:
    dq 1000, 2000, 3000, 4000, 5000, 6000, 7000, 8000
    dq 9000, 10000, 11000, 12000, 13000, 14000, 15000, 16000
    dq 17000, 18000, 19000, 20000, 21000, 22000, 23000, 24000
    dq 25000, 26000, 27000, 28000, 29000, 30000, 31000, 32000
    dq 33000, 34000, 35000, 36000, 37000, 38000, 39000, 40000
    dq 41000, 42000, 43000, 44000, 45000, 46000, 47000, 48000
    dq 49000, 50000, 51000, 52000, 53000, 54000, 55000, 56000
    dq 57000, 58000, 59000, 60000, 61000, 62000, 63000, 65535

; Phase encoding constants
align 64
phase_scale:
    times 8 dq 0x3FF0000000000000   ; 1.0 in IEEE 754 double

; Coherence threshold (0.5 as IEEE 754 double)
align 8
coherence_threshold:
    dq 0x3FE0000000000000

; Pi constant for phase normalization
align 8
pi_constant:
    dq 0x400921FB54442D18

; Two-Pi constant
align 8
two_pi:
    dq 0x401921FB54442D18

; Sensor ID multiplier for hash mixing
align 8
sensor_id_mult:
    dq 0x9E3779B97F4A7C15   ; Fibonacci hashing constant

; Timestamp mixing constant
align 8
timestamp_mix:
    dq 0x6C62272E07BB0142   ; FNV-1a prime

; Encoding version
align 4
encoding_version: dd 1

; Statistics
align 8
samples_encoded:    dq 0
encoding_errors:    dq 0
total_encode_ns:    dq 0

; =============================================================================
; SECTION: .bss
; =============================================================================
SECTION .bss ALIGN=64

; Temporary encoding workspace (512 bytes)
align 64
encode_workspace: resb 512

; Intermediate ADC buffer (8192 bytes = 1024 x uint64)
align 64
adc_buffer: resq 1024

; =============================================================================
; SECTION: .text
; =============================================================================
SECTION .text

global sensor_encode_sample
global sensor_encode_batch
global sensor_encode_coherence
global sensor_encode_phase
global sensor_encode_adc
global sensor_hash_mix
global sensor_normalize_phase
global sensor_quantize_adc
global sensor_pack_bits
global sensor_encode_full
global sensor_validate_sample
global sensor_get_encoding_stats
global sensor_reset_stats
global sensor_encode_differential
global sensor_encode_delta_batch

; =============================================================================
; sensor_encode_sample
; Encode a single SafaSensor sample to 512-bit hash
; Input:  rdi = sensor_id (uint16)
;         rsi = coherence (double, in xmm0)
;         rdx = phase (double, in xmm1)
;         rcx = adc (uint32)
;         r8  = timestamp (uint64)
;         r9  = pointer to output hash (uint64*, 8 words = 64 bytes)
; Output: rax = 0 (success), -1 (invalid sample)
; =============================================================================
sensor_encode_sample:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15

    mov     r12, rdi        ; sensor_id
    movq    r13, xmm0       ; coherence bits
    movq    r14, xmm1       ; phase bits
    mov     r15, rcx        ; adc
    ; r8 = timestamp, r9 = output

    ; Validate coherence [0.0, 1.0]
    xorpd   xmm2, xmm2
    ucomisd xmm0, xmm2
    jb      .coherence_low
    movsd   xmm2, [phase_scale]
    ucomisd xmm0, xmm2
    ja      .coherence_low

    ; Encode coherence to 16-bit fixed point
    ; coherence_fixed = (uint16)(coherence * 65535.0)
    movsd   xmm2, xmm0
    mov     rax, 0x40EFFFE000000000  ; 65535.0 as double
    movq    xmm4, rax
    mulsd   xmm2, xmm4
    cvttsd2si   eax, xmm2
    and     eax, 0xFFFF
    mov     rbx, rax                ; coherence_fixed

    ; Encode phase to 16-bit fixed point
    ; phase_norm = phase / (2*pi), then to uint16
    movsd   xmm3, xmm1
    divsd   xmm3, [two_pi]
    mov     rax, 0x40EFFFE000000000
    movq    xmm4, rax
    mulsd   xmm3, xmm4
    cvttsd2si   eax, xmm3
    shl     rax, 16
    or      rbx, rax                ; pack coherence | (phase << 16)

    ; Encode ADC to 16-bit (top 16 bits of 32-bit ADC)
    mov     rax, r15
    shr     rax, 16
    and     rax, 0xFFFF
    shl     rax, 32
    or      rbx, rax

    ; Pack sensor_id into bits 48-63
    mov     rax, r12
    and     rax, 0xFFFF
    shl     rax, 48
    or      rbx, rax

    ; rbx now contains packed word 0 of the hash

    ; Mix with timestamp using FNV-1a style
    mov     rax, r8
    xor     rax, [timestamp_mix]
    imul    rax, [sensor_id_mult]
    xor     rax, rbx

    ; Store word 0
    mov     [r9], rax

    ; Generate remaining 7 words via hash chain
    mov     rcx, 1
.hash_chain:
    cmp     rcx, 8
    jge     .encode_done

    ; Mix previous word with index
    lea     rax, [rcx - 1]
    mov     rdx, [r9 + rax*8]
    xor     rdx, rcx
    imul    rdx, [sensor_id_mult]
    xor     rdx, r8
    ror     rdx, 17
    xor     rdx, r12
    imul    rdx, [timestamp_mix]

    mov     [r9 + rcx*8], rdx
    inc     rcx
    jmp     .hash_chain

.encode_done:
    inc     qword [samples_encoded]
    xor     eax, eax
    jmp     .done

.coherence_low:
    inc     qword [encoding_errors]
    mov     eax, -1

.done:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; =============================================================================
; sensor_encode_batch
; Encode a batch of sensor samples using AVX-512
; Input:  rdi = pointer to sensor_data array (struct SensorSample*)
;         rsi = count
;         rdx = pointer to output hash array (uint64*, count*8 words)
;         rcx = struct stride in bytes
; Output: rax = number of successfully encoded samples
; =============================================================================
sensor_encode_batch:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    push    rbp

    mov     r12, rdi        ; input array
    mov     r13, rsi        ; count
    mov     r14, rdx        ; output array
    mov     r15, rcx        ; stride

    xor     rbx, rbx        ; index
    xor     rbp, rbp        ; success count

.batch_encode_loop:
    cmp     rbx, r13
    jge     .batch_encode_done

    ; Load sample fields (assuming struct layout):
    ; offset 0:  sensor_id (uint16)
    ; offset 8:  coherence (double)
    ; offset 16: phase (double)
    ; offset 24: adc (uint32)
    ; offset 32: timestamp (uint64)

    mov     rax, rbx
    imul    rax, r15
    add     rax, r12        ; pointer to current sample

    movzx   rdi, word [rax]         ; sensor_id
    movsd   xmm0, [rax + 8]        ; coherence
    movsd   xmm1, [rax + 16]       ; phase
    mov     ecx, [rax + 24]        ; adc
    mov     r8, [rax + 32]         ; timestamp

    ; Compute output pointer
    mov     r9, rbx
    imul    r9, 64                  ; 8 words * 8 bytes
    add     r9, r14

    call    sensor_encode_sample

    test    eax, eax
    jnz     .batch_skip
    inc     rbp

.batch_skip:
    inc     rbx
    jmp     .batch_encode_loop

.batch_encode_done:
    mov     rax, rbp

    pop     rbp
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; =============================================================================
; sensor_encode_coherence
; Encode coherence value to 16-bit fixed point
; Input:  xmm0 = coherence (double, [0.0, 1.0])
; Output: rax = encoded value (uint16)
; =============================================================================
sensor_encode_coherence:
    ; Clamp to [0.0, 1.0]
    xorpd   xmm1, xmm1
    maxsd   xmm0, xmm1
    movsd   xmm2, [phase_scale]
    minsd   xmm0, xmm2

    ; Scale to [0, 65535]
    mov     rax, 0x40EFFFE000000000  ; 65535.0 as double
    movq    xmm3, rax
    mulsd   xmm0, xmm3
    cvttsd2si   eax, xmm0
    and     eax, 0xFFFF
    ret

; =============================================================================
; sensor_encode_phase
; Encode phase value to 16-bit fixed point (normalized by 2*pi)
; Input:  xmm0 = phase (double, radians)
; Output: rax = encoded value (uint16)
; =============================================================================
sensor_encode_phase:
    ; Normalize by 2*pi
    divsd   xmm0, [two_pi]

    ; Take fractional part (fmod 1.0)
    movsd   xmm1, xmm0
    cvttsd2si   rax, xmm1
    cvtsi2sd    xmm2, rax
    subsd   xmm0, xmm2

    ; Ensure positive
    xorpd   xmm3, xmm3
    maxsd   xmm0, xmm3

    ; Scale to [0, 65535]
    mov     rax, 0x40EFFFE000000000
    movq    xmm4, rax
    mulsd   xmm0, xmm4
    cvttsd2si   eax, xmm0
    and     eax, 0xFFFF
    ret

; =============================================================================
; sensor_encode_adc
; Encode 32-bit ADC value to 16-bit via top-bit extraction
; Input:  rdi = adc (uint32)
; Output: rax = encoded value (uint16)
; =============================================================================
sensor_encode_adc:
    mov     rax, rdi
    shr     rax, 16
    and     rax, 0xFFFF
    ret

; =============================================================================
; sensor_hash_mix
; Mix two 64-bit values using multiply-xor-rotate
; Input:  rdi = value A
;         rsi = value B
; Output: rax = mixed hash
; =============================================================================
sensor_hash_mix:
    mov     rax, rdi
    xor     rax, rsi
    imul    rax, [sensor_id_mult]
    ror     rax, 31
    xor     rax, rsi
    imul    rax, [timestamp_mix]
    ror     rax, 27
    ret

; =============================================================================
; sensor_normalize_phase
; Normalize phase to [0, 2*pi)
; Input:  xmm0 = phase (double)
; Output: xmm0 = normalized phase
; =============================================================================
sensor_normalize_phase:
    ; Compute phase mod 2*pi
    movsd   xmm1, [two_pi]
    divsd   xmm0, xmm1
    cvttsd2si   rax, xmm0
    cvtsi2sd    xmm2, rax
    subsd   xmm0, xmm2
    mulsd   xmm0, xmm1

    xorpd   xmm3, xmm3
    comisd  xmm0, xmm3
    jae     .phase_nonnegative
    addsd   xmm0, xmm1
.phase_nonnegative:
    ret

; =============================================================================
; sensor_quantize_adc
; Quantize ADC value to N-bit binary code using AVX-512 threshold comparison
; Input:  rdi = adc (uint32)
;         rsi = N (number of bits, must be <= 64)
;         rdx = pointer to threshold array (uint64*, N thresholds)
; Output: rax = N-bit binary code
; =============================================================================
sensor_quantize_adc:
    push    rbx
    push    r12
    push    r13

    mov     r12, rdi        ; adc
    mov     r13, rsi        ; N bits
    ; rdx = threshold array

    xor     rax, rax        ; result code
    xor     rbx, rbx        ; bit index

.quantize_loop:
    cmp     rbx, r13
    jge     .quantize_done

    mov     rcx, [rdx + rbx*8]
    jb      .quantize_zero

    ; ADC >= threshold: set bit
    mov     rcx, 1
    shl     rcx, cl         ; 1 << rbx (using cl)
    ; Note: need to use rbx as shift count
    mov     r8, 1
    mov     rcx, rbx
    shl     r8, cl
    or      rax, r8
    jmp     .quantize_next

.quantize_zero:
    ; bit remains 0

.quantize_next:
    inc     rbx
    jmp     .quantize_loop

.quantize_done:
    pop     r13
    pop     r12
    pop     rbx
    ret

; =============================================================================
; sensor_pack_bits
; Pack multiple encoded fields into a 512-bit hash vector
; Input:  rdi = pointer to field array (uint64*, 8 fields)
;         rsi = pointer to output hash (uint64*, 8 words)
; Output: rax = 0 (success)
; =============================================================================
sensor_pack_bits:
    ; Load 8 fields
    vmovdqu64   zmm0, [rdi]

    ; Apply bit-mixing permutation
    ; Rotate each 64-bit word by its index
    ; Word 0: no rotation
    ; Word 1: rotate left 8
    ; Word 2: rotate left 16
    ; ... etc.

    ; Extract and rotate each word
    vpextrq     rax, xmm0, 0
    mov         [rsi], rax

    vpextrq     rax, xmm0, 1
    rol         rax, 8
    mov         [rsi + 8], rax

    vextracti128    xmm1, ymm0, 1
    vpextrq     rax, xmm1, 0
    rol         rax, 16
    mov         [rsi + 16], rax

    vpextrq     rax, xmm1, 1
    rol         rax, 24
    mov         [rsi + 24], rax

    vextracti64x4   ymm2, zmm0, 1
    vpextrq     rax, xmm2, 0
    rol         rax, 32
    mov         [rsi + 32], rax

    vpextrq     rax, xmm2, 1
    rol         rax, 40
    mov         [rsi + 40], rax

    vextracti128    xmm3, ymm2, 1
    vpextrq     rax, xmm3, 0
    rol         rax, 48
    mov         [rsi + 48], rax

    vpextrq     rax, xmm3, 1
    rol         rax, 56
    mov         [rsi + 56], rax

    xor     eax, eax
    ret

; =============================================================================
; sensor_encode_full
; Full pipeline: raw sensor data → 512-bit hash
; Input:  rdi = sensor_id (uint16)
;         rsi = pointer to raw ADC array (uint32*, 5000 samples)
;         rdx = pointer to coherence array (double*, 5000 samples)
;         rcx = pointer to phase array (double*, 5000 samples)
;         r8  = timestamp (uint64)
;         r9  = pointer to output hash (uint64*, 8 words)
; Output: rax = 0 (success)
; =============================================================================
sensor_encode_full:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    push    rbp

    mov     r12, rdi        ; sensor_id
    mov     r13, rsi        ; ADC array
    mov     r14, rdx        ; coherence array
    mov     r15, rcx        ; phase array
    ; r8 = timestamp, r9 = output

    ; Step 1: Compute mean ADC using AVX-512
    vpxorq      zmm16, zmm16, zmm16     ; accumulator
    xor         rbx, rbx
    mov         rbp, 5000

.adc_sum_loop:
    cmp     rbx, rbp
    jge     .adc_sum_done

    ; Load 8 uint32 ADC values, zero-extend to uint64
    ; (simplified: process one at a time for correctness)
    mov     eax, [r13 + rbx*4]
    add     qword [encode_workspace], rax

    inc     rbx
    jmp     .adc_sum_loop

.adc_sum_done:
    mov     rax, [encode_workspace]
    mov     rbx, 5000
    xor     rdx, rdx
    div     rbx                 ; mean ADC in rax

    ; Step 2: Compute mean coherence
    ; (simplified scalar computation)
    xorpd   xmm8, xmm8
    xor     rbx, rbx

.coh_sum_loop:
    cmp     rbx, 5000
    jge     .coh_sum_done
    addsd   xmm8, [r14 + rbx*8]
    inc     rbx
    jmp     .coh_sum_loop

.coh_sum_done:
    mov     rbx, 5000
    cvtsi2sd    xmm9, rbx
    divsd   xmm8, xmm9          ; mean coherence in xmm8

    ; Step 3: Compute mean phase
    xorpd   xmm10, xmm10
    xor     rbx, rbx

.phase_sum_loop:
    cmp     rbx, 5000
    jge     .phase_sum_done
    addsd   xmm10, [r15 + rbx*8]
    inc     rbx
    jmp     .phase_sum_loop

.phase_sum_done:
    divsd   xmm10, xmm9         ; mean phase in xmm10

    ; Step 4: Encode the aggregated sample
    mov     rdi, r12
    movsd   xmm0, xmm8
    movsd   xmm1, xmm10
    mov     ecx, eax            ; mean ADC
    mov     r8, r8              ; timestamp (already in r8)
    ; r9 = output (already in r9)

    call    sensor_encode_sample

    ; Clear workspace
    mov     qword [encode_workspace], 0

    pop     rbp
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; =============================================================================
; sensor_validate_sample
; Validate sensor sample fields
; Input:  rdi = sensor_id (uint16)
;         xmm0 = coherence (double)
;         xmm1 = phase (double)
;         rsi = adc (uint32)
;         rdx = timestamp (uint64)
; Output: rax = 0 (valid), bitmask of errors otherwise
; =============================================================================
sensor_validate_sample:
    xor     eax, eax

    ; Check sensor_id range [0, 4999]
    cmp     rdi, 5000
    jl      .id_ok
    or      eax, 0x01           ; bit 0: invalid sensor_id
.id_ok:

    ; Check coherence [0.0, 1.0]
    xorpd   xmm2, xmm2
    ucomisd xmm0, xmm2
    jb      .coh_invalid
    movsd   xmm3, [phase_scale]
    ucomisd xmm0, xmm3
    ja      .coh_invalid
    jmp     .coh_ok
.coh_invalid:
    or      eax, 0x02           ; bit 1: invalid coherence
.coh_ok:

    ; Check phase [0, 2*pi]
    xorpd   xmm4, xmm4
    ucomisd xmm1, xmm4
    jb      .phase_invalid
    movsd   xmm5, [two_pi]
    ucomisd xmm1, xmm5
    ja      .phase_invalid
    jmp     .phase_ok
.phase_invalid:
    or      eax, 0x04           ; bit 2: invalid phase
.phase_ok:

    ; Check ADC [0, 65535]
    cmp     rsi, 65536
    jl      .adc_ok
    or      eax, 0x08           ; bit 3: invalid ADC
.adc_ok:

    ; Check timestamp non-zero
    test    rdx, rdx
    jnz     .ts_ok
    or      eax, 0x10           ; bit 4: zero timestamp
.ts_ok:

    ret

; =============================================================================
; sensor_encode_differential
; Encode differential between two consecutive samples
; Input:  rdi = pointer to previous hash (uint64*, 8 words)
;         rsi = pointer to current hash (uint64*, 8 words)
;         rdx = pointer to output delta hash (uint64*, 8 words)
; Output: rax = Hamming distance between samples
; =============================================================================
sensor_encode_differential:
    vmovdqu64   zmm0, [rdi]
    vmovdqu64   zmm1, [rsi]
    vpxorq      zmm2, zmm0, zmm1
    vmovdqu64   [rdx], zmm2

    ; Compute Hamming distance of delta
    vpopcntq    zmm3, zmm2
    vextracti64x4   ymm4, zmm3, 1
    vpaddq          ymm5, ymm4, ymm3
    vextracti128    xmm6, ymm5, 1
    vpaddq          xmm7, xmm6, xmm5
    vpextrq         rax, xmm7, 0
    vpextrq         rcx, xmm7, 1
    add             rax, rcx
    ret

; =============================================================================
; sensor_encode_delta_batch
; Encode differential batch: compute XOR deltas for consecutive pairs
; Input:  rdi = pointer to hash array (uint64*, N*8 words)
;         rsi = N (number of hashes)
;         rdx = pointer to output delta array (uint64*, (N-1)*8 words)
; Output: rax = N-1 (number of deltas computed)
; =============================================================================
sensor_encode_delta_batch:
    push    rbx
    push    r12
    push    r13
    push    r14

    mov     r12, rdi        ; hash array
    mov     r13, rsi        ; N
    mov     r14, rdx        ; output delta array

    xor     rbx, rbx        ; index

.delta_loop:
    lea     rax, [rbx + 1]
    cmp     rax, r13
    jge     .delta_done

    ; Load consecutive hashes
    mov     rdi, rbx
    imul    rdi, 64
    add     rdi, r12        ; pointer to hash[i]

    mov     rsi, rbx
    inc     rsi
    imul    rsi, 64
    add     rsi, r12        ; pointer to hash[i+1]

    mov     rdx, rbx
    imul    rdx, 64
    add     rdx, r14        ; pointer to delta[i]

    call    sensor_encode_differential

    inc     rbx
    jmp     .delta_loop

.delta_done:
    mov     rax, rbx

    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; =============================================================================
; sensor_get_encoding_stats
; Return encoding statistics
; Input:  rdi = pointer to stats struct {uint64 encoded, uint64 errors, uint64 ns}
; Output: rax = 0
; =============================================================================
sensor_get_encoding_stats:
    mov     rax, [samples_encoded]
    mov     [rdi], rax
    mov     rax, [encoding_errors]
    mov     [rdi + 8], rax
    mov     rax, [total_encode_ns]
    mov     [rdi + 16], rax
    xor     eax, eax
    ret

; =============================================================================
; sensor_reset_stats
; Reset all encoding statistics to zero
; =============================================================================
sensor_reset_stats:
    mov     qword [samples_encoded], 0
    mov     qword [encoding_errors], 0
    mov     qword [total_encode_ns], 0
    ret
