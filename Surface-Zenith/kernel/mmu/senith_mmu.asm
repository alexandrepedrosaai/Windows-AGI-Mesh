; =============================================================================
; Surface Zenith OS — Memory Management Unit (ARM64 Assembly)
; File: kernel/mmu/zenith_mmu.asm
;
; Implements:
;   - 4-level page table walk (L0→L1→L2→L3)
;   - TLB flush operations
;   - Memory barrier primitives
;   - Cache maintenance operations
;   - Physical/virtual address translation helpers
;   - Domain memory isolation enforcement
;   - Copy-on-Write page fault handler stub
;
; ARM64 MMU uses a 4KB granule with 48-bit virtual addresses.
; Page table entry format: [63:48]=upper attrs, [47:12]=OA, [11:2]=lower attrs
; =============================================================================

    .arch   armv8-a
    .section .text.mmu, "ax", @progbits

; -----------------------------------------------------------------------------
; Page table entry attribute constants
; -----------------------------------------------------------------------------
    .equ PTE_VALID,             (1 << 0)    ; Entry is valid
    .equ PTE_TABLE,             (1 << 1)    ; Points to next-level table
    .equ PTE_PAGE,              (1 << 1)    ; L3 page descriptor
    .equ PTE_AF,                (1 << 10)   ; Access Flag
    .equ PTE_SH_INNER,          (3 << 8)    ; Inner shareable
    .equ PTE_SH_OUTER,          (2 << 8)    ; Outer shareable
    .equ PTE_AP_RW_EL1,         (0 << 6)    ; EL1 R/W, EL0 no access
    .equ PTE_AP_RW_ALL,         (1 << 6)    ; EL1 R/W, EL0 R/W
    .equ PTE_AP_RO_EL1,         (2 << 6)    ; EL1 R/O, EL0 no access
    .equ PTE_AP_RO_ALL,         (3 << 6)    ; EL1 R/O, EL0 R/O
    .equ PTE_UXN,               (1 << 54)   ; Unprivileged Execute Never
    .equ PTE_PXN,               (1 << 53)   ; Privileged Execute Never
    .equ PTE_CONTIGUOUS,        (1 << 52)   ; Contiguous hint
    .equ PTE_DBM,               (1 << 51)   ; Dirty Bit Modifier
    .equ PTE_NG,                (1 << 11)   ; Not Global (ASID-tagged)
    .equ PTE_MAIR_DEVICE,       (0 << 2)    ; MAIR index 0 (device)
    .equ PTE_MAIR_NORMAL_NC,    (1 << 2)    ; MAIR index 1 (normal NC)
    .equ PTE_MAIR_NORMAL_WB,    (2 << 2)    ; MAIR index 2 (normal WB)

; Page size and mask
    .equ PAGE_SIZE,             0x1000      ; 4 KB
    .equ PAGE_MASK,             0xFFFFFFFFFFFFF000
    .equ PAGE_OFFSET_MASK,      0xFFF

; Level shift amounts
    .equ L0_SHIFT,              39
    .equ L1_SHIFT,              30
    .equ L2_SHIFT,              21
    .equ L3_SHIFT,              12
    .equ TABLE_INDEX_MASK,      0x1FF       ; 9-bit index

; CoW page flags (stored in software-defined bits [58:55])
    .equ PTE_COW,               (1 << 55)   ; Copy-on-Write page
    .equ PTE_SHARED,            (1 << 56)   ; Shared across domains
    .equ PTE_PINNED,            (1 << 57)   ; Pinned (not swappable)
    .equ PTE_DIRTY,             (1 << 58)   ; Software dirty bit

; =============================================================================
; zenith_mmu_map_page — Map a virtual address to a physical address
;
; Prototype:
;   int zenith_mmu_map_page(
;       uint64_t* pgd,      // x0: page global directory (L0 table)
;       uint64_t va,        // x1: virtual address (must be page-aligned)
;       uint64_t pa,        // x2: physical address (must be page-aligned)
;       uint64_t attrs      // x3: PTE attribute flags
;   );
;
; Returns: 0 on success, -1 on failure (e.g., allocation failure)
; =============================================================================
    .global zenith_mmu_map_page
    .type   zenith_mmu_map_page, @function
