// =============================================================================
// Api.qs — Public API surface for Windows-AGI-Mesh-QuantumSDK
// =============================================================================

namespace WindowsAGI.QuantumSDK.Api {

    import WindowsAGI.QuantumSDK.Sampling.*;
    import WindowsAGI.QuantumSDK.Types.*;
    import WindowsAGI.QuantumSDK.Validation.*;
    import WindowsAGI.QuantumSDK.Factorization.*;

    // ─────────────────────────────────────────────────────────────────────────
    // Primary experiment entry point
    // ─────────────────────────────────────────────────────────────────────────
    operation RunExperiment(
        qubitCount   : Int,
        ancillaCount : Int,
        thetaZ       : Double,
        thetaY       : Double,
        shotCount    : Int,
        threshold    : Double
    ) : ExperimentResult {
        return RunSampling(
            qubitCount, ancillaCount,
            thetaZ, thetaY,
            shotCount, threshold
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Majorana-protected experiment
    // ─────────────────────────────────────────────────────────────────────────
    operation RunMajoranaExperiment(
        qubitCount   : Int,
        ancillaCount : Int,
        thetaZ       : Double,
        thetaY       : Double,
        shotCount    : Int,
        threshold    : Double,
        braidDepth   : Int
    ) : ExperimentResult {
        return MajoranaProtectedSampling(
            qubitCount, ancillaCount,
            thetaZ, thetaY,
            shotCount, threshold, braidDepth
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Batch experiment
    // ─────────────────────────────────────────────────────────────────────────
    operation RunBatchExperiment(
        qubitCount   : Int,
        ancillaCount : Int,
        thetaZList   : Double[],
        thetaYList   : Double[],
        shotCount    : Int,
        threshold    : Double
    ) : ExperimentResult[] {
        return BatchSampling(
            qubitCount, ancillaCount,
            thetaZList, thetaYList,
            shotCount, threshold
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Sampling statistics
    // ─────────────────────────────────────────────────────────────────────────
    operation GetSamplingStats(
        qubitCount   : Int,
        ancillaCount : Int,
        thetaZ       : Double,
        thetaY       : Double,
        shotCount    : Int
    ) : SamplingStats {
        return ComputeSamplingStats(
            qubitCount, ancillaCount,
            thetaZ, thetaY, shotCount
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Quantum token sampling for LLM inference
    // ─────────────────────────────────────────────────────────────────────────
    operation SampleNextToken(
        logits      : Double[],
        temperature : Double,
        topK        : Int
    ) : Int {
        return QuantumTokenSampling(logits, temperature, topK, true);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Integer factorization
    // ─────────────────────────────────────────────────────────────────────────
    operation FactorInteger(n : Int) : FactorizationResult {
        ValidateFactorizationInput(n);
        return RunShorAlgorithm(n);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Backward-compatible wrapper (deprecated)
    // ─────────────────────────────────────────────────────────────────────────
    @Deprecated("Use RunExperiment instead.")
    operation Operation_1_1(
        inputQ  : Qubit[],
        ancillaQ: Qubit[],
        param1  : Double,
        param2  : Double,
        nShots  : Int
    ) : (Double, Double, Bool) {
        let result = RunExperiment(
            Length(inputQ), Length(ancillaQ),
            param1, param2, nShots, 0.5
        );
        let (mean, dev, flag, _, _, _, _, _, _, _, _) = result!;
        return (mean, dev, flag);
    }
}
