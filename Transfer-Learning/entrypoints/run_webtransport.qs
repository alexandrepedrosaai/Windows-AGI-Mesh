// =============================================================================
// run_webtransport.qs
// WebTransport pipeline entry point — WT-MAIA/1.0 protocol demonstration
// Namespace: SiameseTwinAI.Entrypoints
// =============================================================================

namespace SiameseTwinAI.Entrypoints {

    open Microsoft.Quantum.Arrays;
    open Microsoft.Quantum.Convert;
    open Microsoft.Quantum.Intrinsic;
    open Microsoft.Quantum.Math;
    open Microsoft.Quantum.Diagnostics;
    open SiameseTwinAI.WebTransport;

    // =========================================================================
    // WebTransport Demo Configuration
    // =========================================================================

    newtype WTDemoConfig = (
        WindowsNodeId   : String,
        LinuxNodeId     : String,
        MAIANodeId      : String,
        ServerUrl       : String,
        NSteps          : Int,
        SensorFreqHz    : Double,
        GradientFreq    : Int,
        WeightFreq      : Int,
        FisherFreq      : Int,
        ReplayFreq      : Int,
        AnchorFreq      : Int,
        BlockchainFreq  : Int,
        MAIAInferFreq   : Int,
        MAIATrainFreq   : Int,
        TelemetryFreq   : Int,
        LinkBandwidthMbps : Double,
        BaseRTTMs       : Double,
        PacketLossRate  : Double
    );

    function DefaultWTDemoConfig() : WTDemoConfig {
        return WTDemoConfig(
            "windows_node_0",
            "linux_node_0",
            "maia_300_0",
            "https://mesh.agi.local:4433",
            100,
            1000.0,
            10,
            100,
            50,
            10,
            20,
            200,
            5,
            100,
            50,
            1000.0,
            2.0,
            0.001
        );
    }

    // =========================================================================
    // Multi-Session State
    // =========================================================================

    newtype MeshNetworkState = (
        WindowsSession  : SessionState,
        LinuxSession    : SessionState,
        MAIASession     : SessionState,
        WindowsCongestion : CongestionState,
        LinuxCongestion : CongestionState,
        MAIACongestion  : CongestionState,
        Registry        : SessionRegistry,
        Step            : Int,
        TotalFramesSent : Int,
        TotalBytesTransferred : Int
    );

    function InitMeshNetwork(config : WTDemoConfig, timestamp : Int) : MeshNetworkState {
        let windowsSession = InitSession(
            "wt_session_windows_001",
            config::WindowsNodeId,
            config::ServerUrl,
            timestamp
        );
        let linuxSession = InitSession(
            "wt_session_linux_001",
            config::LinuxNodeId,
            config::ServerUrl,
            timestamp
        );
        let maiaSession = InitSession(
            "wt_session_maia_001",
            config::MAIANodeId,
            config::ServerUrl,
            timestamp
        );

        let registry = InitSessionRegistry(100, timestamp);
        let registry1 = AddSession(registry, windowsSession, timestamp);
        let registry2 = AddSession(registry1, linuxSession, timestamp);
        let registry3 = AddSession(registry2, maiaSession, timestamp);

        return MeshNetworkState(
            windowsSession, linuxSession, maiaSession,
            InitCongestionState(AlgorithmCUBIC()),
            InitCongestionState(AlgorithmBBR()),
            InitCongestionState(AlgorithmCUBIC()),
            registry3,
            0, 0, 0
        );
    }

    // =========================================================================
    // Stream Transmission Simulation
    // =========================================================================

    operation TransmitSensorData(
        mesh : MeshNetworkState,
        sensorId : Int,
        coherence : Double,
        phase : Double,
        adc : Int,
        timestamp : Int
    ) : MeshNetworkState {
        let payload = BuildSensorDataPayload(
            sensorId, coherence, phase, adc, timestamp,
            mesh::WindowsSession::NodeId, mesh::Step
        );
        let frameSize = Length(payload) + 28;  // payload + header

        if CanSendFrame(mesh::WindowsSession, StreamIdSensorData(), frameSize) {
            let newWindowsSession = RecordFrameSent(
                mesh::WindowsSession, StreamIdSensorData(), frameSize, timestamp
            );
            let newCongestion = OnSend(mesh::WindowsCongestion, frameSize);
            LogFrameSent(StreamIdSensorData(), newWindowsSession::Streams[0]::SequenceNumber, frameSize, FlagReliable());

            return MeshNetworkState(
                newWindowsSession, mesh::LinuxSession, mesh::MAIASession,
                newCongestion, mesh::LinuxCongestion, mesh::MAIACongestion,
                mesh::Registry,
                mesh::Step, mesh::TotalFramesSent + 1,
                mesh::TotalBytesTransferred + frameSize
            );
        }
        return mesh;
    }

