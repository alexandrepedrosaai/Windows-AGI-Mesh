// =============================================================================
// run_windows_linux_mesh.qs
// Windows ↔ Linux mesh bridge entry point
// Namespace: SiameseTwinAI.Entrypoints
// =============================================================================

namespace SiameseTwinAI.Entrypoints {

    open Microsoft.Quantum.Arrays;
    open Microsoft.Quantum.Convert;
    open Microsoft.Quantum.Intrinsic;
    open Microsoft.Quantum.Math;
    open Microsoft.Quantum.Diagnostics;
    open SiameseTwinAI.WebTransport;
    open SiameseTwinAI.Clustering;

    // =========================================================================
    // Windows-Linux Bridge Configuration
    // =========================================================================

    newtype WLBridgeConfig = (
        WindowsNodeId       : String,
        LinuxNodeId         : String,
        WindowsAddress      : String,
        LinuxAddress        : String,
        BridgePort          : Int,
        SyncIntervalMs      : Int,
        MaxSyncRetries      : Int,
        CheckpointSyncFreq  : Int,
        GradientSyncFreq    : Int,
        ClusterSyncFreq     : Int,
        GraphSyncFreq       : Int,
        ModelDistribFreq    : Int,
        EnableDiffPrivacy   : Bool,
        DPEpsilon           : Double,
        DPDelta             : Double,
        GradientClipNorm    : Double,
        MaxNodesPerFedRound : Int,
        FedAggregationRounds: Int
    );

    function DefaultWLBridgeConfig() : WLBridgeConfig {
        return WLBridgeConfig(
            "windows_edge_0",
            "linux_firefox_0",
            "192.168.1.10",
            "192.168.1.20",
            4433,
            1000,
            3,
            1000,
            10,
            100,
            500,
            200,
            true,
            0.1,
            1e-5,
            5.0,
            10,
            5
        );
    }

    // =========================================================================
    // Bridge State
    // =========================================================================

    newtype BridgeState = (
        Config              : WLBridgeConfig,
        WindowsSession      : SessionState,
        LinuxSession        : SessionState,
        WindowsClusters     : ReplayCluster[],
        LinuxClusters       : ReplayCluster[],
        MergedClusters      : ReplayCluster[],
        SyncRound           : Int,
        TotalGradientsSynced: Int,
        TotalWeightsSynced  : Int,
        TotalClustersSynced : Int,
        TotalCheckpoints    : Int,
        LastSyncTimestamp   : Int,
        IsConnected         : Bool
    );

    function InitBridgeState(config : WLBridgeConfig, timestamp : Int) : BridgeState {
        let windowsSession = InitSession(
            "bridge_windows_001",
            config::WindowsNodeId,
            config::LinuxAddress,
            timestamp
        );
        let linuxSession = InitSession(
            "bridge_linux_001",
            config::LinuxNodeId,
            config::WindowsAddress,
            timestamp
        );
        return BridgeState(
            config,
            windowsSession, linuxSession,
            new ReplayCluster[0],
            new ReplayCluster[0],
            new ReplayCluster[0],
            0, 0, 0, 0, 0,
            timestamp, true
        );
    }

    // =========================================================================
    // Gradient Synchronization
    // =========================================================================

    newtype GradientSyncPacket = (
        SourceNode  : String,
        Layer       : String,
        Step        : Int,
        Sparsity    : Double,
        TopKRatio   : Double,
        GradientHash: String,
        Timestamp   : Int,
        DPNoiseApplied : Bool
    );

    function CreateGradientSyncPacket(
        sourceNode : String,
        layer : String,
        step : Int,
        sparsity : Double,
        topKRatio : Double,
        timestamp : Int,
        applyDP : Bool
    ) : GradientSyncPacket {
        return GradientSyncPacket(
            sourceNode, layer, step, sparsity, topKRatio,
            $"grad_hash_{step}_{layer}",
            timestamp, applyDP
        );
    }

