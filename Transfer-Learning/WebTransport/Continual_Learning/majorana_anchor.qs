// =============================================================================
// majorana_anchor.qs
// Q# Majorana-based quantum anchor for continual learning stability
// Implements quantum-stable reference points for parameter space alignment
// Namespace: SiameseTwinAI.ContinualLearning
// =============================================================================

namespace SiameseTwinAI.ContinualLearning {

    open Microsoft.Quantum.Arrays;
    open Microsoft.Quantum.Convert;
    open Microsoft.Quantum.Intrinsic;
    open Microsoft.Quantum.Math;
    open Microsoft.Quantum.Diagnostics;

    // =========================================================================
    // Majorana Anchor Configuration
    // =========================================================================

    newtype AnchorConfig = (
        Alpha           : Double,
        UpdateFreq      : Int,
        MaxAnchors      : Int,
        CoherenceTarget : Double,
        FidelityTarget  : Double,
        ErrorRateMax    : Double,
        TemperatureMK   : Double,
        NQubits         : Int,
        AlignmentThresh : Double,
        DecayRate       : Double
    );

    function DefaultAnchorConfig() : AnchorConfig {
        return AnchorConfig(
            0.5,    // Alpha: anchor alignment weight
            100,    // UpdateFreq: steps between anchor updates
            10,     // MaxAnchors: maximum number of anchors
            0.99,   // CoherenceTarget
            0.995,  // FidelityTarget
            0.001,  // ErrorRateMax
            15.0,   // TemperatureMK: operating temperature
            300,    // NQubits: Majorana qubit count
            0.9,    // AlignmentThreshold
            0.001   // DecayRate: anchor decay per step
        );
    }

    // =========================================================================
    // Quantum State Representation
    // =========================================================================

    newtype QuantumState = (
        Amplitudes      : Double[],
        Phases          : Double[],
        Coherence       : Double,
        Fidelity        : Double,
        ErrorRate       : Double,
        NQubits         : Int,
        Timestamp       : Int
    );

    function InitQuantumState(nQubits : Int, timestamp : Int) : QuantumState {
        // Initialize in |+⟩ superposition
        let amplitude = 1.0 / Sqrt(IntAsDouble(nQubits));
        mutable amplitudes = new Double[nQubits];
        mutable phases = new Double[nQubits];
        for i in 0 .. nQubits - 1 {
            set amplitudes w/= i <- amplitude;
            set phases w/= i <- 0.0;
        }
        return QuantumState(amplitudes, phases, 1.0, 1.0, 0.0, nQubits, timestamp);
    }

    function ComputeStateNorm(state : QuantumState) : Double {
        mutable norm = 0.0;
        for a in state::Amplitudes {
            set norm += a * a;
        }
        return Sqrt(norm);
    }

    function NormalizeState(state : QuantumState) : QuantumState {
        let norm = ComputeStateNorm(state);
        if norm < 1e-10 {
            return state;
        }
        mutable normalized = new Double[Length(state::Amplitudes)];
        for i in 0 .. Length(state::Amplitudes) - 1 {
            set normalized w/= i <- state::Amplitudes[i] / norm;
        }
        return QuantumState(
            normalized, state::Phases,
            state::Coherence, state::Fidelity,
            state::ErrorRate, state::NQubits, state::Timestamp
        );
    }

    function ComputeOverlap(stateA : QuantumState, stateB : QuantumState) : Double {
        let n = MinI(Length(stateA::Amplitudes), Length(stateB::Amplitudes));
        mutable overlap = 0.0;
        for i in 0 .. n - 1 {
            overlap += stateA::Amplitudes[i] * stateB::Amplitudes[i] *
                       Cos(stateA::Phases[i] - stateB::Phases[i]);
        }
        return overlap;
    }

    function ComputeFidelity(stateA : QuantumState, stateB : QuantumState) : Double {
        let overlap = ComputeOverlap(stateA, stateB);
        return overlap * overlap;
    }

    // =========================================================================
    // Majorana Anchor
    // =========================================================================

