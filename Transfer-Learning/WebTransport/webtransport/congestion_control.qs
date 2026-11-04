// =============================================================================
// congestion_control.qs
// Q# QUIC congestion control for WT-MAIA/1.0 protocol
// Implements CUBIC, BBR, and adaptive priority-aware congestion control
// Namespace: SiameseTwinAI.WebTransport
// =============================================================================

namespace SiameseTwinAI.WebTransport {

    open Microsoft.Quantum.Arrays;
    open Microsoft.Quantum.Convert;
    open Microsoft.Quantum.Intrinsic;
    open Microsoft.Quantum.Math;
    open Microsoft.Quantum.Diagnostics;

    // =========================================================================
    // Congestion Control Constants
    // =========================================================================

    function AlgorithmCUBIC()    : Int { return 0; }
    function AlgorithmBBR()      : Int { return 1; }
    function AlgorithmRENO()     : Int { return 2; }
    function AlgorithmCOPA()     : Int { return 3; }
    function AlgorithmADAPTIVE() : Int { return 4; }

    function CUBICBeta()         : Double { return 0.7; }
    function CUBICScalingFactor(): Double { return 0.4; }
    function InitialCWND()       : Int    { return 10; }
    function MaxCWND()           : Int    { return 10000; }
    function MinCWND()           : Int    { return 2; }
    function MSS()               : Int    { return 1460; }

    // =========================================================================
    // Congestion State
    // =========================================================================

    newtype CongestionState = (
        Algorithm      : Int,
        CWND           : Double,
        SSThresh       : Double,
        InSlowStart    : Bool,
        RTT            : Double,
        MinRTT         : Double,
        SmoothedRTT    : Double,
        RTTVariance    : Double,
        PacketLoss     : Double,
        BytesInFlight  : Int,
        TotalBytesSent : Int,
        TotalLost      : Int,
        TotalRetransmit: Int,
        LastLossTime   : Int,
        CUBICWMax      : Double,
        CUBICEpochStart: Int,
        BBRBtlBw       : Double,
        BBRRTprop      : Double,
        BBRState       : Int,
        Step           : Int
    );

    function InitCongestionState(algorithm : Int) : CongestionState {
        return CongestionState(
            algorithm,
            IntAsDouble(InitialCWND()),
            IntAsDouble(MaxCWND()),
            true,
            0.0, 0.0, 0.0, 0.0,
            0.0, 0, 0, 0, 0, 0,
            IntAsDouble(InitialCWND()),
            0,
            0.0, 0.0, 0,
            0
        );
    }

    // =========================================================================
    // RTT Estimation (RFC 6298)
    // =========================================================================

    function UpdateRTT(
        state : CongestionState,
        measuredRTT : Double
    ) : CongestionState {
        let alpha = 0.125;
        let beta = 0.25;

        let newSmoothed = if state::SmoothedRTT == 0.0 {
            measuredRTT
        } else {
            (1.0 - alpha) * state::SmoothedRTT + alpha * measuredRTT
        };

        let newVariance = if state::RTTVariance == 0.0 {
            measuredRTT / 2.0
        } else {
            (1.0 - beta) * state::RTTVariance + beta * AbsD(measuredRTT - newSmoothed)
        };

        let newMinRTT = if state::MinRTT == 0.0 or measuredRTT < state::MinRTT {
            measuredRTT
        } else {
            state::MinRTT
        };

        return CongestionState(
            state::Algorithm,
            state::CWND, state::SSThresh, state::InSlowStart,
            measuredRTT, newMinRTT, newSmoothed, newVariance,
            state::PacketLoss, state::BytesInFlight,
            state::TotalBytesSent, state::TotalLost, state::TotalRetransmit,
            state::LastLossTime,
            state::CUBICWMax, state::CUBICEpochStart,
            state::BBRBtlBw, state::BBRRTprop, state::BBRState,
            state::Step + 1
        );
    }

