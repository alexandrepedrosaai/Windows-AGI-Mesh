// =============================================================================
// replay_scheduler.qs
// Q# Replay Scheduler — orchestrates when and what to replay during training
// Implements task-aware, curriculum-driven, and federated replay scheduling
// Namespace: SiameseTwinAI.Replay
// =============================================================================

namespace SiameseTwinAI.Replay {

    open Microsoft.Quantum.Arrays;
    open Microsoft.Quantum.Convert;
    open Microsoft.Quantum.Intrinsic;
    open Microsoft.Quantum.Math;
    open Microsoft.Quantum.Diagnostics;
    open SiameseTwinAI.Clustering;

    // =========================================================================
    // Scheduler Configuration
    // =========================================================================

    /// Configuration for the replay scheduler
    newtype SchedulerConfig = (
        ReplayFrequency     : Int,      // Replay every N training steps
        ReplayRatio         : Double,   // Fraction of batch from replay
        WarmupSteps         : Int,      // Steps before replay starts
        CurriculumEnabled   : Bool,     // Enable curriculum-based scheduling
        TaskAwareEnabled    : Bool,     // Enable task-aware replay
        FederatedEnabled    : Bool,     // Enable federated replay
        MaxReplayRounds     : Int,      // Max replay rounds per step
        AdaptiveFrequency   : Bool,     // Adapt replay frequency to forgetting
        ForgettingThreshold : Double    // Trigger extra replay if forgetting > threshold
    );

    /// Default scheduler configuration
    function DefaultSchedulerConfig() : SchedulerConfig {
        return SchedulerConfig(
            10,     // ReplayFrequency: replay every 10 steps
            0.3,    // ReplayRatio: 30% of batch from replay
            1000,   // WarmupSteps
            true,   // CurriculumEnabled
            true,   // TaskAwareEnabled
            true,   // FederatedEnabled
            3,      // MaxReplayRounds
            true,   // AdaptiveFrequency
            0.1     // ForgettingThreshold
        );
    }

    // =========================================================================
    // Scheduler State
    // =========================================================================

    /// State of the replay scheduler
    newtype SchedulerState = (
        CurrentStep         : Int,
        CurrentTask         : Int,
        TaskHistory         : Int[],
        ForgettingHistory   : Double[],
        ReplayCount         : Int,
        LastReplayStep      : Int,
        CurrentFrequency    : Int,
        Config              : SchedulerConfig
    );

    /// Initialize scheduler state
    function InitSchedulerState(config : SchedulerConfig) : SchedulerState {
        return SchedulerState(
            0, 0, new Int[0], new Double[0],
            0, 0, config::ReplayFrequency, config
        );
    }

    // =========================================================================
    // Replay Decision Logic
    // =========================================================================

    /// Determine if replay should occur at current step
    function ShouldReplay(
        state : SchedulerState,
        currentForgetting : Double
    ) : Bool {
        let config = state::Config;

        // Warmup period: no replay
        if state::CurrentStep < config::WarmupSteps {
            return false;
        }

        // Adaptive frequency: replay more if forgetting is high
        if config::AdaptiveFrequency and currentForgetting > config::ForgettingThreshold {
            return true;
        }

        // Regular frequency check
        return (state::CurrentStep - state::LastReplayStep) >= state::CurrentFrequency;
    }

    /// Compute adaptive replay frequency based on forgetting rate
    function AdaptiveReplayFrequency(
        forgettingHistory : Double[],
        baseFrequency : Int,
        minFrequency : Int,
        maxFrequency : Int
    ) : Int {
        if Length(forgettingHistory) == 0 {
            return baseFrequency;
        }

        // Compute recent mean forgetting
        let window = MinI(10, Length(forgettingHistory));
        let start = Length(forgettingHistory) - window;
        mutable sum = 0.0;
        for i in start .. Length(forgettingHistory) - 1 {
            set sum += forgettingHistory[i];
        }
        let meanForgetting = sum / IntAsDouble(window);

        // Higher forgetting → lower frequency (replay more often)
        let scale = 1.0 - MinD(0.9, meanForgetting);
        let rawFreq = Ceiling(IntAsDouble(baseFrequency) * scale);
        return MaxI(minFrequency, MinI(maxFrequency, rawFreq));
    }

