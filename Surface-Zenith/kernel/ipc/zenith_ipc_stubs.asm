; =============================================================================
; Surface Zenith OS — IPC System Call Stubs (ARM64 Assembly)
; File: kernel/ipc/zenith_ipc_stubs.asm
;
; These stubs implement the low-level system call interface for the
; Zenith Interdomain Bus (ZIB). Applications call these stubs to
; publish/subscribe messages without knowing the kernel internals.
;
; Zenith Syscall ABI (ARM64):
;   x8  = syscall number
;   x0  = arg0 (return value on exit)
;   x1  = arg1
;   x2  = arg2
;   x3  = arg3
;   x4  = arg4
;   x5  = arg5
;   x6  = arg6
;   x7  = arg7
;
; Syscall numbers:
;   0x100 = ZIB_PUBLISH
;   0x101 = ZIB_SUBSCRIBE
;   0x102 = ZIB_UNSUBSCRIBE
;   0x103 = ZIB_RECV
;   0x104 = ZIB_RECV_TIMEOUT
;   0x105 = ZIB_SEND_DIRECTED
;   0x106 = ZIB_CAPABILITY_CHECK
;   0x107 = ZIB_SESSION_OPEN
;   0x108 = ZIB_SESSION_CLOSE
;   0x109 = ZIB_INTENT_SUBMIT
;   0x10A = ZIB_INTENT_CANCEL
;   0x10B = ZIB_SNAPSHOT_CREATE
;   0x10C = ZIB_SNAPSHOT_RESTORE
;   0x10D = ZIB_MIGRATE_TASK
;   0x10E = ZIB_DOMAIN_QUERY
; =============================================================================

    .arch   armv8-a
    .section .text.ipc, "ax", @progbits

; -----------------------------------------------------------------------------
; Syscall number constants
; -----------------------------------------------------------------------------
    .equ SYSCALL_ZIB_PUBLISH,           0x100
    .equ SYSCALL_ZIB_SUBSCRIBE,         0x101
    .equ SYSCALL_ZIB_UNSUBSCRIBE,       0x102
    .equ SYSCALL_ZIB_RECV,              0x103
    .equ SYSCALL_ZIB_RECV_TIMEOUT,      0x104
    .equ SYSCALL_ZIB_SEND_DIRECTED,     0x105
    .equ SYSCALL_ZIB_CAPABILITY_CHECK,  0x106
    .equ SYSCALL_ZIB_SESSION_OPEN,      0x107
    .equ SYSCALL_ZIB_SESSION_CLOSE,     0x108
    .equ SYSCALL_ZIB_INTENT_SUBMIT,     0x109
    .equ SYSCALL_ZIB_INTENT_CANCEL,     0x10A
    .equ SYSCALL_ZIB_SNAPSHOT_CREATE,   0x10B
    .equ SYSCALL_ZIB_SNAPSHOT_RESTORE,  0x10C
    .equ SYSCALL_ZIB_MIGRATE_TASK,      0x10D
    .equ SYSCALL_ZIB_DOMAIN_QUERY,      0x10E

; Error codes
    .equ ZENITH_OK,                     0
    .equ ZENITH_ERR_INVALID_ARG,        -1
    .equ ZENITH_ERR_PERMISSION_DENIED,  -13
    .equ ZENITH_ERR_BUS_UNAVAILABLE,    -40
    .equ ZENITH_ERR_TIMEOUT,            -50
    .equ ZENITH_ERR_QUEUE_FULL,         -28

; =============================================================================
; zib_publish — Publish a message to the ZIB
;
; Prototype (C-compatible):
;   int64_t zib_publish(
;       uint64_t session_id_lo,   // x0: lower 64 bits of session UUID
;       uint64_t session_id_hi,   // x1: upper 64 bits of session UUID
;       uint32_t topic_id,        // x2: topic enum value
;       uint32_t source_domain,   // x3: source domain enum
;       const void* payload,      // x4: pointer to payload bytes
;       uint64_t payload_len,     // x5: payload length in bytes
;       uint64_t ttl_ms           // x6: time-to-live in milliseconds
;   );
;
; Returns: number of subscribers that received the message, or negative error
; =============================================================================
    .global zib_publish
    .type   zib_publish, @function
