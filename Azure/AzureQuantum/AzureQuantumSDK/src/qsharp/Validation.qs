// =============================================================================
// Validation.qs — Input validation for all SDK operations
// Majorana 1 | MAIA 300 | Brainwave FPGA | Hollow-Core Fiber | 5B-param LLM
// =============================================================================

namespace WindowsAGI.QuantumSDK.Validation {

    import WindowsAGI.QuantumSDK.Types.*;

    // ─────────────────────────────────────────────────────────────────────────
    // Core experiment validation
    // ─────────────────────────────────────────────────────────────────────────
    function ValidateExperiment(qubitCount : Int, shotCount : Int) : Unit {
        if qubitCount <= 0 {
            fail $"qubitCount must be > 0, got {qubitCount}.";
        }
        if qubitCount > 1_000_000 {
            fail $"qubitCount exceeds Majorana-1 chip limit of 1,000,000, got {qubitCount}.";
        }
        if shotCount <= 0 {
            fail $"shotCount must be > 0, got {shotCount}.";
        }
        if shotCount > 10_000_000 {
            fail $"shotCount exceeds maximum of 10,000,000, got {shotCount}.";
        }
    }

    function ValidateThreshold(threshold : Double) : Unit {
        if threshold < 0.0 or threshold > 1.0 {
            fail $"threshold must be in [0,1], got {threshold}.";
        }
    }

    function ValidateAncillaCount(ancillaCount : Int) : Unit {
        if ancillaCount < 0 {
            fail $"ancillaCount must be >= 0, got {ancillaCount}.";
        }
        if ancillaCount > 500_000 {
            fail $"ancillaCount exceeds limit of 500,000, got {ancillaCount}.";
        }
    }

    function ValidateAngle(angle : Double, name : String) : Unit {
        if angle < -6.283185307179586 or angle > 6.283185307179586 {
            fail $"{name} must be in [-2π, 2π], got {angle}.";
        }
    }

    function ValidateCodeDistance(d : Int) : Unit {
        if d < 3 {
            fail $"Code distance must be >= 3 for meaningful QEC, got {d}.";
        }
        if d % 2 == 0 {
            fail $"Code distance must be odd for surface codes, got {d}.";
        }
    }

    function ValidateErrorRate(rate : Double, name : String) : Unit {
        if rate < 0.0 or rate > 1.0 {
            fail $"{name} must be in [0,1], got {rate}.";
        }
    }

    function ValidateFidelity(fidelity : Double, name : String) : Unit {
        if fidelity < 0.0 or fidelity > 1.0 {
            fail $"{name} fidelity must be in [0,1], got {fidelity}.";
        }
        if fidelity < 0.9 {
            Message($"WARNING: {name} fidelity {fidelity} is below 0.9 — results may be unreliable.");
        }
    }

    function ValidateMajoranaIndex(index : Int, maxIndex : Int) : Unit {
        if index < 0 or index >= maxIndex {
            fail $"Majorana index {index} out of range [0, {maxIndex}).";
        }
    }

    function ValidateTopologicalPair(leftIdx : Int, rightIdx : Int) : Unit {
        if leftIdx == rightIdx {
            fail $"Left and right MZM indices must differ, both are {leftIdx}.";
        }
        if leftIdx < 0 or rightIdx < 0 {
            fail $"MZM indices must be non-negative, got {leftIdx} and {rightIdx}.";
        }
    }

    function ValidateLLMDimensions(
        hiddenDim : Int,
        numHeads  : Int,
        ffnDim    : Int
    ) : Unit {
        if hiddenDim <= 0 {
            fail $"hiddenDim must be > 0, got {hiddenDim}.";
        }
        if numHeads <= 0 {
            fail $"numHeads must be > 0, got {numHeads}.";
        }
        if hiddenDim % numHeads != 0 {
            fail $"hiddenDim {hiddenDim} must be divisible by numHeads {numHeads}.";
        }
        if ffnDim <= 0 {
            fail $"ffnDim must be > 0, got {ffnDim}.";
        }
    }

    function ValidateQuantizationBits(bits : Int) : Unit {
        if bits != 2 and bits != 4 and bits != 8 and bits != 16 and bits != 32 {
            fail $"Quantization bits must be 2, 4, 8, 16, or 32, got {bits}.";
        }
    }

