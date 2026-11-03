; =============================================================================
; webtransport_service.ll — QIR Quantum Intermediate Representation
; Qubit mapping, error correction, quantum hardware interface
; Target: MAIA-300 / Azure Quantum / IonQ / Quantinuum
; QIR Spec v1.0 — https://github.com/qir-alliance/qir-spec
; =============================================================================

source_filename = "webtransport_service.ll"
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-f80:128-n8:16:32:64-S128"
target triple = "x86_64-pc-linux-gnu"

%Qubit = type opaque
%Result = type opaque
%Array = type opaque
%Tuple = type opaque
%Callable = type opaque
%Pauli = type i2
%Range = type { i64, i64, i64 }
%BigInt = type opaque
%String = type opaque
%ErrorSyndrome = type { i64, i64, double }
%StabilizerCode = type { i32, i32, %Array* }
%LogicalQubit = type { %Qubit*, i32, %StabilizerCode* }
%QuantumRegister = type { %LogicalQubit**, i32, double }
%FisherMatrix = type { double*, i32, double }
%AnchorState = type { double, double, double, i32 }
%QubitMap = type { i32*, i32*, i32, i32 }
%HardwareTopology = type { i32**, i32, i32 }

declare void @__quantum__rt__initialize(i8*)
declare void @__quantum__rt__finalize()
declare %Qubit* @__quantum__rt__qubit_allocate()
declare void @__quantum__rt__qubit_release(%Qubit*)
declare %Array* @__quantum__rt__qubit_allocate_array(i64)
declare void @__quantum__rt__qubit_release_array(%Array*)
declare %Result* @__quantum__rt__result_get_zero()
declare %Result* @__quantum__rt__result_get_one()
declare i1 @__quantum__rt__result_equal(%Result*, %Result*)
declare void @__quantum__rt__result_update_reference_count(%Result*, i32)
declare %String* @__quantum__rt__string_create(i8*)
declare void @__quantum__rt__message(%String*)
declare void @__quantum__rt__fail(%String*)
declare %Array* @__quantum__rt__array_create_1d(i32, i64)
declare i8* @__quantum__rt__array_get_element_ptr_1d(%Array*, i64)
declare i64 @__quantum__rt__array_get_size_1d(%Array*)
declare void @__quantum__rt__array_update_reference_count(%Array*, i32)
declare void @__quantum__qis__h__body(%Qubit*)
declare void @__quantum__qis__x__body(%Qubit*)
declare void @__quantum__qis__y__body(%Qubit*)
declare void @__quantum__qis__z__body(%Qubit*)
declare void @__quantum__qis__s__body(%Qubit*)
declare void @__quantum__qis__t__body(%Qubit*)
declare void @__quantum__qis__s__adj(%Qubit*)
declare void @__quantum__qis__t__adj(%Qubit*)
declare void @__quantum__qis__cx__body(%Qubit*, %Qubit*)
declare void @__quantum__qis__cy__body(%Qubit*, %Qubit*)
declare void @__quantum__qis__cz__body(%Qubit*, %Qubit*)
declare void @__quantum__qis__ccx__body(%Qubit*, %Qubit*, %Qubit*)
declare void @__quantum__qis__rx__body(double, %Qubit*)
declare void @__quantum__qis__ry__body(double, %Qubit*)
declare void @__quantum__qis__rz__body(double, %Qubit*)
declare void @__quantum__qis__r1__body(double, %Qubit*)
declare void @__quantum__qis__swap__body(%Qubit*, %Qubit*)
declare void @__quantum__qis__iswap__body(%Qubit*, %Qubit*)
declare void @__quantum__qis__reset__body(%Qubit*)
declare %Result* @__quantum__qis__m__body(%Qubit*)
declare %Result* @__quantum__qis__mresetz__body(%Qubit*)
declare void @__quantum__qis__exp__body(%Array*, double, %Array*)
declare void @__maia__qis__majorana_braid(%Qubit*, %Qubit*, i32)
declare void @__maia__qis__majorana_fuse(%Qubit*, %Qubit*, %Result*)
declare double @__maia__qis__majorana_parity(%Qubit*, %Qubit*)
declare void @__maia__qis__topological_gate(%Qubit*, i32, double)
declare double @__maia__qis__coherence_measure(%Qubit*)
declare void @__maia__qis__error_correct(%Array*, %ErrorSyndrome*)
declare %ErrorSyndrome* @__maia__qis__syndrome_measure(%Array*)
declare void @__maia__qis__logical_x(%LogicalQubit*)
declare void @__maia__qis__logical_z(%LogicalQubit*)
declare %Result* @__maia__qis__logical_measure(%LogicalQubit*)
declare void @__maia__qis__stabilizer_round(%StabilizerCode*, %Array*)
declare double @__maia__qis__fidelity(%Qubit*, %Qubit*)
declare void @__maia__qis__anchor_align(%AnchorState*, %Qubit*, double)
declare double @__maia__qis__anchor_phase(%AnchorState*)
declare double @llvm.sqrt.f64(double)
declare double @llvm.fabs.f64(double)
declare double @llvm.exp.f64(double)
declare double @llvm.log.f64(double)
declare double @llvm.sin.f64(double)
declare double @llvm.cos.f64(double)
declare double @llvm.pow.f64(double, double)
declare i32 @printf(i8*, ...)
declare i8* @malloc(i64)
declare void @free(i8*)
declare void @memset(i8*, i32, i64)
declare void @memcpy(i8*, i8*, i64)

; MAIA-300 hardware constants for webtransport_service
@maia300.n_qubits = constant i32 300
@maia300.connectivity = constant i32 6
@maia300.t1_us = constant double 1000.0
@maia300.t2_us = constant double 500.0
@maia300.gate_fidelity = constant double 0.9995
@maia300.readout_fidelity = constant double 0.999
@maia300.gate_time_ns = constant double 50.0
@maia300.temperature_mk = constant double 15.0
@maia300.error_rate = constant double 0.001
@maia300.coherence = constant double 0.99

; ============================================================
; SteaneCode [[7,1,3]] quantum error correcting code
; ============================================================
@SteaneCode.n_physical = constant i32 7
@SteaneCode.n_logical = constant i32 1
@SteaneCode.distance = constant i32 3
@SteaneCode.threshold = constant double 0.01
@SteaneCode.overhead = constant i32 7

@SteaneCode.Xstab.0 = constant [7 x i1] [i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0]
@SteaneCode.Xstab.1 = constant [7 x i1] [i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1]
@SteaneCode.Xstab.2 = constant [7 x i1] [i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0]
@SteaneCode.Xstab.3 = constant [7 x i1] [i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1]
@SteaneCode.Xstab.4 = constant [7 x i1] [i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0]
@SteaneCode.Xstab.5 = constant [7 x i1] [i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1]
@SteaneCode.Zstab.0 = constant [7 x i1] [i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1]
@SteaneCode.Zstab.1 = constant [7 x i1] [i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0]
@SteaneCode.Zstab.2 = constant [7 x i1] [i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1]
@SteaneCode.Zstab.3 = constant [7 x i1] [i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0]
@SteaneCode.Zstab.4 = constant [7 x i1] [i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1]
@SteaneCode.Zstab.5 = constant [7 x i1] [i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0]

define void @SteaneCode.encode(%Array* %qubits, %Qubit* %logical_in) {
entry:
  %n = call i64 @__quantum__rt__array_get_size_1d(%Array* %qubits)
  br label %init_loop
init_loop:
  %i = phi i64 [ 0, %entry ], [ %i_next, %init_loop ]
  %qp = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 %i)
  %qq = load %Qubit*, %Qubit** (bitcast i8* %qp to %Qubit**)
  call void @__quantum__qis__reset__body(%Qubit* %qq)
  %i_next = add i64 %i, 1
  %done = icmp eq i64 %i_next, %n
  br i1 %done, label %encode_body, label %init_loop
encode_body:
  %q0p = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 0)
  %q0 = load %Qubit*, %Qubit** (bitcast i8* %q0p to %Qubit**)
  call void @__quantum__qis__h__body(%Qubit* %q0)
  %q1p = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 1)
  %q1 = load %Qubit*, %Qubit** (bitcast i8* %q1p to %Qubit**)
  call void @__quantum__qis__cx__body(%Qubit* %q0, %Qubit* %q1)
  %q2p = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 2)
  %q2 = load %Qubit*, %Qubit** (bitcast i8* %q2p to %Qubit**)
  call void @__quantum__qis__cx__body(%Qubit* %q0, %Qubit* %q2)
  %q3p = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 3)
  %q3 = load %Qubit*, %Qubit** (bitcast i8* %q3p to %Qubit**)
  call void @__quantum__qis__cx__body(%Qubit* %q0, %Qubit* %q3)
  ret void
}

define %ErrorSyndrome* @SteaneCode.measure_syndrome(%Array* %qubits) {
entry:
  %syn_mem = call i8* @malloc(i64 24)
  %syn = bitcast i8* %syn_mem to %ErrorSyndrome*
  %xs = alloca i64
  store i64 0, i64* %xs
  %ax0 = call %Qubit* @__quantum__rt__qubit_allocate()
  call void @__quantum__qis__h__body(%Qubit* %ax0)
  %xqp0 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 0)
  %xq0 = load %Qubit*, %Qubit** (bitcast i8* %xqp0 to %Qubit**)
  call void @__quantum__qis__cx__body(%Qubit* %ax0, %Qubit* %xq0)
  call void @__quantum__qis__h__body(%Qubit* %ax0)
  %rx0 = call %Result* @__quantum__qis__mresetz__body(%Qubit* %ax0)
  %ox0 = call %Result* @__quantum__rt__result_get_one()
  %ix0 = call i1 @__quantum__rt__result_equal(%Result* %rx0, %Result* %ox0)
  %bx0 = zext i1 %ix0 to i64
  %sx0 = shl i64 %bx0, 0
  %cx0 = load i64, i64* %xs
  %nx0 = or i64 %cx0, %sx0
  store i64 %nx0, i64* %xs
  call void @__quantum__rt__qubit_release(%Qubit* %ax0)
  %ax1 = call %Qubit* @__quantum__rt__qubit_allocate()
  call void @__quantum__qis__h__body(%Qubit* %ax1)
  %xqp1 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 1)
  %xq1 = load %Qubit*, %Qubit** (bitcast i8* %xqp1 to %Qubit**)
  call void @__quantum__qis__cx__body(%Qubit* %ax1, %Qubit* %xq1)
  call void @__quantum__qis__h__body(%Qubit* %ax1)
  %rx1 = call %Result* @__quantum__qis__mresetz__body(%Qubit* %ax1)
  %ox1 = call %Result* @__quantum__rt__result_get_one()
  %ix1 = call i1 @__quantum__rt__result_equal(%Result* %rx1, %Result* %ox1)
  %bx1 = zext i1 %ix1 to i64
  %sx1 = shl i64 %bx1, 1
  %cx1 = load i64, i64* %xs
  %nx1 = or i64 %cx1, %sx1
  store i64 %nx1, i64* %xs
  call void @__quantum__rt__qubit_release(%Qubit* %ax1)
  %ax2 = call %Qubit* @__quantum__rt__qubit_allocate()
  call void @__quantum__qis__h__body(%Qubit* %ax2)
  %xqp2 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 2)
  %xq2 = load %Qubit*, %Qubit** (bitcast i8* %xqp2 to %Qubit**)
  call void @__quantum__qis__cx__body(%Qubit* %ax2, %Qubit* %xq2)
  call void @__quantum__qis__h__body(%Qubit* %ax2)
  %rx2 = call %Result* @__quantum__qis__mresetz__body(%Qubit* %ax2)
  %ox2 = call %Result* @__quantum__rt__result_get_one()
  %ix2 = call i1 @__quantum__rt__result_equal(%Result* %rx2, %Result* %ox2)
  %bx2 = zext i1 %ix2 to i64
  %sx2 = shl i64 %bx2, 2
  %cx2 = load i64, i64* %xs
  %nx2 = or i64 %cx2, %sx2
  store i64 %nx2, i64* %xs
  call void @__quantum__rt__qubit_release(%Qubit* %ax2)
  %fxs = load i64, i64* %xs
  %xf = getelementptr %ErrorSyndrome, %ErrorSyndrome* %syn, i32 0, i32 0
  store i64 %fxs, i64* %xf
  %zs = alloca i64
  store i64 0, i64* %zs
  %az0 = call %Qubit* @__quantum__rt__qubit_allocate()
  %zqp0 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 0)
  %zq0 = load %Qubit*, %Qubit** (bitcast i8* %zqp0 to %Qubit**)
  call void @__quantum__qis__cx__body(%Qubit* %zq0, %Qubit* %az0)
  %rz0 = call %Result* @__quantum__qis__mresetz__body(%Qubit* %az0)
  %oz0 = call %Result* @__quantum__rt__result_get_one()
  %iz0 = call i1 @__quantum__rt__result_equal(%Result* %rz0, %Result* %oz0)
  %bz0 = zext i1 %iz0 to i64
  %sz0 = shl i64 %bz0, 0
  %cz0 = load i64, i64* %zs
  %nz0 = or i64 %cz0, %sz0
  store i64 %nz0, i64* %zs
  call void @__quantum__rt__qubit_release(%Qubit* %az0)
  %az1 = call %Qubit* @__quantum__rt__qubit_allocate()
  %zqp1 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 1)
  %zq1 = load %Qubit*, %Qubit** (bitcast i8* %zqp1 to %Qubit**)
  call void @__quantum__qis__cx__body(%Qubit* %zq1, %Qubit* %az1)
  %rz1 = call %Result* @__quantum__qis__mresetz__body(%Qubit* %az1)
  %oz1 = call %Result* @__quantum__rt__result_get_one()
  %iz1 = call i1 @__quantum__rt__result_equal(%Result* %rz1, %Result* %oz1)
  %bz1 = zext i1 %iz1 to i64
  %sz1 = shl i64 %bz1, 1
  %cz1 = load i64, i64* %zs
  %nz1 = or i64 %cz1, %sz1
  store i64 %nz1, i64* %zs
  call void @__quantum__rt__qubit_release(%Qubit* %az1)
  %az2 = call %Qubit* @__quantum__rt__qubit_allocate()
  %zqp2 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 2)
  %zq2 = load %Qubit*, %Qubit** (bitcast i8* %zqp2 to %Qubit**)
  call void @__quantum__qis__cx__body(%Qubit* %zq2, %Qubit* %az2)
  %rz2 = call %Result* @__quantum__qis__mresetz__body(%Qubit* %az2)
  %oz2 = call %Result* @__quantum__rt__result_get_one()
  %iz2 = call i1 @__quantum__rt__result_equal(%Result* %rz2, %Result* %oz2)
  %bz2 = zext i1 %iz2 to i64
  %sz2 = shl i64 %bz2, 2
  %cz2 = load i64, i64* %zs
  %nz2 = or i64 %cz2, %sz2
  store i64 %nz2, i64* %zs
  call void @__quantum__rt__qubit_release(%Qubit* %az2)
  %fzs = load i64, i64* %zs
  %zf = getelementptr %ErrorSyndrome, %ErrorSyndrome* %syn, i32 0, i32 1
  store i64 %fzs, i64* %zf
  %ff = getelementptr %ErrorSyndrome, %ErrorSyndrome* %syn, i32 0, i32 2
  store double 0.999, double* %ff
  ret %ErrorSyndrome* %syn
}

define void @SteaneCode.correct(%Array* %qubits, %ErrorSyndrome* %syn) {
entry:
  %xf2 = getelementptr %ErrorSyndrome, %ErrorSyndrome* %syn, i32 0, i32 0
  %zf2 = getelementptr %ErrorSyndrome, %ErrorSyndrome* %syn, i32 0, i32 1
  %xv = load i64, i64* %xf2
  %zv = load i64, i64* %zf2
  %xnz = icmp ne i64 %xv, 0
  %znz = icmp ne i64 %zv, 0
  br i1 %xnz, label %xcorr, label %zcheck
xcorr:
  %xidx = and i64 %xv, 7
  %xcp = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 %xidx)
  %xcq = load %Qubit*, %Qubit** (bitcast i8* %xcp to %Qubit**)
  call void @__quantum__qis__z__body(%Qubit* %xcq)
  br label %zcheck
zcheck:
  br i1 %znz, label %zcorr, label %done
zcorr:
  %zidx = and i64 %zv, 7
  %zcp = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 %zidx)
  %zcq = load %Qubit*, %Qubit** (bitcast i8* %zcp to %Qubit**)
  call void @__quantum__qis__x__body(%Qubit* %zcq)
  br label %done
done:
  ret void
}

; ============================================================
; SurfaceCode [[17,1,3]] quantum error correcting code
; ============================================================
@SurfaceCode.n_physical = constant i32 17
@SurfaceCode.n_logical = constant i32 1
@SurfaceCode.distance = constant i32 3
@SurfaceCode.threshold = constant double 0.01
@SurfaceCode.overhead = constant i32 17

