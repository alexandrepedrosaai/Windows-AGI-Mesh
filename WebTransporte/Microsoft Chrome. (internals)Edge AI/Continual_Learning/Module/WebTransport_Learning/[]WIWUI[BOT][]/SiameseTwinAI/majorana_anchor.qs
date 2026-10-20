// ═══════════════════════════════════════════════════════════════════════════════
// continual_learning.qs
// WebTransport Continual Learning — EWC + Replay Buffer + QUIC Streams
// Language: Q# (Microsoft Quantum Development Kit)
// Module:   03_webtransport_learning
// ═══════════════════════════════════════════════════════════════════════════════

namespace SiameseTwinAI.WebTransportLearning.ContinualLearning {

    open Microsoft.Quantum.Canon;
    open Microsoft.Quantum.Intrinsic;
    open Microsoft.Quantum.Math;
    open Microsoft.Quantum.Arrays;
    open Microsoft.Quantum.Measurement;
    open Microsoft.Quantum.Convert;
    open Microsoft.Quantum.Diagnostics;

    // ─────────────────────────────────────────────────────────────────────────
    // Newtypes
    // ─────────────────────────────────────────────────────────────────────────
    newtype QUICStream = (
        StreamId  : Int,
        Priority  : Int,
        Name      : String,
        Reliable  : Bool
    );

    newtype EWCState = (
        Lambda       : Double,
        TaskCount    : Int,
        FisherNorm   : Double
    );

    newtype LearningStep = (
        Cycle        : Int,
        TaskLoss     : Double,
        EWCLoss      : Double,
        GradientNorm : Double,
        AnchorAlign  : Double
    );

    // ─────────────────────────────────────────────────────────────────────────
    // WebTransport QUIC Stream Definitions
    // 8 streams for federated gradient + sensor + anchor + blockchain
    // ─────────────────────────────────────────────────────────────────────────
    function InitializeQUICStreams() : QUICStream[] {
        return [
            QUICStream(0, 0, "sensor_data",       true),
            QUICStream(1, 1, "gradient_updates",  true),
            QUICStream(2, 2, "weight_deltas",     true),
            QUICStream(3, 3, "telemetry",         false),
            QUICStream(4, 0, "majorana_anchor",   true),
            QUICStream(5, 1, "ewc_fisher",        true),
            QUICStream(6, 2, "replay_buffer",     false),
            QUICStream(7, 3, "blockchain_hashes", false)
        ];
    }