    function ValidateMAIA300Task(
        shardId    : Int,
        totalShards: Int,
        batchSize  : Int
    ) : Unit {
        if shardId < 0 or shardId >= totalShards {
            fail $"shardId {shardId} out of range [0, {totalShards}).";
        }
        if totalShards <= 0 or totalShards > 96 {
            fail $"totalShards must be in [1, 96] for MAIA-300 rack, got {totalShards}.";
        }
        if batchSize <= 0 {
            fail $"batchSize must be > 0, got {batchSize}.";
        }
    }

    function ValidatePhotonics(
        lengthKm       : Double,
        bandwidthTbps  : Double,
        latencyUs      : Double
    ) : Unit {
        if lengthKm <= 0.0 {
            fail $"Fiber length must be > 0 km, got {lengthKm}.";
        }
        if bandwidthTbps <= 0.0 {
            fail $"Bandwidth must be > 0 Tbps, got {bandwidthTbps}.";
        }
        if latencyUs < 0.0 {
            fail $"Latency cannot be negative, got {latencyUs}.";
        }
    }

    function ValidateMoEConfig(
        expertCount : Int,
        topK        : Int,
        capacity    : Double
    ) : Unit {
        if expertCount <= 0 {
            fail $"expertCount must be > 0, got {expertCount}.";
        }
        if topK <= 0 or topK > expertCount {
            fail $"topK must be in [1, {expertCount}], got {topK}.";
        }
        if capacity < 1.0 {
            fail $"capacityFactor must be >= 1.0, got {capacity}.";
        }
    }

    function ValidateSurfaceCode(
        dataQubits : Int,
        distance   : Int
    ) : Unit {
        let expected = distance * distance + (distance - 1) * (distance - 1);
        if dataQubits != expected {
            fail $"Surface code d={distance} requires {expected} data qubits, got {dataQubits}.";
        }
    }

    function ValidateResourceEstimate(
        logicalQubits  : Int,
        physicalQubits : Int,
        errorBudget    : Double
    ) : Unit {
        if logicalQubits <= 0 {
            fail $"logicalQubits must be > 0, got {logicalQubits}.";
        }
        if physicalQubits < logicalQubits {
            fail $"physicalQubits {physicalQubits} must be >= logicalQubits {logicalQubits}.";
        }
        if errorBudget <= 0.0 or errorBudget > 1.0 {
            fail $"errorBudget must be in (0,1], got {errorBudget}.";
        }
    }

    function ValidateBenchmarkCase(
        caseId     : String,
        qubitCount : Int,
        shotCount  : Int,
        expectedLo : Double,
        expectedHi : Double
    ) : Unit {
        if caseId == "" {
            fail "caseId must not be empty.";
        }
        ValidateExperiment(qubitCount, shotCount);
        if expectedLo > expectedHi {
            fail $"expectedMeanLo {expectedLo} must be <= expectedMeanHi {expectedHi}.";
        }
        if expectedLo < 0.0 or expectedHi > 1.0 {
            fail $"Expected mean range [{expectedLo}, {expectedHi}] must be within [0,1].";
        }
    }

    function ValidateInferenceRequest(
        inputTokens  : Int,
        maxNewTokens : Int,
        temperature  : Double,
        topP         : Double
    ) : Unit {
        if inputTokens <= 0 {
            fail $"inputTokenCount must be > 0, got {inputTokens}.";
        }
        if inputTokens > 131072 {
            fail $"inputTokenCount {inputTokens} exceeds context window of 131072.";
        }
        if maxNewTokens <= 0 {
            fail $"maxNewTokens must be > 0, got {maxNewTokens}.";
        }
        if temperature < 0.0 {
            fail $"temperature must be >= 0.0, got {temperature}.";
        }
        if topP <= 0.0 or topP > 1.0 {
            fail $"topP must be in (0,1], got {topP}.";
        }
    }

    function ValidateWeightShard(
        shardId    : Int,
        layerStart : Int,
        layerEnd   : Int,
        totalLayers: Int
    ) : Unit {
        if shardId < 0 {
            fail $"shardId must be >= 0, got {shardId}.";
        }
        if layerStart < 0 or layerStart >= totalLayers {
            fail $"layerStart {layerStart} out of range [0, {totalLayers}).";
        }
        if layerEnd <= layerStart or layerEnd > totalLayers {
            fail $"layerEnd {layerEnd} must be in ({layerStart}, {totalLayers}].";
        }
    }