@SurfaceCode.Xstab.0 = constant [17 x i1] [i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0]
@SurfaceCode.Xstab.1 = constant [17 x i1] [i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1]
@SurfaceCode.Xstab.2 = constant [17 x i1] [i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0]
@SurfaceCode.Xstab.3 = constant [17 x i1] [i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1]
@SurfaceCode.Xstab.4 = constant [17 x i1] [i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0]
@SurfaceCode.Xstab.5 = constant [17 x i1] [i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1]
@SurfaceCode.Xstab.6 = constant [17 x i1] [i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0]
@SurfaceCode.Xstab.7 = constant [17 x i1] [i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1]
@SurfaceCode.Xstab.8 = constant [17 x i1] [i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0]
@SurfaceCode.Xstab.9 = constant [17 x i1] [i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1]
@SurfaceCode.Xstab.10 = constant [17 x i1] [i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0]
@SurfaceCode.Xstab.11 = constant [17 x i1] [i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1]
@SurfaceCode.Xstab.12 = constant [17 x i1] [i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0]
@SurfaceCode.Xstab.13 = constant [17 x i1] [i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1]
@SurfaceCode.Xstab.14 = constant [17 x i1] [i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0]
@SurfaceCode.Xstab.15 = constant [17 x i1] [i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1]
@SurfaceCode.Zstab.0 = constant [17 x i1] [i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1]
@SurfaceCode.Zstab.1 = constant [17 x i1] [i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0]
@SurfaceCode.Zstab.2 = constant [17 x i1] [i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1]
@SurfaceCode.Zstab.3 = constant [17 x i1] [i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0]
@SurfaceCode.Zstab.4 = constant [17 x i1] [i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1]
@SurfaceCode.Zstab.5 = constant [17 x i1] [i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0]
@SurfaceCode.Zstab.6 = constant [17 x i1] [i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1]
@SurfaceCode.Zstab.7 = constant [17 x i1] [i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0]
@SurfaceCode.Zstab.8 = constant [17 x i1] [i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1]
@SurfaceCode.Zstab.9 = constant [17 x i1] [i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0]
@SurfaceCode.Zstab.10 = constant [17 x i1] [i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1]
@SurfaceCode.Zstab.11 = constant [17 x i1] [i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0]
@SurfaceCode.Zstab.12 = constant [17 x i1] [i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1]
@SurfaceCode.Zstab.13 = constant [17 x i1] [i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0]
@SurfaceCode.Zstab.14 = constant [17 x i1] [i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1]
@SurfaceCode.Zstab.15 = constant [17 x i1] [i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0]

define void @SurfaceCode.encode(%Array* %qubits, %Qubit* %logical_in) {
entry:
  %n = call i64 @__quantum__rt__array_get_size_1d(%Array* %qubits)
  br label %init_loop
init_loop:
  %i = phi i64 [ 0, %entry ], [ %i_next, %init_loop ]
  %qp = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 %i)
  %qq = load %Qubit*, %Qubit** (bitcast i8* %qp to %Qubit**)
  call void @__quantum__qis__reset__body(%Qubit* %qq)
  %i_next = add i64 %i, 1
  %done = icmp eq i64 %i_next, %n
  br i1 %done, label %encode_body, label %init_loop
encode_body:
  %q0p = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 0)
  %q0 = load %Qubit*, %Qubit** (bitcast i8* %q0p to %Qubit**)
  call void @__quantum__qis__h__body(%Qubit* %q0)
  %q1p = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 1)
  %q1 = load %Qubit*, %Qubit** (bitcast i8* %q1p to %Qubit**)
  call void @__quantum__qis__cx__body(%Qubit* %q0, %Qubit* %q1)
  %q2p = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 2)
  %q2 = load %Qubit*, %Qubit** (bitcast i8* %q2p to %Qubit**)
  call void @__quantum__qis__cx__body(%Qubit* %q0, %Qubit* %q2)
  %q3p = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 3)
  %q3 = load %Qubit*, %Qubit** (bitcast i8* %q3p to %Qubit**)
  call void @__quantum__qis__cx__body(%Qubit* %q0, %Qubit* %q3)
  ret void
}

define %ErrorSyndrome* @SurfaceCode.measure_syndrome(%Array* %qubits) {
entry:
  %syn_mem = call i8* @malloc(i64 24)
  %syn = bitcast i8* %syn_mem to %ErrorSyndrome*
  %xs = alloca i64
  store i64 0, i64* %xs
  %ax0 = call %Qubit* @__quantum__rt__qubit_allocate()
  call void @__quantum__qis__h__body(%Qubit* %ax0)
  %xqp0 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 0)
  %xq0 = load %Qubit*, %Qubit** (bitcast i8* %xqp0 to %Qubit**)
  call void @__quantum__qis__cx__body(%Qubit* %ax0, %Qubit* %xq0)
  call void @__quantum__qis__h__body(%Qubit* %ax0)
  %rx0 = call %Result* @__quantum__qis__mresetz__body(%Qubit* %ax0)
  %ox0 = call %Result* @__quantum__rt__result_get_one()
  %ix0 = call i1 @__quantum__rt__result_equal(%Result* %rx0, %Result* %ox0)
  %bx0 = zext i1 %ix0 to i64
  %sx0 = shl i64 %bx0, 0
  %cx0 = load i64, i64* %xs
  %nx0 = or i64 %cx0, %sx0
  store i64 %nx0, i64* %xs
  call void @__quantum__rt__qubit_release(%Qubit* %ax0)
  %ax1 = call %Qubit* @__quantum__rt__qubit_allocate()
  call void @__quantum__qis__h__body(%Qubit* %ax1)
  %xqp1 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 1)
  %xq1 = load %Qubit*, %Qubit** (bitcast i8* %xqp1 to %Qubit**)
  call void @__quantum__qis__cx__body(%Qubit* %ax1, %Qubit* %xq1)
  call void @__quantum__qis__h__body(%Qubit* %ax1)
  %rx1 = call %Result* @__quantum__qis__mresetz__body(%Qubit* %ax1)
  %ox1 = call %Result* @__quantum__rt__result_get_one()
  %ix1 = call i1 @__quantum__rt__result_equal(%Result* %rx1, %Result* %ox1)
  %bx1 = zext i1 %ix1 to i64
  %sx1 = shl i64 %bx1, 1
  %cx1 = load i64, i64* %xs
  %nx1 = or i64 %cx1, %sx1
  store i64 %nx1, i64* %xs
  call void @__quantum__rt__qubit_release(%Qubit* %ax1)
  %ax2 = call %Qubit* @__quantum__rt__qubit_allocate()
  call void @__quantum__qis__h__body(%Qubit* %ax2)
  %xqp2 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 2)
  %xq2 = load %Qubit*, %Qubit** (bitcast i8* %xqp2 to %Qubit**)
  call void @__quantum__qis__cx__body(%Qubit* %ax2, %Qubit* %xq2)
  call void @__quantum__qis__h__body(%Qubit* %ax2)
  %rx2 = call %Result* @__quantum__qis__mresetz__body(%Qubit* %ax2)
  %ox2 = call %Result* @__quantum__rt__result_get_one()
  %ix2 = call i1 @__quantum__rt__result_equal(%Result* %rx2, %Result* %ox2)
  %bx2 = zext i1 %ix2 to i64
  %sx2 = shl i64 %bx2, 2
  %cx2 = load i64, i64* %xs
  %nx2 = or i64 %cx2, %sx2
  store i64 %nx2, i64* %xs
  call void @__quantum__rt__qubit_release(%Qubit* %ax2)
  %fxs = load i64, i64* %xs
  %xf = getelementptr %ErrorSyndrome, %ErrorSyndrome* %syn, i32 0, i32 0
  store i64 %fxs, i64* %xf
  %zs = alloca i64
  store i64 0, i64* %zs
  %az0 = call %Qubit* @__quantum__rt__qubit_allocate()
  %zqp0 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 0)
  %zq0 = load %Qubit*, %Qubit** (bitcast i8* %zqp0 to %Qubit**)
  call void @__quantum__qis__cx__body(%Qubit* %zq0, %Qubit* %az0)
  %rz0 = call %Result* @__quantum__qis__mresetz__body(%Qubit* %az0)
  %oz0 = call %Result* @__quantum__rt__result_get_one()
  %iz0 = call i1 @__quantum__rt__result_equal(%Result* %rz0, %Result* %oz0)
  %bz0 = zext i1 %iz0 to i64
  %sz0 = shl i64 %bz0, 0
  %cz0 = load i64, i64* %zs
  %nz0 = or i64 %cz0, %sz0
  store i64 %nz0, i64* %zs
  call void @__quantum__rt__qubit_release(%Qubit* %az0)
  %az1 = call %Qubit* @__quantum__rt__qubit_allocate()
  %zqp1 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 1)
  %zq1 = load %Qubit*, %Qubit** (bitcast i8* %zqp1 to %Qubit**)
  call void @__quantum__qis__cx__body(%Qubit* %zq1, %Qubit* %az1)
  %rz1 = call %Result* @__quantum__qis__mresetz__body(%Qubit* %az1)
  %oz1 = call %Result* @__quantum__rt__result_get_one()
  %iz1 = call i1 @__quantum__rt__result_equal(%Result* %rz1, %Result* %oz1)
  %bz1 = zext i1 %iz1 to i64
  %sz1 = shl i64 %bz1, 1
  %cz1 = load i64, i64* %zs
  %nz1 = or i64 %cz1, %sz1
  store i64 %nz1, i64* %zs
  call void @__quantum__rt__qubit_release(%Qubit* %az1)
  %az2 = call %Qubit* @__quantum__rt__qubit_allocate()
  %zqp2 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 2)
  %zq2 = load %Qubit*, %Qubit** (bitcast i8* %zqp2 to %Qubit**)
  call void @__quantum__qis__cx__body(%Qubit* %zq2, %Qubit* %az2)
  %rz2 = call %Result* @__quantum__qis__mresetz__body(%Qubit* %az2)
  %oz2 = call %Result* @__quantum__rt__result_get_one()
  %iz2 = call i1 @__quantum__rt__result_equal(%Result* %rz2, %Result* %oz2)
  %bz2 = zext i1 %iz2 to i64
  %sz2 = shl i64 %bz2, 2
  %cz2 = load i64, i64* %zs
  %nz2 = or i64 %cz2, %sz2
  store i64 %nz2, i64* %zs
  call void @__quantum__rt__qubit_release(%Qubit* %az2)
  %fzs = load i64, i64* %zs
  %zf = getelementptr %ErrorSyndrome, %ErrorSyndrome* %syn, i32 0, i32 1
  store i64 %fzs, i64* %zf
  %ff = getelementptr %ErrorSyndrome, %ErrorSyndrome* %syn, i32 0, i32 2
  store double 0.999, double* %ff
  ret %ErrorSyndrome* %syn
}

define void @SurfaceCode.correct(%Array* %qubits, %ErrorSyndrome* %syn) {
entry:
  %xf2 = getelementptr %ErrorSyndrome, %ErrorSyndrome* %syn, i32 0, i32 0
  %zf2 = getelementptr %ErrorSyndrome, %ErrorSyndrome* %syn, i32 0, i32 1
  %xv = load i64, i64* %xf2
  %zv = load i64, i64* %zf2
  %xnz = icmp ne i64 %xv, 0
  %znz = icmp ne i64 %zv, 0
  br i1 %xnz, label %xcorr, label %zcheck
xcorr:
  %xidx = and i64 %xv, 7
  %xcp = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 %xidx)
  %xcq = load %Qubit*, %Qubit** (bitcast i8* %xcp to %Qubit**)
  call void @__quantum__qis__z__body(%Qubit* %xcq)
  br label %zcheck
zcheck:
  br i1 %znz, label %zcorr, label %done
zcorr:
  %zidx = and i64 %zv, 7
  %zcp = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 %zidx)
  %zcq = load %Qubit*, %Qubit** (bitcast i8* %zcp to %Qubit**)
  call void @__quantum__qis__x__body(%Qubit* %zcq)
  br label %done
done:
  ret void
}

; ============================================================
; ColorCode [[12,1,3]] quantum error correcting code
; ============================================================
@ColorCode.n_physical = constant i32 12
@ColorCode.n_logical = constant i32 1
@ColorCode.distance = constant i32 3
@ColorCode.threshold = constant double 0.01
@ColorCode.overhead = constant i32 12

@ColorCode.Xstab.0 = constant [12 x i1] [i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1]
@ColorCode.Xstab.1 = constant [12 x i1] [i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0]
@ColorCode.Xstab.2 = constant [12 x i1] [i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1]
@ColorCode.Xstab.3 = constant [12 x i1] [i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0]
@ColorCode.Xstab.4 = constant [12 x i1] [i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1]
@ColorCode.Xstab.5 = constant [12 x i1] [i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0]
@ColorCode.Xstab.6 = constant [12 x i1] [i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1]
@ColorCode.Xstab.7 = constant [12 x i1] [i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0]
@ColorCode.Xstab.8 = constant [12 x i1] [i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1]
@ColorCode.Xstab.9 = constant [12 x i1] [i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0]
@ColorCode.Xstab.10 = constant [12 x i1] [i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1]
@ColorCode.Zstab.0 = constant [12 x i1] [i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0]
@ColorCode.Zstab.1 = constant [12 x i1] [i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1]
@ColorCode.Zstab.2 = constant [12 x i1] [i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0]
@ColorCode.Zstab.3 = constant [12 x i1] [i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1]
@ColorCode.Zstab.4 = constant [12 x i1] [i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0]
@ColorCode.Zstab.5 = constant [12 x i1] [i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1]
@ColorCode.Zstab.6 = constant [12 x i1] [i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0]
@ColorCode.Zstab.7 = constant [12 x i1] [i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1]
@ColorCode.Zstab.8 = constant [12 x i1] [i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0]
@ColorCode.Zstab.9 = constant [12 x i1] [i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1]
@ColorCode.Zstab.10 = constant [12 x i1] [i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0,i1 1,i1 0]

define void @ColorCode.encode(%Array* %qubits, %Qubit* %logical_in) {
entry:
  %n = call i64 @__quantum__rt__array_get_size_1d(%Array* %qubits)
  br label %init_loop
init_loop:
  %i = phi i64 [ 0, %entry ], [ %i_next, %init_loop ]
  %qp = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 %i)
  %qq = load %Qubit*, %Qubit** (bitcast i8* %qp to %Qubit**)
  call void @__quantum__qis__reset__body(%Qubit* %qq)
  %i_next = add i64 %i, 1
  %done = icmp eq i64 %i_next, %n
  br i1 %done, label %encode_body, label %init_loop
encode_body:
  %q0p = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 0)
  %q0 = load %Qubit*, %Qubit** (bitcast i8* %q0p to %Qubit**)
  call void @__quantum__qis__h__body(%Qubit* %q0)
  %q1p = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 1)
  %q1 = load %Qubit*, %Qubit** (bitcast i8* %q1p to %Qubit**)
  call void @__quantum__qis__cx__body(%Qubit* %q0, %Qubit* %q1)
  %q2p = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 2)
  %q2 = load %Qubit*, %Qubit** (bitcast i8* %q2p to %Qubit**)
  call void @__quantum__qis__cx__body(%Qubit* %q0, %Qubit* %q2)
  %q3p = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 3)
  %q3 = load %Qubit*, %Qubit** (bitcast i8* %q3p to %Qubit**)
  call void @__quantum__qis__cx__body(%Qubit* %q0, %Qubit* %q3)
  ret void
}

