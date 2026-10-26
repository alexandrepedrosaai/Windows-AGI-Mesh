// ════════════════════════════════════════════════════════════════════════════
// WINDOWS AI PIPELINE — QFT Grover Shor HHL QSVT
// Namespace: WindowsAI.Pipeline.Algorithms.Core
// ════════════════════════════════════════════════════════════════════════════
namespace WindowsAI.Pipeline.Algorithms.Core {
    open Microsoft.Quantum.Intrinsic;
    open Microsoft.Quantum.Canon;
    open Microsoft.Quantum.Math;
    open Microsoft.Quantum.Arrays;
    open Microsoft.Quantum.Convert;
    open Microsoft.Quantum.Diagnostics;

    // ────────────────────────────────────────────────────────────────────────
    // SEÇÃO 1: QFT Grover Shor HHL QSVT — Módulo 1
    // ────────────────────────────────────────────────────────────────────────
    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 1, Operação 1
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_1_1
    operation Operation_1_1(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_1_1: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 1, Operação 2
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_1_2
    operation Operation_1_2(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_1_2: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 1, Operação 3
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_1_3
    operation Operation_1_3(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_1_3: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 1, Operação 4
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_1_4
    operation Operation_1_4(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_1_4: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 1, Operação 5
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_1_5
    operation Operation_1_5(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_1_5: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 1, Operação 6
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_1_6
    operation Operation_1_6(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_1_6: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 1, Operação 7
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_1_7
    operation Operation_1_7(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_1_7: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 1, Operação 8
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_1_8
    operation Operation_1_8(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_1_8: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    // ────────────────────────────────────────────────────────────────────────
    // SEÇÃO 2: QFT Grover Shor HHL QSVT — Módulo 2
    // ────────────────────────────────────────────────────────────────────────
    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 2, Operação 1
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_2_1
    operation Operation_2_1(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_2_1: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 2, Operação 2
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_2_2
    operation Operation_2_2(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_2_2: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 2, Operação 3
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_2_3
    operation Operation_2_3(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_2_3: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 2, Operação 4
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_2_4
    operation Operation_2_4(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_2_4: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 2, Operação 5
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_2_5
    operation Operation_2_5(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_2_5: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 2, Operação 6
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_2_6
    operation Operation_2_6(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_2_6: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 2, Operação 7
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_2_7
    operation Operation_2_7(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_2_7: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 2, Operação 8
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_2_8
    operation Operation_2_8(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_2_8: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    // ────────────────────────────────────────────────────────────────────────
    // SEÇÃO 3: QFT Grover Shor HHL QSVT — Módulo 3
    // ────────────────────────────────────────────────────────────────────────
    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 3, Operação 1
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_3_1
    operation Operation_3_1(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_3_1: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 3, Operação 2
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_3_2
    operation Operation_3_2(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_3_2: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 3, Operação 3
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_3_3
    operation Operation_3_3(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_3_3: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 3, Operação 4
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_3_4
    operation Operation_3_4(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_3_4: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 3, Operação 5
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_3_5
    operation Operation_3_5(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_3_5: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 3, Operação 6
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_3_6
    operation Operation_3_6(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_3_6: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 3, Operação 7
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_3_7
    operation Operation_3_7(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_3_7: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 3, Operação 8
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_3_8
    operation Operation_3_8(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_3_8: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    // ────────────────────────────────────────────────────────────────────────
    // SEÇÃO 4: QFT Grover Shor HHL QSVT — Módulo 4
    // ────────────────────────────────────────────────────────────────────────
    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 4, Operação 1
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_4_1
    operation Operation_4_1(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_4_1: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 4, Operação 2
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_4_2
    operation Operation_4_2(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_4_2: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 4, Operação 3
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_4_3
    operation Operation_4_3(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_4_3: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 4, Operação 4
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_4_4
    operation Operation_4_4(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_4_4: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 4, Operação 5
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_4_5
    operation Operation_4_5(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_4_5: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 4, Operação 6
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_4_6
    operation Operation_4_6(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_4_6: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 4, Operação 7
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_4_7
    operation Operation_4_7(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_4_7: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 4, Operação 8
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_4_8
    operation Operation_4_8(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_4_8: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    // ────────────────────────────────────────────────────────────────────────
    // SEÇÃO 5: QFT Grover Shor HHL QSVT — Módulo 5
    // ────────────────────────────────────────────────────────────────────────
    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 5, Operação 1
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_5_1
    operation Operation_5_1(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_5_1: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 5, Operação 2
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_5_2
    operation Operation_5_2(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_5_2: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 5, Operação 3
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_5_3
    operation Operation_5_3(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_5_3: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 5, Operação 4
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_5_4
    operation Operation_5_4(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_5_4: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 5, Operação 5
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_5_5
    operation Operation_5_5(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_5_5: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 5, Operação 6
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_5_6
    operation Operation_5_6(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_5_6: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 5, Operação 7
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_5_7
    operation Operation_5_7(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_5_7: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 5, Operação 8
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_5_8
    operation Operation_5_8(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_5_8: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    // ────────────────────────────────────────────────────────────────────────
    // SEÇÃO 6: QFT Grover Shor HHL QSVT — Módulo 6
    // ────────────────────────────────────────────────────────────────────────
    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 6, Operação 1
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_6_1
    operation Operation_6_1(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_6_1: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 6, Operação 2
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_6_2
    operation Operation_6_2(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_6_2: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 6, Operação 3
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_6_3
    operation Operation_6_3(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_6_3: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 6, Operação 4
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_6_4
    operation Operation_6_4(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_6_4: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 6, Operação 5
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_6_5
    operation Operation_6_5(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_6_5: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 6, Operação 6
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_6_6
    operation Operation_6_6(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_6_6: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 6, Operação 7
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_6_7
    operation Operation_6_7(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_6_7: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 6, Operação 8
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_6_8
    operation Operation_6_8(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_6_8: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    // ────────────────────────────────────────────────────────────────────────
    // SEÇÃO 7: QFT Grover Shor HHL QSVT — Módulo 7
    // ────────────────────────────────────────────────────────────────────────
    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 7, Operação 1
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_7_1
    operation Operation_7_1(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_7_1: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 7, Operação 2
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_7_2
    operation Operation_7_2(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_7_2: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 7, Operação 3
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_7_3
    operation Operation_7_3(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_7_3: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 7, Operação 4
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_7_4
    operation Operation_7_4(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_7_4: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 7, Operação 5
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_7_5
    operation Operation_7_5(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_7_5: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 7, Operação 6
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_7_6
    operation Operation_7_6(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_7_6: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 7, Operação 7
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_7_7
    operation Operation_7_7(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_7_7: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 7, Operação 8
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_7_8
    operation Operation_7_8(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_7_8: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    // ────────────────────────────────────────────────────────────────────────
    // SEÇÃO 8: QFT Grover Shor HHL QSVT — Módulo 8
    // ────────────────────────────────────────────────────────────────────────
    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 8, Operação 1
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_8_1
    operation Operation_8_1(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_8_1: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 8, Operação 2
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_8_2
    operation Operation_8_2(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_8_2: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 8, Operação 3
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_8_3
    operation Operation_8_3(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_8_3: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 8, Operação 4
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_8_4
    operation Operation_8_4(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_8_4: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 8, Operação 5
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_8_5
    operation Operation_8_5(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_8_5: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 8, Operação 6
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_8_6
    operation Operation_8_6(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_8_6: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 8, Operação 7
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_8_7
    operation Operation_8_7(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_8_7: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 8, Operação 8
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_8_8
    operation Operation_8_8(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_8_8: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    // ────────────────────────────────────────────────────────────────────────
    // SEÇÃO 9: QFT Grover Shor HHL QSVT — Módulo 9
    // ────────────────────────────────────────────────────────────────────────
    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 9, Operação 1
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_9_1
    operation Operation_9_1(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_9_1: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 9, Operação 2
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_9_2
    operation Operation_9_2(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_9_2: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 9, Operação 3
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_9_3
    operation Operation_9_3(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_9_3: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 9, Operação 4
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_9_4
    operation Operation_9_4(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_9_4: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 9, Operação 5
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_9_5
    operation Operation_9_5(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_9_5: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 9, Operação 6
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_9_6
    operation Operation_9_6(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_9_6: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 9, Operação 7
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_9_7
    operation Operation_9_7(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_9_7: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 9, Operação 8
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_9_8
    operation Operation_9_8(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_9_8: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    // ────────────────────────────────────────────────────────────────────────
    // SEÇÃO 10: QFT Grover Shor HHL QSVT — Módulo 10
    // ────────────────────────────────────────────────────────────────────────
    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 10, Operação 1
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_10_1
    operation Operation_10_1(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_10_1: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 10, Operação 2
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_10_2
    operation Operation_10_2(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_10_2: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 10, Operação 3
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_10_3
    operation Operation_10_3(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_10_3: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 10, Operação 4
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_10_4
    operation Operation_10_4(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_10_4: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 10, Operação 5
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_10_5
    operation Operation_10_5(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_10_5: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 10, Operação 6
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_10_6
    operation Operation_10_6(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_10_6: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 10, Operação 7
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_10_7
    operation Operation_10_7(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_10_7: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 10, Operação 8
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_10_8
    operation Operation_10_8(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_10_8: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    // ────────────────────────────────────────────────────────────────────────
    // SEÇÃO 11: QFT Grover Shor HHL QSVT — Módulo 11
    // ────────────────────────────────────────────────────────────────────────
    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 11, Operação 1
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_11_1
    operation Operation_11_1(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_11_1: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 11, Operação 2
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_11_2
    operation Operation_11_2(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_11_2: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 11, Operação 3
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_11_3
    operation Operation_11_3(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_11_3: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 11, Operação 4
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_11_4
    operation Operation_11_4(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_11_4: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 11, Operação 5
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_11_5
    operation Operation_11_5(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_11_5: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 11, Operação 6
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_11_6
    operation Operation_11_6(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_11_6: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 11, Operação 7
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_11_7
    operation Operation_11_7(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_11_7: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 11, Operação 8
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_11_8
    operation Operation_11_8(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_11_8: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    // ────────────────────────────────────────────────────────────────────────
    // SEÇÃO 12: QFT Grover Shor HHL QSVT — Módulo 12
    // ────────────────────────────────────────────────────────────────────────
    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 12, Operação 1
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_12_1
    operation Operation_12_1(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_12_1: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 12, Operação 2
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_12_2
    operation Operation_12_2(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_12_2: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 12, Operação 3
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_12_3
    operation Operation_12_3(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_12_3: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 12, Operação 4
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_12_4
    operation Operation_12_4(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_12_4: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 12, Operação 5
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_12_5
    operation Operation_12_5(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_12_5: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 12, Operação 6
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_12_6
    operation Operation_12_6(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_12_6: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 12, Operação 7
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_12_7
    operation Operation_12_7(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_12_7: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 12, Operação 8
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_12_8
    operation Operation_12_8(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_12_8: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    // ────────────────────────────────────────────────────────────────────────
    // SEÇÃO 13: QFT Grover Shor HHL QSVT — Módulo 13
    // ────────────────────────────────────────────────────────────────────────
    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 13, Operação 1
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_13_1
    operation Operation_13_1(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_13_1: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 13, Operação 2
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_13_2
    operation Operation_13_2(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_13_2: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 13, Operação 3
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_13_3
    operation Operation_13_3(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_13_3: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 13, Operação 4
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_13_4
    operation Operation_13_4(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_13_4: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 13, Operação 5
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_13_5
    operation Operation_13_5(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_13_5: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 13, Operação 6
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_13_6
    operation Operation_13_6(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_13_6: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 13, Operação 7
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_13_7
    operation Operation_13_7(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_13_7: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 13, Operação 8
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_13_8
    operation Operation_13_8(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_13_8: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    // ────────────────────────────────────────────────────────────────────────
    // SEÇÃO 14: QFT Grover Shor HHL QSVT — Módulo 14
    // ────────────────────────────────────────────────────────────────────────
    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 14, Operação 1
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_14_1
    operation Operation_14_1(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_14_1: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 14, Operação 2
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_14_2
    operation Operation_14_2(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_14_2: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 14, Operação 3
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_14_3
    operation Operation_14_3(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_14_3: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 14, Operação 4
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_14_4
    operation Operation_14_4(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_14_4: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 14, Operação 5
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_14_5
    operation Operation_14_5(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_14_5: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 14, Operação 6
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_14_6
    operation Operation_14_6(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_14_6: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 14, Operação 7
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_14_7
    operation Operation_14_7(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_14_7: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 14, Operação 8
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_14_8
    operation Operation_14_8(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_14_8: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    // ────────────────────────────────────────────────────────────────────────
    // SEÇÃO 15: QFT Grover Shor HHL QSVT — Módulo 15
    // ────────────────────────────────────────────────────────────────────────
    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 15, Operação 1
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_15_1
    operation Operation_15_1(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_15_1: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 15, Operação 2
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_15_2
    operation Operation_15_2(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_15_2: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 15, Operação 3
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_15_3
    operation Operation_15_3(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_15_3: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 15, Operação 4
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_15_4
    operation Operation_15_4(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_15_4: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 15, Operação 5
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_15_5
    operation Operation_15_5(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_15_5: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 15, Operação 6
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_15_6
    operation Operation_15_6(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_15_6: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 15, Operação 7
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_15_7
    operation Operation_15_7(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_15_7: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 15, Operação 8
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_15_8
    operation Operation_15_8(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_15_8: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    // ────────────────────────────────────────────────────────────────────────
    // SEÇÃO 16: QFT Grover Shor HHL QSVT — Módulo 16
    // ────────────────────────────────────────────────────────────────────────
    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 16, Operação 1
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_16_1
    operation Operation_16_1(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_16_1: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 16, Operação 2
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_16_2
    operation Operation_16_2(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_16_2: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 16, Operação 3
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_16_3
    operation Operation_16_3(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_16_3: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 16, Operação 4
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_16_4
    operation Operation_16_4(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_16_4: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 16, Operação 5
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_16_5
    operation Operation_16_5(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_16_5: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 16, Operação 6
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_16_6
    operation Operation_16_6(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_16_6: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 16, Operação 7
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_16_7
    operation Operation_16_7(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_16_7: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    /// # Summary
    /// QFT Grover Shor HHL QSVT — Seção 16, Operação 8
    /// Implementa lógica quântica para WindowsAI.Pipeline.Algorithms.Core.Operation_16_8
    operation Operation_16_8(
        inputQ    : Qubit[],
        ancillaQ  : Qubit[],
        param1    : Double,
        param2    : Double,
        nShots    : Int
    ) : (Double, Double, Bool) {
        let n = Length(inputQ);
        let m = Length(ancillaQ);
        mutable result1 = 0.0;
        mutable result2 = 0.0;
        mutable flag    = false;
        Message($"[WindowsAI.Pipeline.Algorithms.Core] Operation_16_8: n={n} param1={param1:.4f}");
        // Inicializar estado quântico
        ApplyToEach(H, inputQ);
        for i in 0..n-2 {
            CNOT(inputQ[i], inputQ[i+1]);
            Rz(param1 * PI() / IntAsDouble(sec), inputQ[i]);
            Ry(param2 * PI() / IntAsDouble(op),  inputQ[i+1]);
        }
        // Acoplamento com ancilla
        for i in 0..MinI(n,m)-1 {
            Controlled Rz([inputQ[i]], (param1*PI()/8.0, ancillaQ[i]));
        }
        // Medição Monte Carlo
        mutable s1 = 0.0;
        mutable s2 = 0.0;
        for _ in 1..nShots {
            use mQ = Qubit[n] {
                for i in 0..n-1 { CNOT(inputQ[i], mQ[i]); }
                mutable v = 0.0;
                for i in 0..n-1 {
                    let r = MResetZ(mQ[i]);
                    set v += r == One ? 1.0 | 0.0;
                }
                set s1 += v / IntAsDouble(n);
                set s2 += (v / IntAsDouble(n) - 0.5) * (v / IntAsDouble(n) - 0.5);
            }
        }
        set result1 = s1 / IntAsDouble(nShots);
        set result2 = Sqrt(s2 / IntAsDouble(nShots));
        set flag    = result1 > 0.5;
        ResetAll(inputQ);
        ResetAll(ancillaQ);
        return (result1, result2, flag);
    }

    @EntryPoint()
    operation CoreMain() : Unit {
        Message("╔══════════════════════════════════════════╗");
        Message("║  QFT Grover Shor HHL QSVT                  ║");
        Message("╚══════════════════════════════════════════╝");
        use (q, a) = (Qubit[4], Qubit[4]) {
            ApplyToEach(H, q);
            let (r1_1, r2_1, f_1) = Operation_1_1(q, a, 0.5, 0.3, 50);
            Message($"  Sec1: r1={r1_1:.4f} r2={r2_1:.4f} flag={f_1}");
            let (r1_2, r2_2, f_2) = Operation_2_1(q, a, 0.5, 0.3, 50);
            Message($"  Sec2: r1={r1_2:.4f} r2={r2_2:.4f} flag={f_2}");
            let (r1_3, r2_3, f_3) = Operation_3_1(q, a, 0.5, 0.3, 50);
            Message($"  Sec3: r1={r1_3:.4f} r2={r2_3:.4f} flag={f_3}");
            ResetAll(q); ResetAll(a);
        }
        Message("  ✓ QFT Grover Shor HHL QSVT concluído");
    }
}