    newtype MajoranaAnchor = (
        AnchorId        : String,
        TaskId          : Int,
        QuantumState    : QuantumState,
        ClassicalParams : Double[],
        Alignment       : Double,
        Phase           : Double,
        Fidelity        : Double,
        ErrorRate       : Double,
        CreatedAt       : Int,
        LastUpdated     : Int,
        UpdateCount     : Int,
        IsActive        : Bool
    );

    function CreateAnchor(
        anchorId : String,
        taskId : Int,
        classicalParams : Double[],
        nQubits : Int,
        timestamp : Int
    ) : MajoranaAnchor {
        let quantumState = InitQuantumState(nQubits, timestamp);
        return MajoranaAnchor(
            anchorId, taskId,
            quantumState, classicalParams,
            1.0, 0.0, 1.0, 0.0,
            timestamp, timestamp, 0, true
        );
    }

    function UpdateAnchorAlignment(
        anchor : MajoranaAnchor,
        currentParams : Double[],
        alpha : Double,
        timestamp : Int
    ) : MajoranaAnchor {
        let n = MinI(Length(anchor::ClassicalParams), Length(currentParams));

        // Compute alignment (cosine similarity)
        mutable dot = 0.0;
        mutable normA = 0.0;
        mutable normB = 0.0;
        for i in 0 .. n - 1 {
            set dot += anchor::ClassicalParams[i] * currentParams[i];
            set normA += anchor::ClassicalParams[i] * anchor::ClassicalParams[i];
            set normB += currentParams[i] * currentParams[i];
        }
        set normA = Sqrt(normA);
        set normB = Sqrt(normB);

        let alignment = if normA > 1e-10 and normB > 1e-10 {
            dot / (normA * normB)
        } else { 0.0 };

        // Compute phase difference
        let phase = ArcTan2(
            Sqrt(MaxD(0.0, 1.0 - alignment * alignment)),
            alignment
        );

        // Update classical params with EMA
        mutable newParams = anchor::ClassicalParams;
        for i in 0 .. n - 1 {
            set newParams w/= i <- (1.0 - alpha) * anchor::ClassicalParams[i] + alpha * currentParams[i];
        }

        // Simulate quantum fidelity decay and correction
        let fidelity = MaxD(0.0, anchor::Fidelity - anchor::ErrorRate * 0.01);
        let correctedFidelity = MinD(1.0, fidelity + alpha * 0.1);

        return MajoranaAnchor(
            anchor::AnchorId, anchor::TaskId,
            anchor::QuantumState,
            newParams,
            alignment, phase, correctedFidelity,
            anchor::ErrorRate,
            anchor::CreatedAt, timestamp,
            anchor::UpdateCount + 1,
            anchor::IsActive
        );
    }

    function DeactivateAnchor(anchor : MajoranaAnchor) : MajoranaAnchor {
        return MajoranaAnchor(
            anchor::AnchorId, anchor::TaskId,
            anchor::QuantumState, anchor::ClassicalParams,
            anchor::Alignment, anchor::Phase,
            anchor::Fidelity, anchor::ErrorRate,
            anchor::CreatedAt, anchor::LastUpdated,
            anchor::UpdateCount, false
        );
    }

    // =========================================================================
    // Anchor System State
    // =========================================================================

    newtype AnchorSystemState = (
        Config          : AnchorConfig,
        Anchors         : MajoranaAnchor[],
        ActiveAnchorIdx : Int,
        GlobalStep      : Int,
        MeanAlignment   : Double,
        MeanFidelity    : Double,
        TotalUpdates    : Int,
        DecoherenceEvents : Int
    );

    function InitAnchorSystem(config : AnchorConfig) : AnchorSystemState {
        return AnchorSystemState(
            config,
            new MajoranaAnchor[0],
            -1, 0, 0.0, 0.0, 0, 0
        );
    }

    function AddAnchor(
        state : AnchorSystemState,
        anchor : MajoranaAnchor
    ) : AnchorSystemState {
        mutable anchors = state::Anchors;
        if Length(anchors) >= state::Config::MaxAnchors {
            // Replace least aligned anchor
            mutable worstIdx = 0;
            mutable worstAlignment = anchors[0]::Alignment;
            for i in 1 .. Length(anchors) - 1 {
                if anchors[i]::Alignment < worstAlignment {
                    set worstAlignment = anchors[i]::Alignment;
                    set worstIdx = i;
                }
            }
            set anchors w/= worstIdx <- anchor;
        } else {
            set anchors += [anchor];
        }

        return AnchorSystemState(
            state::Config, anchors,
            Length(anchors) - 1,
            state::GlobalStep, state::MeanAlignment,
            state::MeanFidelity, state::TotalUpdates,
            state::DecoherenceEvents
        );
    }

