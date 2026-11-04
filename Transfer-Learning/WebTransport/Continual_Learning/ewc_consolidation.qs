// =============================================================================
// ewc_consolidation.qs
// Q# EWC (Elastic Weight Consolidation) for continual learning
// Implements Fisher-based regularization to prevent catastrophic forgetting
// Namespace: SiameseTwinAI.ContinualLearning
// =============================================================================

namespace SiameseTwinAI.ContinualLearning {

    open Microsoft.Quantum.Arrays;
    open Microsoft.Quantum.Convert;
    open Microsoft.Quantum.Intrinsic;
    open Microsoft.Quantum.Math;
    open Microsoft.Quantum.Diagnostics;

    // =========================================================================
    // EWC Configuration
    // =========================================================================

    newtype EWCConfig = (
        Lambda          : Double,
        LambdaMin       : Double,
        LambdaMax       : Double,
        FisherSamples   : Int,
        FisherUpdateFreq: Int,
        FisherDecay     : Double,
        OnlineEWC       : Bool,
        Gamma           : Double,
        GradClip        : Double,
        NormalizeFisher : Bool,
        FisherEpsilon   : Double,
        AdaptiveLambda  : Bool,
        LambdaAdaptRate : Double
    );

    function DefaultEWCConfig() : EWCConfig {
        return EWCConfig(
            400.0, 10.0, 2000.0,
            200, 100, 0.9,
            true, 1.0,
            5.0, true, 1e-7,
            true, 0.05
        );
    }

    // =========================================================================
    // Task Memory
    // =========================================================================

    newtype TaskMemory = (
        TaskId          : Int,
        ThetaStar       : Double[],
        FisherDiagonal  : Double[],
        FisherNorm      : Double,
        TaskLoss        : Double,
        ConsolidatedAt  : Int,
        NParams         : Int
    );

    function CreateTaskMemory(
        taskId : Int,
        thetaStar : Double[],
        fisherDiagonal : Double[],
        taskLoss : Double,
        timestamp : Int
    ) : TaskMemory {
        let n = Length(thetaStar);
        mutable fisherNorm = 0.0;
        for f in fisherDiagonal {
            set fisherNorm += f * f;
        }
        set fisherNorm = Sqrt(fisherNorm);

        return TaskMemory(
            taskId, thetaStar, fisherDiagonal,
            fisherNorm, taskLoss, timestamp, n
        );
    }

    // =========================================================================
    // EWC State
    // =========================================================================

    newtype EWCState = (
        Config          : EWCConfig,
        TaskMemories    : TaskMemory[],
        CurrentTask     : Int,
        GlobalStep      : Int,
        TotalPenalty    : Double,
        MeanForgetting  : Double,
        LastConsolidation : Int,
        AdaptiveLambda  : Double
    );

    function InitEWCState(config : EWCConfig) : EWCState {
        return EWCState(
            config,
            new TaskMemory[0],
            0, 0, 0.0, 0.0, 0,
            config::Lambda
        );
    }

    // =========================================================================
    // Fisher Information Computation
    // =========================================================================

    function ComputeFisherDiagonal(
        gradients : Double[][],
        nSamples : Int,
        normalize : Bool,
        epsilon : Double
    ) : Double[] {
        if Length(gradients) == 0 or nSamples == 0 {
            return new Double[0];
        }

        let nParams = Length(gradients[0]);
        mutable fisher = new Double[nParams];

        // Accumulate squared gradients
        for grad in gradients {
            for i in 0 .. MinI(nParams, Length(grad)) - 1 {
                set fisher w/= i <- fisher[i] + grad[i] * grad[i];
            }
        }

        // Normalize by sample count
        for i in 0 .. nParams - 1 {
            set fisher w/= i <- fisher[i] / IntAsDouble(nSamples);
        }

        // Normalize by max value if requested
        if normalize {
            mutable maxF = 0.0;
            for f in fisher {
                if f > maxF { set maxF = f; }
            }
            if maxF > epsilon {
                for i in 0 .. nParams - 1 {
                    set fisher w/= i <- fisher[i] / maxF;
                }
            }
        }

        return fisher;
    }