    /// Update scheduler state after a training step
    function UpdateSchedulerStep(
        state : SchedulerState,
        forgetting : Double,
        didReplay : Bool
    ) : SchedulerState {
        let config = state::Config;
        mutable forgettingHistory = state::ForgettingHistory + [forgetting];
        if Length(forgettingHistory) > 1000 {
            set forgettingHistory = forgettingHistory[Length(forgettingHistory) - 1000 .. Length(forgettingHistory) - 1];
        }

        let newFrequency = if config::AdaptiveFrequency {
            AdaptiveReplayFrequency(forgettingHistory, config::ReplayFrequency, 1, 100)
        } else {
            config::ReplayFrequency
        };

        return SchedulerState(
            state::CurrentStep + 1,
            state::CurrentTask,
            state::TaskHistory,
            forgettingHistory,
            state::ReplayCount + (if didReplay { 1 } else { 0 }),
            if didReplay { state::CurrentStep } else { state::LastReplayStep },
            newFrequency,
            config
        );
    }

    /// Signal task boundary to scheduler
    function OnTaskBoundary(
        state : SchedulerState,
        newTaskId : Int
    ) : SchedulerState {
        return SchedulerState(
            state::CurrentStep,
            newTaskId,
            state::TaskHistory + [state::CurrentTask],
            state::ForgettingHistory,
            state::ReplayCount,
            state::LastReplayStep,
            state::CurrentFrequency,
            state::Config
        );
    }

    // =========================================================================
    // Replay Batch Composition
    // =========================================================================

    /// Compute how many replay samples to include in a batch
    function ReplaySampleCount(
        totalBatchSize : Int,
        replayRatio : Double,
        bufferSize : Int
    ) : Int {
        let rawCount = Ceiling(IntAsDouble(totalBatchSize) * replayRatio);
        return MinI(rawCount, bufferSize);
    }

    /// Compute task-aware replay allocation
    /// Allocates more replay to tasks with higher forgetting
    function TaskAwareAllocation(
        taskIds : Int[],
        forgettingPerTask : Double[],
        totalReplaySamples : Int
    ) : (Int, Int)[] {
        let numTasks = MinI(Length(taskIds), Length(forgettingPerTask));
        if numTasks == 0 {
            return new (Int, Int)[0];
        }

        mutable totalForgetting = 0.0;
        for i in 0 .. numTasks - 1 {
            set totalForgetting += forgettingPerTask[i];
        }

        mutable allocations = new (Int, Int)[numTasks];
        mutable allocated = 0;

        for i in 0 .. numTasks - 1 {
            let share = if totalForgetting > 0.0 {
                Ceiling(forgettingPerTask[i] / totalForgetting * IntAsDouble(totalReplaySamples))
            } else {
                totalReplaySamples / numTasks
            };
            set allocations w/= i <- (taskIds[i], share);
            set allocated += share;
        }

        return allocations;
    }

    /// Compute curriculum-based replay allocation
    /// Earlier tasks get more replay (to prevent forgetting)
    function CurriculumAllocation(
        taskHistory : Int[],
        totalReplaySamples : Int
    ) : (Int, Int)[] {
        let numTasks = Length(taskHistory);
        if numTasks == 0 {
            return new (Int, Int)[0];
        }

        // Exponential decay: older tasks get more replay
        mutable weights = new Double[numTasks];
        mutable totalWeight = 0.0;
        for i in 0 .. numTasks - 1 {
            let age = numTasks - i;  // Older tasks have higher age
            let w = E() ^ (IntAsDouble(age) * 0.1);
            set weights w/= i <- w;
            set totalWeight += w;
        }

        mutable allocations = new (Int, Int)[numTasks];
        for i in 0 .. numTasks - 1 {
            let share = Ceiling(weights[i] / totalWeight * IntAsDouble(totalReplaySamples));
            set allocations w/= i <- (taskHistory[i], share);
        }
        return allocations;
    }

    // =========================================================================
    // Replay Round Management
    // =========================================================================

    /// Replay round descriptor
    newtype ReplayRound = (
        RoundId       : Int,
        TaskId        : Int,
        SampleCount   : Int,
        Priority      : Double,
        IsWarmup      : Bool
    );

    /// Plan replay rounds for current training step
    function PlanReplayRounds(
        state : SchedulerState,
        bufferState : ReplayBufferState,
        totalBatchSize : Int,
        forgettingPerTask : Double[]
    ) : ReplayRound[] {
        let config = state::Config;
        let replayCount = ReplaySampleCount(
            totalBatchSize,
            config::ReplayRatio,
            Length(bufferState::Experiences)
        );

        if replayCount == 0 {
            return new ReplayRound[0];
        }

        let maxRounds = config::MaxReplayRounds;
        let samplesPerRound = MaxI(1, replayCount / maxRounds);

        mutable rounds = new ReplayRound[0];

        if config::TaskAwareEnabled and Length(state::TaskHistory) > 0 {
            let allocations = TaskAwareAllocation(
                state::TaskHistory,
                forgettingPerTask,
                replayCount
            );
            for i in 0 .. MinI(maxRounds, Length(allocations)) - 1 {
                let (tid, count) = allocations[i];
                set rounds += [ReplayRound(i, tid, count, 1.0, false)];
            }
        } elif config::CurriculumEnabled and Length(state::TaskHistory) > 0 {
            let allocations = CurriculumAllocation(state::TaskHistory, replayCount);
            for i in 0 .. MinI(maxRounds, Length(allocations)) - 1 {
                let (tid, count) = allocations[i];
                set rounds += [ReplayRound(i, tid, count, 1.0, false)];
            }
        } else {
            // Uniform replay
            for i in 0 .. maxRounds - 1 {
                set rounds += [ReplayRound(i, -1, samplesPerRound, 1.0, false)];
            }
        }

        return rounds;
    }

