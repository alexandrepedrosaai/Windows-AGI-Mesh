// =============================================================================
// Sampling.qs — Shot-based sampling engine with per-shot qubit allocation
// Corrects collapsed-state re-measurement bug from original implementation
// =============================================================================

namespace WindowsAGI.QuantumSDK.Sampling {

    import Std.Arrays.*;
    import Std.Convert.*;
    import Std.Intrinsic.*;
    import Std.Math.*;
    import Std.Measurement.*;

    import WindowsAGI.QuantumSDK.Circuits.*;
    import WindowsAGI.QuantumSDK.Types.*;
    import WindowsAGI.QuantumSDK.Validation.*;
    import WindowsAGI.QuantumSDK.Arrays.*;

    // ─────────────────────────────────────────────────────────────────────────
    // Single shot — fresh qubit allocation per shot avoids collapsed-state bug
    // ─────────────────────────────────────────────────────────────────────────
    operation ExecuteShot(
        qubitCount   : Int,
        ancillaCount : Int,
        thetaZ       : Double,
        thetaY       : Double
    ) : Double {
        use input    = Qubit[qubitCount];
        use ancillas = Qubit[ancillaCount];

        PrepareParameterizedState(input, ancillas, thetaZ, thetaY);

        mutable ones = 0;
        for qubit in input {
            if MResetZ(qubit) == One { set ones += 1; }
        }
        ResetAll(ancillas);

        return IntAsDouble(ones) / IntAsDouble(qubitCount);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Multi-shot sampling with proper variance calculation
    // ─────────────────────────────────────────────────────────────────────────
    operation RunSampling(
        qubitCount   : Int,
        ancillaCount : Int,
        thetaZ       : Double,
        thetaY       : Double,
        shotCount    : Int,
        threshold    : Double
    ) : ExperimentResult {
        ValidateExperiment(qubitCount, shotCount);
        ValidateAncillaCount(ancillaCount);
        ValidateThreshold(threshold);
        ValidateAngle(thetaZ, "thetaZ");
        ValidateAngle(thetaY, "thetaY");

        mutable sum       = 0.0;
        mutable squaredSum = 0.0;
        mutable minVal    = 1.0;
        mutable maxVal    = 0.0;

        for _ in 1..shotCount {
            let sample = ExecuteShot(qubitCount, ancillaCount, thetaZ, thetaY);
            set sum        += sample;
            set squaredSum += sample * sample;
            if sample < minVal { set minVal = sample; }
            if sample > maxVal { set maxVal = sample; }
        }

        let mean     = sum / IntAsDouble(shotCount);
        let variance = MaxD(0.0, squaredSum / IntAsDouble(shotCount) - mean * mean);
        let deviation = Sqrt(variance);

        return ExperimentResult(
            mean, deviation, mean > threshold,
            shotCount, qubitCount, ancillaCount,
            thetaZ, thetaY, threshold,
            "microsoft.simulator.full-state",
            "2026-11-07T00:00:00Z"
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Compute full sampling statistics
    // ─────────────────────────────────────────────────────────────────────────
    operation ComputeSamplingStats(
        qubitCount   : Int,
        ancillaCount : Int,
        thetaZ       : Double,
        thetaY       : Double,
        shotCount    : Int
    ) : SamplingStats {
        ValidateExperiment(qubitCount, shotCount);
        ValidateAncillaCount(ancillaCount);
        ValidateAngle(thetaZ, "thetaZ");
        ValidateAngle(thetaY, "thetaY");

        mutable samples = [];
        for _ in 1..shotCount {
            set samples += [ExecuteShot(qubitCount, ancillaCount, thetaZ, thetaY)];
        }

        let mean   = DoubleArrayMean(samples);
        let stddev = DoubleArrayStdDev(samples);
        let minVal = DoubleArrayMin(samples);
        let maxVal = DoubleArrayMax(samples);

        // Median (approximate via sorted index)
        let n = Length(samples);
        let medIdx = n / 2;
        mutable sorted = samples;
        // Bubble sort for small arrays
        for i in 0..n - 2 {
            for j in 0..n - 2 - i {
                if sorted[j] > sorted[j + 1] {
                    let tmp = sorted[j];
                    set sorted w/= j <- sorted[j + 1];
                    set sorted w/= j + 1 <- tmp;
                }
            }
        }
        let median = sorted[medIdx];

        // Skewness and kurtosis
        mutable m3 = 0.0;
        mutable m4 = 0.0;
        for s in samples {
            let d = s - mean;
            set m3 += d * d * d;
            set m4 += d * d * d * d;
        }
        let variance = stddev * stddev;
        let skewness = if variance > 0.0
                       { (m3 / IntAsDouble(n)) / (variance * stddev) }
                       else { 0.0 };
        let kurtosis = if variance > 0.0
                       { (m4 / IntAsDouble(n)) / (variance * variance) - 3.0 }
                       else { 0.0 };

        // 95% CI (normal approximation)
        let se = stddev / Sqrt(IntAsDouble(n));
        let ci95Lo = mean - 1.96 * se;
        let ci95Hi = mean + 1.96 * se;

        return SamplingStats(
            mean, variance, stddev, minVal, maxVal,
            median, skewness, kurtosis,
            ci95Lo, ci95Hi, n
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Batch sampling across multiple parameter sets
    // ─────────────────────────────────────────────────────────────────────────
    operation BatchSampling(
        qubitCount   : Int,
        ancillaCount : Int,
        thetaZList   : Double[],
        thetaYList   : Double[],
        shotCount    : Int,
        threshold    : Double
    ) : ExperimentResult[] {
        if Length(thetaZList) != Length(thetaYList) {
            fail "BatchSampling: thetaZList and thetaYList must have equal length.";
        }
        mutable results = [];
        for i in 0..Length(thetaZList) - 1 {
            let r = RunSampling(
                qubitCount, ancillaCount,
                thetaZList[i], thetaYList[i],
                shotCount, threshold
            );
            set results += [r];
        }
        return results;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Quantum-enhanced sampling for LLM token generation
    // ─────────────────────────────────────────────────────────────────────────
    operation QuantumTokenSampling(
        logits       : Double[],
        temperature  : Double,
        topK         : Int,
        useQuantum   : Bool
    ) : Int {
        let n = Length(logits);
        if n == 0 { fail "QuantumTokenSampling: empty logits."; }

        // Scale by temperature
        mutable scaled = [];
        for l in logits {
            set scaled += [l / (temperature + 1e-8)];
        }

        // Softmax
        let probs = DoubleArraySoftmax(scaled);

        // Top-K filtering
        let k = if topK <= 0 or topK > n { n } else { topK };
        mutable topKProbs = DoubleArrayZeros(n);
        mutable topKIndices = [];

        // Find top-K indices
        mutable remaining = probs;
        for _ in 0..k - 1 {
            let bestIdx = DoubleArrayArgMax(remaining);
            set topKIndices += [bestIdx];
            set remaining w/= bestIdx <- -1.0;
        }

        mutable filteredSum = 0.0;
        for idx in topKIndices {
            set filteredSum += probs[idx];
        }

        // Sample
        let threshold = if useQuantum
                        { QuantumRandomDouble() * filteredSum }
                        else { filteredSum / 2.0 };

        mutable cumulative = 0.0;
        for idx in topKIndices {
            set cumulative += probs[idx];
            if cumulative >= threshold { return idx; }
        }
        return topKIndices[0];
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Majorana-protected sampling (topological noise suppression)
    // ─────────────────────────────────────────────────────────────────────────
    operation MajoranaProtectedSampling(
        qubitCount   : Int,
        ancillaCount : Int,
        thetaZ       : Double,
        thetaY       : Double,
        shotCount    : Int,
        threshold    : Double,
        braidDepth   : Int
    ) : ExperimentResult {
        ValidateExperiment(qubitCount, shotCount);

        mutable sum        = 0.0;
        mutable squaredSum = 0.0;

        for _ in 1..shotCount {
            use input    = Qubit[qubitCount];
            use ancillas = Qubit[ancillaCount];

            // Topological protection via braiding before state prep
            let braidSeq = IntArrayRange(0, qubitCount - 1, 1);
            for _ in 0..braidDepth - 1 {
                SimulateMajoranaBraiding(input, braidSeq, 1.0);
            }

            PrepareParameterizedState(input, ancillas, thetaZ, thetaY);

            mutable ones = 0;
            for q in input {
                if MResetZ(q) == One { set ones += 1; }
            }
            ResetAll(ancillas);

            let sample = IntAsDouble(ones) / IntAsDouble(qubitCount);
            set sum        += sample;
            set squaredSum += sample * sample;
        }

        let mean     = sum / IntAsDouble(shotCount);
        let variance = MaxD(0.0, squaredSum / IntAsDouble(shotCount) - mean * mean);

        return ExperimentResult(
            mean, Sqrt(variance), mean > threshold,
            shotCount, qubitCount, ancillaCount,
            thetaZ, thetaY, threshold,
            "microsoft.majorana-1",
            "2026-11-07T00:00:00Z"
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Importance sampling for quantum Monte Carlo
    // ─────────────────────────────────────────────────────────────────────────
    operation ImportanceSampling(
        qubitCount   : Int,
        ancillaCount : Int,
        thetaZ       : Double,
        thetaY       : Double,
        shotCount    : Int,
        importanceWeights: Double[]
    ) : Double {
ValidateExperiment(qubitCount, shotCount);
        if Length(importanceWeights) == 0 { fail "ImportanceSampling: importanceWeights must not be empty."; }

        mutable weightedSum = 0.0;
        mutable totalWeight = 0.0;

        for i in 1..shotCount {
            let sample = ExecuteShot(qubitCount, ancillaCount, thetaZ, thetaY);
            let wIdx   = (i - 1) % Length(importanceWeights);
            let w      = if wIdx < Length(importanceWeights)
                         { importanceWeights[wIdx] } else { 1.0 };
            set weightedSum += w * sample;
            set totalWeight += w;
        }

        return if totalWeight > 0.0 { weightedSum / totalWeight } else { 0.0 };
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Quantum Markov Chain Monte Carlo step
    // ─────────────────────────────────────────────────────────────────────────
    operation QMCMCStep(
        qubitCount   : Int,
        ancillaCount : Int,
        currentTheta : Double,
        stepSize     : Double,
        shotCount    : Int
    ) : (Double, Bool) {
        let proposal = currentTheta + (QuantumRandomDouble() - 0.5) * 2.0 * stepSize;
        let clipped  = MaxD(-PI(), MinD(PI(), proposal));

        let currentEnergy  = RunSampling(qubitCount, ancillaCount, currentTheta, 0.0, shotCount, 0.5);
        let proposedEnergy = RunSampling(qubitCount, ancillaCount, clipped, 0.0, shotCount, 0.5);

        let (cMean, _, _, _, _, _, _, _, _, _, _) = currentEnergy!;
        let (pMean, _, _, _, _, _, _, _, _, _, _) = proposedEnergy!;

        let acceptProb = MinD(1.0, Exp(cMean - pMean));
        let u          = QuantumRandomDouble();
        let accepted   = u < acceptProb;

        return (accepted ? clipped | currentTheta, accepted);
    }
}
