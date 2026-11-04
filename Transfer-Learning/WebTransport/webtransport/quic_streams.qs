// =============================================================================
// quic_streams.qs
// Q# QUIC stream management for WT-MAIA/1.0 protocol
// Implements stream lifecycle, flow control, and priority scheduling
// Namespace: SiameseTwinAI.WebTransport
// =============================================================================

namespace SiameseTwinAI.WebTransport {

    open Microsoft.Quantum.Arrays;
    open Microsoft.Quantum.Convert;
    open Microsoft.Quantum.Intrinsic;
    open Microsoft.Quantum.Math;
    open Microsoft.Quantum.Diagnostics;

    // =========================================================================
    // Stream Constants
    // =========================================================================

    // Stream IDs
    function StreamIdSensorData()       : Int { return 0; }
    function StreamIdGradientUpdates()  : Int { return 1; }
    function StreamIdWeightDeltas()     : Int { return 2; }
    function StreamIdTelemetry()        : Int { return 3; }
    function StreamIdMajoranaAnchor()   : Int { return 4; }
    function StreamIdEWCFisher()        : Int { return 5; }
    function StreamIdReplayClusters()   : Int { return 6; }
    function StreamIdBlockchainHashes() : Int { return 7; }
    function StreamIdMAIAInference()    : Int { return 8; }
    function StreamIdMAIATraining()     : Int { return 9; }

    // Stream priorities (0 = highest, 7 = lowest)
    function PrioritySensorData()       : Int { return 0; }
    function PriorityGradientUpdates()  : Int { return 1; }
    function PriorityWeightDeltas()     : Int { return 1; }
    function PriorityTelemetry()        : Int { return 6; }
    function PriorityMajoranaAnchor()   : Int { return 0; }
    function PriorityEWCFisher()        : Int { return 3; }
    function PriorityReplayClusters()   : Int { return 3; }
    function PriorityBlockchainHashes() : Int { return 5; }
    function PriorityMAIAInference()    : Int { return 0; }
    function PriorityMAIATraining()     : Int { return 2; }

    // Frame flags
    function FlagReliable()      : Int { return 0x0001; }
    function FlagCompressed()    : Int { return 0x0002; }
    function FlagEncrypted()     : Int { return 0x0004; }
    function FlagPriorityHigh()  : Int { return 0x0008; }
    function FlagBatch()         : Int { return 0x0010; }
    function FlagAckRequired()   : Int { return 0x0020; }
    function FlagLastFrame()     : Int { return 0x0040; }
    function FlagQuantum()       : Int { return 0x0080; }

    // Max frame sizes per stream (bytes)
    function MaxFrameSizeSensor()       : Int { return 4096; }
    function MaxFrameSizeGradient()     : Int { return 65536; }
    function MaxFrameSizeWeight()       : Int { return 131072; }
    function MaxFrameSizeTelemetry()    : Int { return 512; }
    function MaxFrameSizeAnchor()       : Int { return 2048; }
    function MaxFrameSizeFisher()       : Int { return 32768; }
    function MaxFrameSizeReplay()       : Int { return 16384; }
    function MaxFrameSizeBlockchain()   : Int { return 1024; }
    function MaxFrameSizeMAIAInfer()    : Int { return 65536; }
    function MaxFrameSizeMAIATrain()    : Int { return 262144; }

    // =========================================================================
    // Stream State Types
    // =========================================================================

    newtype StreamState = (
        StreamId        : Int,
        Priority        : Int,
        IsOpen          : Bool,
        IsReliable      : Bool,
        BytesSent       : Int,
        BytesReceived   : Int,
        FramesSent      : Int,
        FramesReceived  : Int,
        SequenceNumber  : Int,
        FlowWindow      : Int,
        MaxFrameSize    : Int,
        LastActivity    : Int
    );