    // =========================================================================
    // Forgetting Detection
    // =========================================================================

    /// Compute forgetting metric from validation losses
    function ComputeForgetting(
        currentLoss : Double,
        bestLoss : Double
    ) : Double {
        if bestLoss <= 0.0 {
            return 0.0;
        }
        return MaxD(0.0, (currentLoss - bestLoss) / bestLoss);
    }

    /// Compute backward transfer (forgetting on previous tasks)
    function BackwardTransfer(
        currentLosses : Double[],
        bestLosses : Double[]
    ) : Double {
        let n = MinI(Length(currentLosses), Length(bestLosses));
        if n == 0 {
            return 0.0;
        }
        mutable totalForgetting = 0.0;
        for i in 0 .. n - 1 {
            set totalForgetting += ComputeForgetting(currentLosses[i], bestLosses[i]);
        }
        return totalForgetting / IntAsDouble(n);
    }

    /// Compute forward transfer (improvement on future tasks from past learning)
    function ForwardTransfer(
        currentLosses : Double[],
        randomInitLosses : Double[]
    ) : Double {
        let n = MinI(Length(currentLosses), Length(randomInitLosses));
        if n == 0 {
            return 0.0;
        }
        mutable totalTransfer = 0.0;
        for i in 0 .. n - 1 {
            if randomInitLosses[i] > 0.0 {
                set totalTransfer += (randomInitLosses[i] - currentLosses[i]) / randomInitLosses[i];
            }
        }
        return totalTransfer / IntAsDouble(n);
    }

    /// Detect catastrophic forgetting event
    function IsCatastrophicForgetting(
        forgetting : Double,
        threshold : Double
    ) : Bool {
        return forgetting > threshold;
    }

    // =========================================================================
    // Federated Replay Scheduling
    // =========================================================================

    /// Federated replay request from a remote node
    newtype FederatedReplayRequest = (
        NodeId        : String,
        TaskId        : Int,
        SampleCount   : Int,
        Priority      : Double,
        Timestamp     : Int
    );

    /// Federated replay response
    newtype FederatedReplayResponse = (
        NodeId        : String,
        ExperienceIds : Int[],
        Accepted      : Bool,
        Reason        : String
    );

    /// Process a federated replay request
    function ProcessFederatedRequest(
        request : FederatedReplayRequest,
        bufferState : ReplayBufferState,
        config : SchedulerConfig
    ) : FederatedReplayResponse {
        if not config::FederatedEnabled {
            return FederatedReplayResponse(
                request::NodeId, new Int[0], false, "Federated replay disabled"
            );
        }

        let available = Length(bufferState::Experiences);
        if available == 0 {
            return FederatedReplayResponse(
                request::NodeId, new Int[0], false, "Buffer empty"
            );
        }

        let count = MinI(request::SampleCount, available);
        let (indices, _) = SampleBatch(bufferState, count, request::Timestamp);

        return FederatedReplayResponse(
            request::NodeId, indices, true, "OK"
        );
    }

    /// Merge remote replay experiences into local buffer
    function MergeFederatedExperiences(
        localBuffer : ReplayBufferState,
        remoteExperiences : ReplayExperience[],
        maxMergeCount : Int
    ) : ReplayBufferState {
        let toMerge = MinI(maxMergeCount, Length(remoteExperiences));
        mutable result = localBuffer;
        for i in 0 .. toMerge - 1 {
            set result = AddExperience(result, remoteExperiences[i]);
        }
        return result;
    }

    // =========================================================================
    // Replay Quality Metrics
    // =========================================================================

    /// Compute replay effectiveness (reduction in forgetting due to replay)
    function ReplayEffectiveness(
        forgettingWithReplay : Double,
        forgettingWithoutReplay : Double
    ) : Double {
        if forgettingWithoutReplay <= 0.0 {
            return 0.0;
        }
        return (forgettingWithoutReplay - forgettingWithReplay) / forgettingWithoutReplay;
    }