define %ErrorSyndrome* @ColorCode.measure_syndrome(%Array* %qubits) {
entry:
  %syn_mem = call i8* @malloc(i64 24)
  %syn = bitcast i8* %syn_mem to %ErrorSyndrome*
  %xs = alloca i64
  store i64 0, i64* %xs
  %ax0 = call %Qubit* @__quantum__rt__qubit_allocate()
  call void @__quantum__qis__h__body(%Qubit* %ax0)
  %xqp0 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 0)
  %xq0 = load %Qubit*, %Qubit** (bitcast i8* %xqp0 to %Qubit**)
  call void @__quantum__qis__cx__body(%Qubit* %ax0, %Qubit* %xq0)
  call void @__quantum__qis__h__body(%Qubit* %ax0)
  %rx0 = call %Result* @__quantum__qis__mresetz__body(%Qubit* %ax0)
  %ox0 = call %Result* @__quantum__rt__result_get_one()
  %ix0 = call i1 @__quantum__rt__result_equal(%Result* %rx0, %Result* %ox0)
  %bx0 = zext i1 %ix0 to i64
  %sx0 = shl i64 %bx0, 0
  %cx0 = load i64, i64* %xs
  %nx0 = or i64 %cx0, %sx0
  store i64 %nx0, i64* %xs
  call void @__quantum__rt__qubit_release(%Qubit* %ax0)
  %ax1 = call %Qubit* @__quantum__rt__qubit_allocate()
  call void @__quantum__qis__h__body(%Qubit* %ax1)
  %xqp1 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 1)
  %xq1 = load %Qubit*, %Qubit** (bitcast i8* %xqp1 to %Qubit**)
  call void @__quantum__qis__cx__body(%Qubit* %ax1, %Qubit* %xq1)
  call void @__quantum__qis__h__body(%Qubit* %ax1)
  %rx1 = call %Result* @__quantum__qis__mresetz__body(%Qubit* %ax1)
  %ox1 = call %Result* @__quantum__rt__result_get_one()
  %ix1 = call i1 @__quantum__rt__result_equal(%Result* %rx1, %Result* %ox1)
  %bx1 = zext i1 %ix1 to i64
  %sx1 = shl i64 %bx1, 1
  %cx1 = load i64, i64* %xs
  %nx1 = or i64 %cx1, %sx1
  store i64 %nx1, i64* %xs
  call void @__quantum__rt__qubit_release(%Qubit* %ax1)
  %ax2 = call %Qubit* @__quantum__rt__qubit_allocate()
  call void @__quantum__qis__h__body(%Qubit* %ax2)
  %xqp2 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 2)
  %xq2 = load %Qubit*, %Qubit** (bitcast i8* %xqp2 to %Qubit**)
  call void @__quantum__qis__cx__body(%Qubit* %ax2, %Qubit* %xq2)
  call void @__quantum__qis__h__body(%Qubit* %ax2)
  %rx2 = call %Result* @__quantum__qis__mresetz__body(%Qubit* %ax2)
  %ox2 = call %Result* @__quantum__rt__result_get_one()
  %ix2 = call i1 @__quantum__rt__result_equal(%Result* %rx2, %Result* %ox2)
  %bx2 = zext i1 %ix2 to i64
  %sx2 = shl i64 %bx2, 2
  %cx2 = load i64, i64* %xs
  %nx2 = or i64 %cx2, %sx2
  store i64 %nx2, i64* %xs
  call void @__quantum__rt__qubit_release(%Qubit* %ax2)
  %fxs = load i64, i64* %xs
  %xf = getelementptr %ErrorSyndrome, %ErrorSyndrome* %syn, i32 0, i32 0
  store i64 %fxs, i64* %xf
  %zs = alloca i64
  store i64 0, i64* %zs
  %az0 = call %Qubit* @__quantum__rt__qubit_allocate()
  %zqp0 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 0)
  %zq0 = load %Qubit*, %Qubit** (bitcast i8* %zqp0 to %Qubit**)
  call void @__quantum__qis__cx__body(%Qubit* %zq0, %Qubit* %az0)
  %rz0 = call %Result* @__quantum__qis__mresetz__body(%Qubit* %az0)
  %oz0 = call %Result* @__quantum__rt__result_get_one()
  %iz0 = call i1 @__quantum__rt__result_equal(%Result* %rz0, %Result* %oz0)
  %bz0 = zext i1 %iz0 to i64
  %sz0 = shl i64 %bz0, 0
  %cz0 = load i64, i64* %zs
  %nz0 = or i64 %cz0, %sz0
  store i64 %nz0, i64* %zs
  call void @__quantum__rt__qubit_release(%Qubit* %az0)
  %az1 = call %Qubit* @__quantum__rt__qubit_allocate()
  %zqp1 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 1)
  %zq1 = load %Qubit*, %Qubit** (bitcast i8* %zqp1 to %Qubit**)
  call void @__quantum__qis__cx__body(%Qubit* %zq1, %Qubit* %az1)
  %rz1 = call %Result* @__quantum__qis__mresetz__body(%Qubit* %az1)
  %oz1 = call %Result* @__quantum__rt__result_get_one()
  %iz1 = call i1 @__quantum__rt__result_equal(%Result* %rz1, %Result* %oz1)
  %bz1 = zext i1 %iz1 to i64
  %sz1 = shl i64 %bz1, 1
  %cz1 = load i64, i64* %zs
  %nz1 = or i64 %cz1, %sz1
  store i64 %nz1, i64* %zs
  call void @__quantum__rt__qubit_release(%Qubit* %az1)
  %az2 = call %Qubit* @__quantum__rt__qubit_allocate()
  %zqp2 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 2)
  %zq2 = load %Qubit*, %Qubit** (bitcast i8* %zqp2 to %Qubit**)
  call void @__quantum__qis__cx__body(%Qubit* %zq2, %Qubit* %az2)
  %rz2 = call %Result* @__quantum__qis__mresetz__body(%Qubit* %az2)
  %oz2 = call %Result* @__quantum__rt__result_get_one()
  %iz2 = call i1 @__quantum__rt__result_equal(%Result* %rz2, %Result* %oz2)
  %bz2 = zext i1 %iz2 to i64
  %sz2 = shl i64 %bz2, 2
  %cz2 = load i64, i64* %zs
  %nz2 = or i64 %cz2, %sz2
  store i64 %nz2, i64* %zs
  call void @__quantum__rt__qubit_release(%Qubit* %az2)
  %fzs = load i64, i64* %zs
  %zf = getelementptr %ErrorSyndrome, %ErrorSyndrome* %syn, i32 0, i32 1
  store i64 %fzs, i64* %zf
  %ff = getelementptr %ErrorSyndrome, %ErrorSyndrome* %syn, i32 0, i32 2
  store double 0.999, double* %ff
  ret %ErrorSyndrome* %syn
}

define void @ColorCode.correct(%Array* %qubits, %ErrorSyndrome* %syn) {
entry:
  %xf2 = getelementptr %ErrorSyndrome, %ErrorSyndrome* %syn, i32 0, i32 0
  %zf2 = getelementptr %ErrorSyndrome, %ErrorSyndrome* %syn, i32 0, i32 1
  %xv = load i64, i64* %xf2
  %zv = load i64, i64* %zf2
  %xnz = icmp ne i64 %xv, 0
  %znz = icmp ne i64 %zv, 0
  br i1 %xnz, label %xcorr, label %zcheck
xcorr:
  %xidx = and i64 %xv, 7
  %xcp = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 %xidx)
  %xcq = load %Qubit*, %Qubit** (bitcast i8* %xcp to %Qubit**)
  call void @__quantum__qis__z__body(%Qubit* %xcq)
  br label %zcheck
zcheck:
  br i1 %znz, label %zcorr, label %done
zcorr:
  %zidx = and i64 %zv, 7
  %zcp = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 %zidx)
  %zcq = load %Qubit*, %Qubit** (bitcast i8* %zcp to %Qubit**)
  call void @__quantum__qis__x__body(%Qubit* %zcq)
  br label %done
done:
  ret void
}

; ============================================================
; RepetitionCode [[3,1,3]] quantum error correcting code
; ============================================================
@RepetitionCode.n_physical = constant i32 3
@RepetitionCode.n_logical = constant i32 1
@RepetitionCode.distance = constant i32 3
@RepetitionCode.threshold = constant double 0.01
@RepetitionCode.overhead = constant i32 3

@RepetitionCode.Xstab.0 = constant [3 x i1] [i1 0,i1 1,i1 0]
@RepetitionCode.Xstab.1 = constant [3 x i1] [i1 1,i1 0,i1 1]
@RepetitionCode.Zstab.0 = constant [3 x i1] [i1 1,i1 0,i1 1]
@RepetitionCode.Zstab.1 = constant [3 x i1] [i1 0,i1 1,i1 0]

define void @RepetitionCode.encode(%Array* %qubits, %Qubit* %logical_in) {
entry:
  %n = call i64 @__quantum__rt__array_get_size_1d(%Array* %qubits)
  br label %init_loop
init_loop:
  %i = phi i64 [ 0, %entry ], [ %i_next, %init_loop ]
  %qp = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 %i)
  %qq = load %Qubit*, %Qubit** (bitcast i8* %qp to %Qubit**)
  call void @__quantum__qis__reset__body(%Qubit* %qq)
  %i_next = add i64 %i, 1
  %done = icmp eq i64 %i_next, %n
  br i1 %done, label %encode_body, label %init_loop
encode_body:
  %q0p = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 0)
  %q0 = load %Qubit*, %Qubit** (bitcast i8* %q0p to %Qubit**)
  call void @__quantum__qis__h__body(%Qubit* %q0)
  %q1p = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 1)
  %q1 = load %Qubit*, %Qubit** (bitcast i8* %q1p to %Qubit**)
  call void @__quantum__qis__cx__body(%Qubit* %q0, %Qubit* %q1)
  %q2p = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 2)
  %q2 = load %Qubit*, %Qubit** (bitcast i8* %q2p to %Qubit**)
  call void @__quantum__qis__cx__body(%Qubit* %q0, %Qubit* %q2)
  ret void
}

define %ErrorSyndrome* @RepetitionCode.measure_syndrome(%Array* %qubits) {
entry:
  %syn_mem = call i8* @malloc(i64 24)
  %syn = bitcast i8* %syn_mem to %ErrorSyndrome*
  %xs = alloca i64
  store i64 0, i64* %xs
  %ax0 = call %Qubit* @__quantum__rt__qubit_allocate()
  call void @__quantum__qis__h__body(%Qubit* %ax0)
  %xqp0 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 0)
  %xq0 = load %Qubit*, %Qubit** (bitcast i8* %xqp0 to %Qubit**)
  call void @__quantum__qis__cx__body(%Qubit* %ax0, %Qubit* %xq0)
  call void @__quantum__qis__h__body(%Qubit* %ax0)
  %rx0 = call %Result* @__quantum__qis__mresetz__body(%Qubit* %ax0)
  %ox0 = call %Result* @__quantum__rt__result_get_one()
  %ix0 = call i1 @__quantum__rt__result_equal(%Result* %rx0, %Result* %ox0)
  %bx0 = zext i1 %ix0 to i64
  %sx0 = shl i64 %bx0, 0
  %cx0 = load i64, i64* %xs
  %nx0 = or i64 %cx0, %sx0
  store i64 %nx0, i64* %xs
  call void @__quantum__rt__qubit_release(%Qubit* %ax0)
  %ax1 = call %Qubit* @__quantum__rt__qubit_allocate()
  call void @__quantum__qis__h__body(%Qubit* %ax1)
  %xqp1 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 1)
  %xq1 = load %Qubit*, %Qubit** (bitcast i8* %xqp1 to %Qubit**)
  call void @__quantum__qis__cx__body(%Qubit* %ax1, %Qubit* %xq1)
  call void @__quantum__qis__h__body(%Qubit* %ax1)
  %rx1 = call %Result* @__quantum__qis__mresetz__body(%Qubit* %ax1)
  %ox1 = call %Result* @__quantum__rt__result_get_one()
  %ix1 = call i1 @__quantum__rt__result_equal(%Result* %rx1, %Result* %ox1)
  %bx1 = zext i1 %ix1 to i64
  %sx1 = shl i64 %bx1, 1
  %cx1 = load i64, i64* %xs
  %nx1 = or i64 %cx1, %sx1
  store i64 %nx1, i64* %xs
  call void @__quantum__rt__qubit_release(%Qubit* %ax1)
  %fxs = load i64, i64* %xs
  %xf = getelementptr %ErrorSyndrome, %ErrorSyndrome* %syn, i32 0, i32 0
  store i64 %fxs, i64* %xf
  %zs = alloca i64
  store i64 0, i64* %zs
  %az0 = call %Qubit* @__quantum__rt__qubit_allocate()
  %zqp0 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 0)
  %zq0 = load %Qubit*, %Qubit** (bitcast i8* %zqp0 to %Qubit**)
  call void @__quantum__qis__cx__body(%Qubit* %zq0, %Qubit* %az0)
  %rz0 = call %Result* @__quantum__qis__mresetz__body(%Qubit* %az0)
  %oz0 = call %Result* @__quantum__rt__result_get_one()
  %iz0 = call i1 @__quantum__rt__result_equal(%Result* %rz0, %Result* %oz0)
  %bz0 = zext i1 %iz0 to i64
  %sz0 = shl i64 %bz0, 0
  %cz0 = load i64, i64* %zs
  %nz0 = or i64 %cz0, %sz0
  store i64 %nz0, i64* %zs
  call void @__quantum__rt__qubit_release(%Qubit* %az0)
  %az1 = call %Qubit* @__quantum__rt__qubit_allocate()
  %zqp1 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 1)
  %zq1 = load %Qubit*, %Qubit** (bitcast i8* %zqp1 to %Qubit**)
  call void @__quantum__qis__cx__body(%Qubit* %zq1, %Qubit* %az1)
  %rz1 = call %Result* @__quantum__qis__mresetz__body(%Qubit* %az1)
  %oz1 = call %Result* @__quantum__rt__result_get_one()
  %iz1 = call i1 @__quantum__rt__result_equal(%Result* %rz1, %Result* %oz1)
  %bz1 = zext i1 %iz1 to i64
  %sz1 = shl i64 %bz1, 1
  %cz1 = load i64, i64* %zs
  %nz1 = or i64 %cz1, %sz1
  store i64 %nz1, i64* %zs
  call void @__quantum__rt__qubit_release(%Qubit* %az1)
  %fzs = load i64, i64* %zs
  %zf = getelementptr %ErrorSyndrome, %ErrorSyndrome* %syn, i32 0, i32 1
  store i64 %fzs, i64* %zf
  %ff = getelementptr %ErrorSyndrome, %ErrorSyndrome* %syn, i32 0, i32 2
  store double 0.999, double* %ff
  ret %ErrorSyndrome* %syn
}

define void @RepetitionCode.correct(%Array* %qubits, %ErrorSyndrome* %syn) {
entry:
  %xf2 = getelementptr %ErrorSyndrome, %ErrorSyndrome* %syn, i32 0, i32 0
  %zf2 = getelementptr %ErrorSyndrome, %ErrorSyndrome* %syn, i32 0, i32 1
  %xv = load i64, i64* %xf2
  %zv = load i64, i64* %zf2
  %xnz = icmp ne i64 %xv, 0
  %znz = icmp ne i64 %zv, 0
  br i1 %xnz, label %xcorr, label %zcheck
xcorr:
  %xidx = and i64 %xv, 7
  %xcp = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 %xidx)
  %xcq = load %Qubit*, %Qubit** (bitcast i8* %xcp to %Qubit**)
  call void @__quantum__qis__z__body(%Qubit* %xcq)
  br label %zcheck
zcheck:
  br i1 %znz, label %zcorr, label %done
zcorr:
  %zidx = and i64 %zv, 7
  %zcp = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 %zidx)
  %zcq = load %Qubit*, %Qubit** (bitcast i8* %zcp to %Qubit**)
  call void @__quantum__qis__x__body(%Qubit* %zcq)
  br label %done
done:
  ret void
}

; ============================================================
; Qubit Mapping and Routing — webtransport_service
; ============================================================

define %QubitMap* @webtransport_service.allocate_qubits(i32 %n_logical) {
entry:
  %sz = mul i32 %n_logical, 4
  %sz64 = zext i32 %sz to i64
  %l2p = call i8* @malloc(i64 %sz64)
  %p2l = call i8* @malloc(i64 1200)
  call void @memset(i8* %p2l, i32 -1, i64 1200)
  %qm = call i8* @malloc(i64 32)
  %qmap = bitcast i8* %qm to %QubitMap*
  %f0 = getelementptr %QubitMap, %QubitMap* %qmap, i32 0, i32 0
  store i32* (bitcast i8* %l2p to i32*), i32** %f0
  %f1 = getelementptr %QubitMap, %QubitMap* %qmap, i32 0, i32 1
  store i32* (bitcast i8* %p2l to i32*), i32** %f1
  %f2 = getelementptr %QubitMap, %QubitMap* %qmap, i32 0, i32 2
  store i32 %n_logical, i32* %f2
  %f3 = getelementptr %QubitMap, %QubitMap* %qmap, i32 0, i32 3
  store i32 300, i32* %f3
  br label %map_loop
map_loop:
  %li = phi i32 [ 0, %entry ], [ %li_next, %map_loop ]
  %lb = load i32*, i32** %f0
  %le = getelementptr i32, i32* %lb, i32 %li
  store i32 %li, i32* %le
  %li_next = add i32 %li, 1
  %map_done = icmp eq i32 %li_next, %n_logical
  br i1 %map_done, label %map_done_label, label %map_loop
map_done_label:
  ret %QubitMap* %qmap
}

; ============================================================
; Quantum circuit 0 for webtransport_service (n_qubits=4)
; ============================================================

define void @webtransport_service.circuit_0(%Array* %qubits, double %theta, double %phi) {
entry:
  %p0_0 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 0)
  %q0_0 = load %Qubit*, %Qubit** (bitcast i8* %p0_0 to %Qubit**)
  %p0_1 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 1)
  %q0_1 = load %Qubit*, %Qubit** (bitcast i8* %p0_1 to %Qubit**)
  %p0_2 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 2)
  %q0_2 = load %Qubit*, %Qubit** (bitcast i8* %p0_2 to %Qubit**)
  %p0_3 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 3)
  %q0_3 = load %Qubit*, %Qubit** (bitcast i8* %p0_3 to %Qubit**)
  call void @__quantum__qis__h__body(%Qubit* %q0_0)
  call void @__quantum__qis__rx__body(double %theta, %Qubit* %q0_0)
  call void @__quantum__qis__cx__body(%Qubit* %q0_0, %Qubit* %q0_1)
  call void @__quantum__qis__ry__body(double %phi, %Qubit* %q0_1)
  call void @__quantum__qis__cx__body(%Qubit* %q0_1, %Qubit* %q0_2)
  call void @__quantum__qis__rz__body(double %theta, %Qubit* %q0_2)
  call void @__quantum__qis__ccx__body(%Qubit* %q0_0, %Qubit* %q0_1, %Qubit* %q0_3)
  call void @__maia__qis__majorana_braid(%Qubit* %q0_0, %Qubit* %q0_1, i32 0)
  ret void
}