    function ComputeRTO(state : CongestionState) : Double {
        // RTO = SRTT + max(G, 4*RTTVAR) where G = clock granularity (1ms)
        let g = 1.0;
        return state::SmoothedRTT + MaxD(g, 4.0 * state::RTTVariance);
    }

    // =========================================================================
    // CUBIC Congestion Control
    // =========================================================================

    function CUBICWindowIncrease(
        state : CongestionState,
        ackedBytes : Int,
        currentTime : Int
    ) : Double {
        if state::InSlowStart {
            // Slow start: exponential increase
            return state::CWND + IntAsDouble(ackedBytes) / IntAsDouble(MSS());
        }

        // CUBIC window function: W(t) = C*(t-K)^3 + W_max
        let c = CUBICScalingFactor();
        let wMax = state::CUBICWMax;
        let beta = CUBICBeta();

        // Time since last congestion event (in seconds)
        let t = IntAsDouble(currentTime - state::CUBICEpochStart) / 1000.0;

        // K = cube_root(W_max * (1-beta) / C)
        let k = (wMax * (1.0 - beta) / c) ^ (1.0 / 3.0);

        // CUBIC window
        let wCubic = c * ((t - k) ^ 3.0) + wMax;

        // TCP-friendly window (for fairness)
        let wTCP = wMax * beta + 3.0 * beta / (2.0 - beta) *
                   IntAsDouble(ackedBytes) / IntAsDouble(MSS());

        return MaxD(wCubic, wTCP);
    }

    function CUBICOnAck(
        state : CongestionState,
        ackedBytes : Int,
        currentTime : Int
    ) : CongestionState {
        let newCWND = if state::InSlowStart {
            let increased = state::CWND + IntAsDouble(ackedBytes) / IntAsDouble(MSS());
            if increased >= state::SSThresh {
                state::SSThresh
            } else {
                increased
            }
        } else {
            MinD(
                IntAsDouble(MaxCWND()),
                CUBICWindowIncrease(state, ackedBytes, currentTime)
            )
        };

        let inSlowStart = newCWND < state::SSThresh;

        return CongestionState(
            state::Algorithm,
            newCWND, state::SSThresh, inSlowStart,
            state::RTT, state::MinRTT, state::SmoothedRTT, state::RTTVariance,
            state::PacketLoss,
            MaxI(0, state::BytesInFlight - ackedBytes),
            state::TotalBytesSent, state::TotalLost, state::TotalRetransmit,
            state::LastLossTime,
            state::CUBICWMax, state::CUBICEpochStart,
            state::BBRBtlBw, state::BBRRTprop, state::BBRState,
            state::Step + 1
        );
    }

    function CUBICOnLoss(
        state : CongestionState,
        lostBytes : Int,
        currentTime : Int
    ) : CongestionState {
        let beta = CUBICBeta();
        let newSSThresh = MaxD(
            IntAsDouble(MinCWND()),
            state::CWND * beta
        );
        let newCWND = newSSThresh;

        return CongestionState(
            state::Algorithm,
            newCWND, newSSThresh, false,
            state::RTT, state::MinRTT, state::SmoothedRTT, state::RTTVariance,
            state::PacketLoss + IntAsDouble(lostBytes) / IntAsDouble(state::TotalBytesSent + 1),
            state::BytesInFlight,
            state::TotalBytesSent,
            state::TotalLost + lostBytes,
            state::TotalRetransmit + 1,
            currentTime,
            state::CWND,  // Save W_max before reduction
            currentTime,  // Reset CUBIC epoch
            state::BBRBtlBw, state::BBRRTprop, state::BBRState,
            state::Step + 1
        );
    }

    // =========================================================================
    // BBR Congestion Control
    // =========================================================================

    // BBR states
    function BBRStateStartup()    : Int { return 0; }
    function BBRStateDrain()      : Int { return 1; }
    function BBRStateProbeBW()    : Int { return 2; }
    function BBRStateProbeRTT()   : Int { return 3; }

