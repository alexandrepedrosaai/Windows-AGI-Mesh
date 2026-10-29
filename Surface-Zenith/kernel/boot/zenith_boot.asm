; =============================================================================
; Surface Zenith OS — Microkernel Bootstrap (ARM64 Assembly)
; File: kernel/boot/zenith_boot.asm
;
; This is the first code executed when the Zenith microkernel starts.
; Responsibilities:
;   1. Set up the exception vector table
;   2. Initialize the stack pointer for each EL (Exception Level)
;   3. Configure the MMU (Memory Management Unit)
;   4. Set up the GIC (Generic Interrupt Controller)
;   5. Initialize the BSS segment
;   6. Jump to the Rust kernel entry point (zenith_kernel_main)

    .section .bss.boot, "aw", %nobits
    .align 12
    .global zenith_user_page_table_l0
zenith_user_page_table_l0:
    .skip 4096
;
; Target: AArch64 (ARM64), EL1 (Kernel mode)
; Assembler: GNU AS (gas) / LLVM integrated assembler
; =============================================================================

; -----------------------------------------------------------------------------
; Assembler directives
; -----------------------------------------------------------------------------
    .arch   armv8-a
    .section .text.boot, "ax", @progbits
    .global _start
    .global zenith_exception_vectors
    .global zenith_el1_stack_top
    .global zenith_el0_stack_top

; -----------------------------------------------------------------------------
; Constants
; -----------------------------------------------------------------------------
    .equ ZENITH_STACK_SIZE,         0x10000         ; 64 KB per-EL stack
    .equ ZENITH_EL1_STACK_BASE,     0xFFFF000000000000
    .equ ZENITH_EL0_STACK_BASE,     0x0000FFFF00000000
    .equ SCTLR_EL1_MMU_ENABLE,      (1 << 0)
    .equ SCTLR_EL1_CACHE_ENABLE,    (1 << 2)
    .equ SCTLR_EL1_ICACHE_ENABLE,   (1 << 12)
    .equ MAIR_DEVICE_nGnRnE,        0x00
    .equ MAIR_NORMAL_NC,            0x44
    .equ MAIR_NORMAL_WB,            0xFF
    .equ TCR_T0SZ,                  (64 - 48)       ; 48-bit VA space
    .equ TCR_T1SZ,                  (64 - 48)
    .equ TCR_TG0_4K,                (0 << 14)
    .equ TCR_TG1_4K,                (2 << 30)
    .equ TCR_IPS_48BIT,             (5 << 32)
    .equ GIC_DIST_BASE,             0x08000000
    .equ GIC_CPU_BASE,              0x08010000
    .equ GICD_CTLR,                 0x000
    .equ GICC_CTLR,                 0x000
    .equ GICC_PMR,                  0x004

; =============================================================================
; _start — Kernel entry point
; =============================================================================
_start:
    ; -------------------------------------------------------------------------
    ; Step 1: Disable all interrupts at EL1
    ; -------------------------------------------------------------------------
    msr     DAIFSet, #0xF           ; Mask Debug, SError, IRQ, FIQ

    ; -------------------------------------------------------------------------
    ; Step 2: Determine current exception level
    ; -------------------------------------------------------------------------
    mrs     x0, CurrentEL
    lsr     x0, x0, #2
    cmp     x0, #2                  ; Are we at EL2?
    b.eq    .Lfrom_el2
    cmp     x0, #1                  ; Are we at EL1?
    b.eq    .Lat_el1
    ; EL3 — drop to EL2 first
    b       .Lfrom_el3

; -----------------------------------------------------------------------------
; Drop from EL3 to EL2
; -----------------------------------------------------------------------------
.Lfrom_el3:
    mov     x0, #0x501              ; SCR_EL3: NS=1, HCE=1, RW=1 (AArch64)
    mov     x0, #0x3C9              ; SPSR_EL3: EL2h, all interrupts masked
    msr     SPSR_EL3, x0
    adr     x0, .Lfrom_el2
    msr     ELR_EL3, x0
    eret

