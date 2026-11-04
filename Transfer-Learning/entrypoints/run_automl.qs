// =============================================================================
// run_automl.qs
// AutoML pipeline entry point — hyperparameter optimization for AGI mesh
// Namespace: SiameseTwinAI.Entrypoints
// =============================================================================

namespace SiameseTwinAI.Entrypoints {

    open Microsoft.Quantum.Arrays;
    open Microsoft.Quantum.Convert;
    open Microsoft.Quantum.Intrinsic;
    open Microsoft.Quantum.Math;
    open Microsoft.Quantum.Diagnostics;

    // =========================================================================
    // AutoML Configuration
    // =========================================================================

    newtype AutoMLRunConfig = (
        NTrials             : Int,
        Strategy            : String,
        Seed                : Int,
        Minimize            : Bool,
        NJobs               : Int,
        CheckpointDir       : String,
        EWCLambdaMin        : Double,
        EWCLambdaMax        : Double,
        ReplayBufferMin     : Int,
        ReplayBufferMax     : Int,
        HammingThreshMin    : Int,
        HammingThreshMax    : Int,
        LRMin               : Double,
        LRMax               : Double,
        AnchorAlphaMin      : Double,
        AnchorAlphaMax      : Double,
        TopKMin             : Double,
        TopKMax             : Double,
        MaxClustersMin      : Int,
        MaxClustersMax      : Int,
        TargetNoveltyRate   : Double,
        ForgettingThreshold : Double,
        BandwidthTarget     : Double,
        LatencyTarget       : Double
    );

    function DefaultAutoMLRunConfig() : AutoMLRunConfig {
        return AutoMLRunConfig(
            200,
            "bayesian",
            42,
            true,
            4,
            "automl_checkpoints",
            10.0, 2000.0,
            256, 65536,
            4, 64,
            1e-5, 1e-1,
            0.0, 1.0,
            0.01, 1.0,
            4, 256,
            0.15,
            0.05,
            1000.0,
            5.0
        );
    }

    // =========================================================================
    // Trial State
    // =========================================================================

    newtype AutoMLTrial = (
        TrialId         : Int,
        EWCLambda       : Double,
        ReplayBufferSize: Int,
        HammingThreshold: Int,
        LearningRate    : Double,
        AnchorAlpha     : Double,
        TopKRatio       : Double,
        MaxClusters     : Int,
        ObjectiveValue  : Double,
        TaskLoss        : Double,
        Forgetting      : Double,
        Bandwidth       : Double,
        Latency         : Double,
        NoveltyRate     : Double,
        Status          : String,
        Duration        : Int
    );

    function CreateTrial(
        trialId : Int,
        ewcLambda : Double,
        replayBufferSize : Int,
        hammingThreshold : Int,
        learningRate : Double,
        anchorAlpha : Double,
        topKRatio : Double,
        maxClusters : Int
    ) : AutoMLTrial {
        return AutoMLTrial(
            trialId, ewcLambda, replayBufferSize, hammingThreshold,
            learningRate, anchorAlpha, topKRatio, maxClusters,
            0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
            "pending", 0
        );
    }