    function BBRComputePacingRate(
        state : CongestionState,
        gainFactor : Double
    ) : Double {
        if state::BBRRTprop <= 0.0 or state::BBRBtlBw <= 0.0 {
            return 0.0;
        }
        return gainFactor * state::BBRBtlBw;
    }

    function BBRComputeCWND(
        state : CongestionState,
        gainFactor : Double
    ) : Double {
        if state::BBRRTprop <= 0.0 or state::BBRBtlBw <= 0.0 {
            return IntAsDouble(InitialCWND());
        }
        let bdp = state::BBRBtlBw * state::BBRRTprop / 1000.0;
        return gainFactor * bdp;
    }

    function BBROnAck(
        state : CongestionState,
        ackedBytes : Int,
        deliveryRate : Double,
        currentTime : Int
    ) : CongestionState {
        // Update bottleneck bandwidth estimate
        let newBtlBw = MaxD(state::BBRBtlBw, deliveryRate);

        // Update RTprop (minimum RTT)
        let newRTprop = if state::BBRRTprop == 0.0 or state::RTT < state::BBRRTprop {
            state::RTT
        } else {
            state::BBRRTprop
        };

        // Compute new CWND based on BBR state
        let gainFactor = if state::BBRState == BBRStateStartup() { 2.885 }
                         elif state::BBRState == BBRStateDrain() { 0.75 }
                         elif state::BBRState == BBRStateProbeBW() { 1.25 }
                         else { 1.0 };

        let newCWND = MinD(
            IntAsDouble(MaxCWND()),
            MaxD(IntAsDouble(MinCWND()), BBRComputeCWND(state, gainFactor))
        );

        // State transitions
        let newBBRState = if state::BBRState == BBRStateStartup() and
                             newBtlBw <= state::BBRBtlBw * 1.25 {
            BBRStateDrain()
        } elif state::BBRState == BBRStateDrain() and
               IntAsDouble(state::BytesInFlight) <= newCWND {
            BBRStateProbeBW()
        } else {
            state::BBRState
        };

        return CongestionState(
            state::Algorithm,
            newCWND, state::SSThresh, false,
            state::RTT, state::MinRTT, state::SmoothedRTT, state::RTTVariance,
            state::PacketLoss,
            MaxI(0, state::BytesInFlight - ackedBytes),
            state::TotalBytesSent, state::TotalLost, state::TotalRetransmit,
            state::LastLossTime,
            state::CUBICWMax, state::CUBICEpochStart,
            newBtlBw, newRTprop, newBBRState,
            state::Step + 1
        );
    }

    // =========================================================================
    // Adaptive Algorithm Selection
    // =========================================================================

    function SelectAlgorithm(
        state : CongestionState,
        currentTime : Int
    ) : Int {
        // High loss → CUBIC (conservative)
        if state::PacketLoss > 0.05 {
            return AlgorithmCUBIC();
        }
        // Low RTT, low loss → BBR
        if state::MinRTT < 5.0 and state::PacketLoss < 0.001 {
            return AlgorithmBBR();
        }
        // High RTT → COPA
        if state::MinRTT > 50.0 {
            return AlgorithmCOPA();
        }
        // Default: CUBIC
        return AlgorithmCUBIC();
    }

    function AdaptiveOnAck(
        state : CongestionState,
        ackedBytes : Int,
        deliveryRate : Double,
        currentTime : Int
    ) : CongestionState {
        let newAlgorithm = SelectAlgorithm(state, currentTime);
        let stateWithNewAlg = CongestionState(
            newAlgorithm,
            state::CWND, state::SSThresh, state::InSlowStart,
            state::RTT, state::MinRTT, state::SmoothedRTT, state::RTTVariance,
            state::PacketLoss, state::BytesInFlight,
            state::TotalBytesSent, state::TotalLost, state::TotalRetransmit,
            state::LastLossTime,
            state::CUBICWMax, state::CUBICEpochStart,
            state::BBRBtlBw, state::BBRRTprop, state::BBRState,
            state::Step
        );

        if newAlgorithm == AlgorithmBBR() {
            return BBROnAck(stateWithNewAlg, ackedBytes, deliveryRate, currentTime);
        } else {
            return CUBICOnAck(stateWithNewAlg, ackedBytes, currentTime);
        }
    }

