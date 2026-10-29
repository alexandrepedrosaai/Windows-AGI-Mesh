; =============================================================================
; Surface Zenith OS — System Call Table & Dispatcher (ARM64 Assembly)
; File: kernel/syscall/zenith_syscall.asm
;
; The Zenith syscall interface is the boundary between user-space domains
; (Android, Windows, AI) and the Zenith microkernel.
;
; Syscall convention (ARM64 / AArch64):
;   x8  = syscall number
;   x0–x7 = arguments (up to 8)
;   x0  = return value
;   SVC #0 = syscall entry
;
; Syscall categories:
;   0x000–0x0FF: POSIX-compatible (process, file, memory)
;   0x100–0x1FF: Zenith IPC (ZIB publish/subscribe)
;   0x200–0x2FF: Zenith Session & Identity
;   0x300–0x3FF: Zenith Memory Fabric (UMO operations)
;   0x400–0x4FF: Zenith Device Broker
;   0x500–0x5FF: Zenith AI/Inference
;   0x600–0x6FF: Zenith Quantum
;   0x700–0x7FF: Zenith Security & Capability
;   0x800–0x8FF: Zenith Scheduler & Migration
; =============================================================================

    .arch   armv8-a
    .section .text.syscall, "ax", @progbits

; -----------------------------------------------------------------------------
; Syscall number ranges
; -----------------------------------------------------------------------------
    .equ SYSCALL_POSIX_BASE,        0x000
    .equ SYSCALL_POSIX_MAX,         0x0FF
    .equ SYSCALL_ZIB_BASE,          0x100
    .equ SYSCALL_ZIB_MAX,           0x1FF
    .equ SYSCALL_SESSION_BASE,      0x200
    .equ SYSCALL_SESSION_MAX,       0x2FF
    .equ SYSCALL_MEMORY_BASE,       0x300
    .equ SYSCALL_MEMORY_MAX,        0x3FF
    .equ SYSCALL_DEVICE_BASE,       0x400
    .equ SYSCALL_DEVICE_MAX,        0x4FF
    .equ SYSCALL_AI_BASE,           0x500
    .equ SYSCALL_AI_MAX,            0x5FF
    .equ SYSCALL_QUANTUM_BASE,      0x600
    .equ SYSCALL_QUANTUM_MAX,       0x6FF
    .equ SYSCALL_SECURITY_BASE,     0x700
    .equ SYSCALL_SECURITY_MAX,      0x7FF
    .equ SYSCALL_SCHEDULER_BASE,    0x800
    .equ SYSCALL_SCHEDULER_MAX,     0x8FF

; POSIX-compatible syscalls
    .equ SYS_EXIT,                  0x001
    .equ SYS_READ,                  0x003
    .equ SYS_WRITE,                 0x004
    .equ SYS_OPEN,                  0x005
    .equ SYS_CLOSE,                 0x006
    .equ SYS_MMAP,                  0x009
    .equ SYS_MUNMAP,                0x00B
    .equ SYS_GETPID,                0x014
    .equ SYS_GETTID,                0x0BA
    .equ SYS_NANOSLEEP,             0x0A2
    .equ SYS_CLOCK_GETTIME,         0x0E4

; Zenith Memory Fabric syscalls
    .equ SYS_UMO_CREATE,            0x300
    .equ SYS_UMO_MAP,               0x301
    .equ SYS_UMO_UNMAP,             0x302
    .equ SYS_UMO_WRITE,             0x303
    .equ SYS_UMO_READ,              0x304
    .equ SYS_UMO_FREE,              0x305
    .equ SYS_UMO_LOCK,              0x306
    .equ SYS_UMO_UNLOCK,            0x307
    .equ SYS_UMO_DIRTY_PAGES,       0x308
    .equ SYS_UMO_CHECKPOINT,        0x309

; Zenith Device Broker syscalls
    .equ SYS_DEVICE_ACQUIRE,        0x400
    .equ SYS_DEVICE_RELEASE,        0x401
    .equ SYS_DEVICE_QUERY,          0x402
    .equ SYS_DEVICE_COMMAND,        0x403
    .equ SYS_DEVICE_LIST,           0x404

