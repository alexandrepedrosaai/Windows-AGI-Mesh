// =============================================================================
// windows_linux_bridge.qs
// Q# Windows ↔ Linux bridge for federated AGI mesh learning
// Implements cross-platform synchronization, gradient federation, and model distribution
// Namespace: SiameseTwinAI.WindowsLinux
// =============================================================================

namespace SiameseTwinAI.WindowsLinux {

    open Microsoft.Quantum.Arrays;
    open Microsoft.Quantum.Convert;
    open Microsoft.Quantum.Intrinsic;
    open Microsoft.Quantum.Math;
    open Microsoft.Quantum.Diagnostics;
    open SiameseTwinAI.WebTransport;
    open SiameseTwinAI.Clustering;

    // =========================================================================
    // Node Information
    // =========================================================================

    newtype NodeInfo = (
        NodeId      : String,
        Platform    : String,
        Address     : String,
        Port        : Int,
        IsActive    : Bool,
        LastSeen    : Int,
        NWorkers    : Int,
        HasGPU      : Bool,
        HasMAIA     : Bool
    );

    function CreateWindowsNode(
        nodeId : String,
        address : String,
        port : Int,
        timestamp : Int
    ) : NodeInfo {
        return NodeInfo(nodeId, "windows", address, port, true, timestamp, 4, true, false);
    }

    function CreateLinuxNode(
        nodeId : String,
        address : String,
        port : Int,
        timestamp : Int
    ) : NodeInfo {
        return NodeInfo(nodeId, "linux", address, port, true, timestamp, 8, true, false);
    }

    function CreateMAIANode(
        nodeId : String,
        address : String,
        port : Int,
        timestamp : Int
    ) : NodeInfo {
        return NodeInfo(nodeId, "maia", address, port, true, timestamp, 128, true, true);
    }

    function IsNodeAlive(node : NodeInfo, currentTimestamp : Int, timeoutMs : Int) : Bool {
        return node::IsActive and (currentTimestamp - node::LastSeen) < timeoutMs;
    }

    function UpdateNodeLastSeen(node : NodeInfo, timestamp : Int) : NodeInfo {
        return NodeInfo(
            node::NodeId, node::Platform, node::Address, node::Port,
            true, timestamp, node::NWorkers, node::HasGPU, node::HasMAIA
        );
    }

    // =========================================================================
    // Bridge Configuration
    // =========================================================================

    newtype BridgeConfig = (
        WindowsNodeId       : String,
        LinuxNodeId         : String,
        MAIANodeId          : String,
        SyncIntervalMs      : Int,
        GradientSyncFreq    : Int,
        WeightSyncFreq      : Int,
        ClusterSyncFreq     : Int,
        CheckpointSyncFreq  : Int,
        GraphSyncFreq       : Int,
        ModelDistribFreq    : Int,
        EnableDiffPrivacy   : Bool,
        DPEpsilon           : Double,
        DPDelta             : Double,
        GradientClipNorm    : Double,
        MaxNodesPerRound    : Int,
        FedAggRounds        : Int,
        MergeThreshold      : Int
    );

    function DefaultBridgeConfig() : BridgeConfig {
        return BridgeConfig(
            "windows_edge_0",
            "linux_firefox_0",
            "maia_300_0",
            1000,
            10, 100, 100, 1000, 500, 200,
            true, 0.1, 1e-5,
            5.0, 10, 5, 16
        );
    }

    // =========================================================================
    // Bridge State
    // =========================================================================

    newtype BridgeState = (
        Config              : BridgeConfig,
        WindowsNode         : NodeInfo,
        LinuxNode           : NodeInfo,
        MAIANode            : NodeInfo,
        WindowsSession      : SessionState,
        LinuxSession        : SessionState,
        SyncRound           : Int,
        TotalGradientsSynced: Int,
        TotalWeightsSynced  : Int,
        TotalClustersSynced : Int,
        TotalCheckpoints    : Int,
        MergedClusters      : ReplayCluster[],
        LastSyncTimestamp   : Int,
        IsConnected         : Bool
    );