define double @webtransport_service.vqe_0(%Array* %qubits, double* %params) {
entry:
  %energy_0 = alloca double
  store double 0.0, double* %energy_0
  %vp0_0 = getelementptr double, double* %params, i32 0
  %vv0_0 = load double, double* %vp0_0
  %vqp0_0 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 0)
  %vq0_0 = load %Qubit*, %Qubit** (bitcast i8* %vqp0_0 to %Qubit**)
  call void @__quantum__qis__ry__body(double %vv0_0, %Qubit* %vq0_0)
  %vp0_1 = getelementptr double, double* %params, i32 1
  %vv0_1 = load double, double* %vp0_1
  %vqp0_1 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 1)
  %vq0_1 = load %Qubit*, %Qubit** (bitcast i8* %vqp0_1 to %Qubit**)
  call void @__quantum__qis__ry__body(double %vv0_1, %Qubit* %vq0_1)
  %vp0_2 = getelementptr double, double* %params, i32 2
  %vv0_2 = load double, double* %vp0_2
  %vqp0_2 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 2)
  %vq0_2 = load %Qubit*, %Qubit** (bitcast i8* %vqp0_2 to %Qubit**)
  call void @__quantum__qis__ry__body(double %vv0_2, %Qubit* %vq0_2)
  %vp0_3 = getelementptr double, double* %params, i32 3
  %vv0_3 = load double, double* %vp0_3
  %vqp0_3 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 3)
  %vq0_3 = load %Qubit*, %Qubit** (bitcast i8* %vqp0_3 to %Qubit**)
  call void @__quantum__qis__ry__body(double %vv0_3, %Qubit* %vq0_3)
  %eq0_0p = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 0)
  %eq0_0 = load %Qubit*, %Qubit** (bitcast i8* %eq0_0p to %Qubit**)
  %eq0_1p = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 1)
  %eq0_1 = load %Qubit*, %Qubit** (bitcast i8* %eq0_1p to %Qubit**)
  call void @__quantum__qis__cx__body(%Qubit* %eq0_0, %Qubit* %eq0_1)
  %eq0_1p = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 1)
  %eq0_1 = load %Qubit*, %Qubit** (bitcast i8* %eq0_1p to %Qubit**)
  %eq0_2p = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 2)
  %eq0_2 = load %Qubit*, %Qubit** (bitcast i8* %eq0_2p to %Qubit**)
  call void @__quantum__qis__cx__body(%Qubit* %eq0_1, %Qubit* %eq0_2)
  %eq0_2p = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 2)
  %eq0_2 = load %Qubit*, %Qubit** (bitcast i8* %eq0_2p to %Qubit**)
  %eq0_3p = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 3)
  %eq0_3 = load %Qubit*, %Qubit** (bitcast i8* %eq0_3p to %Qubit**)
  call void @__quantum__qis__cx__body(%Qubit* %eq0_2, %Qubit* %eq0_3)
  %fe_0 = load double, double* %energy_0
  ret double %fe_0
}

define double @webtransport_service.qfi_0(%Array* %qubits, double* %params, i32 %pidx) {
entry:
  %anc_0 = call %Qubit* @__quantum__rt__qubit_allocate()
  call void @__quantum__qis__h__body(%Qubit* %anc_0)
  %pp_0 = getelementptr double, double* %params, i32 %pidx
  %pv_0 = load double, double* %pp_0
  %qfp_0 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 0)
  %qfq_0 = load %Qubit*, %Qubit** (bitcast i8* %qfp_0 to %Qubit**)
  call void @__quantum__qis__rx__body(double %pv_0, %Qubit* %qfq_0)
  call void @__quantum__qis__h__body(%Qubit* %anc_0)
  %mr_0 = call %Result* @__quantum__qis__mresetz__body(%Qubit* %anc_0)
  %mo_0 = call %Result* @__quantum__rt__result_get_one()
  %mi_0 = call i1 @__quantum__rt__result_equal(%Result* %mr_0, %Result* %mo_0)
  %fv_0 = select i1 %mi_0, double 4.0, double 0.0
  call void @__quantum__rt__qubit_release(%Qubit* %anc_0)
  ret double %fv_0
}

define void @webtransport_service.teleport_0(%Qubit* %src, %Qubit* %ea, %Qubit* %eb, %Qubit* %tgt) {
entry:
  call void @__quantum__qis__h__body(%Qubit* %ea)
  call void @__quantum__qis__cx__body(%Qubit* %ea, %Qubit* %eb)
  call void @__quantum__qis__cx__body(%Qubit* %src, %Qubit* %ea)
  call void @__quantum__qis__h__body(%Qubit* %src)
  %m1_0 = call %Result* @__quantum__qis__mresetz__body(%Qubit* %src)
  %m2_0 = call %Result* @__quantum__qis__mresetz__body(%Qubit* %ea)
  %one_0 = call %Result* @__quantum__rt__result_get_one()
  %m1o_0 = call i1 @__quantum__rt__result_equal(%Result* %m1_0, %Result* %one_0)
  %m2o_0 = call i1 @__quantum__rt__result_equal(%Result* %m2_0, %Result* %one_0)
  br i1 %m2o_0, label %ax_0, label %cz_0
ax_0:
  call void @__quantum__qis__x__body(%Qubit* %tgt)
  br label %cz_0
cz_0:
  br i1 %m1o_0, label %az_0, label %done_0
az_0:
  call void @__quantum__qis__z__body(%Qubit* %tgt)
  br label %done_0
done_0:
  ret void
}

; ============================================================
; Quantum circuit 1 for webtransport_service (n_qubits=6)
; ============================================================

define void @webtransport_service.circuit_1(%Array* %qubits, double %theta, double %phi) {
entry:
  %p1_0 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 0)
  %q1_0 = load %Qubit*, %Qubit** (bitcast i8* %p1_0 to %Qubit**)
  %p1_1 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 1)
  %q1_1 = load %Qubit*, %Qubit** (bitcast i8* %p1_1 to %Qubit**)
  %p1_2 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 2)
  %q1_2 = load %Qubit*, %Qubit** (bitcast i8* %p1_2 to %Qubit**)
  %p1_3 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 3)
  %q1_3 = load %Qubit*, %Qubit** (bitcast i8* %p1_3 to %Qubit**)
  %p1_4 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 4)
  %q1_4 = load %Qubit*, %Qubit** (bitcast i8* %p1_4 to %Qubit**)
  %p1_5 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 5)
  %q1_5 = load %Qubit*, %Qubit** (bitcast i8* %p1_5 to %Qubit**)
  call void @__quantum__qis__h__body(%Qubit* %q1_0)
  call void @__quantum__qis__rx__body(double %theta, %Qubit* %q1_0)
  call void @__quantum__qis__cx__body(%Qubit* %q1_0, %Qubit* %q1_1)
  call void @__quantum__qis__ry__body(double %phi, %Qubit* %q1_1)
  call void @__quantum__qis__cx__body(%Qubit* %q1_1, %Qubit* %q1_2)
  call void @__quantum__qis__rz__body(double %theta, %Qubit* %q1_2)
  call void @__quantum__qis__ccx__body(%Qubit* %q1_0, %Qubit* %q1_1, %Qubit* %q1_3)
  call void @__quantum__qis__swap__body(%Qubit* %q1_2, %Qubit* %q1_4)
  call void @__quantum__qis__cx__body(%Qubit* %q1_3, %Qubit* %q1_5)
  call void @__maia__qis__majorana_braid(%Qubit* %q1_0, %Qubit* %q1_1, i32 1)
  ret void
}

define double @webtransport_service.vqe_1(%Array* %qubits, double* %params) {
entry:
  %energy_1 = alloca double
  store double 0.0, double* %energy_1
  %vp1_0 = getelementptr double, double* %params, i32 0
  %vv1_0 = load double, double* %vp1_0
  %vqp1_0 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 0)
  %vq1_0 = load %Qubit*, %Qubit** (bitcast i8* %vqp1_0 to %Qubit**)
  call void @__quantum__qis__ry__body(double %vv1_0, %Qubit* %vq1_0)
  %vp1_1 = getelementptr double, double* %params, i32 1
  %vv1_1 = load double, double* %vp1_1
  %vqp1_1 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 1)
  %vq1_1 = load %Qubit*, %Qubit** (bitcast i8* %vqp1_1 to %Qubit**)
  call void @__quantum__qis__ry__body(double %vv1_1, %Qubit* %vq1_1)
  %vp1_2 = getelementptr double, double* %params, i32 2
  %vv1_2 = load double, double* %vp1_2
  %vqp1_2 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 2)
  %vq1_2 = load %Qubit*, %Qubit** (bitcast i8* %vqp1_2 to %Qubit**)
  call void @__quantum__qis__ry__body(double %vv1_2, %Qubit* %vq1_2)
  %vp1_3 = getelementptr double, double* %params, i32 3
  %vv1_3 = load double, double* %vp1_3
  %vqp1_3 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 3)
  %vq1_3 = load %Qubit*, %Qubit** (bitcast i8* %vqp1_3 to %Qubit**)
  call void @__quantum__qis__ry__body(double %vv1_3, %Qubit* %vq1_3)
  %eq1_0p = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 0)
  %eq1_0 = load %Qubit*, %Qubit** (bitcast i8* %eq1_0p to %Qubit**)
  %eq1_1p = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 1)
  %eq1_1 = load %Qubit*, %Qubit** (bitcast i8* %eq1_1p to %Qubit**)
  call void @__quantum__qis__cx__body(%Qubit* %eq1_0, %Qubit* %eq1_1)
  %eq1_1p = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 1)
  %eq1_1 = load %Qubit*, %Qubit** (bitcast i8* %eq1_1p to %Qubit**)
  %eq1_2p = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 2)
  %eq1_2 = load %Qubit*, %Qubit** (bitcast i8* %eq1_2p to %Qubit**)
  call void @__quantum__qis__cx__body(%Qubit* %eq1_1, %Qubit* %eq1_2)
  %eq1_2p = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 2)
  %eq1_2 = load %Qubit*, %Qubit** (bitcast i8* %eq1_2p to %Qubit**)
  %eq1_3p = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 3)
  %eq1_3 = load %Qubit*, %Qubit** (bitcast i8* %eq1_3p to %Qubit**)
  call void @__quantum__qis__cx__body(%Qubit* %eq1_2, %Qubit* %eq1_3)
  %fe_1 = load double, double* %energy_1
  ret double %fe_1
}

define double @webtransport_service.qfi_1(%Array* %qubits, double* %params, i32 %pidx) {
entry:
  %anc_1 = call %Qubit* @__quantum__rt__qubit_allocate()
  call void @__quantum__qis__h__body(%Qubit* %anc_1)
  %pp_1 = getelementptr double, double* %params, i32 %pidx
  %pv_1 = load double, double* %pp_1
  %qfp_1 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 0)
  %qfq_1 = load %Qubit*, %Qubit** (bitcast i8* %qfp_1 to %Qubit**)
  call void @__quantum__qis__rx__body(double %pv_1, %Qubit* %qfq_1)
  call void @__quantum__qis__h__body(%Qubit* %anc_1)
  %mr_1 = call %Result* @__quantum__qis__mresetz__body(%Qubit* %anc_1)
  %mo_1 = call %Result* @__quantum__rt__result_get_one()
  %mi_1 = call i1 @__quantum__rt__result_equal(%Result* %mr_1, %Result* %mo_1)
  %fv_1 = select i1 %mi_1, double 4.0, double 0.0
  call void @__quantum__rt__qubit_release(%Qubit* %anc_1)
  ret double %fv_1
}

define void @webtransport_service.teleport_1(%Qubit* %src, %Qubit* %ea, %Qubit* %eb, %Qubit* %tgt) {
entry:
  call void @__quantum__qis__h__body(%Qubit* %ea)
  call void @__quantum__qis__cx__body(%Qubit* %ea, %Qubit* %eb)
  call void @__quantum__qis__cx__body(%Qubit* %src, %Qubit* %ea)
  call void @__quantum__qis__h__body(%Qubit* %src)
  %m1_1 = call %Result* @__quantum__qis__mresetz__body(%Qubit* %src)
  %m2_1 = call %Result* @__quantum__qis__mresetz__body(%Qubit* %ea)
  %one_1 = call %Result* @__quantum__rt__result_get_one()
  %m1o_1 = call i1 @__quantum__rt__result_equal(%Result* %m1_1, %Result* %one_1)
  %m2o_1 = call i1 @__quantum__rt__result_equal(%Result* %m2_1, %Result* %one_1)
  br i1 %m2o_1, label %ax_1, label %cz_1
ax_1:
  call void @__quantum__qis__x__body(%Qubit* %tgt)
  br label %cz_1
cz_1:
  br i1 %m1o_1, label %az_1, label %done_1
az_1:
  call void @__quantum__qis__z__body(%Qubit* %tgt)
  br label %done_1
done_1:
  ret void
}

; ============================================================
; Quantum circuit 2 for webtransport_service (n_qubits=8)
; ============================================================

define void @webtransport_service.circuit_2(%Array* %qubits, double %theta, double %phi) {
entry:
  %p2_0 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 0)
  %q2_0 = load %Qubit*, %Qubit** (bitcast i8* %p2_0 to %Qubit**)
  %p2_1 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 1)
  %q2_1 = load %Qubit*, %Qubit** (bitcast i8* %p2_1 to %Qubit**)
  %p2_2 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 2)
  %q2_2 = load %Qubit*, %Qubit** (bitcast i8* %p2_2 to %Qubit**)
  %p2_3 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 3)
  %q2_3 = load %Qubit*, %Qubit** (bitcast i8* %p2_3 to %Qubit**)
  %p2_4 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 4)
  %q2_4 = load %Qubit*, %Qubit** (bitcast i8* %p2_4 to %Qubit**)
  %p2_5 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 5)
  %q2_5 = load %Qubit*, %Qubit** (bitcast i8* %p2_5 to %Qubit**)
  call void @__quantum__qis__h__body(%Qubit* %q2_0)
  call void @__quantum__qis__rx__body(double %theta, %Qubit* %q2_0)
  call void @__quantum__qis__cx__body(%Qubit* %q2_0, %Qubit* %q2_1)
  call void @__quantum__qis__ry__body(double %phi, %Qubit* %q2_1)
  call void @__quantum__qis__cx__body(%Qubit* %q2_1, %Qubit* %q2_2)
  call void @__quantum__qis__rz__body(double %theta, %Qubit* %q2_2)
  call void @__quantum__qis__ccx__body(%Qubit* %q2_0, %Qubit* %q2_1, %Qubit* %q2_3)
  call void @__quantum__qis__swap__body(%Qubit* %q2_2, %Qubit* %q2_4)
  call void @__quantum__qis__cx__body(%Qubit* %q2_3, %Qubit* %q2_5)
  call void @__maia__qis__majorana_braid(%Qubit* %q2_0, %Qubit* %q2_1, i32 2)
  ret void
}

define double @webtransport_service.vqe_2(%Array* %qubits, double* %params) {
entry:
  %energy_2 = alloca double
  store double 0.0, double* %energy_2
  %vp2_0 = getelementptr double, double* %params, i32 0
  %vv2_0 = load double, double* %vp2_0
  %vqp2_0 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 0)
  %vq2_0 = load %Qubit*, %Qubit** (bitcast i8* %vqp2_0 to %Qubit**)
  call void @__quantum__qis__ry__body(double %vv2_0, %Qubit* %vq2_0)
  %vp2_1 = getelementptr double, double* %params, i32 1
  %vv2_1 = load double, double* %vp2_1
  %vqp2_1 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 1)
  %vq2_1 = load %Qubit*, %Qubit** (bitcast i8* %vqp2_1 to %Qubit**)
  call void @__quantum__qis__ry__body(double %vv2_1, %Qubit* %vq2_1)
  %vp2_2 = getelementptr double, double* %params, i32 2
  %vv2_2 = load double, double* %vp2_2
  %vqp2_2 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 2)
  %vq2_2 = load %Qubit*, %Qubit** (bitcast i8* %vqp2_2 to %Qubit**)
  call void @__quantum__qis__ry__body(double %vv2_2, %Qubit* %vq2_2)
  %vp2_3 = getelementptr double, double* %params, i32 3
  %vv2_3 = load double, double* %vp2_3
  %vqp2_3 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 3)
  %vq2_3 = load %Qubit*, %Qubit** (bitcast i8* %vqp2_3 to %Qubit**)
  call void @__quantum__qis__ry__body(double %vv2_3, %Qubit* %vq2_3)
  %eq2_0p = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 0)
  %eq2_0 = load %Qubit*, %Qubit** (bitcast i8* %eq2_0p to %Qubit**)
  %eq2_1p = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 1)
  %eq2_1 = load %Qubit*, %Qubit** (bitcast i8* %eq2_1p to %Qubit**)
  call void @__quantum__qis__cx__body(%Qubit* %eq2_0, %Qubit* %eq2_1)
  %eq2_1p = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 1)
  %eq2_1 = load %Qubit*, %Qubit** (bitcast i8* %eq2_1p to %Qubit**)
  %eq2_2p = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 2)
  %eq2_2 = load %Qubit*, %Qubit** (bitcast i8* %eq2_2p to %Qubit**)
  call void @__quantum__qis__cx__body(%Qubit* %eq2_1, %Qubit* %eq2_2)
  %eq2_2p = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 2)
  %eq2_2 = load %Qubit*, %Qubit** (bitcast i8* %eq2_2p to %Qubit**)
  %eq2_3p = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 3)
  %eq2_3 = load %Qubit*, %Qubit** (bitcast i8* %eq2_3p to %Qubit**)
  call void @__quantum__qis__cx__body(%Qubit* %eq2_2, %Qubit* %eq2_3)
  %fe_2 = load double, double* %energy_2
  ret double %fe_2
}

define double @webtransport_service.qfi_2(%Array* %qubits, double* %params, i32 %pidx) {
entry:
  %anc_2 = call %Qubit* @__quantum__rt__qubit_allocate()
  call void @__quantum__qis__h__body(%Qubit* %anc_2)
  %pp_2 = getelementptr double, double* %params, i32 %pidx
  %pv_2 = load double, double* %pp_2
  %qfp_2 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 0)
  %qfq_2 = load %Qubit*, %Qubit** (bitcast i8* %qfp_2 to %Qubit**)
  call void @__quantum__qis__rx__body(double %pv_2, %Qubit* %qfq_2)
  call void @__quantum__qis__h__body(%Qubit* %anc_2)
  %mr_2 = call %Result* @__quantum__qis__mresetz__body(%Qubit* %anc_2)
  %mo_2 = call %Result* @__quantum__rt__result_get_one()
  %mi_2 = call i1 @__quantum__rt__result_equal(%Result* %mr_2, %Result* %mo_2)
  %fv_2 = select i1 %mi_2, double 4.0, double 0.0
  call void @__quantum__rt__qubit_release(%Qubit* %anc_2)
  ret double %fv_2
}