; Zenith AI syscalls
    .equ SYS_INFER_SUBMIT,          0x500
    .equ SYS_INFER_RESULT,          0x501
    .equ SYS_MODEL_LOAD,            0x502
    .equ SYS_MODEL_UNLOAD,          0x503
    .equ SYS_INFER_STREAM,          0x504

; Zenith Quantum syscalls
    .equ SYS_QPU_SUBMIT,            0x600
    .equ SYS_QPU_RESULT,            0x601
    .equ SYS_QKD_INIT,              0x602
    .equ SYS_QKD_EXCHANGE,          0x603
    .equ SYS_QPU_STATUS,            0x604

; Zenith Security syscalls
    .equ SYS_CAP_REQUEST,           0x700
    .equ SYS_CAP_REVOKE,            0x701
    .equ SYS_CAP_VERIFY,            0x702
    .equ SYS_ATTEST,                0x703
    .equ SYS_CONTAINER_SEAL,        0x704
    .equ SYS_CONTAINER_UNSEAL,      0x705

; Zenith Scheduler syscalls
    .equ SYS_INTENT_SUBMIT,         0x800
    .equ SYS_INTENT_CANCEL,         0x801
    .equ SYS_INTENT_STATUS,         0x802
    .equ SYS_TASK_MIGRATE,          0x803
    .equ SYS_TASK_CHECKPOINT,       0x804
    .equ SYS_TASK_RESTORE,          0x805
    .equ SYS_DOMAIN_STATUS,         0x806
    .equ SYS_SCHEDULER_STATS,       0x807

; Error codes
    .equ ENOSYS,                    -38     ; Function not implemented
    .equ EINVAL,                    -22     ; Invalid argument
    .equ EPERM,                     -1      ; Operation not permitted
    .equ ENOMEM,                    -12     ; Out of memory

; =============================================================================
; zenith_syscall_table_dispatch — Main syscall dispatcher
;
; Called from zenith_sync_el0_64 exception handler.
; x0 = pointer to saved ExceptionFrame on kernel stack
; =============================================================================
    .global zenith_syscall_table_dispatch
    .type   zenith_syscall_table_dispatch, @function