    newtype SessionState = (
        SessionId       : String,
        NodeId          : String,
        PeerAddress     : String,
        IsConnected     : Bool,
        Streams         : StreamState[],
        RTT             : Int,
        Bandwidth       : Int,
        PacketLoss      : Double,
        TotalBytesSent  : Int,
        TotalBytesRecv  : Int,
        ConnectedAt     : Int,
        LastHeartbeat   : Int
    );

    // =========================================================================
    // Stream Initialization
    // =========================================================================

    function InitStreamState(
        streamId : Int,
        priority : Int,
        maxFrameSize : Int,
        reliable : Bool
    ) : StreamState {
        return StreamState(
            streamId,
            priority,
            true,
            reliable,
            0, 0, 0, 0,
            0,
            10485760,   // 10 MB flow window
            maxFrameSize,
            0
        );
    }

    function InitAllStreams() : StreamState[] {
        return [
            InitStreamState(0, PrioritySensorData(),       MaxFrameSizeSensor(),    false),
            InitStreamState(1, PriorityGradientUpdates(),  MaxFrameSizeGradient(),  true),
            InitStreamState(2, PriorityWeightDeltas(),     MaxFrameSizeWeight(),    true),
            InitStreamState(3, PriorityTelemetry(),        MaxFrameSizeTelemetry(), false),
            InitStreamState(4, PriorityMajoranaAnchor(),   MaxFrameSizeAnchor(),    true),
            InitStreamState(5, PriorityEWCFisher(),        MaxFrameSizeFisher(),    true),
            InitStreamState(6, PriorityReplayClusters(),   MaxFrameSizeReplay(),    true),
            InitStreamState(7, PriorityBlockchainHashes(), MaxFrameSizeBlockchain(),true),
            InitStreamState(8, PriorityMAIAInference(),    MaxFrameSizeMAIAInfer(), true),
            InitStreamState(9, PriorityMAIATraining(),     MaxFrameSizeMAIATrain(), true)
        ];
    }

    function InitSession(
        sessionId : String,
        nodeId : String,
        peerAddress : String,
        timestamp : Int
    ) : SessionState {
        return SessionState(
            sessionId,
            nodeId,
            peerAddress,
            true,
            InitAllStreams(),
            0, 0, 0.0,
            0, 0,
            timestamp,
            timestamp
        );
    }

    // =========================================================================
    // Stream Operations
    // =========================================================================

    function OpenStream(
        session : SessionState,
        streamId : Int
    ) : SessionState {
        mutable streams = session::Streams;
        if streamId >= 0 and streamId < Length(streams) {
            let s = streams[streamId];
            set streams w/= streamId <- StreamState(
                s::StreamId, s::Priority, true, s::IsReliable,
                s::BytesSent, s::BytesReceived,
                s::FramesSent, s::FramesReceived,
                s::SequenceNumber, s::FlowWindow,
                s::MaxFrameSize, s::LastActivity
            );
        }
        return SessionState(
            session::SessionId, session::NodeId, session::PeerAddress,
            session::IsConnected, streams,
            session::RTT, session::Bandwidth, session::PacketLoss,
            session::TotalBytesSent, session::TotalBytesRecv,
            session::ConnectedAt, session::LastHeartbeat
        );
    }

    function CloseStream(
        session : SessionState,
        streamId : Int
    ) : SessionState {
        mutable streams = session::Streams;
        if streamId >= 0 and streamId < Length(streams) {
            let s = streams[streamId];
            set streams w/= streamId <- StreamState(
                s::StreamId, s::Priority, false, s::IsReliable,
                s::BytesSent, s::BytesReceived,
                s::FramesSent, s::FramesReceived,
                s::SequenceNumber, s::FlowWindow,
                s::MaxFrameSize, s::LastActivity
            );
        }
        return SessionState(
            session::SessionId, session::NodeId, session::PeerAddress,
            session::IsConnected, streams,
            session::RTT, session::Bandwidth, session::PacketLoss,
            session::TotalBytesSent, session::TotalBytesRecv,
            session::ConnectedAt, session::LastHeartbeat
        );
    }

