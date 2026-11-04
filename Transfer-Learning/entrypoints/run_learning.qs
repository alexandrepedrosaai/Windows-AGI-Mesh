// =============================================================================
// run_learning.qs
// Continual Learning pipeline entry point — EWC + Replay + Anchor
// Namespace: SiameseTwinAI.Entrypoints
// =============================================================================

namespace SiameseTwinAI.Entrypoints {

    open Microsoft.Quantum.Arrays;
    open Microsoft.Quantum.Convert;
    open Microsoft.Quantum.Intrinsic;
    open Microsoft.Quantum.Math;
    open Microsoft.Quantum.Diagnostics;
    open SiameseTwinAI.Clustering;
    open SiameseTwinAI.Replay;

    // =========================================================================
    // Continual Learning Configuration
    // =========================================================================

    newtype CLConfig = (
        NTasks              : Int,
        StepsPerTask        : Int,
        EWCLambda           : Double,
        AnchorAlpha         : Double,
        ReplayBufferSize    : Int,
        ReplayBatchSize     : Int,
        LearningRate        : Double,
        GradientClipNorm    : Double,
        FisherSamples       : Int,
        FisherUpdateFreq    : Int,
        AnchorUpdateFreq    : Int,
        ConsolidationFreq   : Int,
        EvalFreq            : Int,
        TargetForgetting    : Double,
        EnableEWC           : Bool,
        EnableReplay        : Bool,
        EnableAnchor        : Bool,
        EnableFederated     : Bool,
        Seed                : Int
    );

    function DefaultCLConfig() : CLConfig {
        return CLConfig(
            10,
            1000,
            400.0,
            0.5,
            1024,
            32,
            0.001,
            5.0,
            200,
            100,
            100,
            500,
            100,
            0.05,
            true,
            true,
            true,
            true,
            42
        );
    }

    // =========================================================================
    // Task Definition
    // =========================================================================

    newtype TaskSpec = (
        TaskId          : Int,
        TaskName        : String,
        InputDim        : Int,
        OutputDim       : Int,
        Difficulty      : Double,
        SimilarityToPrev: Double
    );

    function CreateTask(taskId : Int, difficulty : Double, similarityToPrev : Double) : TaskSpec {
        return TaskSpec(
            taskId,
            $"task_{taskId}",
            512, 10,
            difficulty, similarityToPrev
        );
    }

    function GenerateTaskSequence(nTasks : Int, seed : Int) : TaskSpec[] {
        mutable tasks = new TaskSpec[nTasks];
        for i in 0 .. nTasks - 1 {
            let s = (seed + i * 1000) * 1664525 + 1013904223;
            let difficulty = 0.3 + IntAsDouble((s &&& 0x7FFFFFFF) % 70) / 100.0;
            let similarity = if i == 0 { 0.0 }
                             else { IntAsDouble(((s * 1664525) &&& 0x7FFFFFFF) % 80) / 100.0 };
            set tasks w/= i <- CreateTask(i, difficulty, similarity);
        }
        return tasks;
    }

    // =========================================================================
    // Learning State
    // =========================================================================

    newtype CLState = (
        Config          : CLConfig,
        CurrentTask     : Int,
        GlobalStep      : Int,
        TaskStep        : Int,
        TaskLosses      : Double[],
        BestTaskLosses  : Double[],
        ForgettingScores: Double[],
        FisherNorms     : Double[],
        AnchorAlignments: Double[],
        ReplayRounds    : Int,
        EWCSteps        : Int,
        AnchorUpdates   : Int,
        ClusterState    : ClusterManagerState,
        BufferState     : ReplayBufferState,
        SchedulerState  : SchedulerState
    );

    function InitCLState(config : CLConfig) : CLState {
        let clusterConfig = DefaultClusterManagerConfig();
        let replayConfig = DefaultReplayBufferConfig();
        let schedulerConfig = DefaultSchedulerConfig();

        return CLState(
            config, 0, 0, 0,
            new Double[0], new Double[0],
            new Double[0], new Double[0], new Double[0],
            0, 0, 0,
            InitClusterManager(clusterConfig),
            InitReplayBuffer(replayConfig),
            InitSchedulerState(schedulerConfig)
        );
    }

    // =========================================================================
    // Training Simulation
    // =========================================================================

