# =============================================================================
# Windows AGI Benchmark Lab — RISC-V 64-bit Assembly
# Copyright (c) 2026 Microsoft Corporation. All Rights Reserved.
# =============================================================================
# Target: RV64GC (RISC-V 64-bit, General + Compressed + Atomic + FP)
# Assembler: GNU as (riscv64-linux-gnu-as)
# Build:
#   riscv64-linux-gnu-as hello.s -o hello_riscv64.o
#   riscv64-linux-gnu-ld hello_riscv64.o -o hello_riscv64
# QEMU test:
#   qemu-riscv64 ./hello_riscv64
# =============================================================================
# RISC-V Register ABI:
#   x0  (zero) — hardwired zero
#   x1  (ra)   — return address
#   x2  (sp)   — stack pointer
#   x3  (gp)   — global pointer
#   x4  (tp)   — thread pointer
#   x5-x7  (t0-t2) — temporaries
#   x8  (s0/fp) — saved / frame pointer
#   x9  (s1)   — saved register
#   x10-x11 (a0-a1) — function args / return values
#   x12-x17 (a2-a7) — function arguments
#   x18-x27 (s2-s11) — saved registers
#   x28-x31 (t3-t6) — temporaries
# =============================================================================

.section .data

msg:
    .ascii "Windows AGI Benchmark Lab — RISC-V 64-bit\n"
    .equ msg_len, . - msg

banner:
    .ascii "Microsoft Corporation — Exclusive License\n"
    .equ banner_len, . - banner

arch_msg:
    .ascii "Architecture: RV64GC — RISC-V 64-bit General + Compressed\n"
    .equ arch_msg_len, . - arch_msg

isa_msg:
    .ascii "Extensions: I M A F D C Zicsr Zifencei\n"
    .equ isa_msg_len, . - isa_msg

.section .bss
    .align 8
    buf:    .skip 256
    .align 8
    result: .skip 64

.section .text
.global _start

# =============================================================================
# _start — Entry point
# =============================================================================
_start:
    # Print main message
    li      a7, 64              # sys_write
    li      a0, 1               # fd = stdout
    la      a1, msg             # buffer
    li      a2, msg_len         # length
    ecall

    # Print banner
    li      a7, 64
    li      a0, 1
    la      a1, banner
    li      a2, banner_len
    ecall

    # Print architecture info
    li      a7, 64
    li      a0, 1
    la      a1, arch_msg
    li      a2, arch_msg_len
    ecall

    # Print ISA extensions
    li      a7, 64
    li      a0, 1
    la      a1, isa_msg
    li      a2, isa_msg_len
    ecall

    # Run benchmarks
    call    bench_integer
    call    bench_memory
    call    bench_float
    call    bench_branch
    call    bench_atomic
    call    bench_multiply

    # Exit
    li      a7, 93              # sys_exit
    li      a0, 0               # exit code 0
    ecall


# =============================================================================
# bench_integer — Integer arithmetic benchmark
# RISC-V RV64I integer instructions
# =============================================================================
bench_integer:
    addi    sp, sp, -32
    sd      ra, 24(sp)
    sd      s0, 16(sp)
    sd      s1, 8(sp)
    sd      s2, 0(sp)

    li      t0, 1000000         # iteration count
    li      s0, 0x123456789ABCDEF0  # accumulator (seed)
    li      s1, 0xDEADBEEFCAFEBABE  # multiplier
    li      s2, 0x0123456789ABCDEF  # addend

bench_integer_loop:
    # Multiply-add chain (RV64M extension)
    mul     t1, s0, s1          # t1 = s0 * s1 (lower 64 bits)
    add     t1, t1, s2          # t1 += s2
    xor     s0, t1, s1          # s0 = t1 XOR s1

    # Rotate right by 7 (RISC-V has no native rotate, use shift+or)
    srli    t2, s0, 7
    slli    t3, s0, 57          # 64 - 7 = 57
    or      s0, t2, t3

    mul     t1, s1, s0
    add     t1, t1, s2
    xor     s1, t1, s0

    # Rotate right by 13
    srli    t2, s1, 13
    slli    t3, s1, 51          # 64 - 13 = 51
    or      s1, t2, t3

    # MULH: high 64 bits of 128-bit multiply
    mulh    t4, s0, s1          # signed high multiply
    mulhu   t5, s0, s1          # unsigned high multiply
    xor     s2, t4, t5

    addi    t0, t0, -1
    bnez    t0, bench_integer_loop

    ld      ra, 24(sp)
    ld      s0, 16(sp)
    ld      s1, 8(sp)
    ld      s2, 0(sp)
    addi    sp, sp, 32
    ret


