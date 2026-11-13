// =============================================================================
// Buffers.qs — Quantum buffer management for LLM KV-cache and attention
// =============================================================================

namespace WindowsAGI.QuantumSDK.Buffers {

    import Std.Arrays.*;
    import Std.Convert.*;
    import Std.Intrinsic.*;
    import Std.Math.*;

    import WindowsAGI.QuantumSDK.Types.*;
    import WindowsAGI.QuantumSDK.Arrays.*;

    // ─────────────────────────────────────────────────────────────────────────
    // Quantum ring buffer (circular qubit register)
    // ─────────────────────────────────────────────────────────────────────────
    operation InitRingBuffer(qubits : Qubit[], size : Int) : Unit {
        if size <= 0 or size > Length(qubits) {
            fail $"Ring buffer size {size} must be in [1, {Length(qubits)}].";
        }
        ResetAll(qubits);
    }

    operation WriteRingBuffer(
        qubits  : Qubit[],
        head    : Int,
        value   : Double,
        size    : Int
    ) : Int {
        let idx = head % size;
        let angle = 2.0 * ArcSin(MinD(1.0, MaxD(-1.0, value)));
        Ry(angle, qubits[idx]);
        return (head + 1) % size;
    }

    operation ReadRingBuffer(
        qubits : Qubit[],
        tail   : Int,
        size   : Int
    ) : (Double, Int) {
        let idx = tail % size;
        use ancilla = Qubit();
        CNOT(qubits[idx], ancilla);
        let r = MResetZ(ancilla);
        let value = r == One ? 1.0 | 0.0;
        return (value, (tail + 1) % size);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Quantum KV-cache buffer for transformer attention
    // ─────────────────────────────────────────────────────────────────────────
    operation InitKVCache(
        keyQubits   : Qubit[],
        valueQubits : Qubit[],
        seqLen      : Int,
        headDim     : Int
    ) : Unit {
        if seqLen * headDim > Length(keyQubits) {
            fail "KV cache: insufficient key qubits.";
        }
        if seqLen * headDim > Length(valueQubits) {
            fail "KV cache: insufficient value qubits.";
        }
        ResetAll(keyQubits);
        ResetAll(valueQubits);
    }

    operation WriteKVCache(
        keyQubits   : Qubit[],
        valueQubits : Qubit[],
        position    : Int,
        headDim     : Int,
        keyVec      : Double[],
        valueVec    : Double[]
    ) : Unit {
        let offset = position * headDim;
        for i in 0..headDim - 1 {
            if offset + i < Length(keyQubits) and i < Length(keyVec) {
                let angle = 2.0 * ArcSin(MinD(1.0, MaxD(-1.0, keyVec[i])));
                Ry(angle, keyQubits[offset + i]);
            }
            if offset + i < Length(valueQubits) and i < Length(valueVec) {
                let angle = 2.0 * ArcSin(MinD(1.0, MaxD(-1.0, valueVec[i])));
                Ry(angle, valueQubits[offset + i]);
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Quantum tensor buffer (multi-dimensional)
    // ─────────────────────────────────────────────────────────────────────────
    operation InitTensorBuffer(
        qubits : Qubit[],
        shape  : Int[]
    ) : Unit {
        mutable totalSize = 1;
        for dim in shape { set totalSize *= dim; }
        if totalSize > Length(qubits) {
            fail $"Tensor buffer: shape requires {totalSize} qubits, got {Length(qubits)}.";
        }
        ResetAll(qubits);
    }

    operation WriteTensorElement(
        qubits  : Qubit[],
        shape   : Int[],
        indices : Int[],
        value   : Double
    ) : Unit {
        if Length(indices) != Length(shape) {
            fail "WriteTensorElement: indices and shape must have equal length.";
        }
        mutable flatIdx = 0;
        mutable stride  = 1;
        for i in Length(shape) - 1..-1..0 {
            set flatIdx += indices[i] * stride;
            set stride  *= shape[i];
        }
        if flatIdx < Length(qubits) {
            let angle = 2.0 * ArcSin(MinD(1.0, MaxD(-1.0, value)));
            Ry(angle, qubits[flatIdx]);
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Quantum attention buffer (stores attention scores)
    // ─────────────────────────────────────────────────────────────────────────
    operation StoreAttentionScores(
        qubits  : Qubit[],
        scores  : Double[],
        headIdx : Int,
        headDim : Int
    ) : Unit {
        let offset = headIdx * headDim;
        for i in 0..headDim - 1 {
            if offset + i < Length(qubits) and i < Length(scores) {
                let angle = 2.0 * ArcSin(MinD(1.0, MaxD(-1.0, scores[i])));
                Ry(angle, qubits[offset + i]);
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Quantum gradient buffer (for backpropagation)
    // ─────────────────────────────────────────────────────────────────────────
    operation AccumulateGradient(
        gradQubits : Qubit[],
        gradient   : Double[],
        scale      : Double
    ) : Unit {
        for i in 0..Length(gradient) - 1 {
            if i < Length(gradQubits) {
                let angle = scale * gradient[i] * PI() / 4.0;
                Rz(angle, gradQubits[i]);
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Quantum activation buffer (ReLU, GELU, SiLU)
    // ─────────────────────────────────────────────────────────────────────────
    operation ApplyQuantumReLU(qubits : Qubit[]) : Unit {
        // Quantum analog: measure and re-prepare only positive components
        for q in qubits {
            use ancilla = Qubit();
            CNOT(q, ancilla);
            let r = MResetZ(ancilla);
            if r == Zero { Reset(q); }
        }
    }

    operation ApplyQuantumGELU(qubits : Qubit[], scale : Double) : Unit {
        for q in qubits {
            // GELU approximation via rotation
            Ry(scale * 0.7978845608, q);
            Rz(scale * 0.0356774, q);
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Quantum embedding buffer (token embeddings)
    // ─────────────────────────────────────────────────────────────────────────
    operation LoadEmbedding(
        qubits    : Qubit[],
        tokenId   : Int,
        vocabSize : Int,
        embedDim  : Int
    ) : Unit {
        if tokenId < 0 or tokenId >= vocabSize {
            fail $"LoadEmbedding: tokenId {tokenId} out of range [0, {vocabSize}).";
        }
        // Encode token ID as binary in first log2(vocabSize) qubits
        let bits = Ceiling(Log(IntAsDouble(vocabSize)) / Log(2.0));
        for i in 0..bits - 1 {
            if (tokenId >>> i) &&& 1 == 1 and i < Length(qubits) {
                X(qubits[i]);
            }
        }
        // Spread to embedding dimension via Hadamard
        for i in bits..MinI(embedDim, Length(qubits)) - 1 {
            H(qubits[i]);
        }
    }
}