    operation TransmitGradientUpdate(
        mesh : MeshNetworkState,
        model : String,
        layer : String,
        step : Int,
        timestamp : Int
    ) : MeshNetworkState {
        let payload = BuildGradientPayload(
            model, layer, "ABCD1234", 0.10, step,
            mesh::WindowsSession::NodeId, 0.9
        );
        let frameSize = MaxFrameSizeGradient();

        if CanSendFrame(mesh::WindowsSession, StreamIdGradientUpdates(), frameSize) {
            let newSession = RecordFrameSent(
                mesh::WindowsSession, StreamIdGradientUpdates(), frameSize, timestamp
            );
            LogFrameSent(StreamIdGradientUpdates(), newSession::Streams[1]::SequenceNumber, frameSize, FlagReliable() ||| FlagCompressed());

            return MeshNetworkState(
                newSession, mesh::LinuxSession, mesh::MAIASession,
                mesh::WindowsCongestion, mesh::LinuxCongestion, mesh::MAIACongestion,
                mesh::Registry,
                mesh::Step, mesh::TotalFramesSent + 1,
                mesh::TotalBytesTransferred + frameSize
            );
        }
        return mesh;
    }

    operation TransmitWeightDelta(
        mesh : MeshNetworkState,
        checkpoint : String,
        layer : String,
        timestamp : Int
    ) : MeshNetworkState {
        let frameSize = MaxFrameSizeWeight();

        if CanSendFrame(mesh::LinuxSession, StreamIdWeightDeltas(), frameSize) {
            let newLinuxSession = RecordFrameSent(
                mesh::LinuxSession, StreamIdWeightDeltas(), frameSize, timestamp
            );
            let newWindowsSession = RecordFrameReceived(
                mesh::WindowsSession, StreamIdWeightDeltas(), frameSize, timestamp
            );
            LogFrameSent(StreamIdWeightDeltas(), newLinuxSession::Streams[2]::SequenceNumber, frameSize, FlagReliable() ||| FlagCompressed());

            return MeshNetworkState(
                newWindowsSession, newLinuxSession, mesh::MAIASession,
                mesh::WindowsCongestion, mesh::LinuxCongestion, mesh::MAIACongestion,
                mesh::Registry,
                mesh::Step, mesh::TotalFramesSent + 1,
                mesh::TotalBytesTransferred + frameSize
            );
        }
        return mesh;
    }

    operation TransmitFisherUpdate(
        mesh : MeshNetworkState,
        fisherNorm : Double,
        lambda : Double,
        taskId : Int,
        layer : String,
        timestamp : Int
    ) : MeshNetworkState {
        let payload = BuildFisherPayload(fisherNorm, lambda, taskId, layer, timestamp);
        let frameSize = MaxFrameSizeFisher();

        if CanSendFrame(mesh::LinuxSession, StreamIdEWCFisher(), frameSize) {
            let newLinuxSession = RecordFrameSent(
                mesh::LinuxSession, StreamIdEWCFisher(), frameSize, timestamp
            );
            LogFrameSent(StreamIdEWCFisher(), newLinuxSession::Streams[5]::SequenceNumber, frameSize, FlagReliable());

            return MeshNetworkState(
                mesh::WindowsSession, newLinuxSession, mesh::MAIASession,
                mesh::WindowsCongestion, mesh::LinuxCongestion, mesh::MAIACongestion,
                mesh::Registry,
                mesh::Step, mesh::TotalFramesSent + 1,
                mesh::TotalBytesTransferred + frameSize
            );
        }
        return mesh;
    }

