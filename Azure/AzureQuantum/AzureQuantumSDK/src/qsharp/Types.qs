// =============================================================================
// Types.qs — Core UDTs for Windows-AGI-Mesh-QuantumSDK
// 5B-parameter LLM with hybrid quantum-classical quantization
// Majorana topological qubits | MAIA 300 | Brainwave FPGA | Hollow-Core Fiber
// =============================================================================

namespace WindowsAGI.QuantumSDK.Types {

    // -------------------------------------------------------------------------
    // Fundamental experiment result
    // -------------------------------------------------------------------------
    newtype ExperimentResult = (
        Mean            : Double,
        Deviation       : Double,
        IsAboveThreshold: Bool,
        ShotCount       : Int,
        QubitCount      : Int,
        AncillaCount    : Int,
        ThetaZ          : Double,
        ThetaY          : Double,
        Threshold       : Double,
        BackendId       : String,
        TimestampUtc    : String
    );

    // -------------------------------------------------------------------------
    // Topological qubit state (Majorana 1 QPU)
    // -------------------------------------------------------------------------
    newtype TopologicalQubitState = (
        PhysicalIndex   : Int,
        LogicalIndex    : Int,
        ParityValue     : Int,
        FusionOutcome   : Bool,
        ErrorSyndrome   : Int[],
        CorrectionApplied: Bool,
        Fidelity        : Double,
        CoherenceTimeUs : Double,
        TopoconductorId : String
    );

    // -------------------------------------------------------------------------
    // Majorana zero mode pair
    // -------------------------------------------------------------------------
    newtype MajoranaZeroMode = (
        LeftMZMIndex    : Int,
        RightMZMIndex   : Int,
        PairParity      : Int,
        BraidHistory    : Int[],
        ProtectionGap   : Double,
        IsStabilized    : Bool
    );

    // -------------------------------------------------------------------------
    // Quantum error correction syndrome
    // -------------------------------------------------------------------------
    newtype QECSyndrome = (
        SyndromeVector  : Int[],
        ErrorType       : String,
        ErrorLocation   : Int[],
        CorrectionOp    : String,
        LogicalErrorRate: Double,
        PhysicalErrorRate: Double,
        CodeDistance    : Int,
        CycleCount      : Int
    );

    // -------------------------------------------------------------------------
    // Surface code logical qubit
    // -------------------------------------------------------------------------
    newtype SurfaceCodeQubit = (
        LogicalIndex    : Int,
        CodeDistance    : Int,
        DataQubits      : Int[],
        XStabilizers    : Int[][],
        ZStabilizers    : Int[][],
        LogicalXOp      : Int[],
        LogicalZOp      : Int[],
        LogicalErrorRate: Double,
        PhysicalQubits  : Int
    );

    // -------------------------------------------------------------------------
    // Quantum circuit descriptor
    // -------------------------------------------------------------------------
    newtype CircuitDescriptor = (
        CircuitId       : String,
        QubitCount      : Int,
        AncillaCount    : Int,
        GateCount       : Int,
        Depth           : Int,
        TwoQubitGates   : Int,
        TGateCount      : Int,
        CliffordCount   : Int,
        EstimatedRuntime: Double,
        BackendTarget   : String
    );

    // -------------------------------------------------------------------------
    // Sampling statistics
    // -------------------------------------------------------------------------
    newtype SamplingStats = (
        Mean            : Double,
        Variance        : Double,
        StdDev          : Double,
        Min             : Double,
        Max             : Double,
        Median          : Double,
        Skewness        : Double,
        Kurtosis        : Double,
        ConfidenceInterval95Lo: Double,
        ConfidenceInterval95Hi: Double,
        SampleCount     : Int
    );

    // -------------------------------------------------------------------------
    // Hardware backend descriptor
    // -------------------------------------------------------------------------
    newtype BackendDescriptor = (
        BackendId       : String,
        Provider        : String,
        QubitCount      : Int,
        LogicalQubits   : Int,
        MaxCircuitDepth : Int,
        TwoQubitFidelity: Double,
        OneQubitFidelity: Double,
        ReadoutFidelity : Double,
        T1TimeUs        : Double,
        T2TimeUs        : Double,
        GateSetName     : String,
        ConnectivityType: String,
        IsSimulator     : Bool,
        IsTopological   : Bool,
        SupportsMidCircuitMeasurement: Bool
    );

    // -------------------------------------------------------------------------
    // LLM token embedding (quantum-encoded)
    // -------------------------------------------------------------------------
    newtype QuantumTokenEmbedding = (
        TokenId         : Int,
        EmbeddingDim    : Int,
        AmplitudeVector : Double[],
        PhaseVector     : Double[],
        EntanglementMap : Int[][],
        QuantizationBits: Int,
        CompressionRatio: Double
    );