    function RecordFrameSent(
        session : SessionState,
        streamId : Int,
        frameSize : Int,
        timestamp : Int
    ) : SessionState {
        mutable streams = session::Streams;
        if streamId >= 0 and streamId < Length(streams) {
            let s = streams[streamId];
            set streams w/= streamId <- StreamState(
                s::StreamId, s::Priority, s::IsOpen, s::IsReliable,
                s::BytesSent + frameSize, s::BytesReceived,
                s::FramesSent + 1, s::FramesReceived,
                (s::SequenceNumber + 1) % 4294967296,
                MaxI(0, s::FlowWindow - frameSize),
                s::MaxFrameSize, timestamp
            );
        }
        return SessionState(
            session::SessionId, session::NodeId, session::PeerAddress,
            session::IsConnected, streams,
            session::RTT, session::Bandwidth, session::PacketLoss,
            session::TotalBytesSent + frameSize, session::TotalBytesRecv,
            session::ConnectedAt, timestamp
        );
    }

    function RecordFrameReceived(
        session : SessionState,
        streamId : Int,
        frameSize : Int,
        timestamp : Int
    ) : SessionState {
        mutable streams = session::Streams;
        if streamId >= 0 and streamId < Length(streams) {
            let s = streams[streamId];
            set streams w/= streamId <- StreamState(
                s::StreamId, s::Priority, s::IsOpen, s::IsReliable,
                s::BytesSent, s::BytesReceived + frameSize,
                s::FramesSent, s::FramesReceived + 1,
                s::SequenceNumber,
                MinI(10485760, s::FlowWindow + frameSize),
                s::MaxFrameSize, timestamp
            );
        }
        return SessionState(
            session::SessionId, session::NodeId, session::PeerAddress,
            session::IsConnected, streams,
            session::RTT, session::Bandwidth, session::PacketLoss,
            session::TotalBytesSent, session::TotalBytesRecv + frameSize,
            session::ConnectedAt, timestamp
        );
    }

    // =========================================================================
    // Flow Control
    // =========================================================================

    function CanSendFrame(
        session : SessionState,
        streamId : Int,
        frameSize : Int
    ) : Bool {
        if streamId < 0 or streamId >= Length(session::Streams) {
            return false;
        }
        let stream = session::Streams[streamId];
        return session::IsConnected and
               frameSize >= 0 and
               stream::IsOpen and
               frameSize <= stream::MaxFrameSize and
               frameSize <= stream::FlowWindow
    }

    function UpdateFlowWindow(
        session : SessionState,
        streamId : Int,
        newWindow : Int
    ) : SessionState {
        mutable streams = session::Streams;
        if streamId >= 0 and streamId < Length(streams) {
            let s = streams[streamId];
            set streams w/= streamId <- StreamState(
                s::StreamId, s::Priority, s::IsOpen, s::IsReliable,
                s::BytesSent, s::BytesReceived,
                s::FramesSent, s::FramesReceived,
                s::SequenceNumber, newWindow,
                s::MaxFrameSize, s::LastActivity
            );
        }
        return SessionState(
            session::SessionId, session::NodeId, session::PeerAddress,
            session::IsConnected, streams,
            session::RTT, session::Bandwidth, session::PacketLoss,
            session::TotalBytesSent, session::TotalBytesRecv,
            session::ConnectedAt, session::LastHeartbeat
        );
    }

    // =========================================================================
    // Priority Scheduling
    // =========================================================================

    function GetHighestPriorityOpenStream(
        session : SessionState
    ) : Int {
        mutable bestStream = -1;
        mutable bestPriority = 8;
        for i in 0 .. Length(session::Streams) - 1 {
            let s = session::Streams[i];
            if s::IsOpen and s::Priority < bestPriority {
                set bestPriority = s::Priority;
                set bestStream = i;
            }
        }
        return bestStream;
    }