    // =========================================================================
    // Priority-Aware Bandwidth Allocation
    // =========================================================================

    newtype BandwidthAllocation = (
        TotalBandwidthMbps : Double,
        CriticalFraction   : Double,
        HighFraction       : Double,
        MediumFraction     : Double,
        LowFraction        : Double,
        StreamAllocations  : Double[]
    );

    function InitBandwidthAllocation(
        totalBandwidthMbps : Double
    ) : BandwidthAllocation {
        // Default: Critical 40%, High 30%, Medium 20%, Low 10%
        let streamAllocs = [
            totalBandwidthMbps * 0.40 / 3.0,  // Stream 0: sensor (critical)
            totalBandwidthMbps * 0.30 / 3.0,  // Stream 1: gradient (high)
            totalBandwidthMbps * 0.30 / 3.0,  // Stream 2: weight (high)
            totalBandwidthMbps * 0.10 / 2.0,  // Stream 3: telemetry (low)
            totalBandwidthMbps * 0.40 / 3.0,  // Stream 4: anchor (critical)
            totalBandwidthMbps * 0.20 / 2.0,  // Stream 5: fisher (medium)
            totalBandwidthMbps * 0.20 / 2.0,  // Stream 6: replay (medium)
            totalBandwidthMbps * 0.10 / 2.0,  // Stream 7: blockchain (low)
            totalBandwidthMbps * 0.40 / 3.0,  // Stream 8: MAIA infer (critical)
            totalBandwidthMbps * 0.30 / 3.0   // Stream 9: MAIA train (high)
        ];
        return BandwidthAllocation(
            totalBandwidthMbps,
            0.40, 0.30, 0.20, 0.10,
            streamAllocs
        );
    }

    function GetStreamBandwidth(
        alloc : BandwidthAllocation,
        streamId : Int
    ) : Double {
        if streamId < 0 or streamId >= Length(alloc::StreamAllocations) {
            return 0.0;
        }
        return alloc::StreamAllocations[streamId];
    }

    function AdjustForCongestion(
        alloc : BandwidthAllocation,
        congestionState : CongestionState
    ) : BandwidthAllocation {
        // Reduce non-critical streams during congestion
        let cwndFraction = congestionState::CWND / IntAsDouble(MaxCWND());
        let reductionFactor = MaxD(0.1, cwndFraction);

        mutable newAllocs = alloc::StreamAllocations;
        for i in 0 .. Length(newAllocs) - 1 {
            // Critical streams (0, 4, 8) are protected
            if i != 0 and i != 4 and i != 8 {
                set newAllocs w/= i <- newAllocs[i] * reductionFactor;
            }
        }

        return BandwidthAllocation(
            alloc::TotalBandwidthMbps,
            alloc::CriticalFraction,
            alloc::HighFraction,
            alloc::MediumFraction,
            alloc::LowFraction,
            newAllocs
        );
    }

    function EscalateStreamPriority(
        alloc : BandwidthAllocation,
        streamId : Int,
        rttMs : Double
    ) : BandwidthAllocation {
        // If RTT > 50ms, escalate sensor_data to maximum bandwidth
        if rttMs > 50.0 and streamId == 0 {
            mutable newAllocs = alloc::StreamAllocations;
            let extra = newAllocs[3] * 0.5 + newAllocs[7] * 0.5;
            set newAllocs w/= 0 <- newAllocs[0] + extra;
            set newAllocs w/= 3 <- newAllocs[3] * 0.5;
            set newAllocs w/= 7 <- newAllocs[7] * 0.5;
            return BandwidthAllocation(
                alloc::TotalBandwidthMbps,
                alloc::CriticalFraction,
                alloc::HighFraction,
                alloc::MediumFraction,
                alloc::LowFraction,
                newAllocs
            );
        }
        return alloc;
    }