zenith_syscall_table_dispatch:
    stp     x29, x30, [sp, #-32]!
    stp     x19, x20, [sp, #16]
    mov     x29, sp
    mov     x19, x0                 ; Save frame pointer

    ; Load syscall number from x8 in the saved frame
    ; Frame: x0 at [frame+0], x8 at [frame+64]
    ldr     x20, [x19, #(8 * 8)]   ; x20 = syscall number

    ; ---- Range dispatch -------------------------------------------------------
    ; POSIX range
    cmp     x20, #SYSCALL_POSIX_MAX
    b.le    .Ldispatch_posix

    ; ZIB range
    cmp     x20, #SYSCALL_ZIB_BASE
    b.lt    .Ldispatch_unknown
    cmp     x20, #SYSCALL_ZIB_MAX
    b.le    .Ldispatch_zib

    ; Session range
    cmp     x20, #SYSCALL_SESSION_BASE
    b.lt    .Ldispatch_unknown
    cmp     x20, #SYSCALL_SESSION_MAX
    b.le    .Ldispatch_session

    ; Memory range
    cmp     x20, #SYSCALL_MEMORY_BASE
    b.lt    .Ldispatch_unknown
    cmp     x20, #SYSCALL_MEMORY_MAX
    b.le    .Ldispatch_memory

    ; Device range
    cmp     x20, #SYSCALL_DEVICE_BASE
    b.lt    .Ldispatch_unknown
    cmp     x20, #SYSCALL_DEVICE_MAX
    b.le    .Ldispatch_device

    ; AI range
    cmp     x20, #SYSCALL_AI_BASE
    b.lt    .Ldispatch_unknown
    cmp     x20, #SYSCALL_AI_MAX
    b.le    .Ldispatch_ai

    ; Quantum range
    cmp     x20, #SYSCALL_QUANTUM_BASE
    b.lt    .Ldispatch_unknown
    cmp     x20, #SYSCALL_QUANTUM_MAX
    b.le    .Ldispatch_quantum

    ; Security range
    cmp     x20, #SYSCALL_SECURITY_BASE
    b.lt    .Ldispatch_unknown
    cmp     x20, #SYSCALL_SECURITY_MAX
    b.le    .Ldispatch_security

    ; Scheduler range
    cmp     x20, #SYSCALL_SCHEDULER_BASE
    b.lt    .Ldispatch_unknown
    cmp     x20, #SYSCALL_SCHEDULER_MAX
    b.le    .Ldispatch_scheduler

    b       .Ldispatch_unknown

; ---- POSIX dispatch ----------------------------------------------------------
.Ldispatch_posix:
    ; Load arguments from saved frame
    ldp     x0, x1, [x19, #0]
    ldp     x2, x3, [x19, #16]
    ldp     x4, x5, [x19, #32]
    ldp     x6, x7, [x19, #48]
    mov     x8, x20
    bl      zenith_kern_posix_dispatch
    b       .Ldispatch_done

; ---- ZIB dispatch ------------------------------------------------------------
.Ldispatch_zib:
    ldp     x0, x1, [x19, #0]
    ldp     x2, x3, [x19, #16]
    ldp     x4, x5, [x19, #32]
    ldp     x6, x7, [x19, #48]
    mov     x8, x20
    bl      zenith_kern_zib_dispatch
    b       .Ldispatch_done

; ---- Session dispatch --------------------------------------------------------
.Ldispatch_session:
    ldp     x0, x1, [x19, #0]
    ldp     x2, x3, [x19, #16]
    ldp     x4, x5, [x19, #32]
    mov     x8, x20
    bl      zenith_kern_session_dispatch
    b       .Ldispatch_done

; ---- Memory Fabric dispatch --------------------------------------------------
.Ldispatch_memory:
    ldp     x0, x1, [x19, #0]
    ldp     x2, x3, [x19, #16]
    ldp     x4, x5, [x19, #32]
    ldp     x6, x7, [x19, #48]
    mov     x8, x20
    bl      zenith_kern_memory_dispatch
    b       .Ldispatch_done

; ---- Device Broker dispatch --------------------------------------------------
.Ldispatch_device:
    ldp     x0, x1, [x19, #0]
    ldp     x2, x3, [x19, #16]
    ldp     x4, x5, [x19, #32]
    mov     x8, x20
    bl      zenith_kern_device_dispatch
    b       .Ldispatch_done

; ---- AI/Inference dispatch ---------------------------------------------------
.Ldispatch_ai:
    ldp     x0, x1, [x19, #0]
    ldp     x2, x3, [x19, #16]
    ldp     x4, x5, [x19, #32]
    ldp     x6, x7, [x19, #48]
    mov     x8, x20
    bl      zenith_kern_ai_dispatch
    b       .Ldispatch_done

; ---- Quantum dispatch --------------------------------------------------------
.Ldispatch_quantum:
    ldp     x0, x1, [x19, #0]
    ldp     x2, x3, [x19, #16]
    ldp     x4, x5, [x19, #32]
    mov     x8, x20
    bl      zenith_kern_quantum_dispatch
    b       .Ldispatch_done

; ---- Security dispatch -------------------------------------------------------
.Ldispatch_security:
    ldp     x0, x1, [x19, #0]
    ldp     x2, x3, [x19, #16]
    ldp     x4, x5, [x19, #32]
    mov     x8, x20
    bl      zenith_kern_security_dispatch
    b       .Ldispatch_done

; ---- Scheduler dispatch ------------------------------------------------------
.Ldispatch_scheduler:
    ldp     x0, x1, [x19, #0]
    ldp     x2, x3, [x19, #16]
    ldp     x4, x5, [x19, #32]
    ldp     x6, x7, [x19, #48]
    mov     x8, x20
    bl      zenith_kern_scheduler_dispatch
    b       .Ldispatch_done

; ---- Unknown syscall ---------------------------------------------------------
.Ldispatch_unknown:
    mov     x0, #ENOSYS

.Ldispatch_done:
    ; Write return value back to saved x0 in the exception frame
    str     x0, [x19, #0]

    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

    .size   zenith_syscall_table_dispatch, . - zenith_syscall_table_dispatch

; =============================================================================
; User-space syscall wrappers (for domain runtimes)
; These are linked into each domain's user-space runtime library.
; =============================================================================

; sys_exit — Terminate the current task
    .global sys_exit
    .type   sys_exit, @function
sys_exit:
    mov     x8, #SYS_EXIT
    svc     #0
    ; Should not return
.Lexit_loop:
    wfe
    b       .Lexit_loop
    .size   sys_exit, . - sys_exit

; sys_write — Write to a file descriptor
    .global sys_write
    .type   sys_write, @function
sys_write:
    mov     x8, #SYS_WRITE
    svc     #0
    ret
    .size   sys_write, . - sys_write

; sys_read — Read from a file descriptor
    .global sys_read
    .type   sys_read, @function
sys_read:
    mov     x8, #SYS_READ
    svc     #0
    ret
    .size   sys_read, . - sys_read

; sys_mmap — Map memory
    .global sys_mmap
    .type   sys_mmap, @function
sys_mmap:
    mov     x8, #SYS_MMAP
    svc     #0
    ret
    .size   sys_mmap, . - sys_mmap

; sys_munmap — Unmap memory
    .global sys_munmap
    .type   sys_munmap, @function
sys_munmap:
    mov     x8, #SYS_MUNMAP
    svc     #0
    ret
    .size   sys_munmap, . - sys_munmap

; sys_umo_create — Create a Universal Memory Object
    .global sys_umo_create
    .type   sys_umo_create, @function
sys_umo_create:
    mov     x8, #SYS_UMO_CREATE
    svc     #0
    ret
    .size   sys_umo_create, . - sys_umo_create

; sys_umo_write — Write to a UMO
    .global sys_umo_write
    .type   sys_umo_write, @function
sys_umo_write:
    mov     x8, #SYS_UMO_WRITE
    svc     #0
    ret
    .size   sys_umo_write, . - sys_umo_write

; sys_umo_read — Read from a UMO
    .global sys_umo_read
    .type   sys_umo_read, @function
sys_umo_read:
    mov     x8, #SYS_UMO_READ
    svc     #0
    ret
    .size   sys_umo_read, . - sys_umo_read

; sys_infer_submit — Submit an AI inference request
    .global sys_infer_submit
    .type   sys_infer_submit, @function
sys_infer_submit:
    mov     x8, #SYS_INFER_SUBMIT
    svc     #0
    ret
    .size   sys_infer_submit, . - sys_infer_submit

; sys_qpu_submit — Submit a quantum circuit
    .global sys_qpu_submit
    .type   sys_qpu_submit, @function
sys_qpu_submit:
    mov     x8, #SYS_QPU_SUBMIT
    svc     #0
    ret
    .size   sys_qpu_submit, . - sys_qpu_submit

; sys_intent_submit — Submit an intent to the ZIS
    .global sys_intent_submit
    .type   sys_intent_submit, @function
sys_intent_submit:
    mov     x8, #SYS_INTENT_SUBMIT
    svc     #0
    ret
    .size   sys_intent_submit, . - sys_intent_submit

; sys_task_migrate — Request task migration
    .global sys_task_migrate
    .type   sys_task_migrate, @function
sys_task_migrate:
    mov     x8, #SYS_TASK_MIGRATE
    svc     #0
    ret
    .size   sys_task_migrate, . - sys_task_migrate

; sys_cap_request — Request a capability token
    .global sys_cap_request
    .type   sys_cap_request, @function
sys_cap_request:
    mov     x8, #SYS_CAP_REQUEST
    svc     #0
    ret
    .size   sys_cap_request, . - sys_cap_request

; =============================================================================
; External Rust kernel dispatch handlers
; =============================================================================
    .extern zenith_kern_posix_dispatch
    .extern zenith_kern_zib_dispatch
    .extern zenith_kern_session_dispatch
    .extern zenith_kern_memory_dispatch
    .extern zenith_kern_device_dispatch
    .extern zenith_kern_ai_dispatch
    .extern zenith_kern_quantum_dispatch
    .extern zenith_kern_security_dispatch
    .extern zenith_kern_scheduler_dispatch

; =============================================================================
; End of zenith_syscall.asm
; =============================================================================