    operation TransmitReplayCluster(
        mesh : MeshNetworkState,
        clusterId : Int,
        samples : Int,
        meanHamming : Double,
        threshold : Int,
        noveltyScore : Double,
        timestamp : Int
    ) : MeshNetworkState {
        let payload = BuildReplayClusterPayload(
            clusterId, samples, meanHamming, threshold, noveltyScore, timestamp
        );
        let frameSize = MaxFrameSizeReplay();

        if CanSendFrame(mesh::WindowsSession, StreamIdReplayClusters(), frameSize) {
            let newWindowsSession = RecordFrameSent(
                mesh::WindowsSession, StreamIdReplayClusters(), frameSize, timestamp
            );
            LogFrameSent(StreamIdReplayClusters(), newWindowsSession::Streams[6]::SequenceNumber, frameSize, FlagReliable());

            return MeshNetworkState(
                newWindowsSession, mesh::LinuxSession, mesh::MAIASession,
                mesh::WindowsCongestion, mesh::LinuxCongestion, mesh::MAIACongestion,
                mesh::Registry,
                mesh::Step, mesh::TotalFramesSent + 1,
                mesh::TotalBytesTransferred + frameSize
            );
        }
        return mesh;
    }

    operation TransmitAnchorUpdate(
        mesh : MeshNetworkState,
        anchorId : String,
        alignment : Double,
        phase : Double,
        fidelity : Double,
        timestamp : Int
    ) : MeshNetworkState {
        let payload = BuildAnchorPayload(anchorId, alignment, phase, fidelity, MAIAErrorRate(), timestamp);
        let frameSize = MaxFrameSizeAnchor();

        if CanSendFrame(mesh::WindowsSession, StreamIdMajoranaAnchor(), frameSize) {
            let newWindowsSession = RecordFrameSent(
                mesh::WindowsSession, StreamIdMajoranaAnchor(), frameSize, timestamp
            );
            LogFrameSent(StreamIdMajoranaAnchor(), newWindowsSession::Streams[4]::SequenceNumber, frameSize, FlagReliable() ||| FlagQuantum());

            return MeshNetworkState(
                newWindowsSession, mesh::LinuxSession, mesh::MAIASession,
                mesh::WindowsCongestion, mesh::LinuxCongestion, mesh::MAIACongestion,
                mesh::Registry,
                mesh::Step, mesh::TotalFramesSent + 1,
                mesh::TotalBytesTransferred + frameSize
            );
        }
        return mesh;
    }

    operation TransmitMAIAInference(
        mesh : MeshNetworkState,
        requestId : Int,
        timestamp : Int
    ) : MeshNetworkState {
        let payload = BuildMAIAInferencePayload(requestId, "1.0", 1, timestamp, 1);
        let frameSize = MaxFrameSizeMAIAInfer();

        if CanSendFrame(mesh::WindowsSession, StreamIdMAIAInference(), frameSize) {
            let newWindowsSession = RecordFrameSent(
                mesh::WindowsSession, StreamIdMAIAInference(), frameSize, timestamp
            );
            let newMAIASession = RecordFrameReceived(
                mesh::MAIASession, StreamIdMAIAInference(), frameSize, timestamp
            );
            LogFrameSent(StreamIdMAIAInference(), newWindowsSession::Streams[8]::SequenceNumber, frameSize, FlagReliable() ||| FlagPriorityHigh());

            return MeshNetworkState(
                newWindowsSession, mesh::LinuxSession, newMAIASession,
                mesh::WindowsCongestion, mesh::LinuxCongestion, mesh::MAIACongestion,
                mesh::Registry,
                mesh::Step, mesh::TotalFramesSent + 1,
                mesh::TotalBytesTransferred + frameSize
            );
        }
        return mesh;
    }

    operation TransmitMAIATraining(
        mesh : MeshNetworkState,
        task : String,
        checkpoint : String,
        timestamp : Int
    ) : MeshNetworkState {
        let payload = BuildMAIATrainingPayload(task, checkpoint, 10, timestamp, mesh::LinuxSession::NodeId);
        let frameSize = MaxFrameSizeMAIATrain();

        if CanSendFrame(mesh::LinuxSession, StreamIdMAIATraining(), frameSize) {
            let newLinuxSession = RecordFrameSent(
                mesh::LinuxSession, StreamIdMAIATraining(), frameSize, timestamp
            );
            let newMAIASession = RecordFrameReceived(
                mesh::MAIASession, StreamIdMAIATraining(), frameSize, timestamp
            );
            LogFrameSent(StreamIdMAIATraining(), newLinuxSession::Streams[9]::SequenceNumber, frameSize, FlagReliable() ||| FlagCompressed());

            return MeshNetworkState(
                mesh::WindowsSession, newLinuxSession, newMAIASession,
                mesh::WindowsCongestion, mesh::LinuxCongestion, mesh::MAIACongestion,
                mesh::Registry,
                mesh::Step, mesh::TotalFramesSent + 1,
                mesh::TotalBytesTransferred + frameSize
            );
        }
        return mesh;
    }