    operation SyncGradients(
        state : BridgeState,
        layers : String[],
        step : Int,
        timestamp : Int
    ) : BridgeState {
        Message($"[Bridge] Syncing gradients: {Length(layers)} layers at step {step}");

        mutable totalSynced = 0;
        for layer in layers {
            let packet = CreateGradientSyncPacket(
                state::Config::WindowsNodeId,
                layer, step, 0.9, 0.1, timestamp,
                state::Config::EnableDiffPrivacy
            );

            // Send gradient on Stream 1 (Windows → Linux)
            let newWindowsSession = RecordFrameSent(
                state::WindowsSession,
                StreamIdGradientUpdates(),
                MaxFrameSizeGradient(),
                timestamp
            );

            // Receive on Linux side
            let newLinuxSession = RecordFrameReceived(
                state::LinuxSession,
                StreamIdGradientUpdates(),
                MaxFrameSizeGradient(),
                timestamp
            );

            Message($"[Bridge] Gradient synced: layer={layer} sparsity={packet::Sparsity} " +
                    $"dp={packet::DPNoiseApplied}");
            set totalSynced += 1;
        }

        return BridgeState(
            state::Config,
            state::WindowsSession, state::LinuxSession,
            state::WindowsClusters, state::LinuxClusters, state::MergedClusters,
            state::SyncRound,
            state::TotalGradientsSynced + totalSynced,
            state::TotalWeightsSynced,
            state::TotalClustersSynced,
            state::TotalCheckpoints,
            timestamp, state::IsConnected
        );
    }

    // =========================================================================
    // Weight Distribution
    // =========================================================================

    newtype WeightDistPacket = (
        SourceNode      : String,
        Checkpoint      : String,
        Layer           : String,
        Version         : Int,
        AggRound        : Int,
        NodeCount       : Int,
        IntegrityHash   : String,
        Timestamp       : Int
    );

    function CreateWeightDistPacket(
        sourceNode : String,
        checkpoint : String,
        layer : String,
        version : Int,
        aggRound : Int,
        nodeCount : Int,
        timestamp : Int
    ) : WeightDistPacket {
        return WeightDistPacket(
            sourceNode, checkpoint, layer, version, aggRound, nodeCount,
            $"integrity_{checkpoint}_{layer}",
            timestamp
        );
    }

    operation DistributeWeights(
        state : BridgeState,
        checkpoint : String,
        layers : String[],
        version : Int,
        timestamp : Int
    ) : BridgeState {
        Message($"[Bridge] Distributing weights: checkpoint={checkpoint} layers={Length(layers)}");

        mutable totalSynced = 0;
        for layer in layers {
            let packet = CreateWeightDistPacket(
                state::Config::LinuxNodeId,
                checkpoint, layer, version,
                state::SyncRound, 2, timestamp
            );

            // Send weight delta on Stream 2 (Linux → Windows)
            let newLinuxSession = RecordFrameSent(
                state::LinuxSession,
                StreamIdWeightDeltas(),
                MaxFrameSizeWeight(),
                timestamp
            );

            let newWindowsSession = RecordFrameReceived(
                state::WindowsSession,
                StreamIdWeightDeltas(),
                MaxFrameSizeWeight(),
                timestamp
            );

            Message($"[Bridge] Weight distributed: layer={layer} v={version} " +
                    $"integrity={packet::IntegrityHash}");
            set totalSynced += 1;
        }

        return BridgeState(
            state::Config,
            state::WindowsSession, state::LinuxSession,
            state::WindowsClusters, state::LinuxClusters, state::MergedClusters,
            state::SyncRound,
            state::TotalGradientsSynced,
            state::TotalWeightsSynced + totalSynced,
            state::TotalClustersSynced,
            state::TotalCheckpoints,
            timestamp, state::IsConnected
        );
    }

    // =========================================================================
    // Cluster Federation
    // =========================================================================

    operation FederateClusters(
        state : BridgeState,
        timestamp : Int
    ) : BridgeState {
        Message($"[Bridge] Federating clusters: " +
                $"windows={Length(state::WindowsClusters)} " +
                $"linux={Length(state::LinuxClusters)}");

        // Merge clusters from both nodes
        let merged = FederatedClusterMerge(
            state::WindowsClusters,
            state::LinuxClusters,
            timestamp
        );

        Message($"[Bridge] Merged clusters: {Length(merged)}");

        // Send cluster updates on Stream 6
        let newWindowsSession = RecordFrameSent(
            state::WindowsSession,
            StreamIdReplayClusters(),
            MaxFrameSizeReplay(),
            timestamp
        );

        return BridgeState(
            state::Config,
            newWindowsSession, state::LinuxSession,
            state::WindowsClusters, state::LinuxClusters, merged,
            state::SyncRound,
            state::TotalGradientsSynced,
            state::TotalWeightsSynced,
            state::TotalClustersSynced + Length(merged),
            state::TotalCheckpoints,
            timestamp, state::IsConnected
        );
    }