    function InitBridgeState(
        config : BridgeConfig,
        timestamp : Int
    ) : BridgeState {
        let windowsNode = CreateWindowsNode(config::WindowsNodeId, "192.168.1.10", 4434, timestamp);
        let linuxNode = CreateLinuxNode(config::LinuxNodeId, "192.168.1.20", 4435, timestamp);
        let maiaNode = CreateMAIANode(config::MAIANodeId, "192.168.1.30", 4433, timestamp);

        let windowsSession = InitSession("bridge_win_001", config::WindowsNodeId, "192.168.1.20", timestamp);
        let linuxSession = InitSession("bridge_lin_001", config::LinuxNodeId, "192.168.1.10", timestamp);

        return BridgeState(
            config,
            windowsNode, linuxNode, maiaNode,
            windowsSession, linuxSession,
            0, 0, 0, 0, 0,
            new ReplayCluster[0],
            timestamp, true
        );
    }

    // =========================================================================
    // Gradient Synchronization
    // =========================================================================

    newtype GradientPacket = (
        SourceNode  : String,
        TargetNode  : String,
        Layer       : String,
        Step        : Int,
        Sparsity    : Double,
        TopKRatio   : Double,
        Hash        : String,
        DPApplied   : Bool,
        Timestamp   : Int
    );

    function CreateGradientPacket(
        source : String,
        target : String,
        layer : String,
        step : Int,
        sparsity : Double,
        topK : Double,
        applyDP : Bool,
        timestamp : Int
    ) : GradientPacket {
        return GradientPacket(
            source, target, layer, step, sparsity, topK,
            $"grad_hash_{step}_{layer}",
            applyDP, timestamp
        );
    }

    operation SyncGradientsWindowsToLinux(
        state : BridgeState,
        layers : String[],
        step : Int,
        timestamp : Int
    ) : BridgeState {
        Message($"[Bridge] Syncing {Length(layers)} gradient layers: Windows → Linux (step={step})");

        mutable newWindowsSession = state::WindowsSession;
        mutable totalSynced = 0;

        for layer in layers {
            let packet = CreateGradientPacket(
                state::Config::WindowsNodeId,
                state::Config::LinuxNodeId,
                layer, step, 0.9, 0.1,
                state::Config::EnableDiffPrivacy,
                timestamp
            );

            // Send on Stream 1 (gradient_updates)
            if CanSendFrame(newWindowsSession, StreamIdGradientUpdates(), MaxFrameSizeGradient()) {
                set newWindowsSession = RecordFrameSent(
                    newWindowsSession, StreamIdGradientUpdates(),
                    MaxFrameSizeGradient(), timestamp
                );
                LogFrameSent(StreamIdGradientUpdates(),
                    newWindowsSession::Streams[1]::SequenceNumber,
                    MaxFrameSizeGradient(),
                    FlagReliable() ||| FlagCompressed()
                );
                set totalSynced += 1;
                Message($"[Bridge] Gradient synced: layer={layer} dp={packet::DPApplied} sparsity={packet::Sparsity}");
            } else {
                Message($"[Bridge] Gradient blocked: layer={layer}");
            }
        }

        return BridgeState(
            state::Config,
            state::WindowsNode, state::LinuxNode, state::MAIANode,
            newWindowsSession, state::LinuxSession,
            state::SyncRound,
            state::TotalGradientsSynced + totalSynced,
            state::TotalWeightsSynced,
            state::TotalClustersSynced,
            state::TotalCheckpoints,
            state::MergedClusters,
            timestamp, state::IsConnected
        );
    }

    // =========================================================================
    // Weight Distribution
    // =========================================================================