    function UpdateAllAnchors(
        state : AnchorSystemState,
        currentParams : Double[],
        timestamp : Int
    ) : AnchorSystemState {
        if state::GlobalStep % state::Config::UpdateFreq != 0 {
            return AnchorSystemState(
                state::Config, state::Anchors, state::ActiveAnchorIdx,
                state::GlobalStep + 1, state::MeanAlignment,
                state::MeanFidelity, state::TotalUpdates, state::DecoherenceEvents
            );
        }

        mutable updatedAnchors = state::Anchors;
        mutable totalAlignment = 0.0;
        mutable totalFidelity = 0.0;
        mutable nActive = 0;

        for i in 0 .. Length(updatedAnchors) - 1 {
            if updatedAnchors[i]::IsActive {
                let updated = UpdateAnchorAlignment(
                    updatedAnchors[i], currentParams,
                    state::Config::Alpha, timestamp
                );
                set updatedAnchors w/= i <- updated;
                set totalAlignment += updated::Alignment;
                set totalFidelity += updated::Fidelity;
                set nActive += 1;
            }
        }

        let meanAlignment = if nActive > 0 { totalAlignment / IntAsDouble(nActive) } else { 0.0 };
        let meanFidelity = if nActive > 0 { totalFidelity / IntAsDouble(nActive) } else { 0.0 };

        // Detect decoherence events
        let decoherenceEvents = state::DecoherenceEvents +
            (if nActive > 0 and meanFidelity < state::Config::FidelityTarget { 1 } else { 0 });

        return AnchorSystemState(
            state::Config, updatedAnchors,
            state::ActiveAnchorIdx,
            state::GlobalStep + 1,
            meanAlignment, meanFidelity,
            state::TotalUpdates + nActive,
            decoherenceEvents
        );
    }

    // =========================================================================
    // Anchor-Based Regularization
    // =========================================================================

    function ComputeAnchorPenalty(
        currentParams : Double[],
        anchors : MajoranaAnchor[],
        alpha : Double
    ) : Double {
        mutable totalPenalty = 0.0;
        mutable nActive = 0;

        for anchor in anchors {
            if anchor::IsActive {
                let n = MinI(Length(currentParams), Length(anchor::ClassicalParams));
                mutable dist = 0.0;
                for i in 0 .. n - 1 {
                    let diff = currentParams[i] - anchor::ClassicalParams[i];
                    set dist += diff * diff;
                }
                // Weight by alignment (higher alignment = stronger anchor)
                set totalPenalty += MaxD(0.0, anchor::Alignment) * dist;
                set nActive += 1;
            }
        }

        if nActive == 0 { return 0.0; }
        return alpha * totalPenalty / IntAsDouble(nActive);
    }

    function ComputeAnchorGradient(
        currentParams : Double[],
        anchors : MajoranaAnchor[],
        alpha : Double
    ) : Double[] {
        let nParams = Length(currentParams);
        mutable grad = new Double[nParams];
        mutable nActive = 0;

        for anchor in anchors {
            if anchor::IsActive {
                let n = MinI(nParams, Length(anchor::ClassicalParams));
                for i in 0 .. n - 1 {
                    set grad w/= i <- grad[i] + anchor::Alignment * 2.0 *
                                  (currentParams[i] - anchor::ClassicalParams[i]);
                }
                set nActive += 1;
            }
        }

        if nActive > 0 {
            for i in 0 .. nParams - 1 {
                set grad w/= i <- alpha * grad[i] / IntAsDouble(nActive);
            }
        }

        return grad;
    }

    // =========================================================================
    // Quantum Error Correction (Simplified)
    // =========================================================================