; -----------------------------------------------------------------------------
; Drop from EL2 to EL1
; -----------------------------------------------------------------------------
.Lfrom_el2:
    ; Enable AArch64 at EL1
    mov     x0, #(1 << 31)         ; HCR_EL2.RW = 1 (EL1 is AArch64)
    msr     HCR_EL2, x0

    ; Configure SPSR for EL1h
    mov     x0, #0x3C5             ; EL1h, DAIF masked
    msr     SPSR_EL2, x0
    adr     x0, .Lat_el1
    msr     ELR_EL2, x0
    eret

; -----------------------------------------------------------------------------
; Running at EL1 — main kernel initialization
; -----------------------------------------------------------------------------
.Lat_el1:
    ; -------------------------------------------------------------------------
    ; Step 3: Set up EL1 stack pointer
    ; -------------------------------------------------------------------------
    adr     x0, zenith_el1_stack_top
    ldr     x0, [x0]
    mov     sp, x0

    ; -------------------------------------------------------------------------
    ; Step 4: Install exception vector table
    ; -------------------------------------------------------------------------
    adr     x0, zenith_exception_vectors
    msr     VBAR_EL1, x0
    isb

    ; -------------------------------------------------------------------------
    ; Step 5: Configure MAIR_EL1 (Memory Attribute Indirection Register)
    ; -------------------------------------------------------------------------
    ; Index 0: Device-nGnRnE (strongly ordered, non-cacheable)
    ; Index 1: Normal Non-Cacheable
    ; Index 2: Normal Write-Back Cacheable
    movz    x0, #MAIR_DEVICE_nGnRnE
    movk    x0, #MAIR_NORMAL_NC, lsl #8
    movk    x0, #MAIR_NORMAL_WB, lsl #16
    msr     MAIR_EL1, x0

    ; -------------------------------------------------------------------------
    ; Step 6: Configure TCR_EL1 (Translation Control Register)
    ; -------------------------------------------------------------------------
    mov     x0, #TCR_T0SZ
    orr     x0, x0, #(TCR_T1SZ  << 16)
    orr     x0, x0, #TCR_TG0_4K
    orr     x0, x0, #TCR_TG1_4K
    orr     x0, x0, #TCR_IPS_48BIT
    msr     TCR_EL1, x0
    isb

    ; -------------------------------------------------------------------------
    ; Step 7: Initialize BSS segment to zero (must happen before page table use)
    ; -------------------------------------------------------------------------
    adr     x0, __bss_start
    adr     x1, __bss_end
.Lbss_zero_loop:

    ; -------------------------------------------------------------------------
    ; Step 8: Load page table base addresses (separate user/kernel roots)
    ; -------------------------------------------------------------------------
    adr     x0, zenith_user_page_table_l0
    msr     TTBR0_EL1, x0          ; User space page table (empty/invalid at boot)
    adr     x0, zenith_page_table_l0
    msr     TTBR1_EL1, x0          ; Kernel space page table
    isb

    ; -------------------------------------------------------------------------
    ; Step 9: Enable MMU, D-cache, I-cache, and EL1 hardening controls
    ; -------------------------------------------------------------------------
    mrs     x0, SCTLR_EL1
    orr     x0, x0, #SCTLR_EL1_MMU_ENABLE
    orr     x0, x0, #SCTLR_EL1_CACHE_ENABLE
    orr     x0, x0, #SCTLR_EL1_ICACHE_ENABLE
    orr     x0, x0, #SCTLR_EL1_WXN
    orr     x0, x0, #SCTLR_EL1_SPAN
    msr     SCTLR_EL1, x0
    isb
    dsb     sy
    cmp     x0, x1
    b.ge    .Lbss_done
    str     xzr, [x0], #8
    b       .Lbss_zero_loop
.Lbss_done:

    ; -------------------------------------------------------------------------
    ; Step 10: Initialize GIC (Generic Interrupt Controller)
    ; -------------------------------------------------------------------------
    bl      zenith_gic_init

    ; -------------------------------------------------------------------------
    ; Step 11: Enable IRQ at EL1
    ; -------------------------------------------------------------------------
    msr     DAIFClr, #0x2           ; Unmask IRQ only (keep FIQ, SError masked)

    ; -------------------------------------------------------------------------
    ; Step 12: Jump to Rust kernel main
    ; -------------------------------------------------------------------------
    ; x0 = device tree blob address (passed by bootloader in x0)
    ; x1 = kernel load address
    adr     x1, _start
    bl      zenith_kernel_main

    ; Should never return — halt if it does
.Lhalt:
    wfe
    b       .Lhalt

