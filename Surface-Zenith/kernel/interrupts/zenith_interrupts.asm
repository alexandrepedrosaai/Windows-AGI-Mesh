; =============================================================================
; Surface Zenith OS — Interrupt Controller (ARM64 Assembly)
; File: kernel/interrupts/zenith_interrupts.asm
;
; Implements:
;   - GIC-v3 initialization and configuration
;   - IRQ/FIQ handler entry points
;   - Timer interrupt setup (ARM Generic Timer)
;   - IPI (Inter-Processor Interrupt) for SMP scheduling
;   - Interrupt priority management
;   - Domain-aware interrupt routing
; =============================================================================

    .arch   armv8-a
    .section .text.interrupts, "ax", @progbits

; -----------------------------------------------------------------------------
; GIC-v3 Register Offsets (Distributor — GICD)
; -----------------------------------------------------------------------------
    .equ GICD_BASE,             0x08000000
    .equ GICD_CTLR,             0x0000    ; Distributor Control Register
    .equ GICD_TYPER,            0x0004    ; Interrupt Controller Type Register
    .equ GICD_IIDR,             0x0008    ; Distributor Implementer ID Register
    .equ GICD_IGROUPR0,         0x0080    ; Interrupt Group Registers
    .equ GICD_ISENABLER0,       0x0100    ; Interrupt Set-Enable Registers
    .equ GICD_ICENABLER0,       0x0180    ; Interrupt Clear-Enable Registers
    .equ GICD_ISPENDR0,         0x0200    ; Interrupt Set-Pending Registers
    .equ GICD_ICPENDR0,         0x0280    ; Interrupt Clear-Pending Registers
    .equ GICD_IPRIORITYR0,      0x0400    ; Interrupt Priority Registers
    .equ GICD_ITARGETSR0,       0x0800    ; Interrupt Processor Targets
    .equ GICD_ICFGR0,           0x0C00    ; Interrupt Configuration Registers
    .equ GICD_SGIR,             0x0F00    ; Software Generated Interrupt Register

; GIC-v3 Redistributor (GICR) — per-CPU
    .equ GICR_BASE,             0x080A0000
    .equ GICR_STRIDE,           0x20000   ; 128 KB per redistributor
    .equ GICR_CTLR,             0x0000
    .equ GICR_WAKER,            0x0014
    .equ GICR_IGROUPR0,         0x10080
    .equ GICR_ISENABLER0,       0x10100
    .equ GICR_IPRIORITYR0,      0x10400

; GIC-v3 CPU Interface (ICC system registers)
    ; Accessed via MSR/MRS to ICC_* system registers

; ARM Generic Timer
    .equ CNTV_CTL_ENABLE,       (1 << 0)
    .equ CNTV_CTL_IMASK,        (1 << 1)
    .equ CNTV_CTL_ISTATUS,      (1 << 2)
    .equ TIMER_IRQ,             27          ; Virtual timer PPI

; Interrupt priority levels
    .equ PRIORITY_HIGHEST,      0x00        ; Highest priority (security)
    .equ PRIORITY_REALTIME,     0x10        ; Real-time (audio, sensors)
    .equ PRIORITY_HIGH,         0x40        ; High (user-visible)
    .equ PRIORITY_NORMAL,       0x80        ; Normal
    .equ PRIORITY_LOW,          0xC0        ; Low (background)
    .equ PRIORITY_MASK_ALL,     0xFF        ; Allow all priorities

; IPI (Software Generated Interrupt) numbers
    .equ IPI_RESCHEDULE,        0           ; Trigger scheduler on remote CPU
    .equ IPI_MIGRATE_TASK,      1           ; Migrate task to this CPU
    .equ IPI_FLUSH_TLB,         2           ; TLB shootdown
    .equ IPI_STOP,              3           ; Stop CPU (for shutdown)
    .equ IPI_DOMAIN_NOTIFY,     4           ; Domain state change notification

; =============================================================================
; zenith_gic_v3_init — Initialize GIC-v3
;
; Must be called once on the boot CPU before enabling interrupts.
; =============================================================================
    .global zenith_gic_v3_init
    .type   zenith_gic_v3_init, @function