    // =========================================================================
    // Checkpoint Synchronization
    // =========================================================================

    operation SyncCheckpoint(
        state : BridgeState,
        checkpointId : String,
        step : Int,
        timestamp : Int
    ) : BridgeState {
        Message($"[Bridge] Syncing checkpoint: {checkpointId} (step={step})");

        // Compute checkpoint hash for blockchain
        let blockPayload = BuildBlockchainPayload(
            state::TotalCheckpoints,
            $"sha256_{checkpointId}",
            $"prev_{state::TotalCheckpoints - 1}",
            $"merkle_{checkpointId}",
            timestamp,
            state::Config::LinuxNodeId
        );

        // Send blockchain hash on Stream 7
        let newLinuxSession = RecordFrameSent(
            state::LinuxSession,
            StreamIdBlockchainHashes(),
            MaxFrameSizeBlockchain(),
            timestamp
        );

        Message($"[Bridge] Checkpoint synced: {checkpointId} block={state::TotalCheckpoints}");

        return BridgeState(
            state::Config,
            state::WindowsSession, newLinuxSession,
            state::WindowsClusters, state::LinuxClusters, state::MergedClusters,
            state::SyncRound,
            state::TotalGradientsSynced,
            state::TotalWeightsSynced,
            state::TotalClustersSynced,
            state::TotalCheckpoints + 1,
            timestamp, state::IsConnected
        );
    }

    // =========================================================================
    // Federated Aggregation Round
    // =========================================================================

    operation RunFederatedAggregationRound(
        state : BridgeState,
        step : Int,
        timestamp : Int
    ) : BridgeState {
        Message($"\n[Bridge] === Federated Aggregation Round {state::SyncRound} ===");

        let layers = ["attention_4", "transformer_6", "embedding_proj", "output_head"];

        // Step 1: Sync gradients Windows → Linux
        mutable newState = SyncGradients(state, layers, step, timestamp);

        // Step 2: Aggregate on Linux (simulated)
        Message($"[Bridge] Linux: aggregating {Length(layers)} gradient layers...");
        Message($"[Bridge] Linux: applying FedAvg with DP (ε={state::Config::DPEpsilon})");

        // Step 3: Distribute aggregated weights Linux → Windows
        set newState = DistributeWeights(
            newState,
            $"cp_{step:08d}",
            layers,
            state::SyncRound,
            timestamp + 100
        );

        // Step 4: Federate clusters
        set newState = FederateClusters(newState, timestamp + 200);

        // Step 5: Sync checkpoint
        if step % state::Config::CheckpointSyncFreq == 0 {
            set newState = SyncCheckpoint(newState, $"cp_{step:08d}", step, timestamp + 300);
        }

        // Update sync round
        set newState = BridgeState(
            newState::Config,
            newState::WindowsSession, newState::LinuxSession,
            newState::WindowsClusters, newState::LinuxClusters, newState::MergedClusters,
            newState::SyncRound + 1,
            newState::TotalGradientsSynced,
            newState::TotalWeightsSynced,
            newState::TotalClustersSynced,
            newState::TotalCheckpoints,
            timestamp + 400, newState::IsConnected
        );

        Message($"[Bridge] Round {state::SyncRound} complete: " +
                $"gradients={newState::TotalGradientsSynced} " +
                $"weights={newState::TotalWeightsSynced} " +
                $"clusters={newState::TotalClustersSynced}");

        return newState;
    }

    // =========================================================================
    // Bridge Statistics
    // =========================================================================

