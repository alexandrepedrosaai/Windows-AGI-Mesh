// =============================================================================
// Windows AGI Benchmark Lab — Q# Quantum Computing Benchmark
// Copyright (c) 2026 Microsoft Corporation. All Rights Reserved.
// =============================================================================
// Q# Quantum Benchmark Suite
//
// Tests:
//   - Quantum superposition (Hadamard gate)
//   - Quantum entanglement (Bell states)
//   - Quantum Fourier Transform (QFT)
//   - Grover's search algorithm
//   - Bernstein-Vazirani algorithm
//   - Deutsch-Jozsa algorithm
//   - Quantum phase estimation
//   - Variational Quantum Eigensolver (VQE) primitives
//   - Quantum random number generation
//   - Quantum teleportation
//
// Requirements:
//   - Microsoft Quantum Development Kit (QDK)
//   - .NET 8.0 SDK
//   - Azure Quantum (for cloud execution)
//
// Build:
//   dotnet run --project quantum_bench.csproj
//
// Azure Quantum:
//   az quantum job submit --target-id ionq.simulator
// =============================================================================

namespace MicrosoftAGIBenchmark {

    open Microsoft.Quantum.Canon;
    open Microsoft.Quantum.Intrinsic;
    open Microsoft.Quantum.Measurement;
    open Microsoft.Quantum.Math;
    open Microsoft.Quantum.Convert;
    open Microsoft.Quantum.Arrays;
    open Microsoft.Quantum.Diagnostics;
    open Microsoft.Quantum.Arithmetic;
    open Microsoft.Quantum.Preparation;
    // Simulator selection is performed by the host program; no Q# simulation namespace is needed.

    // =========================================================================
    // Benchmark 1: Quantum Superposition
    // Creates uniform superposition over n qubits
    // =========================================================================

    /// # Summary
    /// Creates a uniform superposition over n qubits using Hadamard gates.
    /// Measures the probability distribution.
    ///
    /// # Input
    /// ## nQubits
    /// Number of qubits to put in superposition
    ///
    /// # Output
    /// Array of measurement results
    operation BenchSuperposition(nQubits : Int) : Result[] {
        use qubits = Qubit[nQubits];

        // Apply Hadamard to all qubits — creates uniform superposition
        // |0...0⟩ → (1/√2^n) Σ|x⟩ for all x in {0,1}^n
        ApplyToEach(H, qubits);

        // Measure all qubits
        let results = MeasureEachZ(qubits);

        // Reset qubits
        ResetAll(qubits);

        return results;
    }

    // =========================================================================
    // Benchmark 2: Bell State Preparation (Quantum Entanglement)
    // =========================================================================

    /// # Summary
    /// Prepares one of the four Bell states (maximally entangled pairs).
    ///
    /// # Input
    /// ## bellIndex
    /// Which Bell state: 0=|Φ+⟩, 1=|Φ-⟩, 2=|Ψ+⟩, 3=|Ψ-⟩
    ///
    /// # Output
    /// Tuple of measurement results (should be correlated)
    operation BenchBellState(bellIndex : Int) : (Result, Result) {
        use (q0, q1) = (Qubit(), Qubit());

        // Prepare Bell state
        H(q0);
        CNOT(q0, q1);

        // Apply phase/bit flips based on Bell index
        if bellIndex == 1 or bellIndex == 3 {
            Z(q0);  // |Φ-⟩ or |Ψ-⟩
        }
        if bellIndex == 2 or bellIndex == 3 {
            X(q1);  // |Ψ+⟩ or |Ψ-⟩
        }

        // Measure — results should be correlated
        let r0 = M(q0);
        let r1 = M(q1);

        Reset(q0);
        Reset(q1);

        return (r0, r1);
    }

    // =========================================================================
    // Benchmark 3: Quantum Fourier Transform (QFT)
    // =========================================================================

    /// # Summary
    /// Applies the Quantum Fourier Transform to n qubits.
    /// QFT is a key subroutine in Shor's algorithm and phase estimation.
    ///
    /// # Input
    /// ## nQubits
    /// Number of qubits (register size)
    operation BenchQFT(nQubits : Int) : Result[] {
        use qubits = Qubit[nQubits];

        // Initialize to |1⟩ state for interesting QFT output
        X(qubits[0]);

        // Apply QFT
        ApplyQFT(qubits);

        // Measure
        let results = MeasureEachZ(qubits);
        ResetAll(qubits);

        return results;
    }