    // =========================================================================
    // Packet Loss Detection
    // =========================================================================

    function DetectPacketLoss(
        expectedSeq : Int,
        receivedSeq : Int,
        threshold : Int
    ) : Bool {
        let gap = receivedSeq - expectedSeq;
        return gap > threshold;
    }

    function ComputeLossRate(
        totalSent : Int,
        totalLost : Int
    ) : Double {
        if totalSent <= 0 {
            return 0.0;
        }
        return IntAsDouble(totalLost) / IntAsDouble(totalSent);
    }

    function ShouldReduceGradientBatch(
        lossRate : Double,
        threshold : Double
    ) : Bool {
        return lossRate > threshold;
    }

    // =========================================================================
    // Congestion Window Management
    // =========================================================================

    function OnAck(
        state : CongestionState,
        ackedBytes : Int,
        deliveryRate : Double,
        currentTime : Int
    ) : CongestionState {
        if state::Algorithm == AlgorithmCUBIC() {
            return CUBICOnAck(state, ackedBytes, currentTime);
        } elif state::Algorithm == AlgorithmBBR() {
            return BBROnAck(state, ackedBytes, deliveryRate, currentTime);
        } elif state::Algorithm == AlgorithmADAPTIVE() {
            return AdaptiveOnAck(state, ackedBytes, deliveryRate, currentTime);
        } else {
            // RENO: simple AIMD
            let newCWND = if state::InSlowStart {
                state::CWND + IntAsDouble(ackedBytes) / IntAsDouble(MSS())
            } else {
                state::CWND + IntAsDouble(MSS()) * IntAsDouble(ackedBytes) / state::CWND
            };
            return CongestionState(
                state::Algorithm,
                MinD(IntAsDouble(MaxCWND()), newCWND),
                state::SSThresh, newCWND < state::SSThresh,
                state::RTT, state::MinRTT, state::SmoothedRTT, state::RTTVariance,
                state::PacketLoss,
                MaxI(0, state::BytesInFlight - ackedBytes),
                state::TotalBytesSent, state::TotalLost, state::TotalRetransmit,
                state::LastLossTime,
                state::CUBICWMax, state::CUBICEpochStart,
                state::BBRBtlBw, state::BBRRTprop, state::BBRState,
                state::Step + 1
            );
        }
    }

    function OnLoss(
        state : CongestionState,
        lostBytes : Int,
        currentTime : Int
    ) : CongestionState {
        if state::Algorithm == AlgorithmCUBIC() or
           state::Algorithm == AlgorithmADAPTIVE() {
            return CUBICOnLoss(state, lostBytes, currentTime);
        } else {
            // RENO/BBR: halve CWND
            let newSSThresh = MaxD(IntAsDouble(MinCWND()), state::CWND / 2.0);
            return CongestionState(
                state::Algorithm,
                newSSThresh, newSSThresh, false,
                state::RTT, state::MinRTT, state::SmoothedRTT, state::RTTVariance,
                state::PacketLoss + IntAsDouble(lostBytes) / IntAsDouble(state::TotalBytesSent + 1),
                state::BytesInFlight,
                state::TotalBytesSent,
                state::TotalLost + lostBytes,
                state::TotalRetransmit + 1,
                currentTime,
                state::CWND,
                currentTime,
                state::BBRBtlBw, state::BBRRTprop, state::BBRState,
                state::Step + 1
            );
        }
    }