    operation DistributeWeightsLinuxToWindows(
        state : BridgeState,
        checkpoint : String,
        layers : String[],
        version : Int,
        timestamp : Int
    ) : BridgeState {
        Message($"[Bridge] Distributing weights: Linux → Windows (checkpoint={checkpoint})");

        mutable newLinuxSession = state::LinuxSession;
        mutable newWindowsSession = state::WindowsSession;
        mutable totalSynced = 0;

        for layer in layers {
            // Send on Stream 2 (weight_deltas)
            if CanSendFrame(newLinuxSession, StreamIdWeightDeltas(), MaxFrameSizeWeight()) {
                set newLinuxSession = RecordFrameSent(
                    newLinuxSession, StreamIdWeightDeltas(),
                    MaxFrameSizeWeight(), timestamp
                );
                set newWindowsSession = RecordFrameReceived(
                    newWindowsSession, StreamIdWeightDeltas(),
                    MaxFrameSizeWeight(), timestamp
                );
                LogFrameSent(StreamIdWeightDeltas(),
                    newLinuxSession::Streams[2]::SequenceNumber,
                    MaxFrameSizeWeight(),
                    FlagReliable() ||| FlagCompressed()
                );
                set totalSynced += 1;
            }

            Message($"[Bridge] Weight distributed: layer={layer} v={version}");
        }

        return BridgeState(
            state::Config,
            state::WindowsNode, state::LinuxNode, state::MAIANode,
            newWindowsSession, newLinuxSession,
            state::SyncRound,
            state::TotalGradientsSynced,
            state::TotalWeightsSynced + totalSynced,
            state::TotalClustersSynced,
            state::TotalCheckpoints,
            state::MergedClusters,
            timestamp, state::IsConnected
        );
    }

    // =========================================================================
    // Cluster Federation
    // =========================================================================