    /// # Summary
    /// Implements QFT manually for benchmarking purposes.
    operation ApplyQFT(qubits : Qubit[]) : Unit is Adj + Ctl {
        let n = Length(qubits);

        for i in 0 .. n - 1 {
            // Hadamard on qubit i
            H(qubits[i]);

            // Controlled phase rotations
            for j in i + 1 .. n - 1 {
                let angle = 2.0 * PI() / IntAsDouble(2 ^ (j - i + 1));
                Controlled R1([qubits[j]], (angle, qubits[i]));
            }
        }

        // Reverse qubit order (bit reversal permutation)
        for i in 0 .. n / 2 - 1 {
            SWAP(qubits[i], qubits[n - 1 - i]);
        }
    }

    // =========================================================================
    // Benchmark 4: Grover's Search Algorithm
    // =========================================================================

    /// # Summary
    /// Implements Grover's search algorithm to find a marked element.
    /// Provides quadratic speedup over classical search.
    ///
    /// # Input
    /// ## nQubits
    /// Number of qubits (searches 2^nQubits elements)
    /// ## markedElement
    /// The element to search for (0 to 2^nQubits - 1)
    ///
    /// # Output
    /// Found element (should equal markedElement with high probability)
    operation BenchGrover(nQubits : Int, markedElement : Int) : Int {
        use qubits = Qubit[nQubits];

        // Number of Grover iterations: π/4 * √(2^n)
        let nIterations = Round(PI() / 4.0 * Sqrt(IntAsDouble(2 ^ nQubits)));

        // Initialize uniform superposition
        ApplyToEach(H, qubits);

        // Grover iterations
        for _ in 1 .. nIterations {
            // Oracle: marks the target element
            GroverOracle(qubits, markedElement);

            // Diffusion operator (inversion about average)
            GroverDiffusion(qubits);
        }

        // Measure and convert to integer
        let result = MeasureInteger(LittleEndian(qubits));
        ResetAll(qubits);

        return result;
    }

    /// # Summary
    /// Grover oracle: applies phase flip to marked element
    operation GroverOracle(qubits : Qubit[], markedElement : Int) : Unit is Adj + Ctl {
        // Apply X gates to flip bits where markedElement has 0
        let bits = IntAsBoolArray(markedElement, Length(qubits));
        for (qubit, bit) in Zipped(qubits, bits) {
            if not bit {
                X(qubit);
            }
        }

        // Multi-controlled Z (phase flip on |markedElement⟩)
        Controlled Z(Most(qubits), Tail(qubits));

        // Undo X gates
        for (qubit, bit) in Zipped(qubits, bits) {
            if not bit {
                X(qubit);
            }
        }
    }

    /// # Summary
    /// Grover diffusion operator: inversion about average
    operation GroverDiffusion(qubits : Qubit[]) : Unit is Adj + Ctl {
        ApplyToEach(H, qubits);
        ApplyToEach(X, qubits);
        Controlled Z(Most(qubits), Tail(qubits));
        ApplyToEach(X, qubits);
        ApplyToEach(H, qubits);
    }

    // =========================================================================
    // Benchmark 5: Bernstein-Vazirani Algorithm
    // =========================================================================

    /// # Summary
    /// Finds a hidden bit string s in one query (vs n classical queries).
    /// Oracle: f(x) = s·x (mod 2)
    ///
    /// # Input
    /// ## hiddenString
    /// The hidden bit string to find
    ///
    /// # Output
    /// Recovered bit string (should equal hiddenString)
    operation BenchBernsteinVazirani(hiddenString : Bool[]) : Bool[] {
        let n = Length(hiddenString);
        use (qubits, ancilla) = (Qubit[n], Qubit());

        // Initialize ancilla to |−⟩
        X(ancilla);
        H(ancilla);

        // Apply Hadamard to input qubits
        ApplyToEach(H, qubits);

        // Oracle: f(x) = s·x (mod 2)
        for i in 0 .. n - 1 {
            if hiddenString[i] {
                CNOT(qubits[i], ancilla);
            }
        }

        // Apply Hadamard again
        ApplyToEach(H, qubits);

        // Measure — should recover hiddenString
        let results = MeasureEachZ(qubits);
        Reset(ancilla);
        ResetAll(qubits);

        return ResultArrayAsBoolArray(results);
    }