    function GetStreamsByPriority(
        session : SessionState
    ) : Int[] {
        let n = Length(session::Streams);
        mutable indices = new Int[n];
        for i in 0 .. n - 1 {
            set indices w/= i <- i;
        }
        // Sort by priority (insertion sort)
        for i in 1 .. n - 1 {
            let key = indices[i];
            let keyPriority = session::Streams[key]::Priority;
            mutable j = i - 1;
            while j >= 0 and session::Streams[indices[j]]::Priority > keyPriority {
                set indices w/= j + 1 <- indices[j];
                set j -= 1;
            }
            set indices w/= j + 1 <- key;
        }
        return indices;
    }

    function ComputeBandwidthAllocation(
        session : SessionState
    ) : Double[] {
        // Allocate bandwidth by priority group
        // Critical (0-1): 40%, High (2-3): 30%, Medium (4-5): 20%, Low (6-7): 10%
        let n = Length(session::Streams);
        mutable alloc = new Double[n];
        for i in 0 .. n - 1 {
            let priority = session::Streams[i]::Priority;
            let bw = if priority <= 1 { 0.40 / 4.0 }
                     elif priority <= 3 { 0.30 / 4.0 }
                     elif priority <= 5 { 0.20 / 4.0 }
                     else { 0.10 / 4.0 };
            set alloc w/= i <- bw;
        }
        return alloc;
    }

    // =========================================================================
    // Telemetry and Statistics
    // =========================================================================

    function UpdateSessionTelemetry(
        session : SessionState,
        rtt : Int,
        bandwidth : Int,
        packetLoss : Double,
        timestamp : Int
    ) : SessionState {
        return SessionState(
            session::SessionId, session::NodeId, session::PeerAddress,
            session::IsConnected, session::Streams,
            rtt, bandwidth, packetLoss,
            session::TotalBytesSent, session::TotalBytesRecv,
            session::ConnectedAt, timestamp
        );
    }

    function ComputeSessionThroughput(
        session : SessionState,
        durationMs : Int
    ) : Double {
        if durationMs <= 0 {
            return 0.0;
        }
        let totalBytes = session::TotalBytesSent + session::TotalBytesRecv;
        return IntAsDouble(totalBytes) * 8.0 / IntAsDouble(durationMs) / 1000.0;  // Mbps
    }

    function GetStreamStats(
        session : SessionState,
        streamId : Int
    ) : (Int, Int, Int, Int) {
        if streamId < 0 or streamId >= Length(session::Streams) {
            return (0, 0, 0, 0);
        }
        let s = session::Streams[streamId];
        return (s::BytesSent, s::BytesReceived, s::FramesSent, s::FramesReceived);
    }

    function TotalFramesSent(session : SessionState) : Int {
        mutable total = 0;
        for s in session::Streams {
            set total += s::FramesSent;
        }
        return total;
    }

    function TotalFramesReceived(session : SessionState) : Int {
        mutable total = 0;
        for s in session::Streams {
            set total += s::FramesReceived;
        }
        return total;
    }

    // =========================================================================
    // Error Detection and Recovery
    // =========================================================================

    function DetectStreamTimeout(
        session : SessionState,
        streamId : Int,
        currentTimestamp : Int,
        timeoutMs : Int
    ) : Bool {
        if streamId < 0 or streamId >= Length(session::Streams) {
            return false;
        }
        let s = session::Streams[streamId];
        if not s::IsOpen {
            return false;
        }
        return (currentTimestamp - s::LastActivity) > timeoutMs;
    }

    function DetectSessionTimeout(
        session : SessionState,
        currentTimestamp : Int,
        timeoutMs : Int
    ) : Bool {
        return (currentTimestamp - session::LastHeartbeat) > timeoutMs;
    }