    // -------------------------------------------------------------------------
    // Attention head quantum state
    // -------------------------------------------------------------------------
    newtype QuantumAttentionState = (
        HeadIndex       : Int,
        QueryQubits     : Int,
        KeyQubits       : Int,
        ValueQubits     : Int,
        AttentionScores : Double[],
        SoftmaxOutput   : Double[],
        ContextVector   : Double[],
        EntanglementDepth: Int
    );

    // -------------------------------------------------------------------------
    // Hybrid quantization descriptor
    // -------------------------------------------------------------------------
    newtype HybridQuantizationConfig = (
        ClassicalBits   : Int,
        QuantumBits     : Int,
        QuantizationScheme: String,
        CalibrationData : Double[],
        ScaleFactors    : Double[],
        ZeroPoints      : Int[],
        PerChannelScale : Bool,
        SymmetricQuant  : Bool,
        MixedPrecision  : Bool,
        FP8Enabled      : Bool,
        INT4Enabled     : Bool,
        BF16Enabled     : Bool
    );

    // -------------------------------------------------------------------------
    // MAIA 300 accelerator task
    // -------------------------------------------------------------------------
    newtype MAIA300Task = (
        TaskId          : String,
        ModelShardId    : Int,
        TotalShards     : Int,
        BatchSize       : Int,
        SequenceLength  : Int,
        HiddenDim       : Int,
        NumHeads        : Int,
        LayerRange      : Int[],
        HBM4BandwidthGBs: Double,
        ComputeTFLOPS   : Double,
        LatencyMs       : Double,
        PowerWatts      : Double,
        ChipletId       : Int,
        RackId          : Int
    );

    // -------------------------------------------------------------------------
    // Brainwave FPGA inference task
    // -------------------------------------------------------------------------
    newtype BrainwaveFPGATask = (
        TaskId          : String,
        FPGAModel       : String,
        MACUnits        : Int,
        SIMDWidth       : Int,
        NativePrecision : String,
        ModelName       : String,
        BatchSize       : Int,
        LatencyMs       : Double,
        ThroughputTFLOPS: Double,
        OnChipMemoryMB  : Int,
        FabricBandwidthGBs: Double,
        IsRealTimeAI    : Bool
    );

    // -------------------------------------------------------------------------
    // Hollow-core fiber photonic transport
    // -------------------------------------------------------------------------
    newtype PhotonicTransportState = (
        FiberId         : String,
        LengthKm        : Double,
        LatencyUs       : Double,
        BandwidthTbps   : Double,
        PhotonLossDB    : Double,
        RefractiveIndex : Double,
        CoreDiameterUm  : Double,
        WavelengthNm    : Double,
        IsHollowCore    : Bool,
        InTransitComputeEnabled: Bool,
        PhotonicAcceleration: Bool,
        LatencyReductionPct: Double
    );

    // -------------------------------------------------------------------------
    // Distributed mesh node
    // -------------------------------------------------------------------------
    newtype MeshNode = (
        NodeId          : String,
        NodeType        : String,
        RegionId        : String,
        DatacenterId    : String,
        HardwareBackend : String,
        AvailableQubits : Int,
        AvailableGPUs   : Int,
        AvailableFPGAs  : Int,
        MAIA300Count    : Int,
        NetworkBandwidthGbps: Double,
        IsQuantumEnabled: Bool,
        IsPhotonicEnabled: Bool,
        HealthScore     : Double
    );

    // -------------------------------------------------------------------------
    // Training workload descriptor
    // -------------------------------------------------------------------------
    newtype TrainingWorkload = (
        WorkloadId      : String,
        ModelName       : String,
        ParameterCount  : Int,
        BatchSize       : Int,
        GradientAccumSteps: Int,
        LearningRate    : Double,
        WarmupSteps     : Int,
        TotalSteps      : Int,
        CheckpointEvery : Int,
        MixedPrecision  : Bool,
        GradientCheckpointing: Bool,
        TensorParallelDegree: Int,
        PipelineParallelDegree: Int,
        DataParallelDegree: Int,
        QuantumAssistedLayers: Int[]
    );

    // -------------------------------------------------------------------------
    // Inference request
    // -------------------------------------------------------------------------
    newtype InferenceRequest = (
        RequestId       : String,
        ModelVersion    : String,
        InputTokenCount : Int,
        MaxNewTokens    : Int,
        Temperature     : Double,
        TopP            : Double,
        TopK            : Int,
        RepetitionPenalty: Double,
        BeamWidth       : Int,
        UseQuantumSampling: Bool,
        TargetBackend   : String,
        PriorityLevel   : Int,
        TimeoutMs       : Int
    );

    // -------------------------------------------------------------------------
    // Factorization result
    // -------------------------------------------------------------------------
    newtype FactorizationResult = (
        InputNumber     : Int,
        Factor1         : Int,
        Factor2         : Int,
        IsPrime         : Bool,
        AlgorithmUsed   : String,
        QubitCount      : Int,
        CircuitDepth    : Int,
        ClassicalSteps  : Int,
        QuantumAdvantage: Bool,
        RuntimeMs       : Double
    );