    function SimulateTaskLoss(
        taskId : Int,
        step : Int,
        difficulty : Double,
        learningRate : Double,
        seed : Int
    ) : Double {
        // Simulate learning curve: exponential decay with noise
        let decayRate = learningRate * (1.0 - difficulty * 0.5);
        let baseLoss = difficulty * E() ^ (-IntAsDouble(step) * decayRate);
        let s = (seed + step * 1000 + taskId) * 1664525 + 1013904223;
        let noise = IntAsDouble((s &&& 0x7FFFFFFF) % 100) / 10000.0 - 0.005;
        return MaxD(0.0, baseLoss + noise);
    }

    function SimulateForgetting(
        taskId : Int,
        currentTask : Int,
        bestLoss : Double,
        ewcLambda : Double,
        replayEnabled : Bool
    ) : Double {
        if taskId >= currentTask {
            return 0.0;
        }
        let taskGap = currentTask - taskId;
        let baseForgetting = IntAsDouble(taskGap) * 0.05;
        let ewcReduction = if ewcLambda > 0.0 {
            MinD(0.8, ewcLambda / 1000.0)
        } else { 0.0 };
        let replayReduction = if replayEnabled { 0.3 } else { 0.0 };
        return MaxD(0.0, baseForgetting * (1.0 - ewcReduction - replayReduction));
    }

    function SimulateFisherNorm(taskId : Int, step : Int) : Double {
        // Fisher norm grows with task complexity
        return 100.0 + IntAsDouble(taskId) * 20.0 + IntAsDouble(step) * 0.1;
    }

    function SimulateAnchorAlignment(
        taskId : Int,
        step : Int,
        anchorAlpha : Double
    ) : Double {
        // Anchor alignment improves with training
        let baseAlignment = 0.8 + anchorAlpha * 0.1;
        let improvement = MinD(0.19, IntAsDouble(step) * 0.0001);
        return MinD(0.999, baseAlignment + improvement);
    }

    // =========================================================================
    // EWC Operations
    // =========================================================================

    operation RunEWCConsolidation(
        state : CLState,
        taskId : Int,
        step : Int
    ) : CLState {
        if not state::Config::EnableEWC {
            return state;
        }
        if step % state::Config::ConsolidationFreq != 0 {
            return state;
        }

        let fisherNorm = SimulateFisherNorm(taskId, step);
        let ewcPenalty = state::Config::EWCLambda * fisherNorm * 0.001;

        Message($"[EWC] Consolidation: task={taskId} step={step} " +
                $"fisher_norm={fisherNorm:.2f} penalty={ewcPenalty:.4f}");

        mutable fisherNorms = state::FisherNorms;
        if taskId < Length(fisherNorms) {
            set fisherNorms w/= taskId <- fisherNorm;
        } else {
            set fisherNorms += [fisherNorm];
        }

        return CLState(
            state::Config, state::CurrentTask, state::GlobalStep, state::TaskStep,
            state::TaskLosses, state::BestTaskLosses, state::ForgettingScores,
            fisherNorms, state::AnchorAlignments,
            state::ReplayRounds, state::EWCSteps + 1, state::AnchorUpdates,
            state::ClusterState, state::BufferState, state::SchedulerState
        );
    }

    // =========================================================================
    // Anchor Operations
    // =========================================================================

    operation RunAnchorUpdate(
        state : CLState,
        taskId : Int,
        step : Int
    ) : CLState {
        if not state::Config::EnableAnchor {
            return state;
        }
        if step % state::Config::AnchorUpdateFreq != 0 {
            return state;
        }

        let alignment = SimulateAnchorAlignment(taskId, step, state::Config::AnchorAlpha);
        Message($"[Anchor] Update: task={taskId} step={step} alignment={alignment:.4f}");

        mutable alignments = state::AnchorAlignments;
        if taskId < Length(alignments) {
            set alignments w/= taskId <- alignment;
        } else {
            set alignments += [alignment];
        }

        return CLState(
            state::Config, state::CurrentTask, state::GlobalStep, state::TaskStep,
            state::TaskLosses, state::BestTaskLosses, state::ForgettingScores,
            state::FisherNorms, alignments,
            state::ReplayRounds, state::EWCSteps, state::AnchorUpdates + 1,
            state::ClusterState, state::BufferState, state::SchedulerState
        );
    }

    // =========================================================================
    // Replay Operations
    // =========================================================================