# =============================================================================
# bench_memory — Memory access benchmark
# Tests load/store with various addressing modes
# =============================================================================
bench_memory:
    addi    sp, sp, -16
    sd      ra, 8(sp)
    sd      s0, 0(sp)

    la      s0, buf

    # Sequential 64-bit writes
    li      t0, 32              # 32 iterations
    li      t1, 0               # value
    mv      t2, s0              # pointer

bench_mem_write:
    sd      t1, 0(t2)           # store doubleword
    addi    t2, t2, 8           # advance pointer
    addi    t1, t1, 1
    addi    t0, t0, -1
    bnez    t0, bench_mem_write

    # Sequential 64-bit reads
    li      t0, 32
    mv      t2, s0
    li      t3, 0               # accumulator

bench_mem_read:
    ld      t1, 0(t2)           # load doubleword
    add     t3, t3, t1
    addi    t2, t2, 8
    addi    t0, t0, -1
    bnez    t0, bench_mem_read

    # 32-bit operations
    li      t0, 32
    mv      t2, s0
    li      t4, 0xDEADBEEF

bench_mem_word:
    sw      t4, 0(t2)           # store word
    lw      t5, 0(t2)           # load word (sign-extended)
    lwu     t6, 0(t2)           # load word (zero-extended)
    addi    t2, t2, 4
    addi    t0, t0, -1
    bnez    t0, bench_mem_word

    # 16-bit operations
    li      t0, 32
    mv      t2, s0
    li      t4, 0xABCD

bench_mem_half:
    sh      t4, 0(t2)           # store halfword
    lh      t5, 0(t2)           # load halfword (sign-extended)
    lhu     t6, 0(t2)           # load halfword (zero-extended)
    addi    t2, t2, 2
    addi    t0, t0, -1
    bnez    t0, bench_mem_half

    ld      ra, 8(sp)
    ld      s0, 0(sp)
    addi    sp, sp, 16
    ret


# =============================================================================
# bench_float — Floating point benchmark (RV64FD extension)
# Single and double precision operations
# =============================================================================
bench_float:
    addi    sp, sp, -16
    sd      ra, 8(sp)

    # Load float constants
    # RISC-V: use fmv.w.x to move integer to float register
    li      t0, 0x3F800000      # 1.0f in IEEE 754
    fmv.w.x f0, t0
    li      t0, 0x40000000      # 2.0f
    fmv.w.x f1, t0
    li      t0, 0x3F000000      # 0.5f
    fmv.w.x f2, t0
    li      t0, 0x40400000      # 3.0f
    fmv.w.x f3, t0

    li      t0, 500000

bench_float_sp_loop:
    # Single precision FMA: f0 = f0 * f1 + f2
    fmadd.s f0, f0, f1, f2
    fmadd.s f1, f1, f0, f3
    fmul.s  f2, f0, f1
    fadd.s  f3, f2, f0
    fsub.s  f0, f3, f1
    fdiv.s  f4, f0, f1          # division (slow)

    addi    t0, t0, -1
    bnez    t0, bench_float_sp_loop

    # Double precision
    # Load double constants
    li      t0, 0x3FF0000000000000  # 1.0 in IEEE 754 double
    fmv.d.x f8, t0
    li      t0, 0x4000000000000000  # 2.0
    fmv.d.x f9, t0
    li      t0, 0x3FE0000000000000  # 0.5
    fmv.d.x f10, t0

    li      t0, 500000

bench_float_dp_loop:
    # Double precision FMA
    fmadd.d f8, f8, f9, f10
    fmadd.d f9, f9, f8, f10
    fmul.d  f10, f8, f9
    fadd.d  f11, f10, f8

    addi    t0, t0, -1
    bnez    t0, bench_float_dp_loop

    ld      ra, 8(sp)
    addi    sp, sp, 16
    ret


# =============================================================================
# bench_branch — Branch prediction benchmark
# Tests various branch types in RISC-V
# =============================================================================
bench_branch:
    addi    sp, sp, -16
    sd      ra, 8(sp)

    li      t0, 1000000
    li      t1, 0               # even counter
    li      t2, 0               # odd counter

bench_branch_loop:
    # Test LSB (even/odd)
    andi    t3, t0, 1
    beqz    t3, bench_branch_even
    addi    t2, t2, 1
    j       bench_branch_next
bench_branch_even:
    addi    t1, t1, 1
bench_branch_next:

    # Comparison branches
    li      t3, 500000
    blt     t0, t3, bench_branch_lt
    addi    t1, t1, 1
    j       bench_branch_lt_end
bench_branch_lt:
    addi    t2, t2, 1
bench_branch_lt_end:

    addi    t0, t0, -1
    bnez    t0, bench_branch_loop

    ld      ra, 8(sp)
    addi    sp, sp, 16
    ret