define void @webtransport_service.teleport_2(%Qubit* %src, %Qubit* %ea, %Qubit* %eb, %Qubit* %tgt) {
entry:
  call void @__quantum__qis__h__body(%Qubit* %ea)
  call void @__quantum__qis__cx__body(%Qubit* %ea, %Qubit* %eb)
  call void @__quantum__qis__cx__body(%Qubit* %src, %Qubit* %ea)
  call void @__quantum__qis__h__body(%Qubit* %src)
  %m1_2 = call %Result* @__quantum__qis__mresetz__body(%Qubit* %src)
  %m2_2 = call %Result* @__quantum__qis__mresetz__body(%Qubit* %ea)
  %one_2 = call %Result* @__quantum__rt__result_get_one()
  %m1o_2 = call i1 @__quantum__rt__result_equal(%Result* %m1_2, %Result* %one_2)
  %m2o_2 = call i1 @__quantum__rt__result_equal(%Result* %m2_2, %Result* %one_2)
  br i1 %m2o_2, label %ax_2, label %cz_2
ax_2:
  call void @__quantum__qis__x__body(%Qubit* %tgt)
  br label %cz_2
cz_2:
  br i1 %m1o_2, label %az_2, label %done_2
az_2:
  call void @__quantum__qis__z__body(%Qubit* %tgt)
  br label %done_2
done_2:
  ret void
}

; ============================================================
; Quantum circuit 3 for webtransport_service (n_qubits=10)
; ============================================================

define void @webtransport_service.circuit_3(%Array* %qubits, double %theta, double %phi) {
entry:
  %p3_0 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 0)
  %q3_0 = load %Qubit*, %Qubit** (bitcast i8* %p3_0 to %Qubit**)
  %p3_1 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 1)
  %q3_1 = load %Qubit*, %Qubit** (bitcast i8* %p3_1 to %Qubit**)
  %p3_2 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 2)
  %q3_2 = load %Qubit*, %Qubit** (bitcast i8* %p3_2 to %Qubit**)
  %p3_3 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 3)
  %q3_3 = load %Qubit*, %Qubit** (bitcast i8* %p3_3 to %Qubit**)
  %p3_4 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 4)
  %q3_4 = load %Qubit*, %Qubit** (bitcast i8* %p3_4 to %Qubit**)
  %p3_5 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 5)
  %q3_5 = load %Qubit*, %Qubit** (bitcast i8* %p3_5 to %Qubit**)
  call void @__quantum__qis__h__body(%Qubit* %q3_0)
  call void @__quantum__qis__rx__body(double %theta, %Qubit* %q3_0)
  call void @__quantum__qis__cx__body(%Qubit* %q3_0, %Qubit* %q3_1)
  call void @__quantum__qis__ry__body(double %phi, %Qubit* %q3_1)
  call void @__quantum__qis__cx__body(%Qubit* %q3_1, %Qubit* %q3_2)
  call void @__quantum__qis__rz__body(double %theta, %Qubit* %q3_2)
  call void @__quantum__qis__ccx__body(%Qubit* %q3_0, %Qubit* %q3_1, %Qubit* %q3_3)
  call void @__quantum__qis__swap__body(%Qubit* %q3_2, %Qubit* %q3_4)
  call void @__quantum__qis__cx__body(%Qubit* %q3_3, %Qubit* %q3_5)
  call void @__maia__qis__majorana_braid(%Qubit* %q3_0, %Qubit* %q3_1, i32 3)
  ret void
}

define double @webtransport_service.vqe_3(%Array* %qubits, double* %params) {
entry:
  %energy_3 = alloca double
  store double 0.0, double* %energy_3
  %vp3_0 = getelementptr double, double* %params, i32 0
  %vv3_0 = load double, double* %vp3_0
  %vqp3_0 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 0)
  %vq3_0 = load %Qubit*, %Qubit** (bitcast i8* %vqp3_0 to %Qubit**)
  call void @__quantum__qis__ry__body(double %vv3_0, %Qubit* %vq3_0)
  %vp3_1 = getelementptr double, double* %params, i32 1
  %vv3_1 = load double, double* %vp3_1
  %vqp3_1 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 1)
  %vq3_1 = load %Qubit*, %Qubit** (bitcast i8* %vqp3_1 to %Qubit**)
  call void @__quantum__qis__ry__body(double %vv3_1, %Qubit* %vq3_1)
  %vp3_2 = getelementptr double, double* %params, i32 2
  %vv3_2 = load double, double* %vp3_2
  %vqp3_2 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 2)
  %vq3_2 = load %Qubit*, %Qubit** (bitcast i8* %vqp3_2 to %Qubit**)
  call void @__quantum__qis__ry__body(double %vv3_2, %Qubit* %vq3_2)
  %vp3_3 = getelementptr double, double* %params, i32 3
  %vv3_3 = load double, double* %vp3_3
  %vqp3_3 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 3)
  %vq3_3 = load %Qubit*, %Qubit** (bitcast i8* %vqp3_3 to %Qubit**)
  call void @__quantum__qis__ry__body(double %vv3_3, %Qubit* %vq3_3)
  %eq3_0p = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 0)
  %eq3_0 = load %Qubit*, %Qubit** (bitcast i8* %eq3_0p to %Qubit**)
  %eq3_1p = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 1)
  %eq3_1 = load %Qubit*, %Qubit** (bitcast i8* %eq3_1p to %Qubit**)
  call void @__quantum__qis__cx__body(%Qubit* %eq3_0, %Qubit* %eq3_1)
  %eq3_1p = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 1)
  %eq3_1 = load %Qubit*, %Qubit** (bitcast i8* %eq3_1p to %Qubit**)
  %eq3_2p = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 2)
  %eq3_2 = load %Qubit*, %Qubit** (bitcast i8* %eq3_2p to %Qubit**)
  call void @__quantum__qis__cx__body(%Qubit* %eq3_1, %Qubit* %eq3_2)
  %eq3_2p = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 2)
  %eq3_2 = load %Qubit*, %Qubit** (bitcast i8* %eq3_2p to %Qubit**)
  %eq3_3p = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 3)
  %eq3_3 = load %Qubit*, %Qubit** (bitcast i8* %eq3_3p to %Qubit**)
  call void @__quantum__qis__cx__body(%Qubit* %eq3_2, %Qubit* %eq3_3)
  %fe_3 = load double, double* %energy_3
  ret double %fe_3
}

define double @webtransport_service.qfi_3(%Array* %qubits, double* %params, i32 %pidx) {
entry:
  %anc_3 = call %Qubit* @__quantum__rt__qubit_allocate()
  call void @__quantum__qis__h__body(%Qubit* %anc_3)
  %pp_3 = getelementptr double, double* %params, i32 %pidx
  %pv_3 = load double, double* %pp_3
  %qfp_3 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 0)
  %qfq_3 = load %Qubit*, %Qubit** (bitcast i8* %qfp_3 to %Qubit**)
  call void @__quantum__qis__rx__body(double %pv_3, %Qubit* %qfq_3)
  call void @__quantum__qis__h__body(%Qubit* %anc_3)
  %mr_3 = call %Result* @__quantum__qis__mresetz__body(%Qubit* %anc_3)
  %mo_3 = call %Result* @__quantum__rt__result_get_one()
  %mi_3 = call i1 @__quantum__rt__result_equal(%Result* %mr_3, %Result* %mo_3)
  %fv_3 = select i1 %mi_3, double 4.0, double 0.0
  call void @__quantum__rt__qubit_release(%Qubit* %anc_3)
  ret double %fv_3
}

define void @webtransport_service.teleport_3(%Qubit* %src, %Qubit* %ea, %Qubit* %eb, %Qubit* %tgt) {
entry:
  call void @__quantum__qis__h__body(%Qubit* %ea)
  call void @__quantum__qis__cx__body(%Qubit* %ea, %Qubit* %eb)
  call void @__quantum__qis__cx__body(%Qubit* %src, %Qubit* %ea)
  call void @__quantum__qis__h__body(%Qubit* %src)
  %m1_3 = call %Result* @__quantum__qis__mresetz__body(%Qubit* %src)
  %m2_3 = call %Result* @__quantum__qis__mresetz__body(%Qubit* %ea)
  %one_3 = call %Result* @__quantum__rt__result_get_one()
  %m1o_3 = call i1 @__quantum__rt__result_equal(%Result* %m1_3, %Result* %one_3)
  %m2o_3 = call i1 @__quantum__rt__result_equal(%Result* %m2_3, %Result* %one_3)
  br i1 %m2o_3, label %ax_3, label %cz_3
ax_3:
  call void @__quantum__qis__x__body(%Qubit* %tgt)
  br label %cz_3
cz_3:
  br i1 %m1o_3, label %az_3, label %done_3
az_3:
  call void @__quantum__qis__z__body(%Qubit* %tgt)
  br label %done_3
done_3:
  ret void
}

; ============================================================
; Quantum circuit 4 for webtransport_service (n_qubits=12)
; ============================================================

define void @webtransport_service.circuit_4(%Array* %qubits, double %theta, double %phi) {
entry:
  %p4_0 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 0)
  %q4_0 = load %Qubit*, %Qubit** (bitcast i8* %p4_0 to %Qubit**)
  %p4_1 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 1)
  %q4_1 = load %Qubit*, %Qubit** (bitcast i8* %p4_1 to %Qubit**)
  %p4_2 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 2)
  %q4_2 = load %Qubit*, %Qubit** (bitcast i8* %p4_2 to %Qubit**)
  %p4_3 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 3)
  %q4_3 = load %Qubit*, %Qubit** (bitcast i8* %p4_3 to %Qubit**)
  %p4_4 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 4)
  %q4_4 = load %Qubit*, %Qubit** (bitcast i8* %p4_4 to %Qubit**)
  %p4_5 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 5)
  %q4_5 = load %Qubit*, %Qubit** (bitcast i8* %p4_5 to %Qubit**)
  call void @__quantum__qis__h__body(%Qubit* %q4_0)
  call void @__quantum__qis__rx__body(double %theta, %Qubit* %q4_0)
  call void @__quantum__qis__cx__body(%Qubit* %q4_0, %Qubit* %q4_1)
  call void @__quantum__qis__ry__body(double %phi, %Qubit* %q4_1)
  call void @__quantum__qis__cx__body(%Qubit* %q4_1, %Qubit* %q4_2)
  call void @__quantum__qis__rz__body(double %theta, %Qubit* %q4_2)
  call void @__quantum__qis__ccx__body(%Qubit* %q4_0, %Qubit* %q4_1, %Qubit* %q4_3)
  call void @__quantum__qis__swap__body(%Qubit* %q4_2, %Qubit* %q4_4)
  call void @__quantum__qis__cx__body(%Qubit* %q4_3, %Qubit* %q4_5)
  call void @__maia__qis__majorana_braid(%Qubit* %q4_0, %Qubit* %q4_1, i32 0)
  ret void
}

define double @webtransport_service.vqe_4(%Array* %qubits, double* %params) {
entry:
  %energy_4 = alloca double
  store double 0.0, double* %energy_4
  %vp4_0 = getelementptr double, double* %params, i32 0
  %vv4_0 = load double, double* %vp4_0
  %vqp4_0 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 0)
  %vq4_0 = load %Qubit*, %Qubit** (bitcast i8* %vqp4_0 to %Qubit**)
  call void @__quantum__qis__ry__body(double %vv4_0, %Qubit* %vq4_0)
  %vp4_1 = getelementptr double, double* %params, i32 1
  %vv4_1 = load double, double* %vp4_1
  %vqp4_1 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 1)
  %vq4_1 = load %Qubit*, %Qubit** (bitcast i8* %vqp4_1 to %Qubit**)
  call void @__quantum__qis__ry__body(double %vv4_1, %Qubit* %vq4_1)
  %vp4_2 = getelementptr double, double* %params, i32 2
  %vv4_2 = load double, double* %vp4_2
  %vqp4_2 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 2)
  %vq4_2 = load %Qubit*, %Qubit** (bitcast i8* %vqp4_2 to %Qubit**)
  call void @__quantum__qis__ry__body(double %vv4_2, %Qubit* %vq4_2)
  %vp4_3 = getelementptr double, double* %params, i32 3
  %vv4_3 = load double, double* %vp4_3
  %vqp4_3 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 3)
  %vq4_3 = load %Qubit*, %Qubit** (bitcast i8* %vqp4_3 to %Qubit**)
  call void @__quantum__qis__ry__body(double %vv4_3, %Qubit* %vq4_3)
  %eq4_0p = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 0)
  %eq4_0 = load %Qubit*, %Qubit** (bitcast i8* %eq4_0p to %Qubit**)
  %eq4_1p = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 1)
  %eq4_1 = load %Qubit*, %Qubit** (bitcast i8* %eq4_1p to %Qubit**)
  call void @__quantum__qis__cx__body(%Qubit* %eq4_0, %Qubit* %eq4_1)
  %eq4_1p = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 1)
  %eq4_1 = load %Qubit*, %Qubit** (bitcast i8* %eq4_1p to %Qubit**)
  %eq4_2p = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 2)
  %eq4_2 = load %Qubit*, %Qubit** (bitcast i8* %eq4_2p to %Qubit**)
  call void @__quantum__qis__cx__body(%Qubit* %eq4_1, %Qubit* %eq4_2)
  %eq4_2p = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 2)
  %eq4_2 = load %Qubit*, %Qubit** (bitcast i8* %eq4_2p to %Qubit**)
  %eq4_3p = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 3)
  %eq4_3 = load %Qubit*, %Qubit** (bitcast i8* %eq4_3p to %Qubit**)
  call void @__quantum__qis__cx__body(%Qubit* %eq4_2, %Qubit* %eq4_3)
  %fe_4 = load double, double* %energy_4
  ret double %fe_4
}

define double @webtransport_service.qfi_4(%Array* %qubits, double* %params, i32 %pidx) {
entry:
  %anc_4 = call %Qubit* @__quantum__rt__qubit_allocate()
  call void @__quantum__qis__h__body(%Qubit* %anc_4)
  %pp_4 = getelementptr double, double* %params, i32 %pidx
  %pv_4 = load double, double* %pp_4
  %qfp_4 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 0)
  %qfq_4 = load %Qubit*, %Qubit** (bitcast i8* %qfp_4 to %Qubit**)
  call void @__quantum__qis__rx__body(double %pv_4, %Qubit* %qfq_4)
  call void @__quantum__qis__h__body(%Qubit* %anc_4)
  %mr_4 = call %Result* @__quantum__qis__mresetz__body(%Qubit* %anc_4)
  %mo_4 = call %Result* @__quantum__rt__result_get_one()
  %mi_4 = call i1 @__quantum__rt__result_equal(%Result* %mr_4, %Result* %mo_4)
  %fv_4 = select i1 %mi_4, double 4.0, double 0.0
  call void @__quantum__rt__qubit_release(%Qubit* %anc_4)
  ret double %fv_4
}

define void @webtransport_service.teleport_4(%Qubit* %src, %Qubit* %ea, %Qubit* %eb, %Qubit* %tgt) {
entry:
  call void @__quantum__qis__h__body(%Qubit* %ea)
  call void @__quantum__qis__cx__body(%Qubit* %ea, %Qubit* %eb)
  call void @__quantum__qis__cx__body(%Qubit* %src, %Qubit* %ea)
  call void @__quantum__qis__h__body(%Qubit* %src)
  %m1_4 = call %Result* @__quantum__qis__mresetz__body(%Qubit* %src)
  %m2_4 = call %Result* @__quantum__qis__mresetz__body(%Qubit* %ea)
  %one_4 = call %Result* @__quantum__rt__result_get_one()
  %m1o_4 = call i1 @__quantum__rt__result_equal(%Result* %m1_4, %Result* %one_4)
  %m2o_4 = call i1 @__quantum__rt__result_equal(%Result* %m2_4, %Result* %one_4)
  br i1 %m2o_4, label %ax_4, label %cz_4
ax_4:
  call void @__quantum__qis__x__body(%Qubit* %tgt)
  br label %cz_4
cz_4:
  br i1 %m1o_4, label %az_4, label %done_4
az_4:
  call void @__quantum__qis__z__body(%Qubit* %tgt)
  br label %done_4
done_4:
  ret void
}

; ============================================================
; Quantum circuit 5 for webtransport_service (n_qubits=14)
; ============================================================