zib_publish:
    ; Validate payload pointer (must not be NULL)
    cbz     x4, .Lpublish_invalid_arg

    ; Validate payload length (must be > 0 and <= 16MB)
    cbz     x5, .Lpublish_invalid_arg
    mov     x7, #(16 * 1024 * 1024)
    cmp     x5, x7
    b.hi    .Lpublish_invalid_arg

    ; Issue syscall
    mov     x8, #SYSCALL_ZIB_PUBLISH
    svc     #0

    ; x0 contains return value (subscriber count or error)
    ret

.Lpublish_invalid_arg:
    mov     x0, #ZENITH_ERR_INVALID_ARG
    ret

    .size   zib_publish, . - zib_publish

; =============================================================================
; zib_subscribe — Subscribe to a topic on the ZIB
;
; Prototype:
;   int64_t zib_subscribe(
;       uint32_t topic_id,        // x0: topic enum value
;       uint32_t domain_id,       // x1: subscribing domain
;       uint64_t* out_sub_id      // x2: output subscription ID
;   );
;
; Returns: 0 on success, negative error code on failure
; =============================================================================
    .global zib_subscribe
    .type   zib_subscribe, @function
zib_subscribe:
    ; Validate output pointer
    cbz     x2, .Lsubscribe_invalid_arg

    ; Issue syscall
    mov     x8, #SYSCALL_ZIB_SUBSCRIBE
    svc     #0
    ret

.Lsubscribe_invalid_arg:
    mov     x0, #ZENITH_ERR_INVALID_ARG
    ret

    .size   zib_subscribe, . - zib_subscribe

; =============================================================================
; zib_unsubscribe — Unsubscribe from a topic
;
; Prototype:
;   int64_t zib_unsubscribe(uint64_t sub_id);
; =============================================================================
    .global zib_unsubscribe
    .type   zib_unsubscribe, @function
zib_unsubscribe:
    mov     x8, #SYSCALL_ZIB_UNSUBSCRIBE
    svc     #0
    ret

    .size   zib_unsubscribe, . - zib_unsubscribe

; =============================================================================
; zib_recv — Receive the next message for a subscription (blocking)
;
; Prototype:
;   int64_t zib_recv(
;       uint64_t sub_id,          // x0: subscription ID
;       void* buf,                // x1: output buffer
;       uint64_t buf_len,         // x2: buffer length
;       uint64_t* out_msg_len     // x3: actual message length written
;   );
; =============================================================================
    .global zib_recv
    .type   zib_recv, @function
zib_recv:
    ; Validate buffer pointer
    cbz     x1, .Lrecv_invalid_arg
    ; Validate buffer length
    cbz     x2, .Lrecv_invalid_arg

    mov     x8, #SYSCALL_ZIB_RECV
    svc     #0
    ret

.Lrecv_invalid_arg:
    mov     x0, #ZENITH_ERR_INVALID_ARG
    ret

    .size   zib_recv, . - zib_recv

; =============================================================================
; zib_recv_timeout — Receive with timeout
;
; Prototype:
;   int64_t zib_recv_timeout(
;       uint64_t sub_id,          // x0
;       void* buf,                // x1
;       uint64_t buf_len,         // x2
;       uint64_t* out_msg_len,    // x3
;       uint64_t timeout_ms       // x4: 0 = non-blocking
;   );
; =============================================================================
    .global zib_recv_timeout
    .type   zib_recv_timeout, @function
zib_recv_timeout:
    cbz     x1, .Lrecv_to_invalid
    cbz     x2, .Lrecv_to_invalid
    mov     x8, #SYSCALL_ZIB_RECV_TIMEOUT
    svc     #0
    ret

.Lrecv_to_invalid:
    mov     x0, #ZENITH_ERR_INVALID_ARG
    ret

    .size   zib_recv_timeout, . - zib_recv_timeout

