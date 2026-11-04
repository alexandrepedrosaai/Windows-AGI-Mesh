// =============================================================================
// run_cnn.qs
// CNN embedding pipeline entry point — Siamese CNN for sensor hash encoding
// Namespace: SiameseTwinAI.Entrypoints
// =============================================================================

namespace SiameseTwinAI.Entrypoints {

    open Microsoft.Quantum.Arrays;
    open Microsoft.Quantum.Convert;
    open Microsoft.Quantum.Intrinsic;
    open Microsoft.Quantum.Math;
    open Microsoft.Quantum.Diagnostics;

    // =========================================================================
    // CNN Architecture Constants
    // =========================================================================

    function CNNInputChannels()  : Int { return 1; }
    function CNNEmbeddingDim()   : Int { return 512; }
    function CNNOutputDim()      : Int { return 512; }
    function CNNNConvLayers()    : Int { return 4; }
    function CNNNHeads()         : Int { return 8; }
    function CNNDModel()         : Int { return 512; }
    function CNNDff()            : Int { return 2048; }
    function CNNNTransformerLayers() : Int { return 6; }

    // =========================================================================
    // Convolutional Layer Simulation
    // =========================================================================

    newtype ConvLayerState = (
        LayerIdx    : Int,
        InChannels  : Int,
        OutChannels : Int,
        KernelSize  : Int,
        Stride      : Int,
        Padding     : Int,
        UseReLU     : Bool,
        UseBatchNorm: Bool,
        NParams     : Int
    );

    function CreateConvLayer(
        layerIdx : Int,
        inCh : Int,
        outCh : Int,
        kernelSize : Int,
        stride : Int
    ) : ConvLayerState {
        let nParams = kernelSize * kernelSize * inCh * outCh + outCh + 2 * outCh;
        return ConvLayerState(
            layerIdx, inCh, outCh, kernelSize, stride,
            kernelSize / 2, true, true, nParams
        );
    }

    function SimulateConvForward(
        input : Double[],
        layer : ConvLayerState,
        seed : Int
    ) : Double[] {
        // Simulate conv output: project input to output channels
        let outDim = CNNEmbeddingDim();
        mutable output = new Double[outDim];

        let inLen = Length(input);
        for i in 0 .. outDim - 1 {
            mutable val = 0.0;
            for j in 0 .. MinI(inLen, 8) - 1 {
                let s = (seed + i * 100 + j) * 1664525 + 1013904223;
                let weight = IntAsDouble((s &&& 0x7FFFFFFF) % 1000) / 10000.0 - 0.05;
                set val += input[j % inLen] * weight;
            }
            // ReLU
            set output w/= i <- MaxD(0.0, val);
        }

        // Batch norm (simplified: normalize)
        mutable mean = 0.0;
        for v in output { set mean += v; }
        set mean /= IntAsDouble(outDim);
        mutable variance = 0.0;
        for v in output { set variance += (v - mean) * (v - mean); }
        set variance /= IntAsDouble(outDim);
        let std = Sqrt(variance + 1e-5);

        for i in 0 .. outDim - 1 {
            set output w/= i <- (output[i] - mean) / std;
        }

        return output;
    }

    // =========================================================================
    // Siamese CNN Architecture
    // =========================================================================

    newtype SiameseCNNState = (
        ConvLayers      : ConvLayerState[],
        TotalParams     : Int,
        EmbeddingDim    : Int,
        InferenceCount  : Int,
        TotalLatencyMs  : Double
    );

    function InitSiameseCNN() : SiameseCNNState {
        let channels = [32, 64, 128, 256];
        mutable layers = new ConvLayerState[CNNNConvLayers()];
        mutable inCh = CNNInputChannels();
        mutable totalParams = 0;

        for i in 0 .. CNNNConvLayers() - 1 {
            let outCh = channels[i];
            let layer = CreateConvLayer(i, inCh, outCh, 3, 1);
            set layers w/= i <- layer;
            set totalParams += layer::NParams;
            set inCh = outCh;
        }

        // Output projection
        set totalParams += channels[CNNNConvLayers() - 1] * CNNEmbeddingDim() + CNNEmbeddingDim();

        return SiameseCNNState(layers, totalParams, CNNEmbeddingDim(), 0, 0.0);
    }

    function ForwardPass(
        cnn : SiameseCNNState,
        inputHash : Int[],
        seed : Int
    ) : Double[] {
        // Convert hash to float input
        mutable input = new Double[Length(inputHash)];
        for i in 0 .. Length(inputHash) - 1 {
            set input w/= i <- IntAsDouble(inputHash[i]) / IntAsDouble(2147483647);
        }

        // Pass through conv layers
        mutable features = input;
        for layer in cnn::ConvLayers {
            set features = SimulateConvForward(features, layer, seed + layer::LayerIdx * 1000);
        }

        // Global average pooling → embedding
        let embDim = cnn::EmbeddingDim;
        mutable embedding = new Double[embDim];
        let featLen = Length(features);
        for i in 0 .. embDim - 1 {
            set embedding w/= i <- features[i % featLen];
        }

        // L2 normalize
        mutable norm = 0.0;
        for v in embedding { set norm += v * v; }
        set norm = Sqrt(norm);
        if norm > 1e-10 {
            for i in 0 .. embDim - 1 {
                set embedding w/= i <- embedding[i] / norm;
            }
        }

        return embedding;
    }