define void @webtransport_service.circuit_5(%Array* %qubits, double %theta, double %phi) {
entry:
  %p5_0 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 0)
  %q5_0 = load %Qubit*, %Qubit** (bitcast i8* %p5_0 to %Qubit**)
  %p5_1 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 1)
  %q5_1 = load %Qubit*, %Qubit** (bitcast i8* %p5_1 to %Qubit**)
  %p5_2 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 2)
  %q5_2 = load %Qubit*, %Qubit** (bitcast i8* %p5_2 to %Qubit**)
  %p5_3 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 3)
  %q5_3 = load %Qubit*, %Qubit** (bitcast i8* %p5_3 to %Qubit**)
  %p5_4 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 4)
  %q5_4 = load %Qubit*, %Qubit** (bitcast i8* %p5_4 to %Qubit**)
  %p5_5 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 5)
  %q5_5 = load %Qubit*, %Qubit** (bitcast i8* %p5_5 to %Qubit**)
  call void @__quantum__qis__h__body(%Qubit* %q5_0)
  call void @__quantum__qis__rx__body(double %theta, %Qubit* %q5_0)
  call void @__quantum__qis__cx__body(%Qubit* %q5_0, %Qubit* %q5_1)
  call void @__quantum__qis__ry__body(double %phi, %Qubit* %q5_1)
  call void @__quantum__qis__cx__body(%Qubit* %q5_1, %Qubit* %q5_2)
  call void @__quantum__qis__rz__body(double %theta, %Qubit* %q5_2)
  call void @__quantum__qis__ccx__body(%Qubit* %q5_0, %Qubit* %q5_1, %Qubit* %q5_3)
  call void @__quantum__qis__swap__body(%Qubit* %q5_2, %Qubit* %q5_4)
  call void @__quantum__qis__cx__body(%Qubit* %q5_3, %Qubit* %q5_5)
  call void @__maia__qis__majorana_braid(%Qubit* %q5_0, %Qubit* %q5_1, i32 1)
  ret void
}

define double @webtransport_service.vqe_5(%Array* %qubits, double* %params) {
entry:
  %energy_5 = alloca double
  store double 0.0, double* %energy_5
  %vp5_0 = getelementptr double, double* %params, i32 0
  %vv5_0 = load double, double* %vp5_0
  %vqp5_0 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 0)
  %vq5_0 = load %Qubit*, %Qubit** (bitcast i8* %vqp5_0 to %Qubit**)
  call void @__quantum__qis__ry__body(double %vv5_0, %Qubit* %vq5_0)
  %vp5_1 = getelementptr double, double* %params, i32 1
  %vv5_1 = load double, double* %vp5_1
  %vqp5_1 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 1)
  %vq5_1 = load %Qubit*, %Qubit** (bitcast i8* %vqp5_1 to %Qubit**)
  call void @__quantum__qis__ry__body(double %vv5_1, %Qubit* %vq5_1)
  %vp5_2 = getelementptr double, double* %params, i32 2
  %vv5_2 = load double, double* %vp5_2
  %vqp5_2 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 2)
  %vq5_2 = load %Qubit*, %Qubit** (bitcast i8* %vqp5_2 to %Qubit**)
  call void @__quantum__qis__ry__body(double %vv5_2, %Qubit* %vq5_2)
  %vp5_3 = getelementptr double, double* %params, i32 3
  %vv5_3 = load double, double* %vp5_3
  %vqp5_3 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 3)
  %vq5_3 = load %Qubit*, %Qubit** (bitcast i8* %vqp5_3 to %Qubit**)
  call void @__quantum__qis__ry__body(double %vv5_3, %Qubit* %vq5_3)
  %eq5_0p = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 0)
  %eq5_0 = load %Qubit*, %Qubit** (bitcast i8* %eq5_0p to %Qubit**)
  %eq5_1p = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 1)
  %eq5_1 = load %Qubit*, %Qubit** (bitcast i8* %eq5_1p to %Qubit**)
  call void @__quantum__qis__cx__body(%Qubit* %eq5_0, %Qubit* %eq5_1)
  %eq5_1p = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 1)
  %eq5_1 = load %Qubit*, %Qubit** (bitcast i8* %eq5_1p to %Qubit**)
  %eq5_2p = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 2)
  %eq5_2 = load %Qubit*, %Qubit** (bitcast i8* %eq5_2p to %Qubit**)
  call void @__quantum__qis__cx__body(%Qubit* %eq5_1, %Qubit* %eq5_2)
  %eq5_2p = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 2)
  %eq5_2 = load %Qubit*, %Qubit** (bitcast i8* %eq5_2p to %Qubit**)
  %eq5_3p = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 3)
  %eq5_3 = load %Qubit*, %Qubit** (bitcast i8* %eq5_3p to %Qubit**)
  call void @__quantum__qis__cx__body(%Qubit* %eq5_2, %Qubit* %eq5_3)
  %fe_5 = load double, double* %energy_5
  ret double %fe_5
}

define double @webtransport_service.qfi_5(%Array* %qubits, double* %params, i32 %pidx) {
entry:
  %anc_5 = call %Qubit* @__quantum__rt__qubit_allocate()
  call void @__quantum__qis__h__body(%Qubit* %anc_5)
  %pp_5 = getelementptr double, double* %params, i32 %pidx
  %pv_5 = load double, double* %pp_5
  %qfp_5 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 0)
  %qfq_5 = load %Qubit*, %Qubit** (bitcast i8* %qfp_5 to %Qubit**)
  call void @__quantum__qis__rx__body(double %pv_5, %Qubit* %qfq_5)
  call void @__quantum__qis__h__body(%Qubit* %anc_5)
  %mr_5 = call %Result* @__quantum__qis__mresetz__body(%Qubit* %anc_5)
  %mo_5 = call %Result* @__quantum__rt__result_get_one()
  %mi_5 = call i1 @__quantum__rt__result_equal(%Result* %mr_5, %Result* %mo_5)
  %fv_5 = select i1 %mi_5, double 4.0, double 0.0
  call void @__quantum__rt__qubit_release(%Qubit* %anc_5)
  ret double %fv_5
}

define void @webtransport_service.teleport_5(%Qubit* %src, %Qubit* %ea, %Qubit* %eb, %Qubit* %tgt) {
entry:
  call void @__quantum__qis__h__body(%Qubit* %ea)
  call void @__quantum__qis__cx__body(%Qubit* %ea, %Qubit* %eb)
  call void @__quantum__qis__cx__body(%Qubit* %src, %Qubit* %ea)
  call void @__quantum__qis__h__body(%Qubit* %src)
  %m1_5 = call %Result* @__quantum__qis__mresetz__body(%Qubit* %src)
  %m2_5 = call %Result* @__quantum__qis__mresetz__body(%Qubit* %ea)
  %one_5 = call %Result* @__quantum__rt__result_get_one()
  %m1o_5 = call i1 @__quantum__rt__result_equal(%Result* %m1_5, %Result* %one_5)
  %m2o_5 = call i1 @__quantum__rt__result_equal(%Result* %m2_5, %Result* %one_5)
  br i1 %m2o_5, label %ax_5, label %cz_5
ax_5:
  call void @__quantum__qis__x__body(%Qubit* %tgt)
  br label %cz_5
cz_5:
  br i1 %m1o_5, label %az_5, label %done_5
az_5:
  call void @__quantum__qis__z__body(%Qubit* %tgt)
  br label %done_5
done_5:
  ret void
}

; ============================================================
; Quantum circuit 6 for webtransport_service (n_qubits=16)
; ============================================================

define void @webtransport_service.circuit_6(%Array* %qubits, double %theta, double %phi) {
entry:
  %p6_0 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 0)
  %q6_0 = load %Qubit*, %Qubit** (bitcast i8* %p6_0 to %Qubit**)
  %p6_1 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 1)
  %q6_1 = load %Qubit*, %Qubit** (bitcast i8* %p6_1 to %Qubit**)
  %p6_2 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 2)
  %q6_2 = load %Qubit*, %Qubit** (bitcast i8* %p6_2 to %Qubit**)
  %p6_3 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 3)
  %q6_3 = load %Qubit*, %Qubit** (bitcast i8* %p6_3 to %Qubit**)
  %p6_4 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 4)
  %q6_4 = load %Qubit*, %Qubit** (bitcast i8* %p6_4 to %Qubit**)
  %p6_5 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 5)
  %q6_5 = load %Qubit*, %Qubit** (bitcast i8* %p6_5 to %Qubit**)
  call void @__quantum__qis__h__body(%Qubit* %q6_0)
  call void @__quantum__qis__rx__body(double %theta, %Qubit* %q6_0)
  call void @__quantum__qis__cx__body(%Qubit* %q6_0, %Qubit* %q6_1)
  call void @__quantum__qis__ry__body(double %phi, %Qubit* %q6_1)
  call void @__quantum__qis__cx__body(%Qubit* %q6_1, %Qubit* %q6_2)
  call void @__quantum__qis__rz__body(double %theta, %Qubit* %q6_2)
  call void @__quantum__qis__ccx__body(%Qubit* %q6_0, %Qubit* %q6_1, %Qubit* %q6_3)
  call void @__quantum__qis__swap__body(%Qubit* %q6_2, %Qubit* %q6_4)
  call void @__quantum__qis__cx__body(%Qubit* %q6_3, %Qubit* %q6_5)
  call void @__maia__qis__majorana_braid(%Qubit* %q6_0, %Qubit* %q6_1, i32 2)
  ret void
}

define double @webtransport_service.vqe_6(%Array* %qubits, double* %params) {
entry:
  %energy_6 = alloca double
  store double 0.0, double* %energy_6
  %vp6_0 = getelementptr double, double* %params, i32 0
  %vv6_0 = load double, double* %vp6_0
  %vqp6_0 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 0)
  %vq6_0 = load %Qubit*, %Qubit** (bitcast i8* %vqp6_0 to %Qubit**)
  call void @__quantum__qis__ry__body(double %vv6_0, %Qubit* %vq6_0)
  %vp6_1 = getelementptr double, double* %params, i32 1
  %vv6_1 = load double, double* %vp6_1
  %vqp6_1 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 1)
  %vq6_1 = load %Qubit*, %Qubit** (bitcast i8* %vqp6_1 to %Qubit**)
  call void @__quantum__qis__ry__body(double %vv6_1, %Qubit* %vq6_1)
  %vp6_2 = getelementptr double, double* %params, i32 2
  %vv6_2 = load double, double* %vp6_2
  %vqp6_2 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 2)
  %vq6_2 = load %Qubit*, %Qubit** (bitcast i8* %vqp6_2 to %Qubit**)
  call void @__quantum__qis__ry__body(double %vv6_2, %Qubit* %vq6_2)
  %vp6_3 = getelementptr double, double* %params, i32 3
  %vv6_3 = load double, double* %vp6_3
  %vqp6_3 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 3)
  %vq6_3 = load %Qubit*, %Qubit** (bitcast i8* %vqp6_3 to %Qubit**)
  call void @__quantum__qis__ry__body(double %vv6_3, %Qubit* %vq6_3)
  %eq6_0p = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 0)
  %eq6_0 = load %Qubit*, %Qubit** (bitcast i8* %eq6_0p to %Qubit**)
  %eq6_1p = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 1)
  %eq6_1 = load %Qubit*, %Qubit** (bitcast i8* %eq6_1p to %Qubit**)
  call void @__quantum__qis__cx__body(%Qubit* %eq6_0, %Qubit* %eq6_1)
  %eq6_1p = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 1)
  %eq6_1 = load %Qubit*, %Qubit** (bitcast i8* %eq6_1p to %Qubit**)
  %eq6_2p = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 2)
  %eq6_2 = load %Qubit*, %Qubit** (bitcast i8* %eq6_2p to %Qubit**)
  call void @__quantum__qis__cx__body(%Qubit* %eq6_1, %Qubit* %eq6_2)
  %eq6_2p = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 2)
  %eq6_2 = load %Qubit*, %Qubit** (bitcast i8* %eq6_2p to %Qubit**)
  %eq6_3p = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 3)
  %eq6_3 = load %Qubit*, %Qubit** (bitcast i8* %eq6_3p to %Qubit**)
  call void @__quantum__qis__cx__body(%Qubit* %eq6_2, %Qubit* %eq6_3)
  %fe_6 = load double, double* %energy_6
  ret double %fe_6
}

define double @webtransport_service.qfi_6(%Array* %qubits, double* %params, i32 %pidx) {
entry:
  %anc_6 = call %Qubit* @__quantum__rt__qubit_allocate()
  call void @__quantum__qis__h__body(%Qubit* %anc_6)
  %pp_6 = getelementptr double, double* %params, i32 %pidx
  %pv_6 = load double, double* %pp_6
  %qfp_6 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 0)
  %qfq_6 = load %Qubit*, %Qubit** (bitcast i8* %qfp_6 to %Qubit**)
  call void @__quantum__qis__rx__body(double %pv_6, %Qubit* %qfq_6)
  call void @__quantum__qis__h__body(%Qubit* %anc_6)
  %mr_6 = call %Result* @__quantum__qis__mresetz__body(%Qubit* %anc_6)
  %mo_6 = call %Result* @__quantum__rt__result_get_one()
  %mi_6 = call i1 @__quantum__rt__result_equal(%Result* %mr_6, %Result* %mo_6)
  %fv_6 = select i1 %mi_6, double 4.0, double 0.0
  call void @__quantum__rt__qubit_release(%Qubit* %anc_6)
  ret double %fv_6
}

define void @webtransport_service.teleport_6(%Qubit* %src, %Qubit* %ea, %Qubit* %eb, %Qubit* %tgt) {
entry:
  call void @__quantum__qis__h__body(%Qubit* %ea)
  call void @__quantum__qis__cx__body(%Qubit* %ea, %Qubit* %eb)
  call void @__quantum__qis__cx__body(%Qubit* %src, %Qubit* %ea)
  call void @__quantum__qis__h__body(%Qubit* %src)
  %m1_6 = call %Result* @__quantum__qis__mresetz__body(%Qubit* %src)
  %m2_6 = call %Result* @__quantum__qis__mresetz__body(%Qubit* %ea)
  %one_6 = call %Result* @__quantum__rt__result_get_one()
  %m1o_6 = call i1 @__quantum__rt__result_equal(%Result* %m1_6, %Result* %one_6)
  %m2o_6 = call i1 @__quantum__rt__result_equal(%Result* %m2_6, %Result* %one_6)
  br i1 %m2o_6, label %ax_6, label %cz_6
ax_6:
  call void @__quantum__qis__x__body(%Qubit* %tgt)
  br label %cz_6
cz_6:
  br i1 %m1o_6, label %az_6, label %done_6
az_6:
  call void @__quantum__qis__z__body(%Qubit* %tgt)
  br label %done_6
done_6:
  ret void
}

; ============================================================
; Quantum circuit 7 for webtransport_service (n_qubits=18)
; ============================================================

define void @webtransport_service.circuit_7(%Array* %qubits, double %theta, double %phi) {
entry:
  %p7_0 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 0)
  %q7_0 = load %Qubit*, %Qubit** (bitcast i8* %p7_0 to %Qubit**)
  %p7_1 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 1)
  %q7_1 = load %Qubit*, %Qubit** (bitcast i8* %p7_1 to %Qubit**)
  %p7_2 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 2)
  %q7_2 = load %Qubit*, %Qubit** (bitcast i8* %p7_2 to %Qubit**)
  %p7_3 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 3)
  %q7_3 = load %Qubit*, %Qubit** (bitcast i8* %p7_3 to %Qubit**)
  %p7_4 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 4)
  %q7_4 = load %Qubit*, %Qubit** (bitcast i8* %p7_4 to %Qubit**)
  %p7_5 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 5)
  %q7_5 = load %Qubit*, %Qubit** (bitcast i8* %p7_5 to %Qubit**)
  call void @__quantum__qis__h__body(%Qubit* %q7_0)
  call void @__quantum__qis__rx__body(double %theta, %Qubit* %q7_0)
  call void @__quantum__qis__cx__body(%Qubit* %q7_0, %Qubit* %q7_1)
  call void @__quantum__qis__ry__body(double %phi, %Qubit* %q7_1)
  call void @__quantum__qis__cx__body(%Qubit* %q7_1, %Qubit* %q7_2)
  call void @__quantum__qis__rz__body(double %theta, %Qubit* %q7_2)
  call void @__quantum__qis__ccx__body(%Qubit* %q7_0, %Qubit* %q7_1, %Qubit* %q7_3)
  call void @__quantum__qis__swap__body(%Qubit* %q7_2, %Qubit* %q7_4)
  call void @__quantum__qis__cx__body(%Qubit* %q7_3, %Qubit* %q7_5)
  call void @__maia__qis__majorana_braid(%Qubit* %q7_0, %Qubit* %q7_1, i32 3)
  ret void
}

