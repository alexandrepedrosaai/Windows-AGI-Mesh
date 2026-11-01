        // Revised ABI-safe version  majorana_phase_shift_aarch64.S - Linux AArch64 / ELF
        // Revised ABI-safe version

        .text
        .p2align 4
        .global majorana_phase_shift_neon
        .type majorana_phase_shift_neon, %function
        .global compute_phase_angles_neon
        .type compute_phase_angles_neon, %function
        .global apply_majorana_identity_neon
        .type apply_majorana_identity_neon, %function
        .global majorana_purity_neon
        .type majorana_purity_neon, %function

majorana_phase_shift_neon:
        stp x29,x30,[sp,#-64]!
        mov x29,sp
        stp x19,x20,[sp,#16]
        stp x21,x22,[sp,#32]
        str x23,[sp,#48]
        mov x19,x0
        mov x20,x1
        mov x21,x2
        mov w22,w3
        bl .L_load_constants
        lsr x23,x22,#2
        cbz x23,.L_phase_tail
.L_phase_vec:
        ld1 {v0.4s},[x21],#16
        fmul v1.4s,v0.4s,v26.4s
        frintn v1.4s,v1.4s
        fmls v0.4s,v1.4s,v27.4s
        fmul v1.4s,v0.4s,v0.4s
        fmul v2.4s,v1.4s,v1.4s
        fmul v3.4s,v2.4s,v1.4s
        fmul v4.4s,v3.4s,v1.4s
        fmul v5.4s,v4.4s,v1.4s
        fmov v6.4s,#1.0
        fmla v6.4s,v1.4s,v16.4s
        fmla v6.4s,v2.4s,v17.4s
        fmla v6.4s,v3.4s,v18.4s
        fmla v6.4s,v4.4s,v19.4s
        fmla v6.4s,v5.4s,v20.4s
        mov v7.16b,v0.16b
        fmul v2.4s,v1.4s,v0.4s
        fmla v7.4s,v2.4s,v21.4s
        fmul v3.4s,v2.4s,v1.4s
        fmla v7.4s,v3.4s,v22.4s
        fmul v4.4s,v3.4s,v1.4s
        fmla v7.4s,v4.4s,v23.4s
        fmul v5.4s,v4.4s,v1.4s
        fmla v7.4s,v5.4s,v24.4s
        fmul v2.4s,v5.4s,v1.4s
        fmla v7.4s,v2.4s,v25.4s
        ld1 {v0.4s},[x19]
        ld1 {v1.4s},[x20]
        fmul v2.4s,v0.4s,v6.4s
        fmls v2.4s,v1.4s,v7.4s
        fmul v3.4s,v0.4s,v7.4s
        fmla v3.4s,v1.4s,v6.4s
        st1 {v2.4s},[x19],#16
        st1 {v3.4s},[x20],#16
        subs x23,x23,#1
        b.ne .L_phase_vec
.L_phase_tail:
        and w23,w22,#3
        cbz w23,.L_phase_done
.L_phase_scalar:
        ldr s0,[x21],#4
        fmul s1,s0,v26.s[0]
        frintn s1,s1
        fmls s0,s1,v27.s[0]
        fmul s1,s0,s0
        fmov s2,#1.0
        fmla s2,s1,v16.s[0]
        fmul s3,s1,s1
        fmla s2,s3,v17.s[0]
        fmul s4,s3,s1
        fmla s2,s4,v18.s[0]
        fmul s5,s4,s1
        fmla s2,s5,v19.s[0]
        fmul s6,s5,s1
        fmla s2,s6,v20.s[0]
        fmov s3,s0
        fmul s4,s1,s0
        fmla s3,s4,v21.s[0]
        fmul s5,s4,s1
        fmla s3,s5,v22.s[0]
        fmul s6,s5,s1
        fmla s3,s6,v23.s[0]
        fmul s4,s6,s1
        fmla s3,s4,v24.s[0]
        fmul s5,s4,s1
        fmla s3,s5,v25.s[0]
        ldr s4,[x19]
        ldr s5,[x20]
        fmul s6,s4,s2
        fmls s6,s5,s3
        fmul s0,s4,s3
        fmla s0,s5,s2
        str s6,[x19],#4
        str s0,[x20],#4
        subs w23,w23,#1
        b.ne .L_phase_scalar
.L_phase_done:
        ldr x23,[sp,#48]
        ldp x21,x22,[sp,#32]
        ldp x19,x20,[sp,#16]
        ldp x29,x30,[sp],#64
        ret
        .size majorana_phase_shift_neon,.-majorana_phase_shift_neon

compute_phase_angles_neon:
        stp x29,x30,[sp,#-64]!
        mov x29,sp
        stp x19,x20,[sp,#16]
        stp x21,x22,[sp,#32]
        str x23,[sp,#48]
        mov x19,x0
        mov x20,x1
        mov w22,w2
        // t is in s0. Save its bits in callee-saved x21 across BL.
        fmov w21,s0
        bl .L_load_constants
        fmov s7,w21
        dup v7.4s,v7.s[0]
        lsr x23,x22,#2
        cbz x23,.L_angles_tail
.L_angles_vec:
        ld1 {v0.4s},[x19],#16
        fmul v0.4s,v0.4s,v7.4s
        fmul v1.4s,v0.4s,v26.4s
        frintn v1.4s,v1.4s
        fmls v0.4s,v1.4s,v27.4s
        st1 {v0.4s},[x20],#16
        subs x23,x23,#1
        b.ne .L_angles_vec
.L_angles_tail:
        and w23,w22,#3
        cbz w23,.L_angles_done
.L_angles_scalar:
        ldr s0,[x19],#4
        fmul s0,s0,v7.s[0]
        fmul s1,s0,v26.s[0]
        frintn s1,s1
        fmls s0,s1,v27.s[0]
        str s0,[x20],#4
        subs w23,w23,#1
        b.ne .L_angles_scalar
.L_angles_done:
        ldr x23,[sp,#48]
        ldp x21,x22,[sp,#32]
        ldp x19,x20,[sp,#16]
        ldp x29,x30,[sp],#64
        ret
        .size compute_phase_angles_neon,.-compute_phase_angles_neon

apply_majorana_identity_neon:
        stp x29,x30,[sp,#-96]!
        mov x29,sp
        stp x19,x20,[sp,#16]
        stp x21,x22,[sp,#32]
        stp x23,x24,[sp,#48]
        stp x25,x26,[sp,#64]
        mov x19,x0
        mov x20,x1
        mov x21,x2
        mov x22,x3
        mov x25,x4
        mov x26,x5
        mov w24,w6
        bl .L_load_constants
        lsr x23,x24,#2
        cbz x23,.L_identity_tail
.L_identity_vec:
        ld1 {v0.4s},[x19],#16
        ld1 {v1.4s},[x20],#16
        ld1 {v2.4s},[x21],#16
        ld1 {v3.4s},[x22],#16
        fneg v3.4s,v3.4s
        fadd v4.4s,v0.4s,v2.4s
        fadd v5.4s,v1.4s,v3.4s
        fmul v4.4s,v4.4s,v28.4s
        fmul v5.4s,v5.4s,v28.4s
        st1 {v4.4s},[x25],#16
        st1 {v5.4s},[x26],#16
        subs x23,x23,#1
        b.ne .L_identity_vec
.L_identity_tail:
        and w23,w24,#3
        cbz w23,.L_identity_done
.L_identity_scalar:
        ldr s0,[x19],#4
        ldr s1,[x20],#4
        ldr s2,[x21],#4
        ldr s3,[x22],#4
        fneg s3,s3
        fadd s4,s0,s2
        fadd s5,s1,s3
        fmul s4,s4,v28.s[0]
        fmul s5,s5,v28.s[0]
        str s4,[x25],#4
        str s5,[x26],#4
        subs w23,w23,#1
        b.ne .L_identity_scalar
.L_identity_done:
        ldp x25,x26,[sp,#64]
        ldp x23,x24,[sp,#48]
        ldp x21,x22,[sp,#32]
        ldp x19,x20,[sp,#16]
        ldp x29,x30,[sp],#96
        ret
        .size apply_majorana_identity_neon,.-apply_majorana_identity_neon

majorana_purity_neon:
        stp x29,x30,[sp,#-48]!
        mov x29,sp
        stp x19,x20,[sp,#16]
        stp x21,x22,[sp,#32]
        mov x19,x0
        mov x20,x1
        mov w22,w2
        movi v0.4s,#0
        lsr x21,x22,#2
        cbz x21,.L_purity_tail
.L_purity_vec:
        ld1 {v1.4s},[x19],#16
        ld1 {v2.4s},[x20],#16
        fmla v0.4s,v1.4s,v1.4s
        fmla v0.4s,v2.4s,v2.4s
        subs x21,x21,#1
        b.ne .L_purity_vec
.L_purity_tail:
        and w21,w22,#3
        cbz w21,.L_purity_reduce
        fmov s4,#0.0
.L_purity_scalar:
        ldr s1,[x19],#4
        ldr s2,[x20],#4
        fmla s4,s1,s1
        fmla s4,s2,s2
        subs w21,w21,#1
        b.ne .L_purity_scalar
        fadd s0,s0,s4
.L_purity_reduce:
        faddp v0.4s,v0.4s,v0.4s
        faddp v0.4s,v0.4s,v0.4s
        fmul s0,s0,s0
        ldp x21,x22,[sp,#32]
        ldp x19,x20,[sp,#16]
        ldp x29,x30,[sp],#48
        ret
        .size majorana_purity_neon,.-majorana_purity_neon

.p2align 4
.L_load_constants:
        adrp x9,.L_constants
        add x9,x9,:lo12:.L_constants
        ld1 {v16.4s},[x9],#16
        ld1 {v17.4s},[x9],#16
        ld1 {v18.4s},[x9],#16
        ld1 {v19.4s},[x9],#16
        ld1 {v20.4s},[x9],#16
        ld1 {v21.4s},[x9],#16
        ld1 {v22.4s},[x9],#16
        ld1 {v23.4s},[x9],#16
        ld1 {v24.4s},[x9],#16
        ld1 {v25.4s},[x9],#16
        ld1 {v26.4s},[x9],#16
        ld1 {v27.4s},[x9],#16
        ld1 {v28.4s},[x9],#16
        ret

.section .rodata
.p2align 4
.L_constants:
        .rept 4
        .float -0.5
        .endr
        .rept 4
        .float 0.041666666666666664
        .endr
        .rept 4
        .float -0.001388888888888889
        .endr
        .rept 4
        .float 0.0000248015873015873
        .endr
        .rept 4
        .float -2.7557319223985893e-07
        .endr
        .rept 4
        .float -0.16666666666666666
        .endr
        .rept 4
        .float 0.008333333333333333
        .endr
        .rept 4
        .float -0.0001984126984126984
        .endr
        .rept 4
        .float 2.755731922398589e-06
        .endr
        .rept 4
        .float -2.505210838544172e-08
        .endr
        .rept 4
        .float 0.15915494309189535
        .endr
        .rept 4
        .float 6.283185307179586
        .endr
        .rept 4
        .float 0.7071067811865475
        .endr

.section .note.GNU-stack,"",%progbits