    // -------------------------------------------------------------------------
    // Cluster topology node
    // -------------------------------------------------------------------------
    newtype ClusterNode = (
        NodeId          : String,
        Rank            : Int,
        WorldSize       : Int,
        LocalRank       : Int,
        HostName        : String,
        IPAddress       : String,
        GPUCount        : Int,
        CPUCores        : Int,
        MemoryGB        : Int,
        NVLinkBandwidthGBs: Double,
        InfiniBandGbps  : Double,
        IsCoordinator   : Bool
    );

    // -------------------------------------------------------------------------
    // Model weight shard
    // -------------------------------------------------------------------------
    newtype WeightShard = (
        ShardId         : Int,
        LayerStart      : Int,
        LayerEnd        : Int,
        ParameterCount  : Int,
        SizeBytes       : Int,
        Precision       : String,
        IsQuantized     : Bool,
        QuantizationBits: Int,
        ChecksumSHA256  : String,
        StorageBackend  : String,
        IsLoaded        : Bool
    );

    // -------------------------------------------------------------------------
    // Benchmark case
    // -------------------------------------------------------------------------
    newtype BenchmarkCase = (
        CaseId          : String,
        CaseName        : String,
        QubitCount      : Int,
        AncillaCount    : Int,
        ThetaZ          : Double,
        ThetaY          : Double,
        ShotCount       : Int,
        Threshold       : Double,
        ExpectedMeanLo  : Double,
        ExpectedMeanHi  : Double,
        BackendTarget   : String,
        TimeoutSeconds  : Int,
        Tags            : String[]
    );

    // -------------------------------------------------------------------------
    // Quantum-classical hybrid layer
    // -------------------------------------------------------------------------
    newtype HybridLayer = (
        LayerId         : Int,
        LayerType       : String,
        ClassicalDim    : Int,
        QuantumDim      : Int,
        QubitCount      : Int,
        ParameterCount  : Int,
        IsVariational   : Bool,
        AnsatzType      : String,
        OptimizationMethod: String,
        GradientMethod  : String,
        ShotBudget      : Int
    );

    // -------------------------------------------------------------------------
    // Mixture-of-experts routing
    // -------------------------------------------------------------------------
    newtype MoERoutingState = (
        TokenIndex      : Int,
        ExpertCount     : Int,
        TopKExperts     : Int,
        RouterLogits    : Double[],
        SelectedExperts : Int[],
        ExpertWeights   : Double[],
        LoadBalanceLoss : Double,
        AuxiliaryLoss   : Double,
        CapacityFactor  : Double,
        IsQuantumRouted : Bool
    );

    // -------------------------------------------------------------------------
    // RLHF reward signal
    // -------------------------------------------------------------------------
    newtype RLHFRewardSignal = (
        ResponseId      : String,
        RewardScore     : Double,
        KLDivergence    : Double,
        PolicyLoss      : Double,
        ValueLoss       : Double,
        EntropyBonus    : Double,
        ClipFraction    : Double,
        ApproxKL        : Double,
        IsPreferred     : Bool,
        HumanRating     : Int
    );

    // -------------------------------------------------------------------------
    // Alignment safety check
    // -------------------------------------------------------------------------
    newtype AlignmentSafetyResult = (
        RequestId       : String,
        IsSafe          : Bool,
        HarmCategory    : String,
        HarmScore       : Double,
        RefusalRequired : Bool,
        RedactionApplied: Bool,
        PolicyVersion   : String,
        CheckLatencyMs  : Double
    );

    // -------------------------------------------------------------------------
    // Photonic in-transit compute result
    // -------------------------------------------------------------------------
    newtype PhotonicComputeResult = (
        FiberId         : String,
        OperationType   : String,
        InputDataSizeKB : Double,
        OutputDataSizeKB: Double,
        ComputeLatencyUs: Double,
        TransportLatencyUs: Double,
        TotalLatencyUs  : Double,
        PhotonicOpsCount: Int,
        EnergyPicoJoules: Double,
        IsSuccessful    : Bool
    );

    // -------------------------------------------------------------------------
    // Quantum resource estimate
    // -------------------------------------------------------------------------
    newtype ResourceEstimate = (
        AlgorithmName   : String,
        LogicalQubits   : Int,
        PhysicalQubits  : Int,
        TGateCount      : Int,
        TFactoryCount   : Int,
        TFactoryFraction: Double,
        RuntimeSeconds  : Double,
        CodeDistance    : Int,
        ErrorBudget     : Double,
        PhysicalErrorRate: Double,
        LogicalErrorRate: Double,
        BackendTarget   : String
    );
}