define double @webtransport_service.vqe_7(%Array* %qubits, double* %params) {
entry:
  %energy_7 = alloca double
  store double 0.0, double* %energy_7
  %vp7_0 = getelementptr double, double* %params, i32 0
  %vv7_0 = load double, double* %vp7_0
  %vqp7_0 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 0)
  %vq7_0 = load %Qubit*, %Qubit** (bitcast i8* %vqp7_0 to %Qubit**)
  call void @__quantum__qis__ry__body(double %vv7_0, %Qubit* %vq7_0)
  %vp7_1 = getelementptr double, double* %params, i32 1
  %vv7_1 = load double, double* %vp7_1
  %vqp7_1 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 1)
  %vq7_1 = load %Qubit*, %Qubit** (bitcast i8* %vqp7_1 to %Qubit**)
  call void @__quantum__qis__ry__body(double %vv7_1, %Qubit* %vq7_1)
  %vp7_2 = getelementptr double, double* %params, i32 2
  %vv7_2 = load double, double* %vp7_2
  %vqp7_2 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 2)
  %vq7_2 = load %Qubit*, %Qubit** (bitcast i8* %vqp7_2 to %Qubit**)
  call void @__quantum__qis__ry__body(double %vv7_2, %Qubit* %vq7_2)
  %vp7_3 = getelementptr double, double* %params, i32 3
  %vv7_3 = load double, double* %vp7_3
  %vqp7_3 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 3)
  %vq7_3 = load %Qubit*, %Qubit** (bitcast i8* %vqp7_3 to %Qubit**)
  call void @__quantum__qis__ry__body(double %vv7_3, %Qubit* %vq7_3)
  %eq7_0p = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 0)
  %eq7_0 = load %Qubit*, %Qubit** (bitcast i8* %eq7_0p to %Qubit**)
  %eq7_1p = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 1)
  %eq7_1 = load %Qubit*, %Qubit** (bitcast i8* %eq7_1p to %Qubit**)
  call void @__quantum__qis__cx__body(%Qubit* %eq7_0, %Qubit* %eq7_1)
  %eq7_1p = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 1)
  %eq7_1 = load %Qubit*, %Qubit** (bitcast i8* %eq7_1p to %Qubit**)
  %eq7_2p = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 2)
  %eq7_2 = load %Qubit*, %Qubit** (bitcast i8* %eq7_2p to %Qubit**)
  call void @__quantum__qis__cx__body(%Qubit* %eq7_1, %Qubit* %eq7_2)
  %eq7_2p = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 2)
  %eq7_2 = load %Qubit*, %Qubit** (bitcast i8* %eq7_2p to %Qubit**)
  %eq7_3p = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 3)
  %eq7_3 = load %Qubit*, %Qubit** (bitcast i8* %eq7_3p to %Qubit**)
  call void @__quantum__qis__cx__body(%Qubit* %eq7_2, %Qubit* %eq7_3)
  %fe_7 = load double, double* %energy_7
  ret double %fe_7
}

define double @webtransport_service.qfi_7(%Array* %qubits, double* %params, i32 %pidx) {
entry:
  %anc_7 = call %Qubit* @__quantum__rt__qubit_allocate()
  call void @__quantum__qis__h__body(%Qubit* %anc_7)
  %pp_7 = getelementptr double, double* %params, i32 %pidx
  %pv_7 = load double, double* %pp_7
  %qfp_7 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 0)
  %qfq_7 = load %Qubit*, %Qubit** (bitcast i8* %qfp_7 to %Qubit**)
  call void @__quantum__qis__rx__body(double %pv_7, %Qubit* %qfq_7)
  call void @__quantum__qis__h__body(%Qubit* %anc_7)
  %mr_7 = call %Result* @__quantum__qis__mresetz__body(%Qubit* %anc_7)
  %mo_7 = call %Result* @__quantum__rt__result_get_one()
  %mi_7 = call i1 @__quantum__rt__result_equal(%Result* %mr_7, %Result* %mo_7)
  %fv_7 = select i1 %mi_7, double 4.0, double 0.0
  call void @__quantum__rt__qubit_release(%Qubit* %anc_7)
  ret double %fv_7
}

define void @webtransport_service.teleport_7(%Qubit* %src, %Qubit* %ea, %Qubit* %eb, %Qubit* %tgt) {
entry:
  call void @__quantum__qis__h__body(%Qubit* %ea)
  call void @__quantum__qis__cx__body(%Qubit* %ea, %Qubit* %eb)
  call void @__quantum__qis__cx__body(%Qubit* %src, %Qubit* %ea)
  call void @__quantum__qis__h__body(%Qubit* %src)
  %m1_7 = call %Result* @__quantum__qis__mresetz__body(%Qubit* %src)
  %m2_7 = call %Result* @__quantum__qis__mresetz__body(%Qubit* %ea)
  %one_7 = call %Result* @__quantum__rt__result_get_one()
  %m1o_7 = call i1 @__quantum__rt__result_equal(%Result* %m1_7, %Result* %one_7)
  %m2o_7 = call i1 @__quantum__rt__result_equal(%Result* %m2_7, %Result* %one_7)
  br i1 %m2o_7, label %ax_7, label %cz_7
ax_7:
  call void @__quantum__qis__x__body(%Qubit* %tgt)
  br label %cz_7
cz_7:
  br i1 %m1o_7, label %az_7, label %done_7
az_7:
  call void @__quantum__qis__z__body(%Qubit* %tgt)
  br label %done_7
done_7:
  ret void
}

; ============================================================
; Quantum circuit 8 for webtransport_service (n_qubits=20)
; ============================================================

define void @webtransport_service.circuit_8(%Array* %qubits, double %theta, double %phi) {
entry:
  %p8_0 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 0)
  %q8_0 = load %Qubit*, %Qubit** (bitcast i8* %p8_0 to %Qubit**)
  %p8_1 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 1)
  %q8_1 = load %Qubit*, %Qubit** (bitcast i8* %p8_1 to %Qubit**)
  %p8_2 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 2)
  %q8_2 = load %Qubit*, %Qubit** (bitcast i8* %p8_2 to %Qubit**)
  %p8_3 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 3)
  %q8_3 = load %Qubit*, %Qubit** (bitcast i8* %p8_3 to %Qubit**)
  %p8_4 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 4)
  %q8_4 = load %Qubit*, %Qubit** (bitcast i8* %p8_4 to %Qubit**)
  %p8_5 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 5)
  %q8_5 = load %Qubit*, %Qubit** (bitcast i8* %p8_5 to %Qubit**)
  call void @__quantum__qis__h__body(%Qubit* %q8_0)
  call void @__quantum__qis__rx__body(double %theta, %Qubit* %q8_0)
  call void @__quantum__qis__cx__body(%Qubit* %q8_0, %Qubit* %q8_1)
  call void @__quantum__qis__ry__body(double %phi, %Qubit* %q8_1)
  call void @__quantum__qis__cx__body(%Qubit* %q8_1, %Qubit* %q8_2)
  call void @__quantum__qis__rz__body(double %theta, %Qubit* %q8_2)
  call void @__quantum__qis__ccx__body(%Qubit* %q8_0, %Qubit* %q8_1, %Qubit* %q8_3)
  call void @__quantum__qis__swap__body(%Qubit* %q8_2, %Qubit* %q8_4)
  call void @__quantum__qis__cx__body(%Qubit* %q8_3, %Qubit* %q8_5)
  call void @__maia__qis__majorana_braid(%Qubit* %q8_0, %Qubit* %q8_1, i32 0)
  ret void
}

define double @webtransport_service.vqe_8(%Array* %qubits, double* %params) {
entry:
  %energy_8 = alloca double
  store double 0.0, double* %energy_8
  %vp8_0 = getelementptr double, double* %params, i32 0
  %vv8_0 = load double, double* %vp8_0
  %vqp8_0 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 0)
  %vq8_0 = load %Qubit*, %Qubit** (bitcast i8* %vqp8_0 to %Qubit**)
  call void @__quantum__qis__ry__body(double %vv8_0, %Qubit* %vq8_0)
  %vp8_1 = getelementptr double, double* %params, i32 1
  %vv8_1 = load double, double* %vp8_1
  %vqp8_1 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 1)
  %vq8_1 = load %Qubit*, %Qubit** (bitcast i8* %vqp8_1 to %Qubit**)
  call void @__quantum__qis__ry__body(double %vv8_1, %Qubit* %vq8_1)
  %vp8_2 = getelementptr double, double* %params, i32 2
  %vv8_2 = load double, double* %vp8_2
  %vqp8_2 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 2)
  %vq8_2 = load %Qubit*, %Qubit** (bitcast i8* %vqp8_2 to %Qubit**)
  call void @__quantum__qis__ry__body(double %vv8_2, %Qubit* %vq8_2)
  %vp8_3 = getelementptr double, double* %params, i32 3
  %vv8_3 = load double, double* %vp8_3
  %vqp8_3 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 3)
  %vq8_3 = load %Qubit*, %Qubit** (bitcast i8* %vqp8_3 to %Qubit**)
  call void @__quantum__qis__ry__body(double %vv8_3, %Qubit* %vq8_3)
  %eq8_0p = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 0)
  %eq8_0 = load %Qubit*, %Qubit** (bitcast i8* %eq8_0p to %Qubit**)
  %eq8_1p = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 1)
  %eq8_1 = load %Qubit*, %Qubit** (bitcast i8* %eq8_1p to %Qubit**)
  call void @__quantum__qis__cx__body(%Qubit* %eq8_0, %Qubit* %eq8_1)
  %eq8_1p = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 1)
  %eq8_1 = load %Qubit*, %Qubit** (bitcast i8* %eq8_1p to %Qubit**)
  %eq8_2p = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 2)
  %eq8_2 = load %Qubit*, %Qubit** (bitcast i8* %eq8_2p to %Qubit**)
  call void @__quantum__qis__cx__body(%Qubit* %eq8_1, %Qubit* %eq8_2)
  %eq8_2p = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 2)
  %eq8_2 = load %Qubit*, %Qubit** (bitcast i8* %eq8_2p to %Qubit**)
  %eq8_3p = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 3)
  %eq8_3 = load %Qubit*, %Qubit** (bitcast i8* %eq8_3p to %Qubit**)
  call void @__quantum__qis__cx__body(%Qubit* %eq8_2, %Qubit* %eq8_3)
  %fe_8 = load double, double* %energy_8
  ret double %fe_8
}

define double @webtransport_service.qfi_8(%Array* %qubits, double* %params, i32 %pidx) {
entry:
  %anc_8 = call %Qubit* @__quantum__rt__qubit_allocate()
  call void @__quantum__qis__h__body(%Qubit* %anc_8)
  %pp_8 = getelementptr double, double* %params, i32 %pidx
  %pv_8 = load double, double* %pp_8
  %qfp_8 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 0)
  %qfq_8 = load %Qubit*, %Qubit** (bitcast i8* %qfp_8 to %Qubit**)
  call void @__quantum__qis__rx__body(double %pv_8, %Qubit* %qfq_8)
  call void @__quantum__qis__h__body(%Qubit* %anc_8)
  %mr_8 = call %Result* @__quantum__qis__mresetz__body(%Qubit* %anc_8)
  %mo_8 = call %Result* @__quantum__rt__result_get_one()
  %mi_8 = call i1 @__quantum__rt__result_equal(%Result* %mr_8, %Result* %mo_8)
  %fv_8 = select i1 %mi_8, double 4.0, double 0.0
  call void @__quantum__rt__qubit_release(%Qubit* %anc_8)
  ret double %fv_8
}

define void @webtransport_service.teleport_8(%Qubit* %src, %Qubit* %ea, %Qubit* %eb, %Qubit* %tgt) {
entry:
  call void @__quantum__qis__h__body(%Qubit* %ea)
  call void @__quantum__qis__cx__body(%Qubit* %ea, %Qubit* %eb)
  call void @__quantum__qis__cx__body(%Qubit* %src, %Qubit* %ea)
  call void @__quantum__qis__h__body(%Qubit* %src)
  %m1_8 = call %Result* @__quantum__qis__mresetz__body(%Qubit* %src)
  %m2_8 = call %Result* @__quantum__qis__mresetz__body(%Qubit* %ea)
  %one_8 = call %Result* @__quantum__rt__result_get_one()
  %m1o_8 = call i1 @__quantum__rt__result_equal(%Result* %m1_8, %Result* %one_8)
  %m2o_8 = call i1 @__quantum__rt__result_equal(%Result* %m2_8, %Result* %one_8)
  br i1 %m2o_8, label %ax_8, label %cz_8
ax_8:
  call void @__quantum__qis__x__body(%Qubit* %tgt)
  br label %cz_8
cz_8:
  br i1 %m1o_8, label %az_8, label %done_8
az_8:
  call void @__quantum__qis__z__body(%Qubit* %tgt)
  br label %done_8
done_8:
  ret void
}

; ============================================================
; Quantum circuit 9 for webtransport_service (n_qubits=22)
; ============================================================

define void @webtransport_service.circuit_9(%Array* %qubits, double %theta, double %phi) {
entry:
  %p9_0 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 0)
  %q9_0 = load %Qubit*, %Qubit** (bitcast i8* %p9_0 to %Qubit**)
  %p9_1 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 1)
  %q9_1 = load %Qubit*, %Qubit** (bitcast i8* %p9_1 to %Qubit**)
  %p9_2 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 2)
  %q9_2 = load %Qubit*, %Qubit** (bitcast i8* %p9_2 to %Qubit**)
  %p9_3 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 3)
  %q9_3 = load %Qubit*, %Qubit** (bitcast i8* %p9_3 to %Qubit**)
  %p9_4 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 4)
  %q9_4 = load %Qubit*, %Qubit** (bitcast i8* %p9_4 to %Qubit**)
  %p9_5 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 5)
  %q9_5 = load %Qubit*, %Qubit** (bitcast i8* %p9_5 to %Qubit**)
  call void @__quantum__qis__h__body(%Qubit* %q9_0)
  call void @__quantum__qis__rx__body(double %theta, %Qubit* %q9_0)
  call void @__quantum__qis__cx__body(%Qubit* %q9_0, %Qubit* %q9_1)
  call void @__quantum__qis__ry__body(double %phi, %Qubit* %q9_1)
  call void @__quantum__qis__cx__body(%Qubit* %q9_1, %Qubit* %q9_2)
  call void @__quantum__qis__rz__body(double %theta, %Qubit* %q9_2)
  call void @__quantum__qis__ccx__body(%Qubit* %q9_0, %Qubit* %q9_1, %Qubit* %q9_3)
  call void @__quantum__qis__swap__body(%Qubit* %q9_2, %Qubit* %q9_4)
  call void @__quantum__qis__cx__body(%Qubit* %q9_3, %Qubit* %q9_5)
  call void @__maia__qis__majorana_braid(%Qubit* %q9_0, %Qubit* %q9_1, i32 1)
  ret void
}

define double @webtransport_service.vqe_9(%Array* %qubits, double* %params) {
entry:
  %energy_9 = alloca double
  store double 0.0, double* %energy_9
  %vp9_0 = getelementptr double, double* %params, i32 0
  %vv9_0 = load double, double* %vp9_0
  %vqp9_0 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 0)
  %vq9_0 = load %Qubit*, %Qubit** (bitcast i8* %vqp9_0 to %Qubit**)
  call void @__quantum__qis__ry__body(double %vv9_0, %Qubit* %vq9_0)
  %vp9_1 = getelementptr double, double* %params, i32 1
  %vv9_1 = load double, double* %vp9_1
  %vqp9_1 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 1)
  %vq9_1 = load %Qubit*, %Qubit** (bitcast i8* %vqp9_1 to %Qubit**)
  call void @__quantum__qis__ry__body(double %vv9_1, %Qubit* %vq9_1)
  %vp9_2 = getelementptr double, double* %params, i32 2
  %vv9_2 = load double, double* %vp9_2
  %vqp9_2 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 2)
  %vq9_2 = load %Qubit*, %Qubit** (bitcast i8* %vqp9_2 to %Qubit**)
  call void @__quantum__qis__ry__body(double %vv9_2, %Qubit* %vq9_2)
  %vp9_3 = getelementptr double, double* %params, i32 3
  %vv9_3 = load double, double* %vp9_3
  %vqp9_3 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 3)
  %vq9_3 = load %Qubit*, %Qubit** (bitcast i8* %vqp9_3 to %Qubit**)
  call void @__quantum__qis__ry__body(double %vv9_3, %Qubit* %vq9_3)
  %eq9_0p = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 0)
  %eq9_0 = load %Qubit*, %Qubit** (bitcast i8* %eq9_0p to %Qubit**)
  %eq9_1p = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 1)
  %eq9_1 = load %Qubit*, %Qubit** (bitcast i8* %eq9_1p to %Qubit**)
  call void @__quantum__qis__cx__body(%Qubit* %eq9_0, %Qubit* %eq9_1)
  %eq9_1p = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 1)
  %eq9_1 = load %Qubit*, %Qubit** (bitcast i8* %eq9_1p to %Qubit**)
  %eq9_2p = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 2)
  %eq9_2 = load %Qubit*, %Qubit** (bitcast i8* %eq9_2p to %Qubit**)
  call void @__quantum__qis__cx__body(%Qubit* %eq9_1, %Qubit* %eq9_2)
  %eq9_2p = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 2)
  %eq9_2 = load %Qubit*, %Qubit** (bitcast i8* %eq9_2p to %Qubit**)
  %eq9_3p = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 3)
  %eq9_3 = load %Qubit*, %Qubit** (bitcast i8* %eq9_3p to %Qubit**)
  call void @__quantum__qis__cx__body(%Qubit* %eq9_2, %Qubit* %eq9_3)
  %fe_9 = load double, double* %energy_9
  ret double %fe_9
}

define double @webtransport_service.qfi_9(%Array* %qubits, double* %params, i32 %pidx) {
entry:
  %anc_9 = call %Qubit* @__quantum__rt__qubit_allocate()
  call void @__quantum__qis__h__body(%Qubit* %anc_9)
  %pp_9 = getelementptr double, double* %params, i32 %pidx
  %pv_9 = load double, double* %pp_9
  %qfp_9 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 0)
  %qfq_9 = load %Qubit*, %Qubit** (bitcast i8* %qfp_9 to %Qubit**)
  call void @__quantum__qis__rx__body(double %pv_9, %Qubit* %qfq_9)
  call void @__quantum__qis__h__body(%Qubit* %anc_9)
  %mr_9 = call %Result* @__quantum__qis__mresetz__body(%Qubit* %anc_9)
  %mo_9 = call %Result* @__quantum__rt__result_get_one()
  %mi_9 = call i1 @__quantum__rt__result_equal(%Result* %mr_9, %Result* %mo_9)
  %fv_9 = select i1 %mi_9, double 4.0, double 0.0
  call void @__quantum__rt__qubit_release(%Qubit* %anc_9)
  ret double %fv_9
}