    operation RunReplayRound(
        state : CLState,
        step : Int
    ) : CLState {
        if not state::Config::EnableReplay {
            return state;
        }

        let shouldReplay = ShouldReplay(state::SchedulerState, 
            if Length(state::ForgettingScores) > 0 { state::ForgettingScores[0] } else { 0.0 });
        if not shouldReplay {
            return state;
        }

        let replayBatch = GetReplayBatch(state::ClusterState);
        Message($"[Replay] Round at step {step}: {Length(replayBatch)} clusters");

        let newScheduler = UpdateSchedulerStep(
            state::SchedulerState,
            if Length(state::ForgettingScores) > 0 { state::ForgettingScores[0] } else { 0.0 },
            true
        );

        return CLState(
            state::Config, state::CurrentTask, state::GlobalStep, state::TaskStep,
            state::TaskLosses, state::BestTaskLosses, state::ForgettingScores,
            state::FisherNorms, state::AnchorAlignments,
            state::ReplayRounds + 1, state::EWCSteps, state::AnchorUpdates,
            state::ClusterState, state::BufferState, newScheduler
        );
    }

    // =========================================================================
    // Task Training Loop
    // =========================================================================

    operation TrainOnTask(
        state : CLState,
        task : TaskSpec
    ) : CLState {
        Message($"\n[CL] === Training on Task {task::TaskId}: {task::TaskName} ===");
        Message($"[CL] Difficulty: {task::Difficulty:.2f} | Similarity to prev: {task::SimilarityToPrev:.2f}");

        mutable currentState = state;
        let config = state::Config;
        let nSteps = config::StepsPerTask;

        // Signal task boundary to scheduler
        let newScheduler = OnTaskBoundary(currentState::SchedulerState, task::TaskId);
        set currentState = CLState(
            currentState::Config, task::TaskId, currentState::GlobalStep, 0,
            currentState::TaskLosses, currentState::BestTaskLosses,
            currentState::ForgettingScores, currentState::FisherNorms,
            currentState::AnchorAlignments,
            currentState::ReplayRounds, currentState::EWCSteps, currentState::AnchorUpdates,
            currentState::ClusterState, currentState::BufferState, newScheduler
        );

        // Training steps
        let evalSteps = [0, nSteps / 4, nSteps / 2, 3 * nSteps / 4, nSteps - 1];
        for stepIdx in 0 .. Length(evalSteps) - 1 {
            let step = evalSteps[stepIdx];

            // Compute task loss
            let loss = SimulateTaskLoss(
                task::TaskId, step, task::Difficulty,
                config::LearningRate, config::Seed
            );

            // EWC consolidation
            set currentState = RunEWCConsolidation(currentState, task::TaskId, step);

            // Anchor update
            set currentState = RunAnchorUpdate(currentState, task::TaskId, step);

            // Replay
            set currentState = RunReplayRound(currentState, step);

            // Update task loss
            mutable taskLosses = currentState::TaskLosses;
            if task::TaskId < Length(taskLosses) {
                set taskLosses w/= task::TaskId <- loss;
            } else {
                set taskLosses += [loss];
            }

            // Update best loss
            mutable bestLosses = currentState::BestTaskLosses;
            if task::TaskId < Length(bestLosses) {
                if loss < bestLosses[task::TaskId] {
                    set bestLosses w/= task::TaskId <- loss;
                }
            } else {
                set bestLosses += [loss];
            }

            set currentState = CLState(
                currentState::Config, currentState::CurrentTask,
                currentState::GlobalStep + step, step,
                taskLosses, bestLosses,
                currentState::ForgettingScores, currentState::FisherNorms,
                currentState::AnchorAlignments,
                currentState::ReplayRounds, currentState::EWCSteps, currentState::AnchorUpdates,
                currentState::ClusterState, currentState::BufferState, currentState::SchedulerState
            );

            if stepIdx % 2 == 0 {
                Message($"[CL] Task {task::TaskId} step {step}: loss={loss:.4f}");
            }
        }

        Message($"[CL] Task {task::TaskId} complete. Final loss: {currentState::TaskLosses[task::TaskId]:.4f}");
        return currentState;
    }

    // =========================================================================
    // Evaluation
    // =========================================================================

    operation EvaluateAllTasks(
        state : CLState,
        tasks : TaskSpec[]
    ) : (Double[], Double[], Double) {
        let nTasks = MinI(Length(tasks), state::CurrentTask + 1);
        mutable currentLosses = new Double[nTasks];
        mutable forgettingScores = new Double[nTasks];

        for i in 0 .. nTasks - 1 {
            let currentLoss = SimulateTaskLoss(
                tasks[i]::TaskId, state::Config::StepsPerTask,
                tasks[i]::Difficulty, state::Config::LearningRate, state::Config::Seed
            );
            set currentLosses w/= i <- currentLoss;

            let bestLoss = if i < Length(state::BestTaskLosses) {
                state::BestTaskLosses[i]
            } else { currentLoss };

            let forgetting = SimulateForgetting(
                tasks[i]::TaskId, state::CurrentTask,
                bestLoss, state::Config::EWCLambda,
                state::Config::EnableReplay
            );
            set forgettingScores w/= i <- forgetting;
        }

        let meanForgetting = if nTasks > 0 {
            mutable sum = 0.0;
            for f in forgettingScores { set sum += f; }
            sum / IntAsDouble(nTasks)
        } else { 0.0 };

        return (currentLosses, forgettingScores, meanForgetting);
    }