; =============================================================================
; zib_send_directed — Send a message to a specific domain
;
; Prototype:
;   int64_t zib_send_directed(
;       uint64_t session_id_lo,   // x0
;       uint64_t session_id_hi,   // x1
;       uint32_t topic_id,        // x2
;       uint32_t source_domain,   // x3
;       uint32_t target_domain,   // x4
;       const void* payload,      // x5
;       uint64_t payload_len      // x6
;   );
; =============================================================================
    .global zib_send_directed
    .type   zib_send_directed, @function
zib_send_directed:
    cbz     x5, .Ldirected_invalid
    cbz     x6, .Ldirected_invalid
    mov     x8, #SYSCALL_ZIB_SEND_DIRECTED
    svc     #0
    ret

.Ldirected_invalid:
    mov     x0, #ZENITH_ERR_INVALID_ARG
    ret

    .size   zib_send_directed, . - zib_send_directed

; =============================================================================
; zib_capability_check — Validate a capability token
;
; Prototype:
;   int64_t zib_capability_check(
;       const void* token_bytes,  // x0: serialized capability token
;       uint64_t token_len,       // x1: token length
;       uint32_t resource_id,     // x2: resource being accessed
;       uint32_t access_level     // x3: requested access level
;   );
;
; Returns: 0 if authorized, negative error code if denied
; =============================================================================
    .global zib_capability_check
    .type   zib_capability_check, @function
zib_capability_check:
    cbz     x0, .Lcap_invalid
    cbz     x1, .Lcap_invalid
    mov     x8, #SYSCALL_ZIB_CAPABILITY_CHECK
    svc     #0
    ret

.Lcap_invalid:
    mov     x0, #ZENITH_ERR_INVALID_ARG
    ret

    .size   zib_capability_check, . - zib_capability_check

; =============================================================================
; zib_session_open — Open a new Zenith session
;
; Prototype:
;   int64_t zib_session_open(
;       const void* identity_bytes, // x0: serialized identity
;       uint64_t identity_len,      // x1
;       uint32_t form_factor,       // x2: FormFactor enum
;       uint64_t* out_session_lo,   // x3: output session UUID low
;       uint64_t* out_session_hi    // x4: output session UUID high
;   );
; =============================================================================
    .global zib_session_open
    .type   zib_session_open, @function
zib_session_open:
    cbz     x0, .Lsession_open_invalid
    cbz     x3, .Lsession_open_invalid
    cbz     x4, .Lsession_open_invalid
    mov     x8, #SYSCALL_ZIB_SESSION_OPEN
    svc     #0
    ret

.Lsession_open_invalid:
    mov     x0, #ZENITH_ERR_INVALID_ARG
    ret

    .size   zib_session_open, . - zib_session_open

; =============================================================================
; zib_session_close — Close a Zenith session
;
; Prototype:
;   int64_t zib_session_close(
;       uint64_t session_id_lo,   // x0
;       uint64_t session_id_hi    // x1
;   );
; =============================================================================
    .global zib_session_close
    .type   zib_session_close, @function
zib_session_close:
    mov     x8, #SYSCALL_ZIB_SESSION_CLOSE
    svc     #0
    ret

    .size   zib_session_close, . - zib_session_close

; =============================================================================
; zib_intent_submit — Submit an intent to the Zenith scheduler
;
; Prototype:
;   int64_t zib_intent_submit(
;       uint64_t session_id_lo,   // x0
;       uint64_t session_id_hi,   // x1
;       const void* intent_bytes, // x2: serialized Intent struct
;       uint64_t intent_len,      // x3
;       uint64_t* out_intent_lo,  // x4: output intent UUID low
;       uint64_t* out_intent_hi   // x5: output intent UUID high
;   );
; =============================================================================
    .global zib_intent_submit
    .type   zib_intent_submit, @function