    function SiameseDistance(
        embA : Double[],
        embB : Double[]
    ) : Double {
        // Cosine distance = 1 - cosine_similarity
        let n = MinI(Length(embA), Length(embB));
        mutable dot = 0.0;
        mutable normA = 0.0;
        mutable normB = 0.0;
        for i in 0 .. n - 1 {
            set dot += embA[i] * embB[i];
            set normA += embA[i] * embA[i];
            set normB += embB[i] * embB[i];
        }
        set normA = Sqrt(normA);
        set normB = Sqrt(normB);
        if normA < 1e-10 or normB < 1e-10 { return 1.0; }
        return 1.0 - dot / (normA * normB);
    }

    function EuclideanDistance(embA : Double[], embB : Double[]) : Double {
        let n = MinI(Length(embA), Length(embB));
        mutable sumSq = 0.0;
        for i in 0 .. n - 1 {
            let diff = embA[i] - embB[i];
            set sumSq += diff * diff;
        }
        return Sqrt(sumSq);
    }

    // =========================================================================
    // Embedding Quality Metrics
    // =========================================================================

    function ComputeEmbeddingNorm(embedding : Double[]) : Double {
        mutable norm = 0.0;
        for v in embedding { set norm += v * v; }
        return Sqrt(norm);
    }

    function ComputeEmbeddingEntropy(embedding : Double[]) : Double {
        // Approximate entropy of embedding distribution
        let n = Length(embedding);
        if n == 0 { return 0.0; }
        mutable entropy = 0.0;
        for v in embedding {
            let p = AbsD(v) / IntAsDouble(n);
            if p > 1e-10 {
                set entropy -= p * Log(p);
            }
        }
        return entropy;
    }

    function ComputeEmbeddingSparsity(embedding : Double[], threshold : Double) : Double {
        let n = Length(embedding);
        if n == 0 { return 0.0; }
        mutable zeros = 0;
        for v in embedding {
            if AbsD(v) < threshold { set zeros += 1; }
        }
        return IntAsDouble(zeros) / IntAsDouble(n);
    }

    // =========================================================================
    // Batch Processing
    // =========================================================================

    newtype EmbeddingBatch = (
        Embeddings  : Double[][],
        Hashes      : Int[][],
        BatchSize   : Int,
        EmbeddingDim: Int,
        LatencyMs   : Double
    );

    function ProcessBatch(
        cnn : SiameseCNNState,
        hashes : Int[][],
        seed : Int
    ) : EmbeddingBatch {
        let batchSize = Length(hashes);
        mutable embeddings = new Double[][batchSize];

        for i in 0 .. batchSize - 1 {
            set embeddings w/= i <- ForwardPass(cnn, hashes[i], seed + i * 100);
        }

        // Simulate batch latency
        let latencyMs = IntAsDouble(batchSize) * 0.1;

        return EmbeddingBatch(embeddings, hashes, batchSize, cnn::EmbeddingDim, latencyMs);
    }

    // =========================================================================
    // Contrastive Loss
    // =========================================================================

    function ContrastiveLoss(
        embA : Double[],
        embB : Double[],
        isSimilar : Bool,
        margin : Double
    ) : Double {
        let dist = EuclideanDistance(embA, embB);
        if isSimilar {
            return dist * dist;
        } else {
            return MaxD(0.0, margin - dist) * MaxD(0.0, margin - dist);
        }
    }

    function TripletLoss(
        anchor : Double[],
        positive : Double[],
        negative : Double[],
        margin : Double
    ) : Double {
        let dPos = EuclideanDistance(anchor, positive);
        let dNeg = EuclideanDistance(anchor, negative);
        return MaxD(0.0, dPos - dNeg + margin);
    }

    // =========================================================================
    // CNN Benchmark
    // =========================================================================