zenith_gic_v3_init:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    ; ---- Distributor initialization -----------------------------------------
    mov     x0, #GICD_BASE

    ; Disable distributor
    str     wzr, [x0, #GICD_CTLR]
    dsb     sy

    ; Read number of supported interrupts
    ldr     w1, [x0, #GICD_TYPER]
    and     w1, w1, #0x1F           ; ITLinesNumber field
    add     w1, w1, #1
    lsl     w1, w1, #5              ; Total interrupts = (ITLinesNumber+1) * 32

    ; Set all interrupts to Group 1 (non-secure)
    mov     w2, #0xFFFFFFFF
    mov     x3, x0
    add     x3, x3, #GICD_IGROUPR0
    mov     w4, w1
    lsr     w4, w4, #5              ; Number of 32-bit registers
.Lgic_group_loop:
    str     w2, [x3], #4
    subs    w4, w4, #1
    b.ne    .Lgic_group_loop

    ; Set all interrupt priorities to PRIORITY_NORMAL
    mov     w2, #PRIORITY_NORMAL
    orr     w2, w2, w2, lsl #8
    orr     w2, w2, w2, lsl #16    ; Fill all 4 bytes
    mov     x3, x0
    add     x3, x3, #GICD_IPRIORITYR0
    mov     w4, w1
    lsr     w4, w4, #2              ; 4 priorities per register
.Lgic_priority_loop:
    str     w2, [x3], #4
    subs    w4, w4, #1
    b.ne    .Lgic_priority_loop

    ; Disable all interrupts initially
    mov     w2, #0xFFFFFFFF
    mov     x3, x0
    add     x3, x3, #GICD_ICENABLER0
    mov     w4, w1
    lsr     w4, w4, #5
.Lgic_disable_loop:
    str     w2, [x3], #4
    subs    w4, w4, #1
    b.ne    .Lgic_disable_loop

    ; Enable distributor (Group 1 non-secure)
    mov     w2, #0x3                ; EnableGrp0 | EnableGrp1NS
    str     w2, [x0, #GICD_CTLR]
    dsb     sy

    ; ---- CPU Interface initialization (ICC system registers) ----------------
    ; Enable System Register Interface
    mrs     x0, S3_0_C12_C12_5     ; ICC_SRE_EL1
    orr     x0, x0, #1             ; SRE bit
    msr     S3_0_C12_C12_5, x0
    isb

    ; Set priority mask to allow all interrupts
    mov     x0, #PRIORITY_MASK_ALL
    msr     S3_0_C4_C6_0, x0       ; ICC_PMR_EL1
    isb

    ; Set binary point register (no preemption grouping)
    mov     x0, #7
    msr     S3_0_C12_C12_3, x0     ; ICC_BPR1_EL1
    isb

    ; Enable Group 1 interrupts
    mov     x0, #1
    msr     S3_0_C12_C12_7, x0     ; ICC_IGRPEN1_EL1
    isb

    ldp     x29, x30, [sp], #16
    ret

    .size   zenith_gic_v3_init, . - zenith_gic_v3_init

; =============================================================================
; zenith_gic_cpu_init — Per-CPU GIC redistributor initialization
;
; Must be called on each CPU during SMP bring-up.
; =============================================================================
    .global zenith_gic_cpu_init
    .type   zenith_gic_cpu_init, @function
zenith_gic_cpu_init:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    ; Get CPU ID
    mrs     x0, MPIDR_EL1
    and     x0, x0, #0xFF           ; Aff0 (CPU number within cluster)

    ; Calculate redistributor base for this CPU
    mov     x1, #GICR_BASE
    mov     x2, #GICR_STRIDE
    madd    x1, x0, x2, x1          ; GICR_BASE + cpu * GICR_STRIDE

    ; Wake up redistributor
    ldr     w2, [x1, #GICR_WAKER]
    bic     w2, w2, #(1 << 1)       ; Clear ProcessorSleep
    str     w2, [x1, #GICR_WAKER]

    ; Wait for ChildrenAsleep to clear
.Lgicr_wake_wait:
    ldr     w2, [x1, #GICR_WAKER]
    tst     w2, #(1 << 2)           ; ChildrenAsleep
    b.ne    .Lgicr_wake_wait

    ; Set SGIs and PPIs to Group 1
    mov     w2, #0xFFFFFFFF
    str     w2, [x1, #GICR_IGROUPR0]

    ; Enable timer PPI (IRQ 27)
    mov     w2, #(1 << TIMER_IRQ)
    str     w2, [x1, #GICR_ISENABLER0]

    ; Set timer priority to HIGH
    mov     w2, #PRIORITY_HIGH
    lsl     w3, w2, #24             ; Priority for IRQ 27 (byte 3 of register 6)
    mov     x4, x1
    add     x4, x4, #GICR_IPRIORITYR0
    add     x4, x4, #(TIMER_IRQ / 4 * 4)
    str     w3, [x4]

    dsb     sy

    ldp     x29, x30, [sp], #16
    ret

    .size   zenith_gic_cpu_init, . - zenith_gic_cpu_init

; =============================================================================
; zenith_irq_handler — Main IRQ handler (called from exception vector)
; =============================================================================
    .global zenith_irq_handler
    .type   zenith_irq_handler, @function
zenith_irq_handler:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

.Lirq_loop:
    ; Acknowledge interrupt — read IAR1 to get interrupt ID
    mrs     x0, S3_0_C12_C12_0     ; ICC_IAR1_EL1
    and     w1, w0, #0x3FF          ; Interrupt ID (bits [9:0])

    ; Check for spurious interrupt (ID = 1023)
    cmp     w1, #1023
    b.eq    .Lirq_done

    ; Check for spurious interrupt (ID = 1022)
    cmp     w1, #1022
    b.eq    .Lirq_eoi_and_loop

    ; ---- Dispatch by interrupt ID -------------------------------------------
    ; Timer interrupt (PPI 27)
    cmp     w1, #TIMER_IRQ
    b.eq    .Lirq_timer

    ; SGI 0–15 (IPIs)
    cmp     w1, #16
    b.lt    .Lirq_ipi

    ; SPI (Shared Peripheral Interrupt) — route to Rust handler
    b       .Lirq_spi

.Lirq_timer:
    ; Acknowledge EOI before calling handler (level-triggered)
    msr     S3_0_C12_C12_1, x0     ; ICC_EOIR1_EL1
    bl      zenith_timer_handler
    b       .Lirq_loop

.Lirq_ipi:
    ; Save IPI number, acknowledge EOI
    mov     x2, x1                  ; IPI number
    msr     S3_0_C12_C12_1, x0     ; ICC_EOIR1_EL1
    mov     x0, x2
    bl      zenith_ipi_handler
    b       .Lirq_loop

.Lirq_spi:
    ; Pass to Rust SPI handler
    mov     x2, x0                  ; full IAR value
    mov     x0, x1                  ; interrupt ID
    bl      zenith_spi_handler
    ; EOI
    msr     S3_0_C12_C12_1, x2     ; ICC_EOIR1_EL1
    b       .Lirq_loop

.Lirq_eoi_and_loop:
    msr     S3_0_C12_C12_1, x0
    b       .Lirq_loop

.Lirq_done:
    ldp     x29, x30, [sp], #16
    ret

    .size   zenith_irq_handler, . - zenith_irq_handler

; =============================================================================
; zenith_ipi_handler — Handle Inter-Processor Interrupts
;
; x0 = IPI number (SGI ID, 0–15)
; =============================================================================
    .global zenith_ipi_handler
    .type   zenith_ipi_handler, @function
zenith_ipi_handler:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    cmp     x0, #IPI_RESCHEDULE
    b.eq    .Lipi_reschedule

    cmp     x0, #IPI_MIGRATE_TASK
    b.eq    .Lipi_migrate

    cmp     x0, #IPI_FLUSH_TLB
    b.eq    .Lipi_flush_tlb

    cmp     x0, #IPI_STOP
    b.eq    .Lipi_stop

    cmp     x0, #IPI_DOMAIN_NOTIFY
    b.eq    .Lipi_domain_notify

    ; Unknown IPI — ignore
    b       .Lipi_done

.Lipi_reschedule:
    bl      zenith_kern_reschedule
    b       .Lipi_done

.Lipi_migrate:
    bl      zenith_kern_ipi_migrate
    b       .Lipi_done

.Lipi_flush_tlb:
    bl      zenith_tlb_flush_all
    b       .Lipi_done

.Lipi_stop:
    ; Disable interrupts and halt this CPU
    msr     DAIFSet, #0xF
.Lipi_stop_loop:
    wfe
    b       .Lipi_stop_loop

.Lipi_domain_notify:
    bl      zenith_kern_domain_notify
    b       .Lipi_done

.Lipi_done:
    ldp     x29, x30, [sp], #16
    ret

    .size   zenith_ipi_handler, . - zenith_ipi_handler

; =============================================================================
; zenith_send_ipi — Send an IPI to a specific CPU
;
; Prototype:
;   void zenith_send_ipi(uint32_t cpu_id, uint32_t ipi_num);
;
; x0 = target CPU ID (Aff0)
; x1 = IPI number (SGI ID, 0–15)
; =============================================================================
    .global zenith_send_ipi
    .type   zenith_send_ipi, @function
zenith_send_ipi:
    ; Build ICC_SGI1R_EL1 value:
    ; [23:16] = TargetList (bitmask of CPUs in cluster)
    ; [15:0]  = INTID (SGI number)
    ; [47:32] = Aff1 (cluster)
    and     x0, x0, #0xFF           ; CPU ID (Aff0)
    mov     x2, #1
    lsl     x2, x2, x0              ; TargetList bitmask
    lsl     x2, x2, #16
    and     x1, x1, #0xF            ; SGI ID
    orr     x2, x2, x1
    msr     S3_0_C12_C11_5, x2     ; ICC_SGI1R_EL1
    isb
    ret

    .size   zenith_send_ipi, . - zenith_send_ipi

; =============================================================================
; zenith_send_ipi_all — Broadcast IPI to all other CPUs
;
; Prototype:
;   void zenith_send_ipi_all(uint32_t ipi_num);
; =============================================================================
    .global zenith_send_ipi_all
    .type   zenith_send_ipi_all, @function
zenith_send_ipi_all:
    and     x0, x0, #0xF
    ; Set IRM bit (Interrupt Routing Mode) to broadcast to all except self
    orr     x0, x0, #(1 << 40)
    msr     S3_0_C12_C11_5, x0     ; ICC_SGI1R_EL1
    isb
    ret

    .size   zenith_send_ipi_all, . - zenith_send_ipi_all

; =============================================================================
; zenith_timer_init — Initialize ARM Generic Timer
;
; Sets up the virtual timer to fire at the scheduler period (10ms).
; =============================================================================
    .global zenith_timer_init
    .type   zenith_timer_init, @function
zenith_timer_init:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    ; Read timer frequency
    mrs     x0, CNTFRQ_EL0          ; Timer frequency in Hz

    ; Calculate ticks for 10ms (SCHEDULING_PERIOD_MS)
    mov     x1, #10
    mul     x0, x0, x1
    mov     x1, #1000
    udiv    x0, x0, x1              ; ticks = freq * 10 / 1000

    ; Set virtual timer compare value
    mrs     x1, CNTVCT_EL0          ; Current virtual count
    add     x0, x0, x1              ; Next fire time
    msr     CNTV_CVAL_EL0, x0      ; Set compare value

    ; Enable virtual timer, unmask interrupt
    mov     x0, #CNTV_CTL_ENABLE
    msr     CNTV_CTL_EL0, x0
    isb

    ldp     x29, x30, [sp], #16
    ret

    .size   zenith_timer_init, . - zenith_timer_init

; =============================================================================
; zenith_timer_handler — Timer interrupt handler
;
; Called every 10ms to trigger the Zenith Intent Scheduler.
; =============================================================================
    .global zenith_timer_handler
    .type   zenith_timer_handler, @function
zenith_timer_handler:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    ; Reprogram timer for next period
    mrs     x0, CNTFRQ_EL0
    mov     x1, #10
    mul     x0, x0, x1
    mov     x1, #1000
    udiv    x0, x0, x1              ; ticks per 10ms

    mrs     x1, CNTV_CVAL_EL0      ; Previous compare value
    add     x0, x0, x1              ; Next compare value
    msr     CNTV_CVAL_EL0, x0
    isb

    ; Call Rust scheduler tick
    bl      zenith_kern_scheduler_tick

    ldp     x29, x30, [sp], #16
    ret

    .size   zenith_timer_handler, . - zenith_timer_handler

; =============================================================================
; zenith_enable_irq / zenith_disable_irq — IRQ masking primitives
; =============================================================================
    .global zenith_enable_irq
zenith_enable_irq:
    msr     DAIFClr, #0x2           ; Unmask IRQ
    isb
    ret

    .global zenith_disable_irq
zenith_disable_irq:
    msr     DAIFSet, #0x2           ; Mask IRQ
    isb
    ret

    .global zenith_enable_fiq
zenith_enable_fiq:
    msr     DAIFClr, #0x1
    isb
    ret

    .global zenith_disable_fiq
zenith_disable_fiq:
    msr     DAIFSet, #0x1
    isb
    ret

    .global zenith_save_irq_flags
zenith_save_irq_flags:
    mrs     x0, DAIF
    ret

    .global zenith_restore_irq_flags
zenith_restore_irq_flags:
    msr     DAIF, x0
    isb
    ret

; =============================================================================
; zenith_gic_enable_irq — Enable a specific interrupt in the GIC distributor
;
; Prototype:
;   void zenith_gic_enable_irq(uint32_t irq_id);
; =============================================================================
    .global zenith_gic_enable_irq
    .type   zenith_gic_enable_irq, @function
zenith_gic_enable_irq:
    mov     x1, #GICD_BASE
    lsr     x2, x0, #5              ; Register index = irq / 32
    and     x3, x0, #0x1F           ; Bit index = irq % 32
    mov     w4, #1
    lsl     w4, w4, w3
    add     x2, x1, x2, lsl #2
    str     w4, [x2, #GICD_ISENABLER0]
    dsb     sy
    ret

    .size   zenith_gic_enable_irq, . - zenith_gic_enable_irq

; =============================================================================
; zenith_gic_disable_irq — Disable a specific interrupt
;
; Prototype:
;   void zenith_gic_disable_irq(uint32_t irq_id);
; =============================================================================
    .global zenith_gic_disable_irq
    .type   zenith_gic_disable_irq, @function
zenith_gic_disable_irq:
    mov     x1, #GICD_BASE
    lsr     x2, x0, #5
    and     x3, x0, #0x1F
    mov     w4, #1
    lsl     w4, w4, w3
    add     x2, x1, x2, lsl #2
    str     w4, [x2, #GICD_ICENABLER0]
    dsb     sy
    ret

    .size   zenith_gic_disable_irq, . - zenith_gic_disable_irq

; =============================================================================
; zenith_gic_set_priority — Set interrupt priority
;
; Prototype:
;   void zenith_gic_set_priority(uint32_t irq_id, uint8_t priority);
; =============================================================================
    .global zenith_gic_set_priority
    .type   zenith_gic_set_priority, @function
zenith_gic_set_priority:
    mov     x2, #GICD_BASE
    add     x2, x2, #GICD_IPRIORITYR0
    add     x2, x2, x0              ; byte offset = irq_id
    strb    w1, [x2]
    dsb     sy
    ret

    .size   zenith_gic_set_priority, . - zenith_gic_set_priority

; =============================================================================
; External Rust symbols
; =============================================================================
    .extern zenith_kern_reschedule
    .extern zenith_kern_ipi_migrate
    .extern zenith_kern_domain_notify
    .extern zenith_kern_scheduler_tick
    .extern zenith_spi_handler
    .extern zenith_tlb_flush_all

; =============================================================================
; End of zenith_interrupts.asm
; =============================================================================