    function OnSend(
        state : CongestionState,
        sentBytes : Int
    ) : CongestionState {
        return CongestionState(
            state::Algorithm,
            state::CWND, state::SSThresh, state::InSlowStart,
            state::RTT, state::MinRTT, state::SmoothedRTT, state::RTTVariance,
            state::PacketLoss,
            state::BytesInFlight + sentBytes,
            state::TotalBytesSent + sentBytes,
            state::TotalLost, state::TotalRetransmit,
            state::LastLossTime,
            state::CUBICWMax, state::CUBICEpochStart,
            state::BBRBtlBw, state::BBRRTprop, state::BBRState,
            state::Step
        );
    }

    function CanSend(state : CongestionState, frameSize : Int) : Bool {
        return IntAsDouble(state::BytesInFlight + frameSize) <= state::CWND * IntAsDouble(MSS());
    }

    function GetCWNDBytes(state : CongestionState) : Int {
        return Ceiling(state::CWND * IntAsDouble(MSS()));
    }

    // =========================================================================
    // Statistics and Diagnostics
    // =========================================================================

    function CongestionStats(state : CongestionState) : (Double, Double, Double, Int, Int) {
        return (
            state::CWND,
            state::SmoothedRTT,
            state::PacketLoss,
            state::TotalLost,
            state::TotalRetransmit
        );
    }

    function IsInCongestion(state : CongestionState) : Bool {
        return state::PacketLoss > 0.01 or
               state::CWND < state::SSThresh * 0.5;
    }

    function CongestionSeverity(state : CongestionState) : Int {
        // 0=none, 1=mild, 2=moderate, 3=severe
        if state::PacketLoss > 0.1 { return 3; }
        elif state::PacketLoss > 0.05 { return 2; }
        elif state::PacketLoss > 0.01 { return 1; }
        else { return 0; }
    }

    // =========================================================================
    // Logging Operations
    // =========================================================================

    operation LogCongestionState(state : CongestionState) : Unit {
        let algName = if state::Algorithm == AlgorithmCUBIC() { "CUBIC" }
                      elif state::Algorithm == AlgorithmBBR() { "BBR" }
                      elif state::Algorithm == AlgorithmRENO() { "RENO" }
                      elif state::Algorithm == AlgorithmCOPA() { "COPA" }
                      else { "ADAPTIVE" };
        Message($"[Congestion:{algName}] cwnd={state::CWND} ssthresh={state::SSThresh} " +
                $"rtt={state::SmoothedRTT}ms loss={state::PacketLoss} " +
                $"inflight={state::BytesInFlight}B step={state::Step}");
    }

    operation LogCongestionEvent(
        eventType : String,
        cwndBefore : Double,
        cwndAfter : Double,
        rtt : Double
    ) : Unit {
        Message($"[Congestion:{eventType}] cwnd {cwndBefore} → {cwndAfter} rtt={rtt}ms");
    }

    operation LogAlgorithmSwitch(
        oldAlgorithm : Int,
        newAlgorithm : Int,
        reason : String
    ) : Unit {
        let oldName = if oldAlgorithm == AlgorithmCUBIC() { "CUBIC" }
                      elif oldAlgorithm == AlgorithmBBR() { "BBR" }
                      else { "OTHER" };
        let newName = if newAlgorithm == AlgorithmCUBIC() { "CUBIC" }
                      elif newAlgorithm == AlgorithmBBR() { "BBR" }
                      elif newAlgorithm == AlgorithmCOPA() { "COPA" }
                      else { "OTHER" };
        Message($"[Congestion] Algorithm switch: {oldName} → {newName} ({reason})");
    }

    operation LogBandwidthAllocation(alloc : BandwidthAllocation) : Unit {
        Message($"[BW Alloc] total={alloc::TotalBandwidthMbps}Mbps " +
                $"critical={alloc::CriticalFraction*100.0}% " +
                $"high={alloc::HighFraction*100.0}% " +
                $"medium={alloc::MediumFraction*100.0}% " +
                $"low={alloc::LowFraction*100.0}%");
    }
}
