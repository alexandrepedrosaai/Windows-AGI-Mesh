// =============================================================================
// Circuits.qs — Parameterized quantum circuits for LLM hybrid layers
// Majorana 1 topological qubits | Surface code QEC | Variational ansätze
// =============================================================================

namespace WindowsAGI.QuantumSDK.Circuits {

    import Std.Arrays.*;
    import Std.Convert.*;
    import Std.Intrinsic.*;
    import Std.Math.*;
    import Std.Measurement.*;

    import WindowsAGI.QuantumSDK.Types.*;
    import WindowsAGI.QuantumSDK.Validation.*;

    // ─────────────────────────────────────────────────────────────────────────
    // Core parameterized state preparation
    // ─────────────────────────────────────────────────────────────────────────
    operation PrepareParameterizedState(
        input    : Qubit[],
        ancillas : Qubit[],
        thetaZ   : Double,
        thetaY   : Double
    ) : Unit is Adj + Ctl {
        let inputCount   = Length(input);
        let ancillaCount = Length(ancillas);

        ApplyToEach(H, input);

        if inputCount > 1 {
            for index in 0..inputCount - 2 {
                CNOT(input[index], input[index + 1]);
                let denom = IntAsDouble(index + 1);
                Rz(thetaZ * PI() / denom, input[index]);
                Ry(thetaY * PI() / denom, input[index + 1]);
            }
        }

    }