    function ResetStream(
        session : SessionState,
        streamId : Int,
        timestamp : Int
    ) : SessionState {
        mutable streams = session::Streams;
        if streamId >= 0 and streamId < Length(streams) {
            let s = streams[streamId];
            set streams w/= streamId <- StreamState(
                s::StreamId, s::Priority, true, s::IsReliable,
                s::BytesSent, s::BytesReceived,
                s::FramesSent, s::FramesReceived,
                0,  // Reset sequence number
                10485760,  // Reset flow window
                s::MaxFrameSize, timestamp
            );
        }
        return SessionState(
            session::SessionId, session::NodeId, session::PeerAddress,
            session::IsConnected, streams,
            session::RTT, session::Bandwidth, session::PacketLoss,
            session::TotalBytesSent, session::TotalBytesRecv,
            session::ConnectedAt, timestamp
        );
    }

    // =========================================================================
    // Logging Operations
    // =========================================================================

    operation LogStreamState(
        session : SessionState,
        streamId : Int
    ) : Unit {
        if streamId >= 0 and streamId < Length(session::Streams) {
            let s = session::Streams[streamId];
            Message($"[Stream {streamId}] open={s::IsOpen} priority={s::Priority} " +
                    $"sent={s::BytesSent}B/{s::FramesSent}f " +
                    $"recv={s::BytesReceived}B/{s::FramesReceived}f " +
                    $"seq={s::SequenceNumber} window={s::FlowWindow}");
        }
    }

    operation LogSessionState(session : SessionState) : Unit {
        Message($"[Session {session::SessionId}] node={session::NodeId} " +
                $"peer={session::PeerAddress} connected={session::IsConnected} " +
                $"rtt={session::RTT}ms bw={session::Bandwidth}Mbps " +
                $"loss={session::PacketLoss} " +
                $"sent={session::TotalBytesSent}B recv={session::TotalBytesRecv}B");
        for i in 0 .. Length(session::Streams) - 1 {
            LogStreamState(session, i);
        }
    }

    operation LogStreamOpened(streamId : Int, priority : Int) : Unit {
        Message($"[QUIC] Stream {streamId} opened (priority={priority})");
    }

    operation LogStreamClosed(streamId : Int, bytesSent : Int, bytesRecv : Int) : Unit {
        Message($"[QUIC] Stream {streamId} closed (sent={bytesSent}B recv={bytesRecv}B)");
    }

    operation LogFrameSent(
        streamId : Int,
        sequenceNumber : Int,
        frameSize : Int,
        flags : Int
    ) : Unit {
        Message($"[QUIC→] Stream {streamId} seq={sequenceNumber} " +
                $"size={frameSize}B flags=0x{flags}");
    }

    operation LogFrameReceived(
        streamId : Int,
        sequenceNumber : Int,
        frameSize : Int
    ) : Unit {
        Message($"[QUIC←] Stream {streamId} seq={sequenceNumber} size={frameSize}B");
    }

    operation LogConnectionError(
        sessionId : String,
        errorCode : Int,
        errorMessage : String
    ) : Unit {
        Message($"[QUIC ERROR] session={sessionId} code=0x{errorCode} msg={errorMessage}");
    }

    // =========================================================================
    // Frame Construction Helpers
    // =========================================================================

    function BuildSensorDataPayload(
        sensorId : Int,
        coherence : Double,
        phase : Double,
        adc : Int,
        timestamp : Int,
        nodeId : String,
        batchSeq : Int
    ) : String {
        return $"{{\"sensor_id\":{sensorId},\"coherence\":{coherence}," +
               $"\"phase\":{phase},\"adc\":{adc},\"timestamp\":{timestamp}," +
               $"\"node_id\":\"{nodeId}\",\"batch_seq\":{batchSeq}}}";
    }

    function BuildGradientPayload(
        model : String,
        layer : String,
        gradientHash : String,
        topk : Double,
        step : Int,
        nodeId : String,
        sparsity : Double
    ) : String {
        return $"{{\"model\":\"{model}\",\"layer\":\"{layer}\"," +
               $"\"gradient_hash\":\"{gradientHash}\",\"topk\":{topk}," +
               $"\"step\":{step},\"node_id\":\"{nodeId}\",\"sparsity\":{sparsity}}}";
    }