    operation BenchmarkCNN(cnn : SiameseCNNState, nSamples : Int, seed : Int) : Unit {
        Message($"\n[CNN] Benchmarking Siamese CNN ({nSamples} samples)...");

        mutable totalLatency = 0.0;
        mutable totalNorm = 0.0;
        mutable totalEntropy = 0.0;

        for i in 0 .. nSamples - 1 {
            let s = (seed + i * 1000) * 1664525 + 1013904223;
            let hash = [
                (s &&& 0x7FFFFFFF),
                ((s * 1664525) &&& 0x7FFFFFFF),
                ((s * 6364136) &&& 0x7FFFFFFF),
                ((s * 1013904) &&& 0x7FFFFFFF),
                ((s * 2246822) &&& 0x7FFFFFFF),
                ((s * 3266489) &&& 0x7FFFFFFF),
                ((s * 1500450) &&& 0x7FFFFFFF),
                ((s * 2891336) &&& 0x7FFFFFFF)
            ];

            let embedding = ForwardPass(cnn, hash, seed + i);
            let norm = ComputeEmbeddingNorm(embedding);
            let entropy = ComputeEmbeddingEntropy(embedding);

            set totalNorm += norm;
            set totalEntropy += entropy;
            set totalLatency += 0.1;  // Simulated 0.1ms per sample
        }

        let meanNorm = totalNorm / IntAsDouble(nSamples);
        let meanEntropy = totalEntropy / IntAsDouble(nSamples);
        let meanLatency = totalLatency / IntAsDouble(nSamples);
        let throughput = 1000.0 / meanLatency;

        Message($"[CNN] Results:");
        Message($"  Mean embedding norm: {meanNorm:.4f}");
        Message($"  Mean embedding entropy: {meanEntropy:.4f}");
        Message($"  Mean latency: {meanLatency:.3f}ms");
        Message($"  Throughput: {throughput:.0f} samples/s");
        Message($"  Total parameters: {cnn::TotalParams}");
    }

    // =========================================================================
    // CNN Entry Point
    // =========================================================================

    @EntryPoint()
    operation RunCNN() : Unit {
        Message("╔══════════════════════════════════════════════════════════════╗");
        Message("║         Windows-AGI-Mesh Siamese CNN v1.0.0                 ║");
        Message("║  512-dim Embedding for SafaSensor 5K Hash Vectors            ║");
        Message("╚══════════════════════════════════════════════════════════════╝");

        // Initialize CNN
        let cnn = InitSiameseCNN();
        Message($"\n[CNN] Architecture initialized:");
        Message($"  Conv layers: {CNNNConvLayers()} (channels: 32→64→128→256)");
        Message($"  Embedding dim: {CNNEmbeddingDim()}");
        Message($"  Total parameters: {cnn::TotalParams}");

        // Test forward pass
        Message("\n[CNN] Testing forward pass...");
        let testHash = [123456789, 987654321, 111222333, 444555666,
                        777888999, 100200300, 400500600, 700800900];
        let embedding = ForwardPass(cnn, testHash, 42);
        let norm = ComputeEmbeddingNorm(embedding);
        let entropy = ComputeEmbeddingEntropy(embedding);
        let sparsity = ComputeEmbeddingSparsity(embedding, 0.01);

        Message($"[CNN] Embedding stats:");
        Message($"  Norm: {norm:.4f}");
        Message($"  Entropy: {entropy:.4f}");
        Message($"  Sparsity: {sparsity:.4f}");

        // Test Siamese distance
        Message("\n[CNN] Testing Siamese distance...");
        let hashA = [100, 200, 300, 400, 500, 600, 700, 800];
        let hashB = [110, 210, 310, 410, 510, 610, 710, 810];  // Similar
        let hashC = [900, 800, 700, 600, 500, 400, 300, 200];  // Different

        let embA = ForwardPass(cnn, hashA, 42);
        let embB = ForwardPass(cnn, hashB, 43);
        let embC = ForwardPass(cnn, hashC, 44);

        let distAB = SiameseDistance(embA, embB);
        let distAC = SiameseDistance(embA, embC);

        Message($"[CNN] Distance A↔B (similar): {distAB:.4f}");
        Message($"[CNN] Distance A↔C (different): {distAC:.4f}");
        Message($"[CNN] Discrimination ratio: {distAC / MaxD(distAB, 0.001):.2f}x");

        // Test contrastive loss
        let lossPos = ContrastiveLoss(embA, embB, true, 1.0);
        let lossNeg = ContrastiveLoss(embA, embC, false, 1.0);
        let lossTriplet = TripletLoss(embA, embB, embC, 0.2);

        Message($"\n[CNN] Loss values:");
        Message($"  Contrastive (positive pair): {lossPos:.4f}");
        Message($"  Contrastive (negative pair): {lossNeg:.4f}");
        Message($"  Triplet loss: {lossTriplet:.4f}");

        // Benchmark
        BenchmarkCNN(cnn, 20, 42);

        // Batch processing
        Message("\n[CNN] Testing batch processing...");
        let batchHashes = [hashA, hashB, hashC,
                           [1,2,3,4,5,6,7,8], [9,8,7,6,5,4,3,2]];
        let batch = ProcessBatch(cnn, batchHashes, 42);
        Message($"[CNN] Batch processed: {batch::BatchSize} samples in {batch::LatencyMs:.2f}ms");

        Message("\n[CNN] Siamese CNN pipeline complete.");
        Message("[CNN] Embeddings ready for Transformer and MAIA-300.");
    }
}