    operation LogBridgeStats(state : BridgeState) : Unit {
        Message("\n╔══════════════════════════════════════════════════════════════╗");
        Message("║           Windows ↔ Linux Bridge Statistics                  ║");
        Message("╠══════════════════════════════════════════════════════════════╣");
        Message($"║  Windows Node: {state::Config::WindowsNodeId}                    ║");
        Message($"║  Linux Node:   {state::Config::LinuxNodeId}                    ║");
        Message($"║  Sync Rounds:  {state::SyncRound}                                    ║");
        Message($"║  Gradients Synced: {state::TotalGradientsSynced}                          ║");
        Message($"║  Weights Synced:   {state::TotalWeightsSynced}                          ║");
        Message($"║  Clusters Synced:  {state::TotalClustersSynced}                          ║");
        Message($"║  Checkpoints:      {state::TotalCheckpoints}                          ║");
        Message($"║  Merged Clusters:  {Length(state::MergedClusters)}                          ║");
        Message($"║  DP Enabled:       {state::Config::EnableDiffPrivacy}                          ║");
        Message($"║  DP Epsilon:       {state::Config::DPEpsilon}                          ║");
        Message("╚══════════════════════════════════════════════════════════════╝");

        // Session stats
        Message("\n[Windows Session]");
        LogSessionState(state::WindowsSession);
        Message("\n[Linux Session]");
        LogSessionState(state::LinuxSession);
    }

    // =========================================================================
    // Windows-Linux Mesh Entry Point
    // =========================================================================

    @EntryPoint()
    operation RunWindowsLinuxMesh() : Unit {
        Message("╔══════════════════════════════════════════════════════════════╗");
        Message("║         Windows-AGI-Mesh Windows↔Linux Bridge v1.0.0        ║");
        Message("║  Federated Learning Bridge via WT-MAIA/1.0                  ║");
        Message("╚══════════════════════════════════════════════════════════════╝");

        let config = DefaultWLBridgeConfig();
        mutable state = InitBridgeState(config, 0);

        Message($"\n[Bridge] Initializing Windows ↔ Linux bridge...");
        Message($"[Bridge] Windows: {config::WindowsNodeId} @ {config::WindowsAddress}");
        Message($"[Bridge] Linux:   {config::LinuxNodeId} @ {config::LinuxAddress}");
        Message($"[Bridge] Port:    {config::BridgePort}");
        Message($"[Bridge] DP:      ε={config::DPEpsilon} δ={config::DPDelta}");

        // Initialize some clusters for federation demo
        let clusterConfig = DefaultClusterManagerConfig();
        let clusterState = InitClusterManager(clusterConfig);

        // Simulate some Windows clusters
        mutable windowsClusters = new ReplayCluster[0];
        for i in 0 .. 4 {
            let centroid = [i * 1000, i * 2000, i * 3000, i * 4000,
                            i * 5000, i * 6000, i * 7000, i * 8000];
            set windowsClusters += [CreateCluster(i, centroid, 24, i * 100)];
        }

        // Simulate some Linux clusters
        mutable linuxClusters = new ReplayCluster[0];
        for i in 0 .. 3 {
            let centroid = [(i + 5) * 1000, (i + 5) * 2000, (i + 5) * 3000, (i + 5) * 4000,
                            (i + 5) * 5000, (i + 5) * 6000, (i + 5) * 7000, (i + 5) * 8000];
            set linuxClusters += [CreateCluster(i + 10, centroid, 24, i * 150)];
        }

        set state = BridgeState(
            state::Config,
            state::WindowsSession, state::LinuxSession,
            windowsClusters, linuxClusters, new ReplayCluster[0],
            state::SyncRound,
            state::TotalGradientsSynced, state::TotalWeightsSynced,
            state::TotalClustersSynced, state::TotalCheckpoints,
            state::LastSyncTimestamp, state::IsConnected
        );

        // Run federated aggregation rounds
        let nRounds = 5;
        for round in 0 .. nRounds - 1 {
            let step = round * config::GradientSyncFreq;
            let timestamp = round * config::SyncIntervalMs;
            set state = RunFederatedAggregationRound(state, step, timestamp);
        }

        // Final statistics
        LogBridgeStats(state);

        Message("\n[Bridge] Windows ↔ Linux mesh bridge operational.");
        Message("[Bridge] Federated learning pipeline synchronized.");
        Message("[Bridge] Edge ⊗ Firefox ⊗ Windows ⊗ Linux mesh active.");
    }
}