    function BuildReplayClusterPayload(
        clusterId : Int,
        samples : Int,
        meanHamming : Double,
        threshold : Int,
        noveltyScore : Double,
        timestamp : Int
    ) : String {
        return $"{{\"cluster\":{clusterId},\"samples\":{samples}," +
               $"\"mean_hamming\":{meanHamming},\"threshold\":{threshold}," +
               $"\"novelty_score\":{noveltyScore},\"timestamp\":{timestamp}}}";
    }

    function BuildFisherPayload(
        fisherNorm : Double,
        lambda : Double,
        taskId : Int,
        layer : String,
        timestamp : Int
    ) : String {
        return $"{{\"fisher_norm\":{fisherNorm},\"lambda\":{lambda}," +
               $"\"task_id\":{taskId},\"layer\":\"{layer}\",\"timestamp\":{timestamp}}}";
    }

    function BuildMAIAInferencePayload(
        requestId : Int,
        modelVersion : String,
        batchSize : Int,
        timestamp : Int,
        priority : Int
    ) : String {
        return $"{{\"request_id\":{requestId},\"model_version\":\"{modelVersion}\"," +
               $"\"batch_size\":{batchSize},\"timestamp\":{timestamp},\"priority\":{priority}}}";
    }

    function BuildMAIATrainingPayload(
        task : String,
        checkpoint : String,
        epochs : Int,
        timestamp : Int,
        nodeId : String
    ) : String {
        return $"{{\"task\":\"{task}\",\"checkpoint\":\"{checkpoint}\"," +
               $"\"epochs\":{epochs},\"timestamp\":{timestamp},\"node_id\":\"{nodeId}\"}}";
    }

    function BuildAnchorPayload(
        anchorId : String,
        alignment : Double,
        phase : Double,
        fidelity : Double,
        errorRate : Double,
        timestamp : Int
    ) : String {
        return $"{{\"anchor_id\":\"{anchorId}\",\"alignment\":{alignment}," +
               $"\"phase\":{phase},\"fidelity\":{fidelity}," +
               $"\"error_rate\":{errorRate},\"timestamp\":{timestamp}}}";
    }

    function BuildBlockchainPayload(
        block : Int,
        sha256 : String,
        prevHash : String,
        merkleRoot : String,
        timestamp : Int,
        nodeId : String
    ) : String {
        return $"{{\"block\":{block},\"sha256\":\"{sha256}\"," +
               $"\"prev_hash\":\"{prevHash}\",\"merkle_root\":\"{merkleRoot}\"," +
               $"\"timestamp\":{timestamp},\"node_id\":\"{nodeId}\"}}";
    }

    // =========================================================================
    // Session Management Operations
    // =========================================================================

    operation OpenSession(
        sessionId : String,
        nodeId : String,
        peerAddress : String,
        timestamp : Int
    ) : SessionState {
        let session = InitSession(sessionId, nodeId, peerAddress, timestamp);
        Message($"[WT-MAIA/1.0] Session opened: {sessionId} node={nodeId} peer={peerAddress}");
        return session;
    }

    operation CloseSession(session : SessionState, timestamp : Int) : Unit {
        let duration = timestamp - session::ConnectedAt;
        Message($"[WT-MAIA/1.0] Session closed: {session::SessionId} " +
                $"duration={duration}ms " +
                $"sent={session::TotalBytesSent}B recv={session::TotalBytesRecv}B");
    }

    operation SendHeartbeat(
        session : SessionState,
        timestamp : Int
    ) : SessionState {
        Message($"[Heartbeat] session={session::SessionId} t={timestamp}");
        return SessionState(
            session::SessionId, session::NodeId, session::PeerAddress,
            session::IsConnected, session::Streams,
            session::RTT, session::Bandwidth, session::PacketLoss,
            session::TotalBytesSent, session::TotalBytesRecv,
            session::ConnectedAt, timestamp
        );
    }
}