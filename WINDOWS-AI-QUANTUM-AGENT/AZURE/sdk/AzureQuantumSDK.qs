// ════════════════════════════════════════════════════════════════════════════
// WINDOWS AI PIPELINE — Azure Quantum SDK Job Submission
// Namespace: WindowsAI.Pipeline.Azure.SDK
// ════════════════════════════════════════════════════════════════════════════
namespace WindowsAI.Pipeline.Azure.SDK {
    open Microsoft.Quantum.Intrinsic;
    open Microsoft.Quantum.Canon;
    open Microsoft.Quantum.Math;
    open Microsoft.Quantum.Arrays;
    open Microsoft.Quantum.Convert;
    open Microsoft.Quantum.Diagnostics;

    // ────────────────────────────────────────────────────────────────────────
    // SEÇÃO 1: Azure Quantum SDK Job Submission — Módulo 1
    // ────────────────────────────────────────────────────────────────────────
    /// # Summary
    /// Azure Quantum SDK Job Submission — Seção 1, Operação 1
    /// Implementa lógica quântica para WindowsAI.Pipeline.Azure.SDK.Operation_1_1
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
        Message($"[WindowsAI.Pipeline.Azure.SDK] Operation_1_1: n={n} param1={param1:.4f}");
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
    /// Azure Quantum SDK Job Submission — Seção 1, Operação 2
    /// Implementa lógica quântica para WindowsAI.Pipeline.Azure.SDK.Operation_1_2
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
        Message($"[WindowsAI.Pipeline.Azure.SDK] Operation_1_2: n={n} param1={param1:.4f}");
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
    /// Azure Quantum SDK Job Submission — Seção 1, Operação 3
    /// Implementa lógica quântica para WindowsAI.Pipeline.Azure.SDK.Operation_1_3
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
        Message($"[WindowsAI.Pipeline.Azure.SDK] Operation_1_3: n={n} param1={param1:.4f}");
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
    /// Azure Quantum SDK Job Submission — Seção 1, Operação 4
    /// Implementa lógica quântica para WindowsAI.Pipeline.Azure.SDK.Operation_1_4
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
        Message($"[WindowsAI.Pipeline.Azure.SDK] Operation_1_4: n={n} param1={param1:.4f}");
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
    /// Azure Quantum SDK Job Submission — Seção 1, Operação 5
    /// Implementa lógica quântica para WindowsAI.Pipeline.Azure.SDK.Operation_1_5
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
        Message($"[WindowsAI.Pipeline.Azure.SDK] Operation_1_5: n={n} param1={param1:.4f}");
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
    /// Azure Quantum SDK Job Submission — Seção 1, Operação 6
    /// Implementa lógica quântica para WindowsAI.Pipeline.Azure.SDK.Operation_1_6
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
        Message($"[WindowsAI.Pipeline.Azure.SDK] Operation_1_6: n={n} param1={param1:.4f}");
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
    // SEÇÃO 2: Azure Quantum SDK Job Submission — Módulo 2
    // ────────────────────────────────────────────────────────────────────────
    /// # Summary
    /// Azure Quantum SDK Job Submission — Seção 2, Operação 1
    /// Implementa lógica quântica para WindowsAI.Pipeline.Azure.SDK.Operation_2_1
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
        Message($"[WindowsAI.Pipeline.Azure.SDK] Operation_2_1: n={n} param1={param1:.4f}");
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
    /// Azure Quantum SDK Job Submission — Seção 2, Operação 2
    /// Implementa lógica quântica para WindowsAI.Pipeline.Azure.SDK.Operation_2_2
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
        Message($"[WindowsAI.Pipeline.Azure.SDK] Operation_2_2: n={n} param1={param1:.4f}");
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
    /// Azure Quantum SDK Job Submission — Seção 2, Operação 3
    /// Implementa lógica quântica para WindowsAI.Pipeline.Azure.SDK.Operation_2_3
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
        Message($"[WindowsAI.Pipeline.Azure.SDK] Operation_2_3: n={n} param1={param1:.4f}");
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
    /// Azure Quantum SDK Job Submission — Seção 2, Operação 4
    /// Implementa lógica quântica para WindowsAI.Pipeline.Azure.SDK.Operation_2_4
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
        Message($"[WindowsAI.Pipeline.Azure.SDK] Operation_2_4: n={n} param1={param1:.4f}");
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
    /// Azure Quantum SDK Job Submission — Seção 2, Operação 5
    /// Implementa lógica quântica para WindowsAI.Pipeline.Azure.SDK.Operation_2_5
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
        Message($"[WindowsAI.Pipeline.Azure.SDK] Operation_2_5: n={n} param1={param1:.4f}");
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
    /// Azure Quantum SDK Job Submission — Seção 2, Operação 6
    /// Implementa lógica quântica para WindowsAI.Pipeline.Azure.SDK.Operation_2_6
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
        Message($"[WindowsAI.Pipeline.Azure.SDK] Operation_2_6: n={n} param1={param1:.4f}");
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
    // SEÇÃO 3: Azure Quantum SDK Job Submission — Módulo 3
    // ────────────────────────────────────────────────────────────────────────
    /// # Summary
    /// Azure Quantum SDK Job Submission — Seção 3, Operação 1
    /// Implementa lógica quântica para WindowsAI.Pipeline.Azure.SDK.Operation_3_1
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
        Message($"[WindowsAI.Pipeline.Azure.SDK] Operation_3_1: n={n} param1={param1:.4f}");
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
    /// Azure Quantum SDK Job Submission — Seção 3, Operação 2
    /// Implementa lógica quântica para WindowsAI.Pipeline.Azure.SDK.Operation_3_2
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
        Message($"[WindowsAI.Pipeline.Azure.SDK] Operation_3_2: n={n} param1={param1:.4f}");
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
    /// Azure Quantum SDK Job Submission — Seção 3, Operação 3
    /// Implementa lógica quântica para WindowsAI.Pipeline.Azure.SDK.Operation_3_3
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
        Message($"[WindowsAI.Pipeline.Azure.SDK] Operation_3_3: n={n} param1={param1:.4f}");
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
    /// Azure Quantum SDK Job Submission — Seção 3, Operação 4
    /// Implementa lógica quântica para WindowsAI.Pipeline.Azure.SDK.Operation_3_4
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
        Message($"[WindowsAI.Pipeline.Azure.SDK] Operation_3_4: n={n} param1={param1:.4f}");
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
    /// Azure Quantum SDK Job Submission — Seção 3, Operação 5
    /// Implementa lógica quântica para WindowsAI.Pipeline.Azure.SDK.Operation_3_5
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
        Message($"[WindowsAI.Pipeline.Azure.SDK] Operation_3_5: n={n} param1={param1:.4f}");
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
    /// Azure Quantum SDK Job Submission — Seção 3, Operação 6
    /// Implementa lógica quântica para WindowsAI.Pipeline.Azure.SDK.Operation_3_6
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
        Message($"[WindowsAI.Pipeline.Azure.SDK] Operation_3_6: n={n} param1={param1:.4f}");
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
    // SEÇÃO 4: Azure Quantum SDK Job Submission — Módulo 4
    // ────────────────────────────────────────────────────────────────────────
    /// # Summary
    /// Azure Quantum SDK Job Submission — Seção 4, Operação 1
    /// Implementa lógica quântica para WindowsAI.Pipeline.Azure.SDK.Operation_4_1
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
        Message($"[WindowsAI.Pipeline.Azure.SDK] Operation_4_1: n={n} param1={param1:.4f}");
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
    /// Azure Quantum SDK Job Submission — Seção 4, Operação 2
    /// Implementa lógica quântica para WindowsAI.Pipeline.Azure.SDK.Operation_4_2
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
        Message($"[WindowsAI.Pipeline.Azure.SDK] Operation_4_2: n={n} param1={param1:.4f}");
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
    /// Azure Quantum SDK Job Submission — Seção 4, Operação 3
    /// Implementa lógica quântica para WindowsAI.Pipeline.Azure.SDK.Operation_4_3
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
        Message($"[WindowsAI.Pipeline.Azure.SDK] Operation_4_3: n={n} param1={param1:.4f}");
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
    /// Azure Quantum SDK Job Submission — Seção 4, Operação 4
    /// Implementa lógica quântica para WindowsAI.Pipeline.Azure.SDK.Operation_4_4
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
        Message($"[WindowsAI.Pipeline.Azure.SDK] Operation_4_4: n={n} param1={param1:.4f}");
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
    /// Azure Quantum SDK Job Submission — Seção 4, Operação 5
    /// Implementa lógica quântica para WindowsAI.Pipeline.Azure.SDK.Operation_4_5
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
        Message($"[WindowsAI.Pipeline.Azure.SDK] Operation_4_5: n={n} param1={param1:.4f}");
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
    /// Azure Quantum SDK Job Submission — Seção 4, Operação 6
    /// Implementa lógica quântica para WindowsAI.Pipeline.Azure.SDK.Operation_4_6
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
        Message($"[WindowsAI.Pipeline.Azure.SDK] Operation_4_6: n={n} param1={param1:.4f}");
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
    // SEÇÃO 5: Azure Quantum SDK Job Submission — Módulo 5
    // ────────────────────────────────────────────────────────────────────────
    /// # Summary
    /// Azure Quantum SDK Job Submission — Seção 5, Operação 1
    /// Implementa lógica quântica para WindowsAI.Pipeline.Azure.SDK.Operation_5_1
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
        Message($"[WindowsAI.Pipeline.Azure.SDK] Operation_5_1: n={n} param1={param1:.4f}");
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
    /// Azure Quantum SDK Job Submission — Seção 5, Operação 2
    /// Implementa lógica quântica para WindowsAI.Pipeline.Azure.SDK.Operation_5_2
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
        Message($"[WindowsAI.Pipeline.Azure.SDK] Operation_5_2: n={n} param1={param1:.4f}");
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
    /// Azure Quantum SDK Job Submission — Seção 5, Operação 3
    /// Implementa lógica quântica para WindowsAI.Pipeline.Azure.SDK.Operation_5_3
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
        Message($"[WindowsAI.Pipeline.Azure.SDK] Operation_5_3: n={n} param1={param1:.4f}");
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
    /// Azure Quantum SDK Job Submission — Seção 5, Operação 4
    /// Implementa lógica quântica para WindowsAI.Pipeline.Azure.SDK.Operation_5_4
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
        Message($"[WindowsAI.Pipeline.Azure.SDK] Operation_5_4: n={n} param1={param1:.4f}");
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
    /// Azure Quantum SDK Job Submission — Seção 5, Operação 5
    /// Implementa lógica quântica para WindowsAI.Pipeline.Azure.SDK.Operation_5_5
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
        Message($"[WindowsAI.Pipeline.Azure.SDK] Operation_5_5: n={n} param1={param1:.4f}");
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
    /// Azure Quantum SDK Job Submission — Seção 5, Operação 6
    /// Implementa lógica quântica para WindowsAI.Pipeline.Azure.SDK.Operation_5_6
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
        Message($"[WindowsAI.Pipeline.Azure.SDK] Operation_5_6: n={n} param1={param1:.4f}");
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
    // SEÇÃO 6: Azure Quantum SDK Job Submission — Módulo 6
    // ────────────────────────────────────────────────────────────────────────
    /// # Summary
    /// Azure Quantum SDK Job Submission — Seção 6, Operação 1
    /// Implementa lógica quântica para WindowsAI.Pipeline.Azure.SDK.Operation_6_1
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
        Message($"[WindowsAI.Pipeline.Azure.SDK] Operation_6_1: n={n} param1={param1:.4f}");
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
    /// Azure Quantum SDK Job Submission — Seção 6, Operação 2
    /// Implementa lógica quântica para WindowsAI.Pipeline.Azure.SDK.Operation_6_2
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
        Message($"[WindowsAI.Pipeline.Azure.SDK] Operation_6_2: n={n} param1={param1:.4f}");
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
    /// Azure Quantum SDK Job Submission — Seção 6, Operação 3
    /// Implementa lógica quântica para WindowsAI.Pipeline.Azure.SDK.Operation_6_3
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
        Message($"[WindowsAI.Pipeline.Azure.SDK] Operation_6_3: n={n} param1={param1:.4f}");
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
    /// Azure Quantum SDK Job Submission — Seção 6, Operação 4
    /// Implementa lógica quântica para WindowsAI.Pipeline.Azure.SDK.Operation_6_4
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
        Message($"[WindowsAI.Pipeline.Azure.SDK] Operation_6_4: n={n} param1={param1:.4f}");
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
    /// Azure Quantum SDK Job Submission — Seção 6, Operação 5
    /// Implementa lógica quântica para WindowsAI.Pipeline.Azure.SDK.Operation_6_5
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
        Message($"[WindowsAI.Pipeline.Azure.SDK] Operation_6_5: n={n} param1={param1:.4f}");
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
    /// Azure Quantum SDK Job Submission — Seção 6, Operação 6
    /// Implementa lógica quântica para WindowsAI.Pipeline.Azure.SDK.Operation_6_6
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
        Message($"[WindowsAI.Pipeline.Azure.SDK] Operation_6_6: n={n} param1={param1:.4f}");
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
    // SEÇÃO 7: Azure Quantum SDK Job Submission — Módulo 7
    // ────────────────────────────────────────────────────────────────────────
    /// # Summary
    /// Azure Quantum SDK Job Submission — Seção 7, Operação 1
    /// Implementa lógica quântica para WindowsAI.Pipeline.Azure.SDK.Operation_7_1
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
        Message($"[WindowsAI.Pipeline.Azure.SDK] Operation_7_1: n={n} param1={param1:.4f}");
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
    /// Azure Quantum SDK Job Submission — Seção 7, Operação 2
    /// Implementa lógica quântica para WindowsAI.Pipeline.Azure.SDK.Operation_7_2
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
        Message($"[WindowsAI.Pipeline.Azure.SDK] Operation_7_2: n={n} param1={param1:.4f}");
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
    /// Azure Quantum SDK Job Submission — Seção 7, Operação 3
    /// Implementa lógica quântica para WindowsAI.Pipeline.Azure.SDK.Operation_7_3
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
        Message($"[WindowsAI.Pipeline.Azure.SDK] Operation_7_3: n={n} param1={param1:.4f}");
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
    /// Azure Quantum SDK Job Submission — Seção 7, Operação 4
    /// Implementa lógica quântica para WindowsAI.Pipeline.Azure.SDK.Operation_7_4
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
        Message($"[WindowsAI.Pipeline.Azure.SDK] Operation_7_4: n={n} param1={param1:.4f}");
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
    /// Azure Quantum SDK Job Submission — Seção 7, Operação 5
    /// Implementa lógica quântica para WindowsAI.Pipeline.Azure.SDK.Operation_7_5
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
        Message($"[WindowsAI.Pipeline.Azure.SDK] Operation_7_5: n={n} param1={param1:.4f}");
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
    /// Azure Quantum SDK Job Submission — Seção 7, Operação 6
    /// Implementa lógica quântica para WindowsAI.Pipeline.Azure.SDK.Operation_7_6
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
        Message($"[WindowsAI.Pipeline.Azure.SDK] Operation_7_6: n={n} param1={param1:.4f}");
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
    // SEÇÃO 8: Azure Quantum SDK Job Submission — Módulo 8
    // ────────────────────────────────────────────────────────────────────────
    /// # Summary
    /// Azure Quantum SDK Job Submission — Seção 8, Operação 1
    /// Implementa lógica quântica para WindowsAI.Pipeline.Azure.SDK.Operation_8_1
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
        Message($"[WindowsAI.Pipeline.Azure.SDK] Operation_8_1: n={n} param1={param1:.4f}");
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
    /// Azure Quantum SDK Job Submission — Seção 8, Operação 2
    /// Implementa lógica quântica para WindowsAI.Pipeline.Azure.SDK.Operation_8_2
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
        Message($"[WindowsAI.Pipeline.Azure.SDK] Operation_8_2: n={n} param1={param1:.4f}");
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
    /// Azure Quantum SDK Job Submission — Seção 8, Operação 3
    /// Implementa lógica quântica para WindowsAI.Pipeline.Azure.SDK.Operation_8_3
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
        Message($"[WindowsAI.Pipeline.Azure.SDK] Operation_8_3: n={n} param1={param1:.4f}");
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
    /// Azure Quantum SDK Job Submission — Seção 8, Operação 4
    /// Implementa lógica quântica para WindowsAI.Pipeline.Azure.SDK.Operation_8_4
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
        Message($"[WindowsAI.Pipeline.Azure.SDK] Operation_8_4: n={n} param1={param1:.4f}");
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
    /// Azure Quantum SDK Job Submission — Seção 8, Operação 5
    /// Implementa lógica quântica para WindowsAI.Pipeline.Azure.SDK.Operation_8_5
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
        Message($"[WindowsAI.Pipeline.Azure.SDK] Operation_8_5: n={n} param1={param1:.4f}");
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
    /// Azure Quantum SDK Job Submission — Seção 8, Operação 6
    /// Implementa lógica quântica para WindowsAI.Pipeline.Azure.SDK.Operation_8_6
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
        Message($"[WindowsAI.Pipeline.Azure.SDK] Operation_8_6: n={n} param1={param1:.4f}");
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
    // SEÇÃO 9: Azure Quantum SDK Job Submission — Módulo 9
    // ────────────────────────────────────────────────────────────────────────
    /// # Summary
    /// Azure Quantum SDK Job Submission — Seção 9, Operação 1
    /// Implementa lógica quântica para WindowsAI.Pipeline.Azure.SDK.Operation_9_1
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
        Message($"[WindowsAI.Pipeline.Azure.SDK] Operation_9_1: n={n} param1={param1:.4f}");
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
    /// Azure Quantum SDK Job Submission — Seção 9, Operação 2
    /// Implementa lógica quântica para WindowsAI.Pipeline.Azure.SDK.Operation_9_2
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
        Message($"[WindowsAI.Pipeline.Azure.SDK] Operation_9_2: n={n} param1={param1:.4f}");
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
    /// Azure Quantum SDK Job Submission — Seção 9, Operação 3
    /// Implementa lógica quântica para WindowsAI.Pipeline.Azure.SDK.Operation_9_3
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
        Message($"[WindowsAI.Pipeline.Azure.SDK] Operation_9_3: n={n} param1={param1:.4f}");
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
    /// Azure Quantum SDK Job Submission — Seção 9, Operação 4
    /// Implementa lógica quântica para WindowsAI.Pipeline.Azure.SDK.Operation_9_4
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
        Message($"[WindowsAI.Pipeline.Azure.SDK] Operation_9_4: n={n} param1={param1:.4f}");
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
    /// Azure Quantum SDK Job Submission — Seção 9, Operação 5
    /// Implementa lógica quântica para WindowsAI.Pipeline.Azure.SDK.Operation_9_5
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
        Message($"[WindowsAI.Pipeline.Azure.SDK] Operation_9_5: n={n} param1={param1:.4f}");
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
    /// Azure Quantum SDK Job Submission — Seção 9, Operação 6
    /// Implementa lógica quântica para WindowsAI.Pipeline.Azure.SDK.Operation_9_6
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
        Message($"[WindowsAI.Pipeline.Azure.SDK] Operation_9_6: n={n} param1={param1:.4f}");
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
    // SEÇÃO 10: Azure Quantum SDK Job Submission — Módulo 10
    // ────────────────────────────────────────────────────────────────────────
    /// # Summary
    /// Azure Quantum SDK Job Submission — Seção 10, Operação 1
    /// Implementa lógica quântica para WindowsAI.Pipeline.Azure.SDK.Operation_10_1
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
        Message($"[WindowsAI.Pipeline.Azure.SDK] Operation_10_1: n={n} param1={param1:.4f}");
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
    /// Azure Quantum SDK Job Submission — Seção 10, Operação 2
    /// Implementa lógica quântica para WindowsAI.Pipeline.Azure.SDK.Operation_10_2
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
        Message($"[WindowsAI.Pipeline.Azure.SDK] Operation_10_2: n={n} param1={param1:.4f}");
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
    /// Azure Quantum SDK Job Submission — Seção 10, Operação 3
    /// Implementa lógica quântica para WindowsAI.Pipeline.Azure.SDK.Operation_10_3
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
        Message($"[WindowsAI.Pipeline.Azure.SDK] Operation_10_3: n={n} param1={param1:.4f}");
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
    /// Azure Quantum SDK Job Submission — Seção 10, Operação 4
    /// Implementa lógica quântica para WindowsAI.Pipeline.Azure.SDK.Operation_10_4
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
        Message($"[WindowsAI.Pipeline.Azure.SDK] Operation_10_4: n={n} param1={param1:.4f}");
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
    /// Azure Quantum SDK Job Submission — Seção 10, Operação 5
    /// Implementa lógica quântica para WindowsAI.Pipeline.Azure.SDK.Operation_10_5
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
        Message($"[WindowsAI.Pipeline.Azure.SDK] Operation_10_5: n={n} param1={param1:.4f}");
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
    /// Azure Quantum SDK Job Submission — Seção 10, Operação 6
    /// Implementa lógica quântica para WindowsAI.Pipeline.Azure.SDK.Operation_10_6
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
        Message($"[WindowsAI.Pipeline.Azure.SDK] Operation_10_6: n={n} param1={param1:.4f}");
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
    // SEÇÃO 11: Azure Quantum SDK Job Submission — Módulo 11
    // ────────────────────────────────────────────────────────────────────────
    /// # Summary
    /// Azure Quantum SDK Job Submission — Seção 11, Operação 1
    /// Implementa lógica quântica para WindowsAI.Pipeline.Azure.SDK.Operation_11_1
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
        Message($"[WindowsAI.Pipeline.Azure.SDK] Operation_11_1: n={n} param1={param1:.4f}");
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
    /// Azure Quantum SDK Job Submission — Seção 11, Operação 2
    /// Implementa lógica quântica para WindowsAI.Pipeline.Azure.SDK.Operation_11_2
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
        Message($"[WindowsAI.Pipeline.Azure.SDK] Operation_11_2: n={n} param1={param1:.4f}");
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
    /// Azure Quantum SDK Job Submission — Seção 11, Operação 3
    /// Implementa lógica quântica para WindowsAI.Pipeline.Azure.SDK.Operation_11_3
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
        Message($"[WindowsAI.Pipeline.Azure.SDK] Operation_11_3: n={n} param1={param1:.4f}");
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
    /// Azure Quantum SDK Job Submission — Seção 11, Operação 4
    /// Implementa lógica quântica para WindowsAI.Pipeline.Azure.SDK.Operation_11_4
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
        Message($"[WindowsAI.Pipeline.Azure.SDK] Operation_11_4: n={n} param1={param1:.4f}");
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
    /// Azure Quantum SDK Job Submission — Seção 11, Operação 5
    /// Implementa lógica quântica para WindowsAI.Pipeline.Azure.SDK.Operation_11_5
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
        Message($"[WindowsAI.Pipeline.Azure.SDK] Operation_11_5: n={n} param1={param1:.4f}");
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
    /// Azure Quantum SDK Job Submission — Seção 11, Operação 6
    /// Implementa lógica quântica para WindowsAI.Pipeline.Azure.SDK.Operation_11_6
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
        Message($"[WindowsAI.Pipeline.Azure.SDK] Operation_11_6: n={n} param1={param1:.4f}");
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
    // SEÇÃO 12: Azure Quantum SDK Job Submission — Módulo 12
    // ────────────────────────────────────────────────────────────────────────
    /// # Summary
    /// Azure Quantum SDK Job Submission — Seção 12, Operação 1
    /// Implementa lógica quântica para WindowsAI.Pipeline.Azure.SDK.Operation_12_1
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
        Message($"[WindowsAI.Pipeline.Azure.SDK] Operation_12_1: n={n} param1={param1:.4f}");
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
    /// Azure Quantum SDK Job Submission — Seção 12, Operação 2
    /// Implementa lógica quântica para WindowsAI.Pipeline.Azure.SDK.Operation_12_2
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
        Message($"[WindowsAI.Pipeline.Azure.SDK] Operation_12_2: n={n} param1={param1:.4f}");
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
    /// Azure Quantum SDK Job Submission — Seção 12, Operação 3
    /// Implementa lógica quântica para WindowsAI.Pipeline.Azure.SDK.Operation_12_3
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
        Message($"[WindowsAI.Pipeline.Azure.SDK] Operation_12_3: n={n} param1={param1:.4f}");
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
    /// Azure Quantum SDK Job Submission — Seção 12, Operação 4
    /// Implementa lógica quântica para WindowsAI.Pipeline.Azure.SDK.Operation_12_4
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
        Message($"[WindowsAI.Pipeline.Azure.SDK] Operation_12_4: n={n} param1={param1:.4f}");
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
    /// Azure Quantum SDK Job Submission — Seção 12, Operação 5
    /// Implementa lógica quântica para WindowsAI.Pipeline.Azure.SDK.Operation_12_5
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
        Message($"[WindowsAI.Pipeline.Azure.SDK] Operation_12_5: n={n} param1={param1:.4f}");
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
    /// Azure Quantum SDK Job Submission — Seção 12, Operação 6
    /// Implementa lógica quântica para WindowsAI.Pipeline.Azure.SDK.Operation_12_6
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
        Message($"[WindowsAI.Pipeline.Azure.SDK] Operation_12_6: n={n} param1={param1:.4f}");
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
    operation SDKMain() : Unit {
        Message("╔══════════════════════════════════════════╗");
        Message("║  Azure Quantum SDK Job Submission          ║");
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
        Message("  ✓ Azure Quantum SDK Job Submission concluído");
    }
}