    function ValidateClusterNode(
        rank      : Int,
        worldSize : Int,
        gpuCount  : Int
    ) : Unit {
        if rank < 0 or rank >= worldSize {
            fail $"rank {rank} out of range [0, {worldSize}).";
        }
        if worldSize <= 0 {
            fail $"worldSize must be > 0, got {worldSize}.";
        }
        if gpuCount < 0 {
            fail $"gpuCount must be >= 0, got {gpuCount}.";
        }
    }

    function ValidateHybridLayer(
        layerId      : Int,
        classicalDim : Int,
        quantumDim   : Int,
        qubitCount   : Int
    ) : Unit {
        if layerId < 0 {
            fail $"layerId must be >= 0, got {layerId}.";
        }
        if classicalDim <= 0 {
            fail $"classicalDim must be > 0, got {classicalDim}.";
        }
        if quantumDim <= 0 {
            fail $"quantumDim must be > 0, got {quantumDim}.";
        }
        if qubitCount <= 0 {
            fail $"qubitCount must be > 0, got {qubitCount}.";
        }
        if qubitCount > 50 {
            Message($"WARNING: qubitCount {qubitCount} > 50 may be slow on classical simulators.");
        }
    }

    function ValidateRLHFSignal(
        rewardScore  : Double,
        klDivergence : Double
    ) : Unit {
        if klDivergence < 0.0 {
            fail $"KL divergence must be >= 0, got {klDivergence}.";
        }
        if klDivergence > 100.0 {
            Message($"WARNING: KL divergence {klDivergence} is very large — policy may have diverged.");
        }
    }

    function ValidateFactorizationInput(n : Int) : Unit {
        if n < 2 {
            fail $"Factorization input must be >= 2, got {n}.";
        }
        if n > 2_147_483_647 {
            fail $"Factorization input exceeds Int32 max, got {n}.";
        }
    }

    function ValidateBackendId(backendId : String) : Unit {
        if backendId == "" {
            fail "backendId must not be empty.";
        }
        let validBackends = [
            "microsoft.majorana-1",
            "quantinuum.helios",
            "quantinuum.h2-1",
            "quantinuum.h2-1e",
            "ibm.nighthawk-r2",
            "ibm.heron-r3",
            "ibm.eagle-r3",
            "ionq.aria-1",
            "ionq.aria-2",
            "ionq.forte-1",
            "rigetti.ankaa-9q-3",
            "pasqal.emu-tn",
            "aqt.pine",
            "oqc.lucy",
            "microsoft.simulator.full-state",
            "microsoft.simulator.sparse",
            "microsoft.resource-estimator"
        ];
        mutable found = false;
        for b in validBackends {
            if b == backendId {
                set found = true;
            }
        }
        if not found {
            Message($"WARNING: backendId '{backendId}' is not in the known backend list.");
        }
    }

    function ValidateTrainingWorkload(
        paramCount   : Int,
        batchSize    : Int,
        learningRate : Double,
        totalSteps   : Int
    ) : Unit {
        if paramCount <= 0 {
            fail $"paramCount must be > 0, got {paramCount}.";
        }
        if batchSize <= 0 {
            fail $"batchSize must be > 0, got {batchSize}.";
        }
        if learningRate <= 0.0 or learningRate > 1.0 {
            fail $"learningRate must be in (0,1], got {learningRate}.";
        }
        if totalSteps <= 0 {
            fail $"totalSteps must be > 0, got {totalSteps}.";
        }
    }

    function ValidateAll(
        qubitCount   : Int,
        ancillaCount : Int,
        thetaZ       : Double,
        thetaY       : Double,
        shotCount    : Int,
        threshold    : Double,
        backendId    : String
    ) : Unit {
        ValidateExperiment(qubitCount, shotCount);
        ValidateAncillaCount(ancillaCount);
        ValidateAngle(thetaZ, "thetaZ");
        ValidateAngle(thetaY, "thetaY");
        ValidateThreshold(threshold);
        ValidateBackendId(backendId);
    }
}