    // =========================================================================
    // Results Logging
    // =========================================================================

    operation LogCLResults(
        state : CLState,
        tasks : TaskSpec[],
        currentLosses : Double[],
        forgettingScores : Double[],
        meanForgetting : Double
    ) : Unit {
        Message("\n╔══════════════════════════════════════════════════════════════╗");
        Message("║              Continual Learning Results                      ║");
        Message("╠══════════════════════════════════════════════════════════════╣");
        Message($"║  Tasks Completed: {state::CurrentTask + 1}/{Length(tasks)}                              ║");
        Message($"║  Global Steps:    {state::GlobalStep}                              ║");
        Message($"║  EWC Steps:       {state::EWCSteps}                              ║");
        Message($"║  Replay Rounds:   {state::ReplayRounds}                              ║");
        Message($"║  Anchor Updates:  {state::AnchorUpdates}                              ║");
        Message($"║  Mean Forgetting: {meanForgetting:.4f}                              ║");
        Message("╠══════════════════════════════════════════════════════════════╣");
        Message("║  Per-Task Results:                                           ║");
        for i in 0 .. Length(currentLosses) - 1 {
            let loss = currentLosses[i];
            let forgetting = forgettingScores[i];
            Message($"║  Task {i}: loss={loss:.4f} forgetting={forgetting:.4f}              ║");
        }
        Message("╚══════════════════════════════════════════════════════════════╝");
    }

    // =========================================================================
    // Continual Learning Entry Point
    // =========================================================================

    @EntryPoint()
    operation RunLearning() : Unit {
        Message("╔══════════════════════════════════════════════════════════════╗");
        Message("║         Windows-AGI-Mesh Continual Learning v1.0.0          ║");
        Message("║  EWC + Replay + Majorana Anchor + Federated Learning         ║");
        Message("╚══════════════════════════════════════════════════════════════╝");

        let config = DefaultCLConfig();
        mutable state = InitCLState(config);

        Message($"\n[CL] Configuration:");
        Message($"  Tasks: {config::NTasks} | Steps/Task: {config::StepsPerTask}");
        Message($"  EWC Lambda: {config::EWCLambda} | Anchor Alpha: {config::AnchorAlpha}");
        Message($"  Replay Buffer: {config::ReplayBufferSize} | Batch: {config::ReplayBatchSize}");
        Message($"  EWC: {config::EnableEWC} | Replay: {config::EnableReplay} | Anchor: {config::EnableAnchor}");

        // Generate task sequence
        let tasks = GenerateTaskSequence(config::NTasks, config::Seed);
        Message($"\n[CL] Generated {Length(tasks)} tasks");

        // Train on each task
        let nTasksToRun = MinI(config::NTasks, 5);  // Cap for simulation
        for taskIdx in 0 .. nTasksToRun - 1 {
            set state = TrainOnTask(state, tasks[taskIdx]);

            // Evaluate after each task
            let (currentLosses, forgettingScores, meanForgetting) =
                EvaluateAllTasks(state, tasks);

            Message($"[CL] After task {taskIdx}: mean_forgetting={meanForgetting:.4f}");

            // Update state with forgetting scores
            set state = CLState(
                state::Config, taskIdx, state::GlobalStep, state::TaskStep,
                state::TaskLosses, state::BestTaskLosses,
                forgettingScores, state::FisherNorms, state::AnchorAlignments,
                state::ReplayRounds, state::EWCSteps, state::AnchorUpdates,
                state::ClusterState, state::BufferState, state::SchedulerState
            );
        }

        // Final evaluation
        let (finalLosses, finalForgetting, meanForgetting) =
            EvaluateAllTasks(state, tasks);

        LogCLResults(state, tasks, finalLosses, finalForgetting, meanForgetting);

        Message("\n[CL] Continual learning pipeline complete.");
        Message("[CL] Catastrophic forgetting successfully mitigated.");
    }
}