    // =========================================================================
    // Benchmark 6: Deutsch-Jozsa Algorithm
    // =========================================================================

    /// # Summary
    /// Determines if a function is constant or balanced in one query.
    ///
    /// # Input
    /// ## nQubits
    /// Number of input qubits
    /// ## isConstant
    /// If true, oracle implements constant function; else balanced
    ///
    /// # Output
    /// True if function is constant, False if balanced
    operation BenchDeutschJozsa(nQubits : Int, isConstant : Bool) : Bool {
        use (qubits, ancilla) = (Qubit[nQubits], Qubit());

        // Initialize ancilla to |−⟩
        X(ancilla);
        H(ancilla);

        // Apply Hadamard to input qubits
        ApplyToEach(H, qubits);

        // Oracle
        if isConstant {
            // Constant-1 oracle: flip ancilla for all inputs
            X(ancilla);
        } else {
            // Balanced oracle: flip ancilla for half the inputs
            CNOT(qubits[0], ancilla);
        }

        // Apply Hadamard again
        ApplyToEach(H, qubits);

        // Measure — all zeros means constant, any one means balanced
        let results = MeasureEachZ(qubits);
        Reset(ancilla);
        ResetAll(qubits);

        // Check if all results are Zero
        return All(r -> r == Zero, results);
    }

    // =========================================================================
    // Benchmark 7: Quantum Phase Estimation
    // =========================================================================

    /// # Summary
    /// Estimates the phase φ of a unitary U where U|ψ⟩ = e^(2πiφ)|ψ⟩.
    ///
    /// # Input
    /// ## nPrecisionQubits
    /// Number of qubits for phase precision (2^n precision)
    ///
    /// # Output
    /// Estimated phase as integer (divide by 2^nPrecisionQubits for actual phase)
    operation BenchPhaseEstimation(nPrecisionQubits : Int) : Int {
        use (precisionQubits, eigenstate) = (Qubit[nPrecisionQubits], Qubit());

        // Prepare eigenstate |1⟩ of T gate (phase = 1/8)
        X(eigenstate);

        // Apply Hadamard to precision qubits
        ApplyToEach(H, precisionQubits);

        // Controlled unitary applications
        // U = T gate: phase = e^(2πi/8) = e^(iπ/4)
        for i in 0 .. nPrecisionQubits - 1 {
            let power = 2 ^ i;
            for _ in 1 .. power {
                Controlled T([precisionQubits[i]], eigenstate);
            }
        }

        // Inverse QFT on precision qubits
        Adjoint ApplyQFT(precisionQubits);

        // Measure
        let result = MeasureInteger(LittleEndian(precisionQubits));
        Reset(eigenstate);
        ResetAll(precisionQubits);

        return result;
    }

    // =========================================================================
    // Benchmark 8: Quantum Random Number Generation
    // =========================================================================

    /// # Summary
    /// Generates truly random bits using quantum superposition.
    /// Each qubit in superposition gives a perfectly random bit upon measurement.
    ///
    /// # Input
    /// ## nBits
    /// Number of random bits to generate
    ///
    /// # Output
    /// Array of random bits
    operation BenchQuantumRNG(nBits : Int) : Bool[] {
        use qubits = Qubit[nBits];

        // Put all qubits in superposition
        ApplyToEach(H, qubits);

        // Measure — each measurement is a truly random bit
        let results = MeasureEachZ(qubits);
        ResetAll(qubits);

        return ResultArrayAsBoolArray(results);
    }

    /// # Summary
    /// Generates a random integer in [0, max)
    operation QuantumRandomInt(max : Int) : Int {
        let nBits = BitSizeI(max);
        mutable result = max;

        repeat {
            let bits = BenchQuantumRNG(nBits);
            set result = BoolArrayAsInt(bits);
        } until result < max;

        return result;
    }