    /// Compute replay overhead (extra compute cost)
    function ReplayOverhead(
        replaySteps : Int,
        totalSteps : Int
    ) : Double {
        if totalSteps == 0 {
            return 0.0;
        }
        return IntAsDouble(replaySteps) / IntAsDouble(totalSteps);
    }

    /// Compute replay efficiency (effectiveness / overhead)
    function ReplayEfficiency(
        effectiveness : Double,
        overhead : Double
    ) : Double {
        if overhead <= 0.0 {
            return 0.0;
        }
        return effectiveness / overhead;
    }

    // =========================================================================
    // Scheduler Statistics
    // =========================================================================

    /// Compute scheduler statistics
    function SchedulerStats(state : SchedulerState) : (Int, Int, Double, Double) {
        let replayRate = if state::CurrentStep > 0 {
            IntAsDouble(state::ReplayCount) / IntAsDouble(state::CurrentStep)
        } else {
            0.0
        };

        let meanForgetting = if Length(state::ForgettingHistory) > 0 {
            mutable sum = 0.0;
            for f in state::ForgettingHistory {
                set sum += f;
            }
            sum / IntAsDouble(Length(state::ForgettingHistory))
        } else {
            0.0
        };

        return (
            state::CurrentStep,
            state::ReplayCount,
            replayRate,
            meanForgetting
        );
    }

    // =========================================================================
    // Logging Operations
    // =========================================================================

    /// Log scheduler state
    operation LogSchedulerState(state : SchedulerState) : Unit {
        let (step, replayCount, replayRate, meanForgetting) = SchedulerStats(state);
        Message($"[Scheduler] step={step} task={state::CurrentTask} " +
                $"replays={replayCount} rate={replayRate} " +
                $"forgetting={meanForgetting} freq={state::CurrentFrequency}");
    }

    /// Log replay round plan
    operation LogReplayPlan(rounds : ReplayRound[]) : Unit {
        Message($"[Replay Plan] rounds={Length(rounds)}");
        for r in rounds {
            Message($"  Round {r::RoundId}: task={r::TaskId} samples={r::SampleCount} priority={r::Priority}");
        }
    }

    /// Log forgetting event
    operation LogForgettingEvent(
        taskId : Int,
        forgetting : Double,
        threshold : Double,
        step : Int
    ) : Unit {
        let severity = if forgetting > threshold * 2.0 { "CRITICAL" }
                       elif forgetting > threshold { "HIGH" }
                       else { "MODERATE" };
        Message($"[Forgetting:{severity}] task={taskId} forgetting={forgetting} " +
                $"threshold={threshold} step={step}");
    }

    /// Log federated replay event
    operation LogFederatedReplay(
        request : FederatedReplayRequest,
        response : FederatedReplayResponse
    ) : Unit {
        let status = if response::Accepted { "ACCEPTED" } else { "REJECTED" };
        Message($"[Federated Replay:{status}] node={request::NodeId} " +
                $"task={request::TaskId} count={request::SampleCount} " +
                $"reason={response::Reason}");
    }

    // =========================================================================
    // AutoML Interface
    // =========================================================================

    /// Export scheduler state as features for AutoML
    function SchedulerStateToFeatures(state : SchedulerState) : Double[] {
        let (step, replayCount, replayRate, meanForgetting) = SchedulerStats(state);
        return [
            IntAsDouble(step),
            IntAsDouble(state::CurrentTask),
            IntAsDouble(Length(state::TaskHistory)),
            IntAsDouble(replayCount),
            replayRate,
            meanForgetting,
            IntAsDouble(state::CurrentFrequency),
            state::Config::ReplayRatio,
            IntAsDouble(state::Config::WarmupSteps),
            IntAsDouble(state::Config::MaxReplayRounds)
        ];
    }

    /// Apply AutoML hyperparameter update to scheduler
    function ApplyAutoMLSchedulerConfig(
        state : SchedulerState,
        newFrequency : Int,
        newReplayRatio : Double,
        newMaxRounds : Int
    ) : SchedulerState {
        let oldConfig = state::Config;
        let newConfig = SchedulerConfig(
            newFrequency,
            newReplayRatio,
            oldConfig::WarmupSteps,
            oldConfig::CurriculumEnabled,
            oldConfig::TaskAwareEnabled,
            oldConfig::FederatedEnabled,
            newMaxRounds,
            oldConfig::AdaptiveFrequency,
            oldConfig::ForgettingThreshold
        );
        return SchedulerState(
            state::CurrentStep,
            state::CurrentTask,
            state::TaskHistory,
            state::ForgettingHistory,
            state::ReplayCount,
            state::LastReplayStep,
            newFrequency,
            newConfig
        );
    }
}