zib_intent_submit:
    cbz     x2, .Lintent_submit_invalid
    cbz     x3, .Lintent_submit_invalid
    mov     x8, #SYSCALL_ZIB_INTENT_SUBMIT
    svc     #0
    ret

.Lintent_submit_invalid:
    mov     x0, #ZENITH_ERR_INVALID_ARG
    ret

    .size   zib_intent_submit, . - zib_intent_submit

; =============================================================================
; zib_intent_cancel — Cancel a pending intent
;
; Prototype:
;   int64_t zib_intent_cancel(
;       uint64_t intent_id_lo,    // x0
;       uint64_t intent_id_hi     // x1
;   );
; =============================================================================
    .global zib_intent_cancel
    .type   zib_intent_cancel, @function
zib_intent_cancel:
    mov     x8, #SYSCALL_ZIB_INTENT_CANCEL
    svc     #0
    ret

    .size   zib_intent_cancel, . - zib_intent_cancel

; =============================================================================
; zib_snapshot_create — Create a task snapshot for migration
;
; Prototype:
;   int64_t zib_snapshot_create(
;       uint64_t task_id_lo,      // x0
;       uint64_t task_id_hi,      // x1
;       void* out_buf,            // x2: output buffer for snapshot
;       uint64_t buf_len,         // x3: buffer length
;       uint64_t* out_snap_len    // x4: actual snapshot size written
;   );
; =============================================================================
    .global zib_snapshot_create
    .type   zib_snapshot_create, @function
zib_snapshot_create:
    cbz     x2, .Lsnap_create_invalid
    cbz     x3, .Lsnap_create_invalid
    cbz     x4, .Lsnap_create_invalid
    mov     x8, #SYSCALL_ZIB_SNAPSHOT_CREATE
    svc     #0
    ret

.Lsnap_create_invalid:
    mov     x0, #ZENITH_ERR_INVALID_ARG
    ret

    .size   zib_snapshot_create, . - zib_snapshot_create

; =============================================================================
; zib_snapshot_restore — Restore a task from a snapshot
;
; Prototype:
;   int64_t zib_snapshot_restore(
;       const void* snap_buf,     // x0: snapshot data
;       uint64_t snap_len,        // x1
;       uint32_t target_domain,   // x2: target domain enum
;       uint64_t* out_task_lo,    // x3: output new task UUID low
;       uint64_t* out_task_hi     // x4: output new task UUID high
;   );
; =============================================================================
    .global zib_snapshot_restore
    .type   zib_snapshot_restore, @function
zib_snapshot_restore:
    cbz     x0, .Lsnap_restore_invalid
    cbz     x1, .Lsnap_restore_invalid
    mov     x8, #SYSCALL_ZIB_SNAPSHOT_RESTORE
    svc     #0
    ret

.Lsnap_restore_invalid:
    mov     x0, #ZENITH_ERR_INVALID_ARG
    ret

    .size   zib_snapshot_restore, . - zib_snapshot_restore

; =============================================================================
; zib_migrate_task — Migrate a running task to another domain
;
; Prototype:
;   int64_t zib_migrate_task(
;       uint64_t task_id_lo,      // x0
;       uint64_t task_id_hi,      // x1
;       uint32_t target_domain,   // x2
;       uint32_t migration_mode,  // x3: 0=full, 1=incremental, 2=live
;       uint32_t trigger_reason   // x4: MigrationTrigger enum
;   );
; =============================================================================
    .global zib_migrate_task
    .type   zib_migrate_task, @function
zib_migrate_task:
    ; Validate migration mode (0, 1, or 2) as uint32_t
    cmp     w3, #2
    b.hi    .Lmigrate_invalid
    mov     x8, #SYSCALL_ZIB_MIGRATE_TASK
    svc     #0
    ret

.Lmigrate_invalid:
    mov     x0, #ZENITH_ERR_INVALID_ARG
    ret

    .size   zib_migrate_task, . - zib_migrate_task

