// =============================================================================
// Benchmarks.qs — Q# benchmark suite for all hardware backends
// =============================================================================

namespace WindowsAGI.QuantumSDK.Benchmarks {

    import Std.Convert.*;
    import Std.Math.*;

    import WindowsAGI.QuantumSDK.Api.*;
    import WindowsAGI.QuantumSDK.Circuits.*;
    import WindowsAGI.QuantumSDK.Types.*;
    import WindowsAGI.QuantumSDK.Sampling.*;

    // ─────────────────────────────────────────────────────────────────────────
    // Benchmark: QFT scaling
    // ─────────────────────────────────────────────────────────────────────────
    operation BenchmarkQFT(maxQubits : Int) : Unit {
        Message("=== QFT Benchmark ===");
        for n in 1..maxQubits {
            use qubits = Qubit[n];
            QFT(qubits);
            ResetAll(qubits);
            Message($"  QFT({n}): OK");
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Benchmark: HEA layers
    // ─────────────────────────────────────────────────────────────────────────
    operation BenchmarkHEA(qubitCount : Int, maxLayers : Int) : Unit {
        Message("=== HEA Benchmark ===");
        for layers in 1..maxLayers {
            let paramCount = 2 * qubitCount * layers;
            mutable thetas = [];
            for i in 0..paramCount - 1 {
                set thetas += [0.1 * IntAsDouble(i)];
            }
            use qubits = Qubit[qubitCount];
            HardwareEfficientAnsatz(qubits, thetas, layers);
            ResetAll(qubits);
            Message($"  HEA(n={qubitCount}, layers={layers}): OK");
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Benchmark: Sampling throughput
    // ─────────────────────────────────────────────────────────────────────────
    operation BenchmarkSampling(
        qubitCounts : Int[],
        shotCount   : Int
    ) : Unit {
        Message("=== Sampling Benchmark ===");
        for n in qubitCounts {
            let result = RunExperiment(n, 0, 0.5, 0.3, shotCount, 0.5);
            let (mean, dev, _, shots, qubits, _, _, _, _, backend, _) = result!;
            Message($"  n={qubits}, shots={shots}: mean={mean}, dev={dev}");
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Benchmark: Bell state fidelity
    // ─────────────────────────────────────────────────────────────────────────
    operation BenchmarkBellFidelity(shots : Int) : Double {
        mutable correct = 0;
        for _ in 0..shots - 1 {
            use (q0, q1) = (Qubit(), Qubit());
            PrepareBellState(q0, q1, 0);
            let r0 = MResetZ(q0);
            let r1 = MResetZ(q1);
            if r0 == r1 { set correct += 1; }
        }
        let fidelity = IntAsDouble(correct) / IntAsDouble(shots);
        Message($"Bell fidelity ({shots} shots): {fidelity}");
        return fidelity;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Benchmark: GHZ state
    // ─────────────────────────────────────────────────────────────────────────
    operation BenchmarkGHZ(maxQubits : Int, shots : Int) : Unit {
        Message("=== GHZ Benchmark ===");
        for n in 2..maxQubits {
            mutable allCorrelated = 0;
            for _ in 0..shots - 1 {
                use qubits = Qubit[n];
                PrepareGHZState(qubits);
                let r0 = MResetZ(qubits[0]);
                mutable allSame = true;
                for i in 1..n - 1 {
                    if MResetZ(qubits[i]) != r0 { set allSame = false; }
                }
                if allSame { set allCorrelated += 1; }
            }
            let fidelity = IntAsDouble(allCorrelated) / IntAsDouble(shots);
            Message($"  GHZ({n}): fidelity={fidelity}");
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Benchmark: Quantum attention circuit
    // ─────────────────────────────────────────────────────────────────────────
    operation BenchmarkQuantumAttention(
        headDim : Int,
        shots   : Int
    ) : Unit {
        Message("=== Quantum Attention Benchmark ===");
        let paramCount = headDim * headDim * 3;
        mutable thetas = [];
        for i in 0..paramCount - 1 {
            set thetas += [0.01 * IntAsDouble(i)];
        }
        for _ in 0..shots - 1 {
            use queryQ = Qubit[headDim];
            use keyQ   = Qubit[headDim];
            use valueQ = Qubit[headDim];
            QuantumAttentionCircuit(queryQ, keyQ, valueQ, thetas);
            ResetAll(queryQ);
            ResetAll(keyQ);
            ResetAll(valueQ);
        }
        Message($"  Attention(headDim={headDim}, shots={shots}): OK");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Full benchmark suite
    // ─────────────────────────────────────────────────────────────────────────
    operation RunAllBenchmarks() : Unit {
        Message("╔══════════════════════════════════════════════════════╗");
        Message("║  Windows-AGI-Mesh-QuantumSDK — Full Benchmark Suite  ║");
        Message("╚══════════════════════════════════════════════════════╝");

        BenchmarkQFT(8);
        BenchmarkHEA(4, 5);
        BenchmarkSampling([1, 2, 4, 6, 8], 100);
        let _ = BenchmarkBellFidelity(1000);
        BenchmarkGHZ(6, 200);
        BenchmarkQuantumAttention(4, 10);

        Message("=== All benchmarks complete ===");
    }
}