    function OnlineFisherUpdate(
        currentFisher : Double[],
        newGradient : Double[],
        alpha : Double
    ) : Double[] {
        let n = MinI(Length(currentFisher), Length(newGradient));
        mutable updated = currentFisher;
        for i in 0 .. n - 1 {
            let newSq = newGradient[i] * newGradient[i];
            set updated w/= i <- (1.0 - alpha) * currentFisher[i] + alpha * newSq;
        }
        return updated;
    }

    // =========================================================================
    // EWC Penalty Computation
    // =========================================================================

    function ComputeEWCPenalty(
        theta : Double[],
        memories : TaskMemory[],
        lambda : Double,
        gamma : Double
    ) : Double {
        mutable totalPenalty = 0.0;
        let nTasks = Length(memories);

        for taskIdx in 0 .. nTasks - 1 {
            let memory = memories[taskIdx];
            let taskGamma = gamma ^ IntAsDouble(nTasks - taskIdx - 1);
            let n = MinI(Length(theta), MinI(Length(memory::ThetaStar), Length(memory::FisherDiagonal)));

            mutable taskPenalty = 0.0;
            for i in 0 .. n - 1 {
                let delta = theta[i] - memory::ThetaStar[i];
                set taskPenalty += memory::FisherDiagonal[i] * delta * delta;
            }

            set totalPenalty += taskGamma * taskPenalty;
        }

        return 0.5 * lambda * totalPenalty;
    }

    function ComputeEWCGradient(
        theta : Double[],
        memories : TaskMemory[],
        lambda : Double,
        gamma : Double
    ) : Double[] {
        let nParams = Length(theta);
        mutable ewcGrad = new Double[nParams];
        let nTasks = Length(memories);

        for taskIdx in 0 .. nTasks - 1 {
            let memory = memories[taskIdx];
            let taskGamma = gamma ^ IntAsDouble(nTasks - taskIdx - 1);
            let n = MinI(nParams, MinI(Length(memory::ThetaStar), Length(memory::FisherDiagonal)));

            for i in 0 .. n - 1 {
                let delta = theta[i] - memory::ThetaStar[i];
                set ewcGrad w/= i <- ewcGrad[i] + taskGamma * lambda * memory::FisherDiagonal[i] * delta;
            }
        }

        return ewcGrad;
    }

    function CombineGradients(
        taskGrad : Double[],
        ewcGrad : Double[],
        clipNorm : Double
    ) : Double[] {
        let n = MinI(Length(taskGrad), Length(ewcGrad));
        mutable combined = new Double[n];
        for i in 0 .. n - 1 {
            set combined w/= i <- taskGrad[i] + ewcGrad[i];
        }

        // Gradient clipping
        mutable norm = 0.0;
        for g in combined { set norm += g * g; }
        set norm = Sqrt(norm);

        if norm > clipNorm and norm > 0.0 {
            let scale = clipNorm / norm;
            for i in 0 .. n - 1 {
                set combined w/= i <- combined[i] * scale;
            }
        }

        return combined;
    }

    // =========================================================================
    // Forgetting Metrics
    // =========================================================================

    function ComputeForgetting(
        currentLoss : Double,
        bestLoss : Double
    ) : Double {
        if bestLoss <= 0.0 { return 0.0; }
        return MaxD(0.0, (currentLoss - bestLoss) / bestLoss);
    }

    function ComputeBackwardTransfer(
        currentLosses : Double[],
        bestLosses : Double[]
    ) : Double {
        let n = MinI(Length(currentLosses), Length(bestLosses));
        if n == 0 { return 0.0; }
        mutable total = 0.0;
        for i in 0 .. n - 1 {
            set total += ComputeForgetting(currentLosses[i], bestLosses[i]);
        }
        return total / IntAsDouble(n);
    }

    function ComputeForwardTransfer(
        currentLosses : Double[],
        randomInitLosses : Double[]
    ) : Double {
        let n = MinI(Length(currentLosses), Length(randomInitLosses));
        if n == 0 { return 0.0; }
        mutable total = 0.0;
        for i in 0 .. n - 1 {
            if randomInitLosses[i] > 0.0 {
                set total += (randomInitLosses[i] - currentLosses[i]) / randomInitLosses[i];
            }
        }
        return total / IntAsDouble(n);
    }