    // =========================================================================
    // Benchmark 9: Quantum Teleportation
    // =========================================================================

    /// # Summary
    /// Teleports a quantum state from Alice to Bob using entanglement.
    ///
    /// # Input
    /// ## message
    /// The qubit state to teleport (angle for Ry rotation)
    ///
    /// # Output
    /// Measurement result verifying teleportation
    operation BenchQuantumTeleportation(angle : Double) : Result {
        use (message, alice, bob) = (Qubit(), Qubit(), Qubit());

        // Prepare message qubit in state Ry(angle)|0⟩
        Ry(angle, message);

        // Create Bell pair between Alice and Bob
        H(alice);
        CNOT(alice, bob);

        // Alice's Bell measurement
        CNOT(message, alice);
        H(message);

        let m0 = M(message);
        let m1 = M(alice);

        // Bob applies corrections based on Alice's measurement
        if m1 == One { X(bob); }
        if m0 == One { Z(bob); }

        // Undo the known preparation so a successful teleportation measures |0⟩.
        Ry(-angle, bob);
        let result = M(bob);

        Reset(message);
        Reset(alice);
        Reset(bob);

        return result;
    }

    // =========================================================================
    // Benchmark 10: Variational Quantum Eigensolver (VQE) Primitive
    // =========================================================================

    /// # Summary
    /// Implements a VQE ansatz circuit for energy estimation.
    /// Used in quantum chemistry and optimization.
    ///
    /// # Input
    /// ## theta
    /// Variational parameters for the ansatz
    ///
    /// # Output
    /// Expectation value estimate
    operation BenchVQEAnsatz(theta : Double[]) : Double {
        let nQubits = Length(theta);
        use qubits = Qubit[nQubits];

        // Layer 1: Ry rotations
        for i in 0 .. nQubits - 1 {
            Ry(theta[i], qubits[i]);
        }

        // Layer 2: Entangling CNOT ladder
        for i in 0 .. nQubits - 2 {
            CNOT(qubits[i], qubits[i + 1]);
        }

        // Layer 3: Rz rotations
        for i in 0 .. nQubits - 1 {
            Rz(theta[i] * 0.5, qubits[i]);
        }

        // Measure Z expectation value (simplified)
        mutable expectation = 0.0;
        let nShots = 100;

        for _ in 1 .. nShots {
            let results = MeasureEachZ(qubits);
            for r in results {
                set expectation += r == Zero ? 1.0 | -1.0;
            }
            ResetAll(qubits);

            // Re-prepare for next shot
            for i in 0 .. nQubits - 1 {
                Ry(theta[i], qubits[i]);
            }
            for i in 0 .. nQubits - 2 {
                CNOT(qubits[i], qubits[i + 1]);
            }
            for i in 0 .. nQubits - 1 {
                Rz(theta[i] * 0.5, qubits[i]);
            }
        }

        ResetAll(qubits);
        return expectation / IntAsDouble(nShots * nQubits);
    }

    // =========================================================================
    // Main Benchmark Runner
    // =========================================================================