    function EvaluateTrial(trial : AutoMLTrial) : AutoMLTrial {
        // Simulate objective evaluation
        // In production: runs actual training and measures metrics

        // Task loss: lower LR → slower convergence, higher LR → instability
        let lrScore = if trial::LearningRate < 1e-4 { 0.8 }
                      elif trial::LearningRate < 1e-3 { 0.3 }
                      elif trial::LearningRate < 1e-2 { 0.2 }
                      else { 0.5 };

        // EWC effectiveness: lambda in [100, 800] is optimal
        let ewcScore = if trial::EWCLambda < 50.0 { 0.4 }
                       elif trial::EWCLambda < 100.0 { 0.2 }
                       elif trial::EWCLambda < 800.0 { 0.1 }
                       elif trial::EWCLambda < 1500.0 { 0.2 }
                       else { 0.5 };

        // Replay buffer: larger is better up to a point
        let replayScore = if trial::ReplayBufferSize < 512 { 0.4 }
                          elif trial::ReplayBufferSize < 2048 { 0.2 }
                          elif trial::ReplayBufferSize < 16384 { 0.1 }
                          else { 0.15 };

        // Hamming threshold: target novelty rate ~15%
        let hammingScore = AbsD(
            IntAsDouble(trial::HammingThreshold) / 64.0 - 0.375
        );

        // Composite objective
        let taskLoss = lrScore + ewcScore * 0.5;
        let forgetting = ewcScore + replayScore * 0.3;
        let bandwidth = IntAsDouble(trial::ReplayBufferSize) / 65536.0 * 100.0;
        let latency = 2.0 + IntAsDouble(trial::MaxClusters) / 64.0;
        let noveltyRate = 0.15 + hammingScore * 0.1;

        let objective = taskLoss + 2.0 * forgetting + 0.2 * bandwidth / 1000.0 + 0.1 * latency / 100.0;

        return AutoMLTrial(
            trial::TrialId, trial::EWCLambda, trial::ReplayBufferSize,
            trial::HammingThreshold, trial::LearningRate, trial::AnchorAlpha,
            trial::TopKRatio, trial::MaxClusters,
            objective, taskLoss, forgetting, bandwidth, latency, noveltyRate,
            "completed", 100
        );
    }

    // =========================================================================
    // Search Space Sampling
    // =========================================================================

    function SampleConfig(
        config : AutoMLRunConfig,
        seed : Int
    ) : (Double, Int, Int, Double, Double, Double, Int) {
        // LCG random number generator
        let s1 = (seed * 1664525 + 1013904223) &&& 0x7FFFFFFF;
        let s2 = (s1 * 1664525 + 1013904223) &&& 0x7FFFFFFF;
        let s3 = (s2 * 1664525 + 1013904223) &&& 0x7FFFFFFF;
        let s4 = (s3 * 1664525 + 1013904223) &&& 0x7FFFFFFF;
        let s5 = (s4 * 1664525 + 1013904223) &&& 0x7FFFFFFF;
        let s6 = (s5 * 1664525 + 1013904223) &&& 0x7FFFFFFF;
        let s7 = (s6 * 1664525 + 1013904223) &&& 0x7FFFFFFF;

        // EWC lambda (log scale)
        let logMin = Log(config::EWCLambdaMin);
        let logMax = Log(config::EWCLambdaMax);
        let ewcLambda = E() ^ (logMin + IntAsDouble(s1 % 1000) / 1000.0 * (logMax - logMin));

        // Replay buffer size (log scale, powers of 2)
        let bufferOptions = [256, 512, 1024, 2048, 4096, 8192, 16384, 32768, 65536];
        let replayBufferSize = bufferOptions[s2 % Length(bufferOptions)];

        // Hamming threshold
        let hammingThreshold = config::HammingThreshMin +
            (s3 % (config::HammingThreshMax - config::HammingThreshMin + 1));

        // Learning rate (log scale)
        let lrLogMin = Log(config::LRMin);
        let lrLogMax = Log(config::LRMax);
        let learningRate = E() ^ (lrLogMin + IntAsDouble(s4 % 1000) / 1000.0 * (lrLogMax - lrLogMin));

        // Anchor alpha
        let anchorAlpha = config::AnchorAlphaMin +
            IntAsDouble(s5 % 1000) / 1000.0 * (config::AnchorAlphaMax - config::AnchorAlphaMin);

        // Top-K ratio
        let topKRatio = config::TopKMin +
            IntAsDouble(s6 % 1000) / 1000.0 * (config::TopKMax - config::TopKMin);

        // Max clusters
        let clusterOptions = [8, 16, 32, 64, 128, 256];
        let maxClusters = clusterOptions[s7 % Length(clusterOptions)];

        return (ewcLambda, replayBufferSize, hammingThreshold, learningRate,
                anchorAlpha, topKRatio, maxClusters);
    }