    operation TransmitBlockchainHash(
        mesh : MeshNetworkState,
        blockNum : Int,
        timestamp : Int
    ) : MeshNetworkState {
        let payload = BuildBlockchainPayload(
            blockNum, "sha256_hash_placeholder",
            "prev_hash_placeholder", "merkle_root_placeholder",
            timestamp, mesh::LinuxSession::NodeId
        );
        let frameSize = MaxFrameSizeBlockchain();

        if CanSendFrame(mesh::LinuxSession, StreamIdBlockchainHashes(), frameSize) {
            let newLinuxSession = RecordFrameSent(
                mesh::LinuxSession, StreamIdBlockchainHashes(), frameSize, timestamp
            );
            LogFrameSent(StreamIdBlockchainHashes(), newLinuxSession::Streams[7]::SequenceNumber, frameSize, FlagReliable());

            return MeshNetworkState(
                mesh::WindowsSession, newLinuxSession, mesh::MAIASession,
                mesh::WindowsCongestion, mesh::LinuxCongestion, mesh::MAIACongestion,
                mesh::Registry,
                mesh::Step, mesh::TotalFramesSent + 1,
                mesh::TotalBytesTransferred + frameSize
            );
        }
        return mesh;
    }

    // =========================================================================
    // Congestion Update
    // =========================================================================

    operation UpdateCongestionStates(
        mesh : MeshNetworkState,
        rttMs : Double,
        timestamp : Int
    ) : MeshNetworkState {
        let ackedBytes = 65536;
        let deliveryRate = 100.0;  // Mbps

        let newWindowsCongestion = OnAck(
            UpdateRTT(mesh::WindowsCongestion, rttMs),
            ackedBytes, deliveryRate, timestamp
        );
        let newLinuxCongestion = OnAck(
            UpdateRTT(mesh::LinuxCongestion, rttMs * 0.9),
            ackedBytes, deliveryRate, timestamp
        );
        let newMAIACongestion = OnAck(
            UpdateRTT(mesh::MAIACongestion, rttMs * 0.5),
            ackedBytes, deliveryRate * 2.0, timestamp
        );

        return MeshNetworkState(
            mesh::WindowsSession, mesh::LinuxSession, mesh::MAIASession,
            newWindowsCongestion, newLinuxCongestion, newMAIACongestion,
            mesh::Registry,
            mesh::Step, mesh::TotalFramesSent, mesh::TotalBytesTransferred
        );
    }

    // =========================================================================
    // Network Statistics
    // =========================================================================

    operation LogNetworkStats(mesh : MeshNetworkState, config : WTDemoConfig) : Unit {
let durationMs = mesh::Step * 1000;

        Message("\n╔══════════════════════════════════════════════════════════════╗");
        Message("║              WT-MAIA/1.0 Network Statistics                  ║");
        Message("╠══════════════════════════════════════════════════════════════╣");
        Message($"║  Steps: {mesh::Step}                                              ║");
        Message($"║  Total Frames Sent: {mesh::TotalFramesSent}                              ║");
        Message($"║  Total Bytes: {mesh::TotalBytesTransferred}                              ║");
        Message($"║  Throughput: {throughputMbps:.2f} Mbps                              ║");
        Message($"║  Windows CWND: {mesh::WindowsCongestion::CWND:.1f}                              ║");
        Message($"║  Linux CWND: {mesh::LinuxCongestion::CWND:.1f}                              ║");
        Message($"║  MAIA CWND: {mesh::MAIACongestion::CWND:.1f}                              ║");
        Message($"║  Windows RTT: {mesh::WindowsCongestion::SmoothedRTT:.2f}ms                              ║");
        Message($"║  Linux RTT: {mesh::LinuxCongestion::SmoothedRTT:.2f}ms                              ║");
        Message("╚══════════════════════════════════════════════════════════════╝");

        // Per-stream stats
        Message("\n[Stream Statistics]");
        for i in 0 .. 9 {
            let (bytesSent, bytesRecv, framesSent, framesRecv) = GetStreamStats(mesh::WindowsSession, i);
            if framesSent > 0 or framesRecv > 0 {
                Message($"  Stream {i}: sent={framesSent}f/{bytesSent}B recv={framesRecv}f/{bytesRecv}B");
            }
        }
    }

    // =========================================================================
    // WebTransport Entry Point
    // =========================================================================