zenith_mmu_map_page:
    stp     x29, x30, [sp, #-64]!
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]
    mov     x29, sp

    mov     x19, x0             ; pgd
    mov     x20, x1             ; va
    mov     x21, x2             ; pa
    mov     x22, x3             ; attrs

    ; ---- L0 index -----------------------------------------------------------
    lsr     x23, x20, #L0_SHIFT
    and     x23, x23, #TABLE_INDEX_MASK
    lsl     x23, x23, #3       ; byte offset = index * 8
    add     x24, x19, x23      ; &pgd[l0_idx]

    ldr     x0, [x24]
    tst     x0, #PTE_VALID
    b.ne    .Lmap_l1_exists

    ; Allocate L1 table
    bl      zenith_alloc_page_table
    cbz     x0, .Lmap_fail
    orr     x0, x0, #(PTE_VALID | PTE_TABLE)
    str     x0, [x24]

.Lmap_l1_exists:
    ; Extract L1 table base address
    and     x19, x0, #PAGE_MASK

    ; ---- L1 index -----------------------------------------------------------
    lsr     x23, x20, #L1_SHIFT
    and     x23, x23, #TABLE_INDEX_MASK
    lsl     x23, x23, #3
    add     x24, x19, x23

    ldr     x0, [x24]
    tst     x0, #PTE_VALID
    b.ne    .Lmap_l2_exists

    ; Allocate L2 table
    bl      zenith_alloc_page_table
    cbz     x0, .Lmap_fail
    orr     x0, x0, #(PTE_VALID | PTE_TABLE)
    str     x0, [x24]

.Lmap_l2_exists:
    and     x19, x0, #PAGE_MASK

    ; ---- L2 index -----------------------------------------------------------
    lsr     x23, x20, #L2_SHIFT
    and     x23, x23, #TABLE_INDEX_MASK
    lsl     x23, x23, #3
    add     x24, x19, x23

    ldr     x0, [x24]
    tst     x0, #PTE_VALID
    b.ne    .Lmap_l3_exists

    ; Allocate L3 table
    bl      zenith_alloc_page_table
    cbz     x0, .Lmap_fail
    orr     x0, x0, #(PTE_VALID | PTE_TABLE)
    str     x0, [x24]

.Lmap_l3_exists:
    and     x19, x0, #PAGE_MASK

    ; ---- L3 index (leaf entry) ----------------------------------------------
    lsr     x23, x20, #L3_SHIFT
    and     x23, x23, #TABLE_INDEX_MASK
    lsl     x23, x23, #3
    add     x24, x19, x23

    ; Build L3 PTE: PA | attrs | PTE_VALID | PTE_PAGE | PTE_AF
    and     x21, x21, #PAGE_MASK
    orr     x0, x21, x22
    orr     x0, x0, #(PTE_VALID | PTE_PAGE | PTE_AF)
    str     x0, [x24]

    ; DSB to ensure page table write is visible before TLB use
    dsb     ishst
    mov     x0, x20
    bl      zenith_tlb_invalidate_va

    mov     x0, #0              ; success
    b       .Lmap_done

.Lmap_fail:
    mov     x0, #-1

.Lmap_done:
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #64
    ret

    .size   zenith_mmu_map_page, . - zenith_mmu_map_page

; =============================================================================
; zenith_mmu_unmap_page — Unmap a virtual address
;
; Prototype:
;   void zenith_mmu_unmap_page(uint64_t* pgd, uint64_t va);
; =============================================================================
    .global zenith_mmu_unmap_page
    .type   zenith_mmu_unmap_page, @function