    // =========================================================================
    // Bayesian Optimization (simplified)
    // =========================================================================

    function BayesianSuggest(
        completedTrials : AutoMLTrial[],
        config : AutoMLRunConfig,
        seed : Int
    ) : (Double, Int, Int, Double, Double, Double, Int) {
        if Length(completedTrials) < 10 {
            return SampleConfig(config, seed);
        }

        // Find best trial
        mutable bestTrial = completedTrials[0];
        for trial in completedTrials {
            if trial::ObjectiveValue < bestTrial::ObjectiveValue {
                set bestTrial = trial;
            }
        }

        // Perturb best configuration
        let s = (seed * 1664525 + 1013904223) &&& 0x7FFFFFFF;
        let perturbation = IntAsDouble(s % 200) / 1000.0 - 0.1;

        let newLambda = MaxD(config::EWCLambdaMin,
            MinD(config::EWCLambdaMax, bestTrial::EWCLambda * (1.0 + perturbation)));

        let newLR = MaxD(config::LRMin,
            MinD(config::LRMax, bestTrial::LearningRate * (1.0 + perturbation)));

        let newAlpha = MaxD(0.0, MinD(1.0, bestTrial::AnchorAlpha + perturbation * 0.5));

        return (newLambda, bestTrial::ReplayBufferSize, bestTrial::HammingThreshold,
                newLR, newAlpha, bestTrial::TopKRatio, bestTrial::MaxClusters);
    }

    // =========================================================================
    // AutoML Run
    // =========================================================================

    operation RunAutoMLSearch(config : AutoMLRunConfig) : AutoMLTrial {
        Message("[AutoML] Starting hyperparameter search");
        Message($"[AutoML] Strategy: {config::Strategy} | Trials: {config::NTrials}");
        Message($"[AutoML] Search space:");
        Message($"  EWC Lambda: [{config::EWCLambdaMin}, {config::EWCLambdaMax}]");
        Message($"  Replay Buffer: [{config::ReplayBufferMin}, {config::ReplayBufferMax}]");
        Message($"  Hamming Threshold: [{config::HammingThreshMin}, {config::HammingThreshMax}]");
        Message($"  Learning Rate: [{config::LRMin}, {config::LRMax}]");
        Message($"  Anchor Alpha: [{config::AnchorAlphaMin}, {config::AnchorAlphaMax}]");
        Message($"  Top-K Ratio: [{config::TopKMin}, {config::TopKMax}]");
        Message($"  Max Clusters: [{config::MaxClustersMin}, {config::MaxClustersMax}]");

        mutable completedTrials = new AutoMLTrial[0];
        mutable bestTrial = CreateTrial(0, 400.0, 1024, 24, 0.001, 0.5, 0.1, 64);
        mutable bestObjective = 1e10;

        // Run trials
        let nTrialsToRun = MinI(config::NTrials, 20);  // Cap for simulation

        for trialId in 0 .. nTrialsToRun - 1 {
            // Sample configuration
            let (ewcLambda, replayBufferSize, hammingThreshold, learningRate,
                 anchorAlpha, topKRatio, maxClusters) =
                if trialId < 10 {
                    SampleConfig(config, config::Seed + trialId)
                } else {
                    BayesianSuggest(completedTrials, config, config::Seed + trialId)
                };

            // Create and evaluate trial
            let trial = CreateTrial(
                trialId, ewcLambda, replayBufferSize, hammingThreshold,
                learningRate, anchorAlpha, topKRatio, maxClusters
            );
            let evaluated = EvaluateTrial(trial);

            set completedTrials += [evaluated];

            // Update best
            if evaluated::ObjectiveValue < bestObjective {
                set bestObjective = evaluated::ObjectiveValue;
                set bestTrial = evaluated;
            }

            if trialId % 5 == 0 {
                Message($"[AutoML] Trial {trialId}: obj={evaluated::ObjectiveValue:.4f} " +
                        $"best={bestObjective:.4f} " +
                        $"lambda={ewcLambda:.1f} lr={learningRate:.6f}");
            }
        }

        Message($"\n[AutoML] Search complete after {nTrialsToRun} trials");
        Message($"[AutoML] Best objective: {bestObjective:.4f}");
        Message($"[AutoML] Best configuration:");
        Message($"  EWC Lambda: {bestTrial::EWCLambda:.2f}");
        Message($"  Replay Buffer: {bestTrial::ReplayBufferSize}");
        Message($"  Hamming Threshold: {bestTrial::HammingThreshold}");
        Message($"  Learning Rate: {bestTrial::LearningRate:.6f}");
        Message($"  Anchor Alpha: {bestTrial::AnchorAlpha:.3f}");
        Message($"  Top-K Ratio: {bestTrial::TopKRatio:.3f}");
        Message($"  Max Clusters: {bestTrial::MaxClusters}");
        Message($"  Task Loss: {bestTrial::TaskLoss:.4f}");
        Message($"  Forgetting: {bestTrial::Forgetting:.4f}");
        Message($"  Novelty Rate: {bestTrial::NoveltyRate:.3f}");

        return bestTrial;
    }