    function ApplyErrorCorrection(
        anchor : MajoranaAnchor,
        errorSyndrome : Int[]
    ) : MajoranaAnchor {
        // Simplified: reduce error rate after correction
        if Length(errorSyndrome) == 0 {
            return anchor;
        }
        let correctedErrorRate = anchor::ErrorRate * 0.1;
        let correctedFidelity = MinD(1.0, anchor::Fidelity + 0.05);

        return MajoranaAnchor(
            anchor::AnchorId, anchor::TaskId,
            anchor::QuantumState, anchor::ClassicalParams,
            anchor::Alignment, anchor::Phase,
            correctedFidelity, correctedErrorRate,
            anchor::CreatedAt, anchor::LastUpdated,
            anchor::UpdateCount, anchor::IsActive
        );
    }

    function DetectDecoherence(
        anchor : MajoranaAnchor,
        config : AnchorConfig
    ) : Bool {
        return anchor::Fidelity < config::FidelityTarget or
               anchor::ErrorRate > config::ErrorRateMax or
               anchor::QuantumState::Coherence < config::CoherenceTarget
    }

    // =========================================================================
    // Anchor Serialization for WebTransport
    // =========================================================================

    function SerializeAnchorForTransport(
        anchor : MajoranaAnchor
    ) : (String, Double, Double, Double, Double, Int) {
        return (
            anchor::AnchorId,
            anchor::Alignment,
            anchor::Phase,
            anchor::Fidelity,
            anchor::ErrorRate,
            anchor::LastUpdated
        );
    }

    function AnchorToPayloadString(anchor : MajoranaAnchor) : String {
        return $"{{\"anchor_id\":\"{anchor::AnchorId}\"," +
               $"\"alignment\":{anchor::Alignment}," +
               $"\"phase\":{anchor::Phase}," +
               $"\"fidelity\":{anchor::Fidelity}," +
               $"\"error_rate\":{anchor::ErrorRate}," +
               $"\"timestamp\":{anchor::LastUpdated}}}";
    }

    // =========================================================================
    // Logging Operations
    // =========================================================================

    operation LogAnchorState(anchor : MajoranaAnchor) : Unit {
        let status = if anchor::IsActive { "ACTIVE" } else { "INACTIVE" };
        Message($"[Anchor:{anchor::AnchorId}] [{status}] task={anchor::TaskId} " +
                $"alignment={anchor::Alignment:.4f} phase={anchor::Phase:.4f} " +
                $"fidelity={anchor::Fidelity:.4f} error_rate={anchor::ErrorRate:.6f} " +
                $"updates={anchor::UpdateCount}");
    }

    operation LogAnchorSystemState(state : AnchorSystemState) : Unit {
        let nActive = Length(Filtered(a -> a::IsActive, state::Anchors));
        Message($"[AnchorSystem] step={state::GlobalStep} " +
                $"anchors={Length(state::Anchors)} active={nActive} " +
                $"mean_alignment={state::MeanAlignment:.4f} " +
                $"mean_fidelity={state::MeanFidelity:.4f} " +
                $"decoherence_events={state::DecoherenceEvents}");
    }

    operation LogDecoherenceEvent(
        anchorId : String,
        fidelity : Double,
        errorRate : Double,
        step : Int
    ) : Unit {
        Message($"[DECOHERENCE] anchor={anchorId} step={step} " +
                $"fidelity={fidelity:.4f} error_rate={errorRate:.6f}");
    }

    operation LogAnchorAlignment(
        anchorId : String,
        oldAlignment : Double,
        newAlignment : Double,
        phase : Double,
        step : Int
    ) : Unit {
        let trend = if newAlignment > oldAlignment { "↑" } else { "↓" };
        Message($"[Anchor Align] {anchorId}: {oldAlignment:.4f} → {newAlignment:.4f} {trend} " +
                $"phase={phase:.4f} step={step}");
    }

    operation LogQuantumState(state : QuantumState) : Unit {
        let norm = ComputeStateNorm(state);
        Message($"[QuantumState] n_qubits={state::NQubits} norm={norm:.4f} " +
                $"coherence={state::Coherence:.4f} fidelity={state::Fidelity:.4f} " +
                $"error_rate={state::ErrorRate:.6f}");
    }
}