define void @webtransport_service.teleport_9(%Qubit* %src, %Qubit* %ea, %Qubit* %eb, %Qubit* %tgt) {
entry:
  call void @__quantum__qis__h__body(%Qubit* %ea)
  call void @__quantum__qis__cx__body(%Qubit* %ea, %Qubit* %eb)
  call void @__quantum__qis__cx__body(%Qubit* %src, %Qubit* %ea)
  call void @__quantum__qis__h__body(%Qubit* %src)
  %m1_9 = call %Result* @__quantum__qis__mresetz__body(%Qubit* %src)
  %m2_9 = call %Result* @__quantum__qis__mresetz__body(%Qubit* %ea)
  %one_9 = call %Result* @__quantum__rt__result_get_one()
  %m1o_9 = call i1 @__quantum__rt__result_equal(%Result* %m1_9, %Result* %one_9)
  %m2o_9 = call i1 @__quantum__rt__result_equal(%Result* %m2_9, %Result* %one_9)
  br i1 %m2o_9, label %ax_9, label %cz_9
ax_9:
  call void @__quantum__qis__x__body(%Qubit* %tgt)
  br label %cz_9
cz_9:
  br i1 %m1o_9, label %az_9, label %done_9
az_9:
  call void @__quantum__qis__z__body(%Qubit* %tgt)
  br label %done_9
done_9:
  ret void
}

; ============================================================
; Quantum circuit 10 for webtransport_service (n_qubits=24)
; ============================================================

define void @webtransport_service.circuit_10(%Array* %qubits, double %theta, double %phi) {
entry:
  %p10_0 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 0)
  %q10_0 = load %Qubit*, %Qubit** (bitcast i8* %p10_0 to %Qubit**)
  %p10_1 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 1)
  %q10_1 = load %Qubit*, %Qubit** (bitcast i8* %p10_1 to %Qubit**)
  %p10_2 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 2)
  %q10_2 = load %Qubit*, %Qubit** (bitcast i8* %p10_2 to %Qubit**)
  %p10_3 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 3)
  %q10_3 = load %Qubit*, %Qubit** (bitcast i8* %p10_3 to %Qubit**)
  %p10_4 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 4)
  %q10_4 = load %Qubit*, %Qubit** (bitcast i8* %p10_4 to %Qubit**)
  %p10_5 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 5)
  %q10_5 = load %Qubit*, %Qubit** (bitcast i8* %p10_5 to %Qubit**)
  call void @__quantum__qis__h__body(%Qubit* %q10_0)
  call void @__quantum__qis__rx__body(double %theta, %Qubit* %q10_0)
  call void @__quantum__qis__cx__body(%Qubit* %q10_0, %Qubit* %q10_1)
  call void @__quantum__qis__ry__body(double %phi, %Qubit* %q10_1)
  call void @__quantum__qis__cx__body(%Qubit* %q10_1, %Qubit* %q10_2)
  call void @__quantum__qis__rz__body(double %theta, %Qubit* %q10_2)
  call void @__quantum__qis__ccx__body(%Qubit* %q10_0, %Qubit* %q10_1, %Qubit* %q10_3)
  call void @__quantum__qis__swap__body(%Qubit* %q10_2, %Qubit* %q10_4)
  call void @__quantum__qis__cx__body(%Qubit* %q10_3, %Qubit* %q10_5)
  call void @__maia__qis__majorana_braid(%Qubit* %q10_0, %Qubit* %q10_1, i32 2)
  ret void
}

define double @webtransport_service.vqe_10(%Array* %qubits, double* %params) {
entry:
  %energy_10 = alloca double
  store double 0.0, double* %energy_10
  %vp10_0 = getelementptr double, double* %params, i32 0
  %vv10_0 = load double, double* %vp10_0
  %vqp10_0 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 0)
  %vq10_0 = load %Qubit*, %Qubit** (bitcast i8* %vqp10_0 to %Qubit**)
  call void @__quantum__qis__ry__body(double %vv10_0, %Qubit* %vq10_0)
  %vp10_1 = getelementptr double, double* %params, i32 1
  %vv10_1 = load double, double* %vp10_1
  %vqp10_1 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 1)
  %vq10_1 = load %Qubit*, %Qubit** (bitcast i8* %vqp10_1 to %Qubit**)
  call void @__quantum__qis__ry__body(double %vv10_1, %Qubit* %vq10_1)
  %vp10_2 = getelementptr double, double* %params, i32 2
  %vv10_2 = load double, double* %vp10_2
  %vqp10_2 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 2)
  %vq10_2 = load %Qubit*, %Qubit** (bitcast i8* %vqp10_2 to %Qubit**)
  call void @__quantum__qis__ry__body(double %vv10_2, %Qubit* %vq10_2)
  %vp10_3 = getelementptr double, double* %params, i32 3
  %vv10_3 = load double, double* %vp10_3
  %vqp10_3 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 3)
  %vq10_3 = load %Qubit*, %Qubit** (bitcast i8* %vqp10_3 to %Qubit**)
  call void @__quantum__qis__ry__body(double %vv10_3, %Qubit* %vq10_3)
  %eq10_0p = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 0)
  %eq10_0 = load %Qubit*, %Qubit** (bitcast i8* %eq10_0p to %Qubit**)
  %eq10_1p = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 1)
  %eq10_1 = load %Qubit*, %Qubit** (bitcast i8* %eq10_1p to %Qubit**)
  call void @__quantum__qis__cx__body(%Qubit* %eq10_0, %Qubit* %eq10_1)
  %eq10_1p = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 1)
  %eq10_1 = load %Qubit*, %Qubit** (bitcast i8* %eq10_1p to %Qubit**)
  %eq10_2p = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 2)
  %eq10_2 = load %Qubit*, %Qubit** (bitcast i8* %eq10_2p to %Qubit**)
  call void @__quantum__qis__cx__body(%Qubit* %eq10_1, %Qubit* %eq10_2)
  %eq10_2p = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 2)
  %eq10_2 = load %Qubit*, %Qubit** (bitcast i8* %eq10_2p to %Qubit**)
  %eq10_3p = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 3)
  %eq10_3 = load %Qubit*, %Qubit** (bitcast i8* %eq10_3p to %Qubit**)
  call void @__quantum__qis__cx__body(%Qubit* %eq10_2, %Qubit* %eq10_3)
  %fe_10 = load double, double* %energy_10
  ret double %fe_10
}

define double @webtransport_service.qfi_10(%Array* %qubits, double* %params, i32 %pidx) {
entry:
  %anc_10 = call %Qubit* @__quantum__rt__qubit_allocate()
  call void @__quantum__qis__h__body(%Qubit* %anc_10)
  %pp_10 = getelementptr double, double* %params, i32 %pidx
  %pv_10 = load double, double* %pp_10
  %qfp_10 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 0)
  %qfq_10 = load %Qubit*, %Qubit** (bitcast i8* %qfp_10 to %Qubit**)
  call void @__quantum__qis__rx__body(double %pv_10, %Qubit* %qfq_10)
  call void @__quantum__qis__h__body(%Qubit* %anc_10)
  %mr_10 = call %Result* @__quantum__qis__mresetz__body(%Qubit* %anc_10)
  %mo_10 = call %Result* @__quantum__rt__result_get_one()
  %mi_10 = call i1 @__quantum__rt__result_equal(%Result* %mr_10, %Result* %mo_10)
  %fv_10 = select i1 %mi_10, double 4.0, double 0.0
  call void @__quantum__rt__qubit_release(%Qubit* %anc_10)
  ret double %fv_10
}

define void @webtransport_service.teleport_10(%Qubit* %src, %Qubit* %ea, %Qubit* %eb, %Qubit* %tgt) {
entry:
  call void @__quantum__qis__h__body(%Qubit* %ea)
  call void @__quantum__qis__cx__body(%Qubit* %ea, %Qubit* %eb)
  call void @__quantum__qis__cx__body(%Qubit* %src, %Qubit* %ea)
  call void @__quantum__qis__h__body(%Qubit* %src)
  %m1_10 = call %Result* @__quantum__qis__mresetz__body(%Qubit* %src)
  %m2_10 = call %Result* @__quantum__qis__mresetz__body(%Qubit* %ea)
  %one_10 = call %Result* @__quantum__rt__result_get_one()
  %m1o_10 = call i1 @__quantum__rt__result_equal(%Result* %m1_10, %Result* %one_10)
  %m2o_10 = call i1 @__quantum__rt__result_equal(%Result* %m2_10, %Result* %one_10)
  br i1 %m2o_10, label %ax_10, label %cz_10
ax_10:
  call void @__quantum__qis__x__body(%Qubit* %tgt)
  br label %cz_10
cz_10:
  br i1 %m1o_10, label %az_10, label %done_10
az_10:
  call void @__quantum__qis__z__body(%Qubit* %tgt)
  br label %done_10
done_10:
  ret void
}

; ============================================================
; Quantum circuit 11 for webtransport_service (n_qubits=26)
; ============================================================

define void @webtransport_service.circuit_11(%Array* %qubits, double %theta, double %phi) {
entry:
  %p11_0 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 0)
  %q11_0 = load %Qubit*, %Qubit** (bitcast i8* %p11_0 to %Qubit**)
  %p11_1 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 1)
  %q11_1 = load %Qubit*, %Qubit** (bitcast i8* %p11_1 to %Qubit**)
  %p11_2 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 2)
  %q11_2 = load %Qubit*, %Qubit** (bitcast i8* %p11_2 to %Qubit**)
  %p11_3 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 3)
  %q11_3 = load %Qubit*, %Qubit** (bitcast i8* %p11_3 to %Qubit**)
  %p11_4 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 4)
  %q11_4 = load %Qubit*, %Qubit** (bitcast i8* %p11_4 to %Qubit**)
  %p11_5 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 5)
  %q11_5 = load %Qubit*, %Qubit** (bitcast i8* %p11_5 to %Qubit**)
  call void @__quantum__qis__h__body(%Qubit* %q11_0)
  call void @__quantum__qis__rx__body(double %theta, %Qubit* %q11_0)
  call void @__quantum__qis__cx__body(%Qubit* %q11_0, %Qubit* %q11_1)
  call void @__quantum__qis__ry__body(double %phi, %Qubit* %q11_1)
  call void @__quantum__qis__cx__body(%Qubit* %q11_1, %Qubit* %q11_2)
  call void @__quantum__qis__rz__body(double %theta, %Qubit* %q11_2)
  call void @__quantum__qis__ccx__body(%Qubit* %q11_0, %Qubit* %q11_1, %Qubit* %q11_3)
  call void @__quantum__qis__swap__body(%Qubit* %q11_2, %Qubit* %q11_4)
  call void @__quantum__qis__cx__body(%Qubit* %q11_3, %Qubit* %q11_5)
  call void @__maia__qis__majorana_braid(%Qubit* %q11_0, %Qubit* %q11_1, i32 3)
  ret void
}

define double @webtransport_service.vqe_11(%Array* %qubits, double* %params) {
entry:
  %energy_11 = alloca double
  store double 0.0, double* %energy_11
  %vp11_0 = getelementptr double, double* %params, i32 0
  %vv11_0 = load double, double* %vp11_0
  %vqp11_0 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 0)
  %vq11_0 = load %Qubit*, %Qubit** (bitcast i8* %vqp11_0 to %Qubit**)
  call void @__quantum__qis__ry__body(double %vv11_0, %Qubit* %vq11_0)
  %vp11_1 = getelementptr double, double* %params, i32 1
  %vv11_1 = load double, double* %vp11_1
  %vqp11_1 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 1)
  %vq11_1 = load %Qubit*, %Qubit** (bitcast i8* %vqp11_1 to %Qubit**)
  call void @__quantum__qis__ry__body(double %vv11_1, %Qubit* %vq11_1)
  %vp11_2 = getelementptr double, double* %params, i32 2
  %vv11_2 = load double, double* %vp11_2
  %vqp11_2 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 2)
  %vq11_2 = load %Qubit*, %Qubit** (bitcast i8* %vqp11_2 to %Qubit**)
  call void @__quantum__qis__ry__body(double %vv11_2, %Qubit* %vq11_2)
  %vp11_3 = getelementptr double, double* %params, i32 3
  %vv11_3 = load double, double* %vp11_3
  %vqp11_3 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 3)
  %vq11_3 = load %Qubit*, %Qubit** (bitcast i8* %vqp11_3 to %Qubit**)
  call void @__quantum__qis__ry__body(double %vv11_3, %Qubit* %vq11_3)
  %eq11_0p = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 0)
  %eq11_0 = load %Qubit*, %Qubit** (bitcast i8* %eq11_0p to %Qubit**)
  %eq11_1p = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 1)
  %eq11_1 = load %Qubit*, %Qubit** (bitcast i8* %eq11_1p to %Qubit**)
  call void @__quantum__qis__cx__body(%Qubit* %eq11_0, %Qubit* %eq11_1)
  %eq11_1p = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 1)
  %eq11_1 = load %Qubit*, %Qubit** (bitcast i8* %eq11_1p to %Qubit**)
  %eq11_2p = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 2)
  %eq11_2 = load %Qubit*, %Qubit** (bitcast i8* %eq11_2p to %Qubit**)
  call void @__quantum__qis__cx__body(%Qubit* %eq11_1, %Qubit* %eq11_2)
  %eq11_2p = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 2)
  %eq11_2 = load %Qubit*, %Qubit** (bitcast i8* %eq11_2p to %Qubit**)
  %eq11_3p = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 3)
  %eq11_3 = load %Qubit*, %Qubit** (bitcast i8* %eq11_3p to %Qubit**)
  call void @__quantum__qis__cx__body(%Qubit* %eq11_2, %Qubit* %eq11_3)
  %fe_11 = load double, double* %energy_11
  ret double %fe_11
}

define double @webtransport_service.qfi_11(%Array* %qubits, double* %params, i32 %pidx) {
entry:
  %anc_11 = call %Qubit* @__quantum__rt__qubit_allocate()
  call void @__quantum__qis__h__body(%Qubit* %anc_11)
  %pp_11 = getelementptr double, double* %params, i32 %pidx
  %pv_11 = load double, double* %pp_11
  %qfp_11 = call i8* @__quantum__rt__array_get_element_ptr_1d(%Array* %qubits, i64 0)
  %qfq_11 = load %Qubit*, %Qubit** (bitcast i8* %qfp_11 to %Qubit**)
  call void @__quantum__qis__rx__body(double %pv_11, %Qubit* %qfq_11)
  call void @__quantum__qis__h__body(%Qubit* %anc_11)
  %mr_11 = call %Result* @__quantum__qis__mresetz__body(%Qubit* %anc_11)
  %mo_11 = call %Result* @__quantum__rt__result_get_one()
  %mi_11 = call i1 @__quantum__rt__result_equal(%Result* %mr_11, %Result* %mo_11)
  %fv_11 = select i1 %mi_11, double 4.0, double 0.0
  call void @__quantum__rt__qubit_release(%Qubit* %anc_11)
  ret double %fv_11
}

define void @webtransport_service.teleport_11(%Qubit* %src, %Qubit* %ea, %Qubit* %eb, %Qubit* %tgt) {
entry:
  call void @__quantum__qis__h__body(%Qubit* %ea)
  call void @__quantum__qis__cx__body(%Qubit* %ea, %Qubit* %eb)
  call void @__quantum__qis__cx__body(%Qubit* %src, %Qubit* %ea)
  call void @__quantum__qis__h__body(%Qubit* %src)
  %m1_11 = call %Result* @__quantum__qis__mresetz__body(%Qubit* %src)
  %m2_11 = call %Result* @__quantum__qis__mresetz__body(%Qubit* %ea)
  %one_11 = call %Result* @__quantum__rt__result_get_one()
  %m1o_11 = call i1 @__quantum__rt__result_equal(%Result* %m1_11, %Result* %one_11)
  %m2o_11 = call i1 @__quantum__rt__result_equal(%Result* %m2_11, %Result* %one_11)
  br i1 %m2o_11, label %ax_11, label %cz_11
ax_11:
  call void @__quantum__qis__x__body(%Qubit* %tgt)
  br label %cz_11
cz_11:
  br i1 %m1o_11, label %az_11, label %done_11
az_11:
  call void @__quantum__qis__z__body(%Qubit* %tgt)
  br label %done_11
done_11:
  ret void
}

define i32 @main(i32 %argc, i8** %argv) {
entry:
  call void @__quantum__rt__initialize(i8* null)
  %qubits = call %Array* @__quantum__rt__qubit_allocate_array(i64 300)
  %qmap = call %QubitMap* @webtransport_service.allocate_qubits(i32 50)
  %params = call i8* @malloc(i64 800)
  %pd = bitcast i8* %params to double*
  %fisher = call double @webtransport_service.qfi_0(%Array* %qubits, double* %pd, i32 0)
  %syn = call %ErrorSyndrome* @SteaneCode.measure_syndrome(%Array* %qubits)
  call void @SteaneCode.correct(%Array* %qubits, %ErrorSyndrome* %syn)
  call void @__quantum__rt__qubit_release_array(%Array* %qubits)
  call void @free(i8* %params)
  call void @free(%syn)
  call void @__quantum__rt__finalize()
  ret i32 0
}

attributes #0 = { nounwind }
attributes #1 = { nounwind readonly }
!llvm.module.flags = !{!0, !1}
!0 = !{i32 1, !"qir_major_version", i32 1}
!1 = !{i32 1, !"qir_minor_version", i32 0}
!llvm.ident = !{!2}
!2 = !{"Windows-AGI-Mesh QIR Compiler 1.0.0"}