    // =========================================================================
    // Adaptive Lambda
    // =========================================================================

    function AdaptLambda(
        currentLambda : Double,
        currentForgetting : Double,
        targetForgetting : Double,
        adaptRate : Double,
        lambdaMin : Double,
        lambdaMax : Double
    ) : Double {
        let error = currentForgetting - targetForgetting;
        let newLambda = currentLambda * (1.0 + adaptRate * error);
        return MaxD(lambdaMin, MinD(lambdaMax, newLambda));
    }

    // =========================================================================
    // Task Boundary Operations
    // =========================================================================

    function OnTaskBoundaryEWC(
        state : EWCState,
        newTaskId : Int,
        thetaStar : Double[],
        fisherDiagonal : Double[],
        taskLoss : Double,
        timestamp : Int
    ) : EWCState {
        let memory = CreateTaskMemory(
            state::CurrentTask, thetaStar, fisherDiagonal, taskLoss, timestamp
        );

        let newMemories = state::TaskMemories + [memory];

        return EWCState(
            state::Config,
            newMemories,
            newTaskId,
            state::GlobalStep,
            state::TotalPenalty,
            state::MeanForgetting,
            timestamp,
            state::AdaptiveLambda
        );
    }

    function UpdateEWCStep(
        state : EWCState,
        theta : Double[],
        taskGrad : Double[],
        currentForgetting : Double,
        timestamp : Int
    ) : (EWCState, Double[]) {
        let config = state::Config;

        // Compute EWC gradient
        let ewcGrad = ComputeEWCGradient(
            theta, state::TaskMemories,
            state::AdaptiveLambda, config::Gamma
        );

        // Combine gradients
        let combinedGrad = CombineGradients(taskGrad, ewcGrad, config::GradClip);

        // Compute penalty
        let penalty = ComputeEWCPenalty(
            theta, state::TaskMemories,
            state::AdaptiveLambda, config::Gamma
        );

        // Adapt lambda if enabled
        let newLambda = if config::AdaptiveLambda {
            AdaptLambda(
                state::AdaptiveLambda, currentForgetting, 0.05,
                config::LambdaAdaptRate, config::LambdaMin, config::LambdaMax
            )
        } else {
            state::AdaptiveLambda
        };

        let newState = EWCState(
            config,
            state::TaskMemories,
            state::CurrentTask,
            state::GlobalStep + 1,
            state::TotalPenalty + penalty,
            currentForgetting,
            state::LastConsolidation,
            newLambda
        );

        return (newState, combinedGrad);
    }

    // =========================================================================
    // Logging Operations
    // =========================================================================

    operation LogEWCState(state : EWCState) : Unit {
        Message($"[EWC] task={state::CurrentTask} step={state::GlobalStep} " +
                $"lambda={state::AdaptiveLambda:.2f} " +
                $"n_memories={Length(state::TaskMemories)} " +
                $"forgetting={state::MeanForgetting:.4f} " +
                $"total_penalty={state::TotalPenalty:.4f}");
    }

    operation LogTaskMemory(memory : TaskMemory) : Unit {
        Message($"[EWC Memory] task={memory::TaskId} " +
                $"fisher_norm={memory::FisherNorm:.2f} " +
                $"task_loss={memory::TaskLoss:.4f} " +
                $"n_params={memory::NParams}");
    }

    operation LogConsolidation(
        taskId : Int,
        penalty : Double,
        forgetting : Double,
        lambda : Double,
        step : Int
    ) : Unit {
        Message($"[EWC Consolidation] task={taskId} step={step} " +
                $"penalty={penalty:.4f} forgetting={forgetting:.4f} lambda={lambda:.2f}");
    }

    operation LogForgettingMetrics(
        backwardTransfer : Double,
        forwardTransfer : Double,
        nTasks : Int
    ) : Unit {
        Message($"[Forgetting] backward_transfer={backwardTransfer:.4f} " +
                $"forward_transfer={forwardTransfer:.4f} n_tasks={nTasks}");
    }
}