    @EntryPoint()
    operation RunWebTransport() : Unit {
        Message("╔══════════════════════════════════════════════════════════════╗");
        Message("║         Windows-AGI-Mesh WebTransport v1.0.0                ║");
        Message("║  WT-MAIA/1.0 Protocol — HTTP/3 + QUIC + TLS 1.3            ║");
        Message("╚══════════════════════════════════════════════════════════════╝");

        let config = DefaultWTDemoConfig();
        mutable mesh = InitMeshNetwork(config, 0);

        Message($"\n[WT-MAIA/1.0] Initializing mesh network...");
        Message($"[WT-MAIA/1.0] Windows: {config::WindowsNodeId}");
        Message($"[WT-MAIA/1.0] Linux:   {config::LinuxNodeId}");
        Message($"[WT-MAIA/1.0] MAIA:    {config::MAIANodeId}");
        Message($"[WT-MAIA/1.0] Server:  {config::ServerUrl}");

        // Open sessions
        let windowsSession = OpenSession("wt_windows_001", config::WindowsNodeId, config::ServerUrl, 0);
        let linuxSession = OpenSession("wt_linux_001", config::LinuxNodeId, config::ServerUrl, 0);
        let maiaSession = OpenSession("wt_maia_001", config::MAIANodeId, config::ServerUrl, 0);

        Message("\n[WT-MAIA/1.0] All sessions established. Starting data exchange...\n");

        // Simulate N steps of the pipeline
        let nSteps = MinI(config::NSteps, 20);

        for step in 0 .. nSteps - 1 {
            let timestamp = step * 1000;

            // Stream 0: Sensor data (every step)
            set mesh = TransmitSensorData(
                mesh, step % 5000, 0.95, IntAsDouble(step) * 0.1,
                32768 + step * 10, timestamp
            );

            // Stream 1: Gradient updates (every 10 steps)
            if step % config::GradientFreq == 0 {
                set mesh = TransmitGradientUpdate(
                    mesh, "siamese_cnn", "attention_4", step, timestamp
                );
            }

            // Stream 2: Weight deltas (every 100 steps)
            if step % config::WeightFreq == 0 {
                set mesh = TransmitWeightDelta(mesh, $"cp_{step}", "transformer_6", timestamp);
            }

            // Stream 4: Majorana anchor (every 20 steps)
            if step % config::AnchorFreq == 0 {
                set mesh = TransmitAnchorUpdate(mesh, "A1", 0.992, 0.05, 0.996, timestamp);
            }

            // Stream 5: Fisher information (every 50 steps)
            if step % config::FisherFreq == 0 {
                set mesh = TransmitFisherUpdate(mesh, 221.4, 400.0, step / 100, "attention_4", timestamp);
            }

            // Stream 6: Replay clusters (every 10 steps)
            if step % config::ReplayFreq == 0 {
                set mesh = TransmitReplayCluster(mesh, step % 64, 258, 17.0, 24, 0.75, timestamp);
            }

            // Stream 7: Blockchain hashes (every 200 steps)
            if step % config::BlockchainFreq == 0 {
                set mesh = TransmitBlockchainHash(mesh, step / 200, timestamp);
            }

            // Stream 8: MAIA inference (every 5 steps)
            if step % config::MAIAInferFreq == 0 {
                set mesh = TransmitMAIAInference(mesh, step, timestamp);
            }

            // Stream 9: MAIA training (every 100 steps)
            if step % config::MAIATrainFreq == 0 {
                set mesh = TransmitMAIATraining(mesh, "ewc_consolidation", $"cp_{step}", timestamp);
            }

            // Update congestion control
            set mesh = UpdateCongestionStates(mesh, config::BaseRTTMs, timestamp);

            // Update step counter
            set mesh = MeshNetworkState(
                mesh::WindowsSession, mesh::LinuxSession, mesh::MAIASession,
                mesh::WindowsCongestion, mesh::LinuxCongestion, mesh::MAIACongestion,
                mesh::Registry,
                step + 1, mesh::TotalFramesSent, mesh::TotalBytesTransferred
            );
        }

        // Log final statistics
        LogNetworkStats(mesh, config);

        // Close sessions
        CloseSession(mesh::WindowsSession, nSteps * 1000);
        CloseSession(mesh::LinuxSession, nSteps * 1000);
        CloseSession(mesh::MAIASession, nSteps * 1000);

        Message("\n[WT-MAIA/1.0] WebTransport pipeline complete.");
        Message("[WT-MAIA/1.0] All 10 streams operational.");
        Message("[WT-MAIA/1.0] Windows ↔ Linux ↔ MAIA-300 mesh synchronized.");
    }
}