; =============================================================================
; GIC Initialization
; =============================================================================
zenith_gic_init:
    ; Enable GIC Distributor
    mov     x0, #GIC_DIST_BASE
    mov     w1, #1
    str     w1, [x0, #GICD_CTLR]

    ; Set priority mask to allow all interrupts (lowest priority = 0xFF)
    mov     x0, #GIC_CPU_BASE
    mov     w1, #0xFF
    str     w1, [x0, #GICC_PMR]

    ; Enable GIC CPU interface
    mov     w1, #1
    str     w1, [x0, #GICC_CTLR]

    ret

; =============================================================================
; Exception Vector Table (aligned to 2KB boundary)
; =============================================================================
    .balign 0x800
zenith_exception_vectors:

    ; ---- Current EL with SP0 ------------------------------------------------
    .balign 0x80
    b       zenith_sync_sp0         ; Synchronous
    .balign 0x80
    b       zenith_irq_sp0          ; IRQ
    .balign 0x80
    b       zenith_fiq_sp0          ; FIQ
    .balign 0x80
    b       zenith_serror_sp0       ; SError

    ; ---- Current EL with SPx ------------------------------------------------
    .balign 0x80
    b       zenith_sync_spx         ; Synchronous
    .balign 0x80
    b       zenith_irq_spx          ; IRQ
    .balign 0x80
    b       zenith_fiq_spx          ; FIQ
    .balign 0x80
    b       zenith_serror_spx       ; SError

    ; ---- Lower EL (AArch64) -------------------------------------------------
    .balign 0x80
    b       zenith_sync_el0_64      ; Synchronous (syscall entry)
    .balign 0x80
    b       zenith_irq_el0_64       ; IRQ
    .balign 0x80
    b       zenith_fiq_el0_64       ; FIQ
    .balign 0x80
    b       zenith_serror_el0_64    ; SError

    ; ---- Lower EL (AArch32) -------------------------------------------------
    .balign 0x80
    b       zenith_sync_el0_32      ; Synchronous
    .balign 0x80
    b       zenith_irq_el0_32       ; IRQ
    .balign 0x80
    b       zenith_fiq_el0_32       ; FIQ
    .balign 0x80
    b       zenith_serror_el0_32    ; SError

; =============================================================================
; Exception Handler Stubs
; =============================================================================

; Macro: save all general-purpose registers to the stack
.macro SAVE_REGS
    sub     sp, sp, #(34 * 8)
    stp     x0,  x1,  [sp, #(0  * 8)]
    stp     x2,  x3,  [sp, #(2  * 8)]
    stp     x4,  x5,  [sp, #(4  * 8)]
    stp     x6,  x7,  [sp, #(6  * 8)]
    stp     x8,  x9,  [sp, #(8  * 8)]
    stp     x10, x11, [sp, #(10 * 8)]
    stp     x12, x13, [sp, #(12 * 8)]
    stp     x14, x15, [sp, #(14 * 8)]
    stp     x16, x17, [sp, #(16 * 8)]
    stp     x18, x19, [sp, #(18 * 8)]
    stp     x20, x21, [sp, #(20 * 8)]
    stp     x22, x23, [sp, #(22 * 8)]
    stp     x24, x25, [sp, #(24 * 8)]
    stp     x26, x27, [sp, #(26 * 8)]
    stp     x28, x29, [sp, #(28 * 8)]
    mrs     x0, ELR_EL1
    mrs     x1, SPSR_EL1
    stp     x30, x0,  [sp, #(30 * 8)]
    str     x1,       [sp, #(32 * 8)]
.endm

; Macro: restore all general-purpose registers from the stack
.macro RESTORE_REGS
    ldr     x1,       [sp, #(32 * 8)]
    ldp     x30, x0,  [sp, #(30 * 8)]
    msr     ELR_EL1, x0
    msr     SPSR_EL1, x1
    ldp     x28, x29, [sp, #(28 * 8)]
    ldp     x26, x27, [sp, #(26 * 8)]
    ldp     x24, x25, [sp, #(24 * 8)]
    ldp     x22, x23, [sp, #(22 * 8)]
    ldp     x20, x21, [sp, #(20 * 8)]
    ldp     x18, x19, [sp, #(18 * 8)]
    ldp     x16, x17, [sp, #(16 * 8)]
    ldp     x14, x15, [sp, #(14 * 8)]
    ldp     x12, x13, [sp, #(12 * 8)]
    ldp     x10, x11, [sp, #(10 * 8)]
    ldp     x8,  x9,  [sp, #(8  * 8)]
    ldp     x6,  x7,  [sp, #(6  * 8)]
    ldp     x4,  x5,  [sp, #(4  * 8)]
    ldp     x2,  x3,  [sp, #(2  * 8)]
    ldp     x0,  x1,  [sp, #(0  * 8)]
    add     sp, sp, #(34 * 8)
.endm

; -----------------------------------------------------------------------------
; Synchronous exception from EL0 (64-bit) — System Call entry
; -----------------------------------------------------------------------------
zenith_sync_el0_64:
    SAVE_REGS
    ; x8 = syscall number (Zenith ABI convention)
    ; x0–x7 = syscall arguments
    mov     x0, sp                  ; Pass register frame pointer
    bl      zenith_syscall_dispatch
    RESTORE_REGS
    eret

; -----------------------------------------------------------------------------
; IRQ from EL0 (64-bit)
; -----------------------------------------------------------------------------
zenith_irq_el0_64:
    SAVE_REGS
    bl      zenith_irq_handler
    RESTORE_REGS
    eret

; -----------------------------------------------------------------------------
; IRQ from current EL with SPx
; -----------------------------------------------------------------------------
zenith_irq_spx:
    SAVE_REGS
    bl      zenith_irq_handler
    RESTORE_REGS
    eret

; -----------------------------------------------------------------------------
; Synchronous exception from current EL with SPx (kernel fault)
; -----------------------------------------------------------------------------
zenith_sync_spx:
    SAVE_REGS
    mrs     x0, ESR_EL1            ; Exception Syndrome Register
    mrs     x1, FAR_EL1            ; Fault Address Register
    mov     x2, sp
    bl      zenith_kernel_fault
    ; If we return, attempt recovery
    RESTORE_REGS
    eret

; -----------------------------------------------------------------------------
; Stub handlers (branch to generic handler)
; -----------------------------------------------------------------------------
zenith_sync_sp0:
    b       zenith_unhandled_exception
zenith_irq_sp0:
    b       zenith_unhandled_exception
zenith_fiq_sp0:
    b       zenith_unhandled_exception
zenith_serror_sp0:
    b       zenith_unhandled_exception
zenith_fiq_spx:
    b       zenith_unhandled_exception
zenith_serror_spx:
    b       zenith_unhandled_exception
zenith_fiq_el0_64:
    b       zenith_unhandled_exception
zenith_serror_el0_64:
    b       zenith_unhandled_exception
zenith_sync_el0_32:
    b       zenith_unhandled_exception
zenith_irq_el0_32:
    b       zenith_unhandled_exception
zenith_fiq_el0_32:
    b       zenith_unhandled_exception
zenith_serror_el0_32:
    b       zenith_unhandled_exception

zenith_unhandled_exception:
    ; Save ESR and FAR for debugging
    mrs     x0, ESR_EL1
    mrs     x1, FAR_EL1
    mrs     x2, ELR_EL1
    ; Halt — unrecoverable
.Lunhandled_halt:
    wfe
    b       .Lunhandled_halt

; =============================================================================
; Data Section
; =============================================================================
    .section .data.boot, "aw", @progbits
    .balign 8

zenith_el1_stack_top:
.quad   zenith_el1_stack + ZENITH_STACK_SIZE

zenith_el0_stack_top:
    .quad   (ZENITH_EL0_STACK_BASE + ZENITH_STACK_SIZE)

; =============================================================================
; BSS Section — zeroed by boot code above
; =============================================================================
    .section .bss.boot, "aw", @nobits
    .balign 4096

__bss_start:

; Level 0 page table (512 entries × 8 bytes = 4 KB)
zenith_page_table_l0:
    .space  4096

; Level 1 page table
zenith_page_table_l1:
    .space  4096

; Level 2 page table
zenith_page_table_l2:
    .space  4096

; EL1 kernel stack (64 KB)
    .balign 4096
zenith_el1_stack:
    .space  ZENITH_STACK_SIZE

__bss_end:

; =============================================================================
; End of zenith_boot.asm
; =============================================================================