; =============================================================================
; zib_domain_query — Query the state of a domain
;
; Prototype:
;   int64_t zib_domain_query(
;       uint32_t domain_id,       // x0: Domain enum
;       void* out_buf,            // x1: output buffer for DomainDescriptor
;       uint64_t buf_len          // x2
;   );
; =============================================================================
    .global zib_domain_query
    .type   zib_domain_query, @function
zib_domain_query:
    cbz     x1, .Ldomain_query_invalid
    cbz     x2, .Ldomain_query_invalid
    mov     x8, #SYSCALL_ZIB_DOMAIN_QUERY
    svc     #0
    ret

.Ldomain_query_invalid:
    mov     x0, #ZENITH_ERR_INVALID_ARG
    ret

    .size   zib_domain_query, . - zib_domain_query

; =============================================================================
; Kernel-side syscall dispatcher (called from exception handler)
;
; x0 = pointer to saved register frame (ExceptionFrame)
; =============================================================================
    .global zenith_syscall_dispatch
    .type   zenith_syscall_dispatch, @function
zenith_syscall_dispatch:
    ; Save frame pointer and link register
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    ; Load syscall number from saved x8 in the exception frame
    ; Frame layout: x0..x7 at offsets 0..56, x8 at offset 64
    ldr     x9, [x0, #(8 * 8)]     ; x9 = syscall number

    ; Dispatch table bounds check
    mov     x10, #SYSCALL_ZIB_PUBLISH
    cmp     x9, x10
    b.lt    .Lsyscall_unknown
    mov     x10, #SYSCALL_ZIB_DOMAIN_QUERY
    cmp     x9, x10
    b.gt    .Lsyscall_unknown

    ; Compute dispatch table index
    mov     x10, #SYSCALL_ZIB_PUBLISH
    sub     x9, x9, x10
    adr     x10, .Lsyscall_table
    ldr     x10, [x10, x9, lsl #3]
    blr     x10

    ldp     x29, x30, [sp], #16
    ret

.Lsyscall_unknown:
    mov     x0, #ZENITH_ERR_INVALID_ARG
    ldp     x29, x30, [sp], #16
    ret

; Syscall dispatch table
    .balign 8
.Lsyscall_table:
    .quad   zenith_kern_zib_publish
    .quad   zenith_kern_zib_subscribe
    .quad   zenith_kern_zib_unsubscribe
    .quad   zenith_kern_zib_recv
    .quad   zenith_kern_zib_recv_timeout
    .quad   zenith_kern_zib_send_directed
    .quad   zenith_kern_zib_capability_check
    .quad   zenith_kern_zib_session_open
    .quad   zenith_kern_zib_session_close
    .quad   zenith_kern_zib_intent_submit
    .quad   zenith_kern_zib_intent_cancel
    .quad   zenith_kern_zib_snapshot_create
    .quad   zenith_kern_zib_snapshot_restore
    .quad   zenith_kern_zib_migrate_task
    .quad   zenith_kern_zib_domain_query

    .size   zenith_syscall_dispatch, . - zenith_syscall_dispatch

; =============================================================================
; Kernel handler stubs — implemented in Rust (zenith-kernel crate)
; These are declared as external symbols resolved at link time.
; =============================================================================
    .extern zenith_kern_zib_publish
    .extern zenith_kern_zib_subscribe
    .extern zenith_kern_zib_unsubscribe
    .extern zenith_kern_zib_recv
    .extern zenith_kern_zib_recv_timeout
    .extern zenith_kern_zib_send_directed
    .extern zenith_kern_zib_capability_check
    .extern zenith_kern_zib_session_open
    .extern zenith_kern_zib_session_close
    .extern zenith_kern_zib_intent_submit
    .extern zenith_kern_zib_intent_cancel
    .extern zenith_kern_zib_snapshot_create
    .extern zenith_kern_zib_snapshot_restore
    .extern zenith_kern_zib_migrate_task
    .extern zenith_kern_zib_domain_query
    .extern zenith_irq_handler
    .extern zenith_kernel_fault
    .extern zenith_kernel_main

; =============================================================================
; End of zenith_ipc_stubs.asm
; =============================================================================