    // ─────────────────────────────────────────────────────────────────────────
    // Hardware-efficient ansatz (HEA) for VQE / QAOA
    // ─────────────────────────────────────────────────────────────────────────
    operation HardwareEfficientAnsatz(
        qubits  : Qubit[],
        thetas  : Double[],
        layers  : Int
    ) : Unit is Adj + Ctl {
        let n = Length(qubits);
        let paramsPerLayer = 2 * n;
        if Length(thetas) < layers * paramsPerLayer {
            fail $"HEA: need {layers * paramsPerLayer} parameters, got {Length(thetas)}.";
        }
        for layer in 0..layers - 1 {
            let offset = layer * paramsPerLayer;
            for i in 0..n - 1 {
                Ry(thetas[offset + i], qubits[i]);
                Rz(thetas[offset + n + i], qubits[i]);
            }
            for i in 0..n - 2 {
                CNOT(qubits[i], qubits[i + 1]);
            }
            if n > 2 {
                CNOT(qubits[n - 1], qubits[0]);
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Quantum Fourier Transform
    // ─────────────────────────────────────────────────────────────────────────
    operation QFT(qubits : Qubit[]) : Unit is Adj + Ctl {
        let n = Length(qubits);
        for i in 0..n - 1 {
            H(qubits[i]);
            for j in i + 1..n - 1 {
                let angle = PI() / IntAsDouble(1 <<< (j - i));
                Controlled R1([qubits[j]], (angle, qubits[i]));
            }
        }
        for i in 0..n / 2 - 1 {
            SWAP(qubits[i], qubits[n - 1 - i]);
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Inverse QFT
    // ─────────────────────────────────────────────────────────────────────────
    operation InverseQFT(qubits : Qubit[]) : Unit is Adj + Ctl {
        Adjoint QFT(qubits);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Quantum Phase Estimation
    // ─────────────────────────────────────────────────────────────────────────
    operation QuantumPhaseEstimation(
        ancillas    : Qubit[],
        eigenstate  : Qubit[],
        oracle      : (Int, Qubit[]) => Unit is Ctl
    ) : Unit {
        let m = Length(ancillas);
        ApplyToEach(H, ancillas);
        for j in 0..m - 1 {
            let power = 1 <<< j;
            Controlled oracle([ancillas[j]], (power, eigenstate));
        }
        Adjoint QFT(ancillas);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Grover diffusion operator
    // ─────────────────────────────────────────────────────────────────────────
    operation GroverDiffusion(qubits : Qubit[]) : Unit is Adj + Ctl {
        ApplyToEach(H, qubits);
        ApplyToEach(X, qubits);
        Controlled Z(Most(qubits), Tail(qubits));
        ApplyToEach(X, qubits);
        ApplyToEach(H, qubits);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Bell state preparation
    // ─────────────────────────────────────────────────────────────────────────
    operation PrepareBellState(q0 : Qubit, q1 : Qubit, bellIndex : Int) : Unit is Adj + Ctl {
        H(q0);
        CNOT(q0, q1);
        if bellIndex == 1 { Z(q0); }
        elif bellIndex == 2 { X(q1); }
        elif bellIndex == 3 { Z(q0); X(q1); }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // GHZ state preparation
    // ─────────────────────────────────────────────────────────────────────────
    operation PrepareGHZState(qubits : Qubit[]) : Unit is Adj + Ctl {
        let n = Length(qubits);
        if n < 2 { fail "GHZ requires at least 2 qubits."; }
        H(qubits[0]);
        for i in 1..n - 1 { CNOT(qubits[0], qubits[i]); }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // W state preparation
    // ─────────────────────────────────────────────────────────────────────────
    operation PrepareWState(qubits : Qubit[]) : Unit {
        let n = Length(qubits);
        if n < 2 { fail "W state requires at least 2 qubits."; }
        X(qubits[0]);
        for i in 0..n - 2 {
            let angle = 2.0 * ArcCos(Sqrt(1.0 / IntAsDouble(n - i)));
            Controlled Ry([qubits[i]], (angle, qubits[i + 1]));
            CNOT(qubits[i + 1], qubits[i]);
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Quantum attention circuit (for LLM hybrid layers)
    // ─────────────────────────────────────────────────────────────────────────
    operation QuantumAttentionCircuit(
        queryQubits : Qubit[],
        keyQubits   : Qubit[],
        valueQubits : Qubit[],
        thetas      : Double[]
    ) : Unit is Adj + Ctl {
        let nQ = Length(queryQubits);
        let nK = Length(keyQubits);
        let nV = Length(valueQubits);

        // Encode query
        for i in 0..nQ - 1 {
            Ry(thetas[i], queryQubits[i]);
        }

        // Encode key
        for i in 0..nK - 1 {
            Ry(thetas[nQ + i], keyQubits[i]);
        }

        // Compute attention scores via controlled rotations
        for i in 0..nQ - 1 {
            for j in 0..nK - 1 {
                let idx = nQ + nK + i * nK + j;
                if idx < Length(thetas) {
                    Controlled Rz([queryQubits[i]], (thetas[idx], keyQubits[j]));
                }
            }
        }

        // Entangle key with value
        let minKV = nK < nV ? nK | nV;
        for i in 0..minKV - 1 {
            CNOT(keyQubits[i], valueQubits[i]);
        }

        // Apply value rotations
        for i in 0..nV - 1 {
            let idx = nQ + nK + nQ * nK + i;
            if idx < Length(thetas) {
                Ry(thetas[idx], valueQubits[i]);
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Quantum embedding circuit (token → quantum state)
    // ─────────────────────────────────────────────────────────────────────────
    operation EncodeTokenEmbedding(
        qubits     : Qubit[],
        amplitudes : Double[]
    ) : Unit {
        let n = Length(qubits);
        if Length(amplitudes) < n {
            fail $"EncodeTokenEmbedding: need {n} amplitudes, got {Length(amplitudes)}.";
        }
        for i in 0..n - 1 {
            let angle = 2.0 * ArcSin(amplitudes[i]);
            Ry(angle, qubits[i]);
        }
        for i in 0..n - 2 {
            CNOT(qubits[i], qubits[i + 1]);
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Topological braiding simulation (Majorana 1)
    // ─────────────────────────────────────────────────────────────────────────
    operation SimulateMajoranaBraiding(
        mzmQubits   : Qubit[],
        braidSeq    : Int[],
        protGap     : Double
    ) : Unit is Adj + Ctl {
        let n = Length(mzmQubits);
        for op in braidSeq {
            let i = op % n;
            let j = (op + 1) % n;
            // Topological braid = controlled phase + SWAP
            let phase = PI() / 4.0 * protGap;
            Controlled Rz([mzmQubits[i]], (phase, mzmQubits[j]));
            SWAP(mzmQubits[i], mzmQubits[j]);
            Rz(-phase / 2.0, mzmQubits[i]);
            Rz(-phase / 2.0, mzmQubits[j]);
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Surface code stabilizer measurement
    // ─────────────────────────────────────────────────────────────────────────
    operation MeasureXStabilizer(
        dataQubits   : Qubit[],
        ancilla      : Qubit,
        support      : Int[]
    ) : Result {
        H(ancilla);
        for idx in support {
            CNOT(ancilla, dataQubits[idx]);
        }
        H(ancilla);
        return MResetZ(ancilla);
    }

    operation MeasureZStabilizer(
        dataQubits   : Qubit[],
        ancilla      : Qubit,
        support      : Int[]
    ) : Result {
        for idx in support {
            CNOT(dataQubits[idx], ancilla);
        }
        return MResetZ(ancilla);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Quantum error correction cycle (one round)
    // ─────────────────────────────────────────────────────────────────────────
    operation QECCycle(
        dataQubits    : Qubit[],
        xAncillas     : Qubit[],
        zAncillas     : Qubit[],
        xStabilizers  : Int[][],
        zStabilizers  : Int[][]
    ) : (Int[], Int[]) {
        mutable xSyndrome = [];
        mutable zSyndrome = [];

        for i in 0..Length(xStabilizers) - 1 {
            let r = MeasureXStabilizer(dataQubits, xAncillas[i], xStabilizers[i]);
            set xSyndrome += [r == One ? 1 | 0];
        }

        for i in 0..Length(zStabilizers) - 1 {
            let r = MeasureZStabilizer(dataQubits, zAncillas[i], zStabilizers[i]);
            set zSyndrome += [r == One ? 1 | 0];
        }

        return (xSyndrome, zSyndrome);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Quantum teleportation
    // ─────────────────────────────────────────────────────────────────────────
    operation QuantumTeleport(
        message : Qubit,
        here    : Qubit,
        there   : Qubit
    ) : Unit {
        PrepareBellState(here, there, 0);
        CNOT(message, here);
        H(message);
        let m1 = MResetZ(message);
        let m2 = MResetZ(here);
        if m2 == One { X(there); }
        if m1 == One { Z(there); }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Quantum random number generation
    // ─────────────────────────────────────────────────────────────────────────
    operation QuantumRandomBit() : Int {
        use q = Qubit();
        H(q);
        let r = MResetZ(q);
        return r == One ? 1 | 0;
    }

    operation QuantumRandomInt(min : Int, max : Int) : Int {
        if min >= max { fail $"QuantumRandomInt: min {min} must be < max {max}."; }
        let range = max - min;
        let bits = Ceiling(Log(IntAsDouble(range)) / Log(2.0));
        mutable value = range;
        repeat {
            set value = 0;
            for i in 0..bits - 1 {
                set value += QuantumRandomBit() <<< i;
            }
        } until value < range;
        return min + value;
    }

    operation QuantumRandomDouble() : Double {
        mutable value = 0.0;
        for i in 0..52 {
            set value += IntAsDouble(QuantumRandomBit()) / IntAsDouble(1 <<< (i + 1));
        }
        return value;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Amplitude amplification
    // ─────────────────────────────────────────────────────────────────────────
    operation AmplitudeAmplification(
        qubits      : Qubit[],
        oracle      : Qubit[] => Unit is Adj,
        statePrep   : Qubit[] => Unit is Adj,
        iterations  : Int
    ) : Unit {
        statePrep(qubits);
        for _ in 0..iterations - 1 {
            oracle(qubits);
            Adjoint statePrep(qubits);
            GroverDiffusion(qubits);
            statePrep(qubits);
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Variational quantum eigensolver layer
    // ─────────────────────────────────────────────────────────────────────────
    operation VQELayer(
        qubits  : Qubit[],
        thetas  : Double[],
        pauliOps: String[]
    ) : Unit is Adj + Ctl {
        let n = Length(qubits);
        for i in 0..n - 1 {
            if i < Length(pauliOps) {
                if pauliOps[i] == "X" { Rx(thetas[i], qubits[i]); }
                elif pauliOps[i] == "Y" { Ry(thetas[i], qubits[i]); }
                else { Rz(thetas[i], qubits[i]); }
            }
        }
        for i in 0..n - 2 {
            CNOT(qubits[i], qubits[i + 1]);
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Quantum approximate optimization algorithm (QAOA) layer
    // ─────────────────────────────────────────────────────────────────────────
    operation QAOALayer(
        qubits  : Qubit[],
        gamma   : Double,
        beta    : Double,
        edges   : (Int, Int)[]
    ) : Unit is Adj + Ctl {
        // Problem unitary
        for (i, j) in edges {
            CNOT(qubits[i], qubits[j]);
            Rz(2.0 * gamma, qubits[j]);
            CNOT(qubits[i], qubits[j]);
        }
        // Mixer unitary
        for q in qubits {
            Rx(2.0 * beta, q);
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Quantum convolutional layer (for quantum CNN)
    // ─────────────────────────────────────────────────────────────────────────
    operation QuantumConvLayer(
        qubits  : Qubit[],
        thetas  : Double[],
        stride  : Int
    ) : Unit is Adj + Ctl {
        let n = Length(qubits);
        mutable paramIdx = 0;
        for i in 0..stride..n - 2 {
            if paramIdx + 1 < Length(thetas) {
                Ry(thetas[paramIdx], qubits[i]);
                Ry(thetas[paramIdx + 1], qubits[i + 1]);
                CNOT(qubits[i], qubits[i + 1]);
                set paramIdx += 2;
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Quantum pooling layer
    // ─────────────────────────────────────────────────────────────────────────
    operation QuantumPoolLayer(
        sourceQubits : Qubit[],
        targetQubits : Qubit[],
        thetas       : Double[]
    ) : Unit {
        let n = Length(targetQubits);
        for i in 0..n - 1 {
            if 2 * i + 1 < Length(sourceQubits) {
                CNOT(sourceQubits[2 * i], targetQubits[i]);
                if i < Length(thetas) {
                    Ry(thetas[i], targetQubits[i]);
                }
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Quantum data re-uploading circuit
    // ─────────────────────────────────────────────────────────────────────────
    operation DataReuploadingCircuit(
        qubits  : Qubit[],
        data    : Double[],
        weights : Double[],
        layers  : Int
    ) : Unit is Adj + Ctl {
        let n = Length(qubits);
        let d = Length(data);
        if d == 0 { fail "DataReuploadingCircuit: data must not be empty."; }
            for i in 0..n - 1 {
                let dataIdx = (layer * n + i) % d;
                let wIdx    = layer * n + i;
                let angle   = if wIdx < Length(weights)
                              { data[dataIdx] * weights[wIdx] }
                              else { data[dataIdx] };
                Ry(angle, qubits[i]);
            }
            for i in 0..n - 2 {
                CNOT(qubits[i], qubits[i + 1]);
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Quantum Boltzmann machine layer
    // ─────────────────────────────────────────────────────────────────────────
    operation QuantumBoltzmannLayer(
        visible : Qubit[],
        hidden  : Qubit[],
        weights : Double[]
    ) : Unit is Adj + Ctl {
        let nV = Length(visible);
        let nH = Length(hidden);
        for i in 0..nV - 1 {
            Ry(PI() / 4.0, visible[i]);
        }
        for j in 0..nH - 1 {
            Ry(PI() / 4.0, hidden[j]);
        }
        for i in 0..nV - 1 {
            for j in 0..nH - 1 {
                let wIdx = i * nH + j;
                if wIdx < Length(weights) {
                    Controlled Rz([visible[i]], (weights[wIdx], hidden[j]));
                }
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Quantum reservoir computing layer
    // ─────────────────────────────────────────────────────────────────────────
    operation QuantumReservoirLayer(
        reservoir : Qubit[],
        input     : Double[],
        connectivity: Int[][]
    ) : Unit {
        let n = Length(reservoir);
        for i in 0..n - 1 {
            let angle = if i < Length(input) { input[i] } else { 0.0 };
            Ry(angle, reservoir[i]);
        }
        for i in 0..Length(connectivity) - 1 {
            if Length(connectivity[i]) >= 2 {
                let src = connectivity[i][0];
                let dst = connectivity[i][1];
                if src < n and dst < n {
                    CNOT(reservoir[src], reservoir[dst]);
                }
            }
        }
    }
}
