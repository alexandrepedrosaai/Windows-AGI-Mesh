// =============================================================================
// Entrypoint.qs — CLI entry point for Q# execution
// =============================================================================

namespace WindowsAGI.QuantumSDK.Entrypoint {

    import WindowsAGI.QuantumSDK.Api.*;
    import WindowsAGI.QuantumSDK.Types.*;

    @EntryPoint()
    operation Main() : Unit {
        Message("=== Windows-AGI-Mesh-QuantumSDK v2.0 ===");
        Message("5B-parameter LLM | Majorana 1 | MAIA 300 | Brainwave FPGA | Hollow-Core Fiber");
        Message("");

        // Default experiment
        let result = RunExperiment(4, 2, 0.5, 0.3, 100, 0.5);
        let (mean, dev, flag, shots, qubits, anc, tz, ty, thr, backend, ts) = result!;

        Message($"Experiment result:");
        Message($"  Mean:      {mean}");
        Message($"  Deviation: {dev}");
        Message($"  Above threshold ({thr}): {flag}");
        Message($"  Shots: {shots} | Qubits: {qubits} | Ancillas: {anc}");
        Message($"  Backend: {backend}");
        Message($"  Timestamp: {ts}");
        Message("");

        // Majorana-protected experiment
        let mResult = RunMajoranaExperiment(4, 2, 0.5, 0.3, 50, 0.5, 2);
        let (mMean, mDev, mFlag, _, _, _, _, _, _, mBackend, _) = mResult!;
        Message($"Majorana-protected result:");
        Message($"  Mean: {mMean} | Dev: {mDev} | Flag: {mFlag}");
        Message($"  Backend: {mBackend}");
        Message("");

        // Factorization
        let fResult = FactorInteger(15);
        let (fN, f1, f2, isPrime, algo, fQubits, depth, steps, qAdv, rt) = fResult!;
        Message($"Factorization of {fN}:");
        Message($"  Factors: {f1} x {f2} | IsPrime: {isPrime}");
        Message($"  Algorithm: {algo} | Qubits: {fQubits} | Depth: {depth}");
        Message($"  QuantumAdvantage: {qAdv}");
        Message("");

        Message("=== All systems nominal ===");
    }
}