zenith_mmu_unmap_page:
    stp     x29, x30, [sp, #-32]!
    stp     x19, x20, [sp, #16]
    mov     x29, sp

    mov     x19, x0             ; pgd
    mov     x20, x1             ; va

    ; Walk to L3 entry
    bl      zenith_mmu_walk_to_l3
    cbz     x0, .Lunmap_done

    ; Clear the PTE
    str     xzr, [x0]
    dsb     ishst

    ; Invalidate TLB entry for this VA
    mov     x0, x20
    bl      zenith_tlb_invalidate_va

.Lunmap_done:
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

    .size   zenith_mmu_unmap_page, . - zenith_mmu_unmap_page

; =============================================================================
; zenith_mmu_walk_to_l3 — Walk page tables to find L3 PTE address
;
; Prototype:
;   uint64_t* zenith_mmu_walk_to_l3(uint64_t* pgd, uint64_t va);
;
; Returns: pointer to L3 PTE, or NULL if not mapped
; =============================================================================
    .global zenith_mmu_walk_to_l3
    .type   zenith_mmu_walk_to_l3, @function
zenith_mmu_walk_to_l3:
    ; L0
    lsr     x2, x1, #L0_SHIFT
    and     x2, x2, #TABLE_INDEX_MASK
    ldr     x3, [x0, x2, lsl #3]
    tst     x3, #PTE_VALID
    b.eq    .Lwalk_not_found
    tst     x3, #PTE_TABLE
    b.eq    .Lwalk_not_found
    and     x0, x3, #PAGE_MASK

    ; L1
    lsr     x2, x1, #L1_SHIFT
    and     x2, x2, #TABLE_INDEX_MASK
    ldr     x3, [x0, x2, lsl #3]
    tst     x3, #PTE_VALID
    b.eq    .Lwalk_not_found
    tst     x3, #PTE_TABLE
    b.eq    .Lwalk_not_found
    and     x0, x3, #PAGE_MASK

    ; L2
    lsr     x2, x1, #L2_SHIFT
    and     x2, x2, #TABLE_INDEX_MASK
    ldr     x3, [x0, x2, lsl #3]
    tst     x3, #PTE_VALID
    b.eq    .Lwalk_not_found
    tst     x3, #PTE_TABLE
    b.eq    .Lwalk_not_found
    and     x0, x3, #PAGE_MASK

    ; L3 — return pointer to PTE
    lsr     x2, x1, #L3_SHIFT
    and     x2, x2, #TABLE_INDEX_MASK
    add     x0, x0, x2, lsl #3
    ldr     x3, [x0]
    tst     x3, #PTE_VALID
    b.eq    .Lwalk_not_found
    ret

.Lwalk_not_found:
    mov     x0, #0
    ret

    .size   zenith_mmu_walk_to_l3, . - zenith_mmu_walk_to_l3

; =============================================================================
; zenith_tlb_flush_all — Flush entire TLB (all ASIDs)
; =============================================================================
    .global zenith_tlb_flush_all
    .type   zenith_tlb_flush_all, @function
zenith_tlb_flush_all:
    dsb     ishst
    tlbi    vmalle1is           ; Invalidate all EL1 TLB entries (inner shareable)
    dsb     ish
    isb
    ret

    .size   zenith_tlb_flush_all, . - zenith_tlb_flush_all

; =============================================================================
; zenith_tlb_invalidate_va — Invalidate TLB entry for a specific VA
;
; Prototype:
;   void zenith_tlb_invalidate_va(uint64_t va);
; =============================================================================
    .global zenith_tlb_invalidate_va
    .type   zenith_tlb_invalidate_va, @function
zenith_tlb_invalidate_va:
    dsb     ishst
    lsr     x0, x0, #12        ; VA >> 12 for TLBI instruction
    tlbi    vaae1is, x0        ; Invalidate by VA, all ASIDs, EL1, inner shareable
    dsb     ish
    isb
    ret

    .size   zenith_tlb_invalidate_va, . - zenith_tlb_invalidate_va

; =============================================================================
; zenith_tlb_invalidate_asid — Invalidate all TLB entries for an ASID
;
; Prototype:
;   void zenith_tlb_invalidate_asid(uint64_t asid);
; =============================================================================
    .global zenith_tlb_invalidate_asid
    .type   zenith_tlb_invalidate_asid, @function
zenith_tlb_invalidate_asid:
    dsb     ishst
    lsl     x0, x0, #48        ; ASID in bits [63:48]
    tlbi    aside1is, x0
    dsb     ish
    isb
    ret

    .size   zenith_tlb_invalidate_asid, . - zenith_tlb_invalidate_asid

; =============================================================================
; zenith_cache_clean_range — Clean (write-back) D-cache for a VA range
;
; Prototype:
;   void zenith_cache_clean_range(uint64_t va_start, uint64_t va_end);
; =============================================================================
    .global zenith_cache_clean_range
    .type   zenith_cache_clean_range, @function
zenith_cache_clean_range:
    ; Get cache line size from CTR_EL0
    mrs     x2, CTR_EL0
    ubfx    x2, x2, #16, #4    ; DminLine field (log2 of cache line size in words)
    mov     x3, #4
    lsl     x3, x3, x2         ; cache line size in bytes

    ; Align start address down to cache line boundary
    sub     x4, x3, #1
    bic     x0, x0, x4

.Lcache_clean_loop:
    cmp     x0, x1
    b.ge    .Lcache_clean_done
    dc      cvac, x0            ; Clean by VA to PoC
    add     x0, x0, x3
    b       .Lcache_clean_loop

.Lcache_clean_done:
    dsb     sy
    ret

    .size   zenith_cache_clean_range, . - zenith_cache_clean_range

; =============================================================================
; zenith_cache_invalidate_range — Invalidate D-cache for a VA range
;
; Prototype:
;   void zenith_cache_invalidate_range(uint64_t va_start, uint64_t va_end);
; =============================================================================
    .global zenith_cache_invalidate_range
    .type   zenith_cache_invalidate_range, @function
zenith_cache_invalidate_range:
    mrs     x2, CTR_EL0
    ubfx    x2, x2, #16, #4
    mov     x3, #4
    lsl     x3, x3, x2
    sub     x4, x3, #1
    bic     x0, x0, x4

.Lcache_inv_loop:
    cmp     x0, x1
    b.ge    .Lcache_inv_done
    dc      ivac, x0            ; Invalidate by VA to PoC
    add     x0, x0, x3
    b       .Lcache_inv_loop

.Lcache_inv_done:
    dsb     sy
    ret

    .size   zenith_cache_invalidate_range, . - zenith_cache_invalidate_range

; =============================================================================
; zenith_cache_flush_range — Clean + Invalidate D-cache for a VA range
;
; Prototype:
;   void zenith_cache_flush_range(uint64_t va_start, uint64_t va_end);
; =============================================================================
    .global zenith_cache_flush_range
    .type   zenith_cache_flush_range, @function
zenith_cache_flush_range:
    mrs     x2, CTR_EL0
    ubfx    x2, x2, #16, #4
    mov     x3, #4
    lsl     x3, x3, x2
    sub     x4, x3, #1
    bic     x0, x0, x4

.Lcache_flush_loop:
    cmp     x0, x1
    b.ge    .Lcache_flush_done
    dc      civac, x0           ; Clean+Invalidate by VA to PoC
    add     x0, x0, x3
    b       .Lcache_flush_loop

.Lcache_flush_done:
    dsb     sy
    isb
    ret

    .size   zenith_cache_flush_range, . - zenith_cache_flush_range

; =============================================================================
; zenith_icache_invalidate_all — Invalidate entire I-cache
; =============================================================================
    .global zenith_icache_invalidate_all
    .type   zenith_icache_invalidate_all, @function
zenith_icache_invalidate_all:
    ic      iallu               ; Invalidate all I-cache to PoU
    dsb     nsh
    isb
    ret

    .size   zenith_icache_invalidate_all, . - zenith_icache_invalidate_all

; =============================================================================
; zenith_mmu_cow_fault — Copy-on-Write page fault handler
;
; Called when a write to a CoW page is detected (permission fault at EL1).
;
; Prototype:
;   int zenith_mmu_cow_fault(
;       uint64_t* pgd,      // x0: page table base
;       uint64_t va,        // x1: faulting virtual address
;       uint64_t domain_id  // x2: domain requesting write access
;   );
;
; Returns: 0 on success (new page allocated and mapped), -1 on failure
; =============================================================================
    .global zenith_mmu_cow_fault
    .type   zenith_mmu_cow_fault, @function
zenith_mmu_cow_fault:
    stp     x29, x30, [sp, #-48]!
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    mov     x29, sp

    mov     x19, x0             ; pgd
    mov     x20, x1             ; va
    mov     x21, x2             ; domain_id

    ; Walk to L3 PTE
    bl      zenith_mmu_walk_to_l3
    cbz     x0, .Lcow_fail
    mov     x22, x0             ; x22 = &pte

    ; Load current PTE
    ldr     x1, [x22]

    ; Check CoW flag
    tst     x1, #PTE_COW
    b.eq    .Lcow_not_cow       ; Not a CoW page — real fault

    ; Allocate a new physical page
    bl      zenith_alloc_physical_page
    cbz     x0, .Lcow_fail

    ; Copy old page content to new page
    ; x0 = new PA, x1 = old PTE (contains old PA)
    mov     x23, x0             ; preserve new PA across memcpy call
    and     x3, x1, #PAGE_MASK  ; old PA
    mov     x0, x3              ; src
    mov     x1, x23             ; dst
    mov     x2, #PAGE_SIZE
    bl      zenith_memcpy_page

    ; Build new PTE: new PA | old attrs | PTE_DIRTY, clear PTE_COW
    ldr     x1, [x22]           ; reload old PTE
    and     x1, x1, #~PAGE_MASK ; keep attribute bits
    bic     x1, x1, #PTE_COW    ; clear CoW flag
    orr     x1, x1, #PTE_DIRTY  ; set dirty
    orr     x1, x1, x23         ; OR in preserved new PA
    ; Re-add write permission (clear AP read-only bits)
    bic     x1, x1, #PTE_AP_RO_EL1
    orr     x1, x1, #PTE_AP_RW_EL1
    str     x1, [x22]

    ; Flush TLB for this VA
    dsb     ishst
    mov     x0, x20
    bl      zenith_tlb_invalidate_va

    ; Notify Rust kernel of CoW completion
    mov     x0, x20             ; va
    mov     x1, x21             ; domain_id
    bl      zenith_kern_cow_complete

    mov     x0, #0
    b       .Lcow_done

.Lcow_not_cow:
    ; Real permission fault — pass to Rust fault handler
    mov     x0, x20
    mov     x1, x21
    bl      zenith_kern_permission_fault
    b       .Lcow_done

.Lcow_fail:
    mov     x0, #-1

.Lcow_done:
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret

    .size   zenith_mmu_cow_fault, . - zenith_mmu_cow_fault

; =============================================================================
; zenith_memcpy_page — Copy one 4KB page
;
; Prototype:
;   void zenith_memcpy_page(uint64_t src, uint64_t dst, uint64_t size);
;
; Uses NEON/SVE for maximum throughput if available.
; Falls back to 64-bit word copy.
; =============================================================================
    .global zenith_memcpy_page
    .type   zenith_memcpy_page, @function
zenith_memcpy_page:
    ; Copy 4KB using 64-byte chunks (8 × 8-byte stores)
    mov     x3, #(PAGE_SIZE / 64)

.Lmemcpy_loop:
    ldp     x4,  x5,  [x0], #16
    ldp     x6,  x7,  [x0], #16
    ldp     x8,  x9,  [x0], #16
    ldp     x10, x11, [x0], #16
    stp     x4,  x5,  [x1], #16
    stp     x6,  x7,  [x1], #16
    stp     x8,  x9,  [x1], #16
    stp     x10, x11, [x1], #16
    subs    x3, x3, #1
    b.ne    .Lmemcpy_loop

    ret

    .size   zenith_memcpy_page, . - zenith_memcpy_page

; =============================================================================
; zenith_memset_page — Zero a 4KB page
;
; Prototype:
;   void zenith_memset_page(uint64_t pa);
; =============================================================================
    .global zenith_memset_page
    .type   zenith_memset_page, @function
zenith_memset_page:
    mov     x1, #(PAGE_SIZE / 64)

.Lmemset_loop:
    stp     xzr, xzr, [x0], #16
    stp     xzr, xzr, [x0], #16
    stp     xzr, xzr, [x0], #16
    stp     xzr, xzr, [x0], #16
    subs    x1, x1, #1
    b.ne    .Lmemset_loop

    ret

    .size   zenith_memset_page, . - zenith_memset_page

; =============================================================================
; Memory barrier primitives
; =============================================================================

    .global zenith_mb_full
zenith_mb_full:
    dsb     sy
    isb
    ret

    .global zenith_mb_read
zenith_mb_read:
    dsb     ld
    ret

    .global zenith_mb_write
zenith_mb_write:
    dsb     st
    ret

    .global zenith_mb_inner_shareable
zenith_mb_inner_shareable:
    dsb     ish
    isb
    ret

; =============================================================================
; Physical address translation (AT instruction)
;
; zenith_va_to_pa — Translate a virtual address to physical (EL1 read)
;
; Prototype:
;   uint64_t zenith_va_to_pa(uint64_t va);
;
; Returns: physical address, or ~0ULL on translation fault
; =============================================================================
    .global zenith_va_to_pa
    .type   zenith_va_to_pa, @function
zenith_va_to_pa:
    mov     x1, x0              ; Preserve VA offset
    at      s1e1r, x0           ; Translate VA using EL1 read permissions
    isb
    mrs     x0, PAR_EL1         ; Read Physical Address Register
    tst     x0, #1              ; Bit 0 = fault indicator
    b.ne    .Lva_to_pa_fault
    and     x0, x0, #PAGE_MASK  ; Extract PA (bits [47:12])
    and     x1, x1, #PAGE_OFFSET_MASK
    orr     x0, x0, x1
    ret

.Lva_to_pa_fault:
    mov     x0, #-1             ; Return ~0 on fault
    ret

    .size   zenith_va_to_pa, . - zenith_va_to_pa

; =============================================================================
; External symbols (implemented in Rust)
; =============================================================================
    .extern zenith_alloc_page_table
    .extern zenith_alloc_physical_page
    .extern zenith_kern_cow_complete
    .extern zenith_kern_permission_fault

; =============================================================================
; End of zenith_mmu.asm
; =============================================================================