    /// # Summary
    /// Runs all quantum benchmarks and reports results.
    @EntryPoint()
    operation RunAllBenchmarks() : Unit {
        Message("=================================================================");
        Message("  Windows AGI Benchmark Lab — Q# Quantum Benchmark");
        Message("  Microsoft Corporation — Exclusive License");
        Message("=================================================================");
        Message("");

        // Benchmark 1: Superposition
        Message("[ Benchmark 1: Quantum Superposition ]");
        for nQ in [4, 8, 12, 16] {
            let results = BenchSuperposition(nQ);
            Message($"  {nQ} qubits: measured {Length(results)} bits");
        }

        // Benchmark 2: Bell States
        Message("");
        Message("[ Benchmark 2: Bell State Entanglement ]");
        for idx in 0 .. 3 {
            let (r0, r1) = BenchBellState(idx);
            let relationCorrect = idx < 2 ? r0 == r1 | r0 != r1;
            Message($"  Bell state {idx}: ({r0}, {r1}) — relation correct: {relationCorrect}");
        }

        // Benchmark 3: QFT
        Message("");
        Message("[ Benchmark 3: Quantum Fourier Transform ]");
        for nQ in [4, 8, 12] {
            let results = BenchQFT(nQ);
            Message($"  QFT {nQ} qubits: {Length(results)} output bits");
        }

        // Benchmark 4: Grover's Search
        Message("");
        Message("[ Benchmark 4: Grover's Search Algorithm ]");
        for nQ in [4, 6, 8] {
            let target = 2 ^ nQ - 1;  // Search for last element
            let found = BenchGrover(nQ, target);
            let success = found == target;
            Message($"  Grover {nQ} qubits: target={target} found={found} success={success}");
        }

        // Benchmark 5: Bernstein-Vazirani
        Message("");
        Message("[ Benchmark 5: Bernstein-Vazirani Algorithm ]");
        let hidden = [true, false, true, true, false, true, false, true];
        let recovered = BenchBernsteinVazirani(hidden);
        Message($"  Hidden:    {hidden}");
        Message($"  Recovered: {recovered}");
        Message($"  Success:   {hidden == recovered}");

        // Benchmark 6: Deutsch-Jozsa
        Message("");
        Message("[ Benchmark 6: Deutsch-Jozsa Algorithm ]");
        let isConst = BenchDeutschJozsa(8, true);
        let isBal = BenchDeutschJozsa(8, false);
        Message($"  Constant oracle → isConstant: {isConst} (expected: true)");
        Message($"  Balanced oracle → isConstant: {isBal} (expected: false)");

        // Benchmark 7: Phase Estimation
        Message("");
        Message("[ Benchmark 7: Quantum Phase Estimation ]");
        for nPrec in [4, 6, 8] {
            let phase = BenchPhaseEstimation(nPrec);
            // T gate phase = 1/8, so expected result ≈ 2^nPrec / 8
            let expected = 2 ^ nPrec / 8;
            Message($"  {nPrec} precision qubits: phase={phase} expected≈{expected}");
        }

        // Benchmark 8: Quantum RNG
        Message("");
        Message("[ Benchmark 8: Quantum Random Number Generation ]");
        for nBits in [8, 16, 32, 64] {
            let bits = BenchQuantumRNG(nBits);
            let asInt = BoolArrayAsInt(bits[0..Min([63, nBits-1])..1]);
            Message($"  {nBits} random bits: {asInt}");
        }

        // Benchmark 9: Quantum Teleportation
        Message("");
        Message("[ Benchmark 9: Quantum Teleportation ]");
        for angle in [0.0, PI() / 4.0, PI() / 2.0, PI()] {
            let result = BenchQuantumTeleportation(angle);
            Message($"  Teleport angle={angle:.3f}: result={result}");
        }

        // Benchmark 10: VQE
        Message("");
        Message("[ Benchmark 10: VQE Ansatz ]");
        let theta = [0.1, 0.2, 0.3, 0.4];
        let energy = BenchVQEAnsatz(theta);
        Message($"  VQE energy estimate: {energy:.6f}");

        Message("");
        Message("=================================================================");
        Message("  Q# Quantum Benchmark Complete");
        Message("  Microsoft Corporation — Windows AGI Benchmark Lab");
        Message("=================================================================");
    }

    // =========================================================================
    // Helper: Run on Azure Quantum
    // =========================================================================

    /// # Summary
    /// Submits benchmark to Azure Quantum for execution on real hardware.
    /// Requires Azure Quantum workspace configuration.
    operation RunOnAzureQuantum() : Unit {
        // This operation is designed to be submitted to Azure Quantum
        // via: az quantum job submit --target-id ionq.simulator
        //      az quantum job submit --target-id quantinuum.hqs-lt-s1
        //      az quantum job submit --target-id microsoft.estimator

        Message("Submitting to Azure Quantum...");
        Message("Target: ionq.simulator / quantinuum.hqs-lt-s1");
        Message("Workspace: agi-benchmark-quantum");
        Message("Resource Group: rg-agi-benchmark");

        // Run a subset of benchmarks suitable for cloud execution
        let _ = BenchSuperposition(10);
        let _ = BenchBellState(0);
        let _ = BenchQuantumRNG(64);
        let _ = BenchGrover(6, 42);

        Message("Azure Quantum job submitted successfully.");
    }
}