    operation FederateClusters(
        state : BridgeState,
        windowsClusters : ReplayCluster[],
        linuxClusters : ReplayCluster[],
        timestamp : Int
    ) : BridgeState {
        Message($"[Bridge] Federating clusters: windows={Length(windowsClusters)} linux={Length(linuxClusters)}");

        let merged = FederatedClusterMerge(windowsClusters, linuxClusters, timestamp);
        Message($"[Bridge] Merged clusters: {Length(merged)}");

        // Send cluster updates on Stream 6
        mutable newWindowsSession = state::WindowsSession;
        if CanSendFrame(newWindowsSession, StreamIdReplayClusters(), MaxFrameSizeReplay()) {
            set newWindowsSession = RecordFrameSent(
                newWindowsSession, StreamIdReplayClusters(),
                MaxFrameSizeReplay(), timestamp
            );
        }

        return BridgeState(
            state::Config,
            state::WindowsNode, state::LinuxNode, state::MAIANode,
            newWindowsSession, state::LinuxSession,
            state::SyncRound,
            state::TotalGradientsSynced,
            state::TotalWeightsSynced,
            state::TotalClustersSynced + Length(merged),
            state::TotalCheckpoints,
            merged,
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

        // Send blockchain hash on Stream 7
        mutable newLinuxSession = state::LinuxSession;
        if CanSendFrame(newLinuxSession, StreamIdBlockchainHashes(), MaxFrameSizeBlockchain()) {
            set newLinuxSession = RecordFrameSent(
                newLinuxSession, StreamIdBlockchainHashes(),
                MaxFrameSizeBlockchain(), timestamp
            );
            LogFrameSent(StreamIdBlockchainHashes(),
                newLinuxSession::Streams[7]::SequenceNumber,
                MaxFrameSizeBlockchain(), FlagReliable()
            );
        }

        Message($"[Bridge] Checkpoint synced: {checkpointId} block={state::TotalCheckpoints}");

        return BridgeState(
            state::Config,
            state::WindowsNode, state::LinuxNode, state::MAIANode,
            state::WindowsSession, newLinuxSession,
            state::SyncRound,
            state::TotalGradientsSynced,
            state::TotalWeightsSynced,
            state::TotalClustersSynced,
            state::TotalCheckpoints + 1,
            state::MergedClusters,
            timestamp, state::IsConnected
        );
    }

    // =========================================================================
    // Fisher Information Sync
    // =========================================================================

    operation SyncFisherInformation(
        state : BridgeState,
        fisherNorm : Double,
        lambda : Double,
        taskId : Int,
        layer : String,
        timestamp : Int
    ) : BridgeState {
        Message($"[Bridge] Syncing Fisher: Linux → Windows (norm={fisherNorm:.2f} lambda={lambda:.1f})");

        let payload = BuildFisherPayload(fisherNorm, lambda, taskId, layer, timestamp);

        mutable newLinuxSession = state::LinuxSession;
        if CanSendFrame(newLinuxSession, StreamIdEWCFisher(), MaxFrameSizeFisher()) {
            set newLinuxSession = RecordFrameSent(
                newLinuxSession, StreamIdEWCFisher(),
                MaxFrameSizeFisher(), timestamp
            );
            LogFrameSent(StreamIdEWCFisher(),
                newLinuxSession::Streams[5]::SequenceNumber,
                MaxFrameSizeFisher(), FlagReliable()
            );
        }

        return BridgeState(
            state::Config,
            state::WindowsNode, state::LinuxNode, state::MAIANode,
            state::WindowsSession, newLinuxSession,
            state::SyncRound,
            state::TotalGradientsSynced,
            state::TotalWeightsSynced,
            state::TotalClustersSynced,
            state::TotalCheckpoints,
            state::MergedClusters,
            timestamp, state::IsConnected
        );
    }

    // =========================================================================
    // Anchor Synchronization
    // =========================================================================

    operation SyncAnchorAlignment(
        state : BridgeState,
        anchorId : String,
        alignment : Double,
        phase : Double,
        fidelity : Double,
        timestamp : Int
    ) : BridgeState {
        Message($"[Bridge] Syncing anchor: {anchorId} alignment={alignment:.4f}");

        let payload = BuildAnchorPayload(anchorId, alignment, phase, fidelity, 0.001, timestamp);

        mutable newWindowsSession = state::WindowsSession;
        if CanSendFrame(newWindowsSession, StreamIdMajoranaAnchor(), MaxFrameSizeAnchor()) {
            set newWindowsSession = RecordFrameSent(
                newWindowsSession, StreamIdMajoranaAnchor(),
                MaxFrameSizeAnchor(), timestamp
            );
            LogFrameSent(StreamIdMajoranaAnchor(),
                newWindowsSession::Streams[4]::SequenceNumber,
                MaxFrameSizeAnchor(),
                FlagReliable() ||| FlagQuantum()
            );
        }

        return BridgeState(
            state::Config,
            state::WindowsNode, state::LinuxNode, state::MAIANode,
            newWindowsSession, state::LinuxSession,
            state::SyncRound,
            state::TotalGradientsSynced,
            state::TotalWeightsSynced,
            state::TotalClustersSynced,
            state::TotalCheckpoints,
            state::MergedClusters,
            timestamp, state::IsConnected
        );
    }

    // =========================================================================
    // MAIA Training Dispatch
    // =========================================================================

    operation DispatchMAIATraining(
        state : BridgeState,
        task : String,
        checkpoint : String,
        epochs : Int,
        timestamp : Int
    ) : BridgeState {
        Message($"[Bridge] Dispatching MAIA training: task={task} checkpoint={checkpoint}");

        let payload = BuildMAIATrainingPayload(task, checkpoint, epochs, timestamp, state::Config::LinuxNodeId);

        mutable newLinuxSession = state::LinuxSession;
        if CanSendFrame(newLinuxSession, StreamIdMAIATraining(), MaxFrameSizeMAIATrain()) {
            set newLinuxSession = RecordFrameSent(
                newLinuxSession, StreamIdMAIATraining(),
                MaxFrameSizeMAIATrain(), timestamp
            );
            LogFrameSent(StreamIdMAIATraining(),
                newLinuxSession::Streams[9]::SequenceNumber,
                MaxFrameSizeMAIATrain(),
                FlagReliable() ||| FlagCompressed()
            );
        }

        return BridgeState(
            state::Config,
            state::WindowsNode, state::LinuxNode, state::MAIANode,
            state::WindowsSession, newLinuxSession,
            state::SyncRound,
            state::TotalGradientsSynced,
            state::TotalWeightsSynced,
            state::TotalClustersSynced,
            state::TotalCheckpoints,
            state::MergedClusters,
            timestamp, state::IsConnected
        );
    }

    // =========================================================================
    // Full Federated Round
    // =========================================================================

    operation RunFederatedRound(
        state : BridgeState,
        windowsClusters : ReplayCluster[],
        linuxClusters : ReplayCluster[],
        step : Int,
        timestamp : Int
    ) : BridgeState {
        Message($"\n[Bridge] === Federated Round {state::SyncRound} (step={step}) ===");

        let layers = ["attention_4", "transformer_6", "embedding_proj", "output_head"];

        // Step 1: Sync gradients Windows → Linux
        mutable newState = SyncGradientsWindowsToLinux(state, layers, step, timestamp);

        // Step 2: Linux aggregates (simulated)
        Message($"[Bridge] Linux: FedAvg aggregation with DP (ε={state::Config::DPEpsilon})");

        // Step 3: Distribute weights Linux → Windows
        set newState = DistributeWeightsLinuxToWindows(
            newState, $"cp_{step:08d}", layers, state::SyncRound, timestamp + 100
        );

        // Step 4: Sync Fisher information
        set newState = SyncFisherInformation(
            newState, 221.4, 400.0, step / 1000, "attention_4", timestamp + 200
        );

        // Step 5: Federate clusters
        set newState = FederateClusters(newState, windowsClusters, linuxClusters, timestamp + 300);

        // Step 6: Sync anchor
        set newState = SyncAnchorAlignment(newState, "A1", 0.992, 0.05, 0.996, timestamp + 400);

        // Step 7: Checkpoint sync (periodic)
        if step % state::Config::CheckpointSyncFreq == 0 {
            set newState = SyncCheckpoint(newState, $"cp_{step:08d}", step, timestamp + 500);
        }

        // Step 8: Dispatch MAIA training (periodic)
        if step % 1000 == 0 {
            set newState = DispatchMAIATraining(
                newState, "ewc_consolidation", $"cp_{step:08d}", 10, timestamp + 600
            );
        }

        // Update sync round
        set newState = BridgeState(
            newState::Config,
            newState::WindowsNode, newState::LinuxNode, newState::MAIANode,
            newState::WindowsSession, newState::LinuxSession,
            newState::SyncRound + 1,
            newState::TotalGradientsSynced,
            newState::TotalWeightsSynced,
            newState::TotalClustersSynced,
            newState::TotalCheckpoints,
            newState::MergedClusters,
            timestamp + 700, newState::IsConnected
        );

        Message($"[Bridge] Round {state::SyncRound} complete: " +
                $"gradients={newState::TotalGradientsSynced} " +
                $"weights={newState::TotalWeightsSynced} " +
                $"clusters={newState::TotalClustersSynced}");

        return newState;
    }

    // =========================================================================
    // Logging Operations
    // =========================================================================

    operation LogBridgeState(state : BridgeState) : Unit {
        Message("╔══════════════════════════════════════════════════════════════╗");
        Message("║           Windows ↔ Linux Bridge State                      ║");
        Message("╠══════════════════════════════════════════════════════════════╣");
        Message($"║  Windows: {state::Config::WindowsNodeId}                    ║");
        Message($"║  Linux:   {state::Config::LinuxNodeId}                    ║");
        Message($"║  MAIA:    {state::Config::MAIANodeId}                    ║");
        Message($"║  Sync Rounds:      {state::SyncRound}                          ║");
        Message($"║  Gradients Synced: {state::TotalGradientsSynced}                          ║");
        Message($"║  Weights Synced:   {state::TotalWeightsSynced}                          ║");
        Message($"║  Clusters Synced:  {state::TotalClustersSynced}                          ║");
        Message($"║  Checkpoints:      {state::TotalCheckpoints}                          ║");
        Message($"║  Merged Clusters:  {Length(state::MergedClusters)}                          ║");
        Message($"║  DP Enabled:       {state::Config::EnableDiffPrivacy}                          ║");
        Message($"║  DP Epsilon:       {state::Config::DPEpsilon}                          ║");
        Message("╚══════════════════════════════════════════════════════════════╝");
    }

    operation LogNodeStatus(node : NodeInfo, currentTimestamp : Int) : Unit {
        let alive = IsNodeAlive(node, currentTimestamp, 30000);
        let status = if alive { "ALIVE" } else { "DEAD" };
        Message($"[Node:{node::NodeId}] [{status}] platform={node::Platform} " +
                $"addr={node::Address}:{node::Port} " +
                $"workers={node::NWorkers} gpu={node::HasGPU} maia={node::HasMAIA}");
    }

    operation LogFederatedRoundSummary(
        round : Int,
        nGradients : Int,
        nWeights : Int,
        nClusters : Int,
        timestamp : Int
    ) : Unit {
        Message($"[Federated Round {round}] t={timestamp} " +
                $"gradients={nGradients} weights={nWeights} clusters={nClusters}");
    }
}