    // =========================================================================
    // Hyperparameter Sensitivity Analysis
    // =========================================================================

    operation RunSensitivityAnalysis(
        bestTrial : AutoMLTrial,
        config : AutoMLRunConfig
    ) : Unit {
        Message("\n[AutoML] Running sensitivity analysis...");

        // Vary EWC lambda
        Message("[AutoML] EWC Lambda sensitivity:");
        let lambdaValues = [10.0, 50.0, 100.0, 200.0, 400.0, 800.0, 1600.0];
        for lambda in lambdaValues {
            let trial = EvaluateTrial(CreateTrial(
                0, lambda, bestTrial::ReplayBufferSize, bestTrial::HammingThreshold,
                bestTrial::LearningRate, bestTrial::AnchorAlpha,
                bestTrial::TopKRatio, bestTrial::MaxClusters
            ));
            Message($"  lambda={lambda:.0f}: obj={trial::ObjectiveValue:.4f} " +
                    $"forgetting={trial::Forgetting:.4f}");
        }

        // Vary Hamming threshold
        Message("[AutoML] Hamming Threshold sensitivity:");
        let threshValues = [4, 8, 12, 16, 20, 24, 32, 48, 64];
        for thresh in threshValues {
            let trial = EvaluateTrial(CreateTrial(
                0, bestTrial::EWCLambda, bestTrial::ReplayBufferSize, thresh,
                bestTrial::LearningRate, bestTrial::AnchorAlpha,
                bestTrial::TopKRatio, bestTrial::MaxClusters
            ));
            Message($"  threshold={thresh}: obj={trial::ObjectiveValue:.4f} " +
                    $"noveltyRate={trial::NoveltyRate:.3f}");
        }

        Message("[AutoML] Sensitivity analysis complete");
    }

    // =========================================================================
    // AutoML Entry Point
    // =========================================================================

    @EntryPoint()
    operation RunAutoML() : Unit {
        Message("╔══════════════════════════════════════════════════════════════╗");
        Message("║         Windows-AGI-Mesh AutoML Optimizer v1.0.0            ║");
        Message("║  Bayesian Hyperparameter Search for Continual Learning       ║");
        Message("╚══════════════════════════════════════════════════════════════╝");

        let config = DefaultAutoMLRunConfig();
        let bestTrial = RunAutoMLSearch(config);
        RunSensitivityAnalysis(bestTrial, config);

        Message("\n[AutoML] Hyperparameter optimization complete.");
        Message("[AutoML] Best configuration ready for deployment.");
    }
}