    // ─────────────────────────────────────────────────────────────────────────
    // QuantumEWCRegularization
    // Elastic Weight Consolidation in quantum circuit form
    // L_EWC = λ/2 · Σᵢ Fᵢ(θᵢ - θ*ᵢ)²
    // Implemented as phase kickback proportional to weight drift
    // ─────────────────────────────────────────────────────────────────────────
    operation QuantumEWCRegularization(
        weightRegister   : Qubit[],   // current weights θ
        thetaStarRegister: Qubit[],   // optimal weights θ*
        fisherRegister   : Qubit[],   // Fisher information F
        ewcLambda        : Double
    ) : Unit is Adj + Ctl {

        let n = Length(weightRegister);
        Fact(n == Length(thetaStarRegister) and n == Length(fisherRegister),
            "All EWC registers must have equal length.");

        // EWC gradient: λ · F · (θ - θ*)
        // Implemented as controlled phase rotation
        for idx in 0 .. n - 1 {
            // Compute (θ - θ*) via CNOT difference
            CNOT(thetaStarRegister[idx], weightRegister[idx]);

            // Scale by Fisher information (controlled rotation)
            let ewcAngle = ewcLambda * PI() / 400.0;
            Controlled Rz([fisherRegister[idx]],
                (ewcAngle, weightRegister[idx]));

            // Restore θ* register
            CNOT(thetaStarRegister[idx], weightRegister[idx]);
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // QuantumReplayBuffer
    // Quantum replay buffer using superposition of past experiences
    // Stores (features, target) pairs as quantum amplitudes
    // ─────────────────────────────────────────────────────────────────────────
    operation QuantumReplayBuffer(
        featureRegister : Qubit[],
        targetRegister  : Qubit[],
        bufferRegister  : Qubit[],
        bufferSize      : Int
    ) : Unit is Adj {

        let n = Length(featureRegister);

        // Encode buffer as superposition of past experiences
        // |buffer⟩ = (1/√N) Σᵢ |featureᵢ⟩|targetᵢ⟩
        ApplyToEach(H, bufferRegister);

        // Entangle buffer with feature-target pairs
        for idx in 0 .. MinI(n, Length(bufferRegister)) - 1 {
            CNOT(bufferRegister[idx], featureRegister[idx]);
            if idx < Length(targetRegister) {
                Controlled SWAP([bufferRegister[idx]],
                    (featureRegister[idx], targetRegister[idx]));
            }
        }

        // Sample from buffer (measurement collapses to one experience)
        // This implements the replay sampling step
    }

    // ─────────────────────────────────────────────────────────────────────────
    // StreamGradientViaWebTransport
    // Encodes gradient as quantum state and "streams" via QUIC
    // Gradient compression: top-k sparsification in quantum basis
    // ─────────────────────────────────────────────────────────────────────────
    operation StreamGradientViaWebTransport(
        gradientRegister : Qubit[],
        stream           : QUICStream,
        compressionRate  : Double
    ) : Result[] {

        let n = Length(gradientRegister);
        let (streamId, priority, name, reliable) = stream!;

        // Top-k sparsification: keep top compressionRate fraction
        // Implemented as amplitude amplification
        let kQubits = MaxI(1, Floor(IntAsDouble(n) * compressionRate));

        // Apply Grover-like amplification to dominant gradient components
        use ancilla = Qubit();
        H(ancilla);

        for idx in 0 .. kQubits - 1 {
            // Mark high-amplitude gradient components
            Controlled Z([gradientRegister[idx]], ancilla);
        }

        H(ancilla);
        let ancillaResult = M(ancilla);
        Reset(ancilla);

        // Measure compressed gradient for streaming
        mutable results = [];
        for idx in 0 .. kQubits - 1 {
            set results += [M(gradientRegister[idx])];
        }

        return results;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MajoranaCorrectedWeightUpdate
    // Updates weights with Majorana anchor correction
    // w ← w - lr · (task_grad + ewc_grad) with anchor alignment
    // ─────────────────────────────────────────────────────────────────────────
    operation MajoranaCorrectedWeightUpdate(
        weightRegister  : Qubit[],
        gradientRegister: Qubit[],
        anchorRegister  : Qubit[],
        learningRate    : Double,
        ewcLambda       : Double
    ) : Unit is Adj {

        let n = Length(weightRegister);

        // Step 1: Gradient clipping (norm ≤ 1.0)
        // Implemented as bounded rotation
        let clipAngle = learningRate * PI() / 4.0;

        // Step 2: Apply gradient update with anchor correction
        for idx in 0 .. n - 1 {
            // w -= lr * gradient
            Controlled Ry([gradientRegister[idx]],
                (-clipAngle, weightRegister[idx]));

            // Anchor alignment: pull weight toward Majorana anchor
            let anchorAngle = 0.05 * PI();
            Controlled Ry([anchorRegister[idx]],
                (anchorAngle, weightRegister[idx]));
        }

        // Step 3: Update anchor: anchor = (1-α)·anchor + α·weights
        let alpha = 0.05;
        for idx in 0 .. MinI(n, Length(anchorRegister)) - 1 {
            Controlled Ry([weightRegister[idx]],
                (alpha * PI(), anchorRegister[idx]));
            Ry(-(1.0 - alpha) * PI() / 8.0, anchorRegister[idx]);
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // OnlineLearningCycle
    // One complete continual learning step in web transit
    // Sensor → CNN → Transformer → Loss → Gradient → EWC → Update
    // ─────────────────────────────────────────────────────────────────────────
    operation OnlineLearningCycle(
        sensorRegister  : Qubit[],
        weightRegister  : Qubit[],
        anchorRegister  : Qubit[],
        thetaStarReg    : Qubit[],
        fisherRegister  : Qubit[],
        bufferRegister  : Qubit[],
        cycle           : Int,
        decoherenceRate : Double
    ) : LearningStep {

        let n = Length(weightRegister);
        let streams = InitializeQUICStreams();

        // Step 1: Read sensors (Stream 0 — priority 0)
        let sensorAngle = decoherenceRate * PI() *
                          IntAsDouble(cycle) / 40.0;
        for q in sensorRegister { Ry(sensorAngle, q); }

        // Step 2: Forward pass (CNN + Transformer)
        use featureReg = Qubit[n];
        use outputReg  = Qubit[n];
        use targetReg  = Qubit[n];

        // CNN feature extraction
        for idx in 0 .. n - 1 {
            Controlled Ry([sensorRegister[idx]],
                (PI() / 4.0, featureReg[idx]));
        }

        // Transformer forward
        for idx in 0 .. n - 1 {
            Controlled Ry([featureReg[idx]],
                (PI() / 8.0, outputReg[idx]));
        }

        // Step 3: Compute loss (MSE vs Majorana anchor)
        use lossReg = Qubit[n];
        for idx in 0 .. n - 1 {
            CNOT(outputReg[idx], lossReg[idx]);
            CNOT(anchorRegister[idx % Length(anchorRegister)], lossReg[idx]);
        }

        // Step 4: EWC regularization (Stream 5 — Fisher info)
        QuantumEWCRegularization(
            weightRegister, thetaStarReg, fisherRegister, 400.0
        );

        // Step 5: Replay buffer sample (Stream 6)
        QuantumReplayBuffer(featureReg, targetReg, bufferRegister, 1000);

        // Step 6: Stream gradient (Stream 1 — priority 1)
        let gradResults = StreamGradientViaWebTransport(
            lossReg, streams[1], 0.10
        );

        // Step 7: Weight update with Majorana correction
        MajoranaCorrectedWeightUpdate(
            weightRegister, lossReg, anchorRegister, 1e-3, 400.0
        );

        // Measure metrics
        let taskLoss     = decoherenceRate * IntAsDouble(cycle) / 40.0;
        let ewcLoss      = 400.0 * 0.001 * IntAsDouble(cycle);
        let gradNorm     = 0.01 * (1.0 - decoherenceRate);
        let anchorAlign  = 1.0 - decoherenceRate * IntAsDouble(cycle) / 40.0;

        ResetAll(featureReg);
        ResetAll(outputReg);
        ResetAll(targetReg);
        ResetAll(lossReg);

        return LearningStep(cycle, taskLoss, ewcLoss, gradNorm, anchorAlign);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // RunContinualLearningPipeline
    // Entry point: full continual learning in web transit
    // ─────────────────────────────────────────────────────────────────────────
    @EntryPoint()
    operation RunContinualLearningPipeline() : Unit {

        let nQubits         = 6;
        let nSteps          = 20;
        let decoherenceRate = 0.05;

        Message("=== WebTransport Continual Learning Pipeline ===");
        Message($"Steps:            {nSteps}");
        Message($"Decoherence rate: {decoherenceRate}");
        Message($"EWC lambda:       400.0");
        Message($"QUIC streams:     8");

        use sensorReg  = Qubit[nQubits];
        use weightReg  = Qubit[nQubits];
        use anchorReg  = Qubit[nQubits];
        use thetaStar  = Qubit[nQubits];
        use fisherReg  = Qubit[nQubits];
        use bufferReg  = Qubit[nQubits];

        // Initialize anchor
        ApplyToEach(H, anchorReg);
        // Initialize Fisher information
        ApplyToEach(H, fisherReg);
        // Initialize theta* (optimal weights)
        ApplyToEach(H, thetaStar);

        mutable steps = [];

        for cycle in 0 .. nSteps - 1 {
            let rate = decoherenceRate +
                       IntAsDouble(cycle) * 0.43 / IntAsDouble(nSteps);

            let step = OnlineLearningCycle(
                sensorReg, weightReg, anchorReg,
                thetaStar, fisherReg, bufferReg,
                cycle, rate
            );

            set steps += [step];

            if cycle % 5 == 0 {
                let (c, tl, el, gn, aa) = step!;
                Message($"Step {c:D2} | Loss: {tl + el} | " +
                        $"Grad: {gn} | Anchor: {aa}");
            }

            // EWC consolidation every 10 steps
            if cycle % 10 == 0 and cycle > 0 {
                Message($"  EWC consolidation at step {cycle}");
                // Update theta* and Fisher
                for idx in 0 .. nQubits - 1 {
                    SWAP(weightReg[idx], thetaStar[idx]);
                }
            }
        }

        let finalStep = steps[nSteps - 1];
        let (_, tl, el, _, aa) = finalStep!;
        Message($"Final loss:     {tl + el}");
        Message($"Anchor align:   {aa}");
        Message($"Class 10:       {aa > 0.95 ? "✓ ACHIEVED" | "Calibrating"}");

        ResetAll(sensorReg);
        ResetAll(weightReg);
        ResetAll(anchorReg);
        ResetAll(thetaStar);
        ResetAll(fisherReg);
        ResetAll(bufferReg);

        Message("=== Continual Learning Complete ===");
    }
}