# =============================================================================
# bench_atomic — Atomic operations (RV64A extension)
# Load-Reserved / Store-Conditional and AMO instructions
# =============================================================================
bench_atomic:
    addi    sp, sp, -32
    sd      ra, 24(sp)

    # Initialize atomic counter on stack
    li      t0, 0
    sd      t0, 0(sp)           # counter = 0

    li      t1, 100000

bench_atomic_loop:
    # Load-Reserved / Store-Conditional (LR/SC)
    la      t2, result
    lr.d    t3, (t2)            # load reserved doubleword
    addi    t3, t3, 1           # increment
    sc.d    t4, t3, (t2)        # store conditional
    bnez    t4, bench_atomic_loop  # retry if SC failed

    # Atomic Memory Operations (AMO)
    la      t2, result
    li      t3, 1
    amoadd.d t4, t3, (t2)       # atomic add, return old value
    amoswap.d t5, t3, (t2)      # atomic swap
    amoand.d t6, t3, (t2)       # atomic AND
    amoor.d  t4, t3, (t2)       # atomic OR
    amoxor.d t5, t3, (t2)       # atomic XOR
    amomax.d t6, t3, (t2)       # atomic max (signed)
    amomin.d t4, t3, (t2)       # atomic min (signed)

    addi    t1, t1, -1
    bnez    t1, bench_atomic_loop

    ld      ra, 24(sp)
    addi    sp, sp, 32
    ret


# =============================================================================
# bench_multiply — Extended multiply benchmark (RV64M)
# Tests all multiply/divide variants
# =============================================================================
bench_multiply:
    addi    sp, sp, -16
    sd      ra, 8(sp)

    li      t0, 500000
    li      s0, 0x123456789ABCDEF0
    li      s1, 0xFEDCBA9876543210

bench_multiply_loop:
    # 64-bit multiply (lower 64 bits)
    mul     t1, s0, s1

    # 64-bit multiply high (signed × signed)
    mulh    t2, s0, s1

    # 64-bit multiply high (unsigned × unsigned)
    mulhu   t3, s0, s1

    # 64-bit multiply high (signed × unsigned)
    mulhsu  t4, s0, s1

    # 32-bit multiply (sign-extended to 64)
    mulw    t5, s0, s1

    # 64-bit divide (signed)
    div     t6, s0, s1

    # 64-bit divide (unsigned)
    divu    t1, s0, s1

    # 64-bit remainder (signed)
    rem     t2, s0, s1

    # 64-bit remainder (unsigned)
    remu    t3, s0, s1

    # 32-bit divide
    divw    t4, s0, s1
    divuw   t5, s0, s1
    remw    t6, s0, s1
    remuw   t1, s0, s1

    # Update values
    xor     s0, t1, t2
    xor     s1, t3, t4

    addi    t0, t0, -1
    bnez    t0, bench_multiply_loop

    ld      ra, 8(sp)
    addi    sp, sp, 16
    ret


# =============================================================================
# bench_csr — Control and Status Register operations (Zicsr)
# Read performance counters
# =============================================================================
bench_csr:
    addi    sp, sp, -16
    sd      ra, 8(sp)

    # Read cycle counter
    csrr    t0, cycle           # read cycle CSR

    # Read instruction retired counter
    csrr    t1, instret

    # Read time CSR
    csrr    t2, time

    # Read cycle counter again to measure overhead
    csrr    t3, cycle
    sub     t4, t3, t0          # elapsed cycles

    ld      ra, 8(sp)
    addi    sp, sp, 16
    ret


# =============================================================================
# bench_fence — Memory fence benchmark (Zifencei)
# Tests fence instruction overhead
# =============================================================================
bench_fence:
    addi    sp, sp, -16
    sd      ra, 8(sp)

    li      t0, 10000

bench_fence_loop:
    # Memory fence (ordering)
    fence   rw, rw              # full fence

    # Instruction fence (for self-modifying code)
    fence.i

    addi    t0, t0, -1
    bnez    t0, bench_fence_loop

    ld      ra, 8(sp)
    addi    sp, sp, 16
    ret


# =============================================================================
# bench_compressed — RV64C Compressed instruction benchmark
# 16-bit compressed instructions for code density
# =============================================================================
bench_compressed:
    # Compressed instructions (C extension)
    # These are automatically selected by the assembler when possible

    li      t0, 100000
    li      t1, 0

bench_compressed_loop:
    # c.addi (compressed add immediate)
    addi    t1, t1, 1           # assembler may emit c.addi

    # c.add (compressed add)
    add     t2, t1, t0          # assembler may emit c.add

    # c.mv (compressed move)
    mv      t3, t2              # assembler may emit c.mv

    # c.li (compressed load immediate)
    li      t4, 42              # assembler may emit c.li

    addi    t0, t0, -1
    bnez    t0, bench_compressed_loop

    ret
