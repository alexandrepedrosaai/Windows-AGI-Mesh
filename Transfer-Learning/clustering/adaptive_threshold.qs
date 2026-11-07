// =============================================================================
// adaptive_threshold.qs
// Q# adaptive threshold management for dynamic Hamming-based clustering
// Implements multiple threshold adaptation strategies for the replay pipeline
// Namespace: SiameseTwinAI.Clustering
// =============================================================================

namespace SiameseTwinAI.Clustering {

    open Microsoft.Quantum.Arrays;
    open Microsoft.Quantum.Convert;
    open Microsoft.Quantum.Intrinsic;
    open Microsoft.Quantum.Math;
    open Microsoft.Quantum.Diagnostics;

    // =========================================================================
    // Threshold Configuration
    // =========================================================================

    /// Configuration for adaptive threshold controller
    newtype ThresholdConfig = (
        MinThreshold      : Int,
        MaxThreshold      : Int,
        InitialThreshold  : Int,
        AdaptRate         : Double,
        TargetNoveltyRate : Double,
        WindowSize        : Int,
        Strategy          : Int      // 0=PID, 1=Percentile, 2=EMA, 3=Bayesian
    );

    /// Default threshold configuration
    function DefaultThresholdConfig() : ThresholdConfig {
        return ThresholdConfig(
            4,      // MinThreshold
            64,     // MaxThreshold
            24,     // InitialThreshold
            0.05,   // AdaptRate
            0.15,   // TargetNoveltyRate (15% of samples should be novel)
            100,    // WindowSize
            2       // Strategy: EMA
        );
    }

    /// Strict threshold configuration (fewer novel samples)
    function StrictThresholdConfig() : ThresholdConfig {
        return ThresholdConfig(
            4, 32, 12, 0.02, 0.05, 200, 1
        );
    }

    /// Exploratory threshold configuration (more novel samples)
    function ExploratoryThresholdConfig() : ThresholdConfig {
        return ThresholdConfig(
            8, 128, 32, 0.10, 0.30, 50, 0
        );
    }

    // =========================================================================
    // Threshold State
    // =========================================================================

    /// State of the adaptive threshold controller
    newtype ThresholdState = (
        CurrentThreshold  : Int,
        NoveltyHistory    : Int[],
        DistanceHistory   : Int[],
        ErrorIntegral     : Double,
        LastError         : Double,
        UpdateCount       : Int,
        Config            : ThresholdConfig
    );

    /// Initialize threshold state with default config
    function InitThresholdState(config : ThresholdConfig) : ThresholdState {
        return ThresholdState(
            config::InitialThreshold,
            new Int[0],
            new Int[0],
            0.0,
            0.0,
            0,
            config
        );
    }

    // =========================================================================
    // Strategy 0: PID Controller
    // =========================================================================

    /// PID-based threshold adaptation
    /// Adjusts threshold to maintain target novelty rate
    function PIDThresholdUpdate(
        state : ThresholdState,
        currentNoveltyRate : Double,
        kp : Double,
        ki : Double,
        kd : Double
    ) : ThresholdState {
        let config = state::Config;
        let error = currentNoveltyRate - config::TargetNoveltyRate;
        let newIntegral = state::ErrorIntegral + error;
        let derivative = error - state::LastError;

        // PID output: positive error → increase threshold (allow more novelty)
        let pidOutput = kp * error + ki * newIntegral + kd * derivative;
        let rawThreshold = IntAsDouble(state::CurrentThreshold) + pidOutput;
        let newThreshold = MaxI(
            config::MinThreshold,
            MinI(config::MaxThreshold, Ceiling(rawThreshold))
        );

        return ThresholdState(
            newThreshold,
            state::NoveltyHistory,
            state::DistanceHistory,
            newIntegral,
            error,
            state::UpdateCount + 1,
            config
        );
    }

    /// Default PID parameters for threshold control
    function DefaultPIDParams() : (Double, Double, Double) {
        return (2.0, 0.1, 0.5);  // (Kp, Ki, Kd)
    }

    // =========================================================================
    // Strategy 1: Percentile-Based Threshold
    // =========================================================================

    /// Compute threshold as a percentile of recent distance distribution
    function PercentileThresholdUpdate(
        state : ThresholdState,
        newDistance : Int,
        percentile : Double
    ) : ThresholdState {
        let config = state::Config;
        let windowSize = config::WindowSize;

        // Add new distance to history
        mutable history = state::DistanceHistory + [newDistance];
        if Length(history) > windowSize {
            set history = history[Length(history) - windowSize .. Length(history) - 1];
        }

        // Compute percentile threshold
        let newThreshold = ThresholdPercentile(history, percentile);
        let clamped = MaxI(config::MinThreshold, MinI(config::MaxThreshold, newThreshold));

        return ThresholdState(
            clamped,
            state::NoveltyHistory,
            history,
            state::ErrorIntegral,
            state::LastError,
            state::UpdateCount + 1,
            config
        );
    }

    /// Compute threshold as 75th percentile of distance history
    function Percentile75Threshold(distances : Int[]) : Int {
        return ThresholdPercentile(distances, 0.75);
    }

    /// Compute threshold as 90th percentile of distance history
    function Percentile90Threshold(distances : Int[]) : Int {
        return ThresholdPercentile(distances, 0.90);
    }

    // =========================================================================
    // Strategy 2: Exponential Moving Average (EMA)
    // =========================================================================

    /// EMA-based threshold adaptation
    function EMAThresholdUpdate(
        state : ThresholdState,
        newDistance : Int
    ) : ThresholdState {
        let config = state::Config;
        let alpha = config::AdaptRate;
        let current = IntAsDouble(state::CurrentThreshold);
        let newVal = IntAsDouble(newDistance);
        let ema = (1.0 - alpha) * current + alpha * newVal;
        let newThreshold = MaxI(
            config::MinThreshold,
            MinI(config::MaxThreshold, Ceiling(ema))
        );

        mutable history = state::DistanceHistory + [newDistance];
        if Length(history) > config::WindowSize {
            set history = history[Length(history) - config::WindowSize .. Length(history) - 1];
        }

        return ThresholdState(
            newThreshold,
            state::NoveltyHistory,
            history,
            state::ErrorIntegral,
            state::LastError,
            state::UpdateCount + 1,
            config
        );
    }

    /// Double EMA (DEMA) for faster adaptation
    function DEMAThresholdUpdate(
        state : ThresholdState,
        newDistance : Int,
        ema1 : Double,
        ema2 : Double
    ) : (ThresholdState, Double, Double) {
        let config = state::Config;
        let alpha = config::AdaptRate;
        let x = IntAsDouble(newDistance);
        let newEma1 = (1.0 - alpha) * ema1 + alpha * x;
        let newEma2 = (1.0 - alpha) * ema2 + alpha * newEma1;
        let dema = 2.0 * newEma1 - newEma2;
        let newThreshold = MaxI(
            config::MinThreshold,
            MinI(config::MaxThreshold, Ceiling(dema))
        );
        mutable history = state::DistanceHistory + [newDistance];
        if Length(history) > config::WindowSize {
            set history = history[Length(history) - config::WindowSize .. Length(history) - 1];
        }
        let newState = ThresholdState(
            newThreshold,
            state::NoveltyHistory,
            history,
            state::ErrorIntegral,
            state::LastError,
            state::UpdateCount + 1,
            config
        );
        return (newState, newEma1, newEma2);
    }

    // =========================================================================
    // Strategy 3: Bayesian Adaptive Threshold
    // =========================================================================

    /// Bayesian threshold update using Beta distribution conjugate prior
    /// Models novelty rate as Beta(alpha, beta) and updates from observations
    newtype BayesianThresholdState = (
        Alpha     : Double,   // Beta distribution alpha (novel observations)
        Beta      : Double,   // Beta distribution beta (non-novel observations)
        BaseState : ThresholdState
    );

    /// Initialize Bayesian threshold state
    function InitBayesianState(
        config : ThresholdConfig,
        priorAlpha : Double,
        priorBeta : Double
    ) : BayesianThresholdState {
        return BayesianThresholdState(
            priorAlpha,
            priorBeta,
            InitThresholdState(config)
        );
    }

    /// Update Bayesian threshold state with new observation
    function BayesianThresholdUpdate(
        state : BayesianThresholdState,
        isNovelObservation : Bool,
        targetNoveltyRate : Double
    ) : BayesianThresholdState {
        let newAlpha = if isNovelObservation { state::Alpha + 1.0 } else { state::Alpha };
        let newBeta = if isNovelObservation { state::Beta } else { state::Beta + 1.0 };

        // Posterior mean of novelty rate
        let posteriorMean = newAlpha / (newAlpha + newBeta);

        // Adjust threshold based on posterior vs target
        let baseState = state::BaseState;
        let config = baseState::Config;
        let error = posteriorMean - targetNoveltyRate;
        let adjustment = Ceiling(error * IntAsDouble(config::MaxThreshold - config::MinThreshold));
        let newThreshold = MaxI(
            config::MinThreshold,
            MinI(config::MaxThreshold, baseState::CurrentThreshold + adjustment)
        );

        let newBaseState = ThresholdState(
            newThreshold,
            baseState::NoveltyHistory,
            baseState::DistanceHistory,
            baseState::ErrorIntegral,
            baseState::LastError,
            baseState::UpdateCount + 1,
            config
        );

        return BayesianThresholdState(newAlpha, newBeta, newBaseState);
    }

    /// Get current novelty rate estimate from Bayesian state
    function BayesianNoveltyEstimate(state : BayesianThresholdState) : Double {
        return state::Alpha / (state::Alpha + state::Beta);
    }

    /// Get 95% credible interval for novelty rate
    function BayesianCredibleInterval(
        state : BayesianThresholdState
    ) : (Double, Double) {
        let a = state::Alpha;
        let b = state::Beta;
        let mean = a / (a + b);
        let variance = (a * b) / ((a + b) * (a + b) * (a + b + 1.0));
        let stdDev = Sqrt(variance);
        // Approximate 95% CI using normal approximation
        return (MaxD(0.0, mean - 1.96 * stdDev), MinD(1.0, mean + 1.96 * stdDev));
    }

    // =========================================================================
    // Multi-Cluster Threshold Management
    // =========================================================================

    /// Per-cluster threshold state
    newtype ClusterThresholdState = (
        ClusterId : Int,
        State     : ThresholdState
    );

    /// Initialize per-cluster threshold states
    function InitClusterThresholds(
        clusterIds : Int[],
        config : ThresholdConfig
    ) : ClusterThresholdState[] {
        mutable states = new ClusterThresholdState[Length(clusterIds)];
        for i in 0 .. Length(clusterIds) - 1 {
            set states w/= i <- ClusterThresholdState(
                clusterIds[i],
                InitThresholdState(config)
            );
        }
        return states;
    }

    /// Update threshold for a specific cluster
    function UpdateClusterThresholdState(
        states : ClusterThresholdState[],
        clusterId : Int,
        newDistance : Int
    ) : ClusterThresholdState[] {
        mutable result = states;
        for i in 0 .. Length(states) - 1 {
            if states[i]::ClusterId == clusterId {
                let updated = EMAThresholdUpdate(states[i]::State, newDistance);
                set result w/= i <- ClusterThresholdState(clusterId, updated);
            }
        }
        return result;
    }

    /// Get threshold for a specific cluster
    function GetClusterThreshold(
        states : ClusterThresholdState[],
        clusterId : Int,
        defaultThreshold : Int
    ) : Int {
        for s in states {
            if s::ClusterId == clusterId {
                return s::State::CurrentThreshold;
            }
        }
        return defaultThreshold;
    }

    // =========================================================================
    // Global Threshold Adaptation
    // =========================================================================

    /// Compute global threshold from all cluster thresholds (weighted mean)
    function GlobalThreshold(
        clusterStates : ClusterThresholdState[],
        clusterSizes : Int[]
    ) : Int {
        if Length(clusterStates) == 0 {
            return 24;
        }
        mutable weightedSum = 0.0;
        mutable totalWeight = 0.0;
        for i in 0 .. Length(clusterStates) - 1 {
            let w = IntAsDouble(clusterSizes[i]);
            set weightedSum += w * IntAsDouble(clusterStates[i]::State::CurrentThreshold);
            set totalWeight += w;
        }
        if totalWeight <= 0.0 {
            return 24;
        }
        return Ceiling(weightedSum / totalWeight);
    }

    /// Compute global threshold as median of cluster thresholds
    function MedianThreshold(clusterStates : ClusterThresholdState[]) : Int {
        if Length(clusterStates) == 0 {
            return 24;
        }
        mutable thresholds = new Int[Length(clusterStates)];
        for i in 0 .. Length(clusterStates) - 1 {
            set thresholds w/= i <- clusterStates[i]::State::CurrentThreshold;
        }
        // Sort thresholds
        let n = Length(thresholds);
        mutable sorted = thresholds;
        for i in 1 .. n - 1 {
            let key = sorted[i];
            mutable j = i - 1;
            while j >= 0 and sorted[j] > key {
                set sorted w/= j + 1 <- sorted[j];
                set j -= 1;
            }
            set sorted w/= j + 1 <- key;
        }
        return sorted[n / 2];
    }

    // =========================================================================
    // Threshold Scheduling
    // =========================================================================

    /// Cosine annealing schedule for threshold
    function CosineAnnealingThreshold(
        step : Int,
        totalSteps : Int,
        minThreshold : Int,
        maxThreshold : Int
    ) : Int {
        let t = IntAsDouble(step) / IntAsDouble(totalSteps);
        let cosVal = (1.0 + Cos(PI() * t)) / 2.0;
        let range = IntAsDouble(maxThreshold - minThreshold);
        return minThreshold + Ceiling(cosVal * range);
    }

    /// Linear warmup then cosine decay schedule
    function WarmupCosineThreshold(
        step : Int,
        warmupSteps : Int,
        totalSteps : Int,
        minThreshold : Int,
        maxThreshold : Int
    ) : Int {
        if step < warmupSteps {
            // Linear warmup
            let t = IntAsDouble(step) / IntAsDouble(warmupSteps);
            return minThreshold + Ceiling(t * IntAsDouble(maxThreshold - minThreshold));
        } else {
            // Cosine decay
            let adjustedStep = step - warmupSteps;
            let adjustedTotal = totalSteps - warmupSteps;
            return CosineAnnealingThreshold(adjustedStep, adjustedTotal, minThreshold, maxThreshold);
        }
    }

    /// Step decay schedule for threshold
    function StepDecayThreshold(
        step : Int,
        initialThreshold : Int,
        decayFactor : Double,
        stepSize : Int
    ) : Int {
        let numDecays = step / stepSize;
        mutable threshold = IntAsDouble(initialThreshold);
        for _ in 0 .. numDecays - 1 {
            set threshold *= decayFactor;
        }
        return MaxI(4, Ceiling(threshold));
    }

    // =========================================================================
    // Threshold Validation and Diagnostics
    // =========================================================================

    /// Validate threshold is within acceptable bounds
    function ValidateThreshold(
        threshold : Int,
        config : ThresholdConfig
    ) : Bool {
        return threshold >= config::MinThreshold and threshold <= config::MaxThreshold;
    }

    /// Clamp threshold to valid range
    function ClampThreshold(
        threshold : Int,
        config : ThresholdConfig
    ) : Int {
        return MaxI(config::MinThreshold, MinI(config::MaxThreshold, threshold));
    }

    /// Compute novelty rate from history
    function ComputeNoveltyRate(
        noveltyHistory : Int[],
        windowSize : Int
    ) : Double {
        if Length(noveltyHistory) == 0 {
            return 0.0;
        }
        let window = MinI(windowSize, Length(noveltyHistory));
        let start = Length(noveltyHistory) - window;
        mutable novelCount = 0;
        for i in start .. Length(noveltyHistory) - 1 {
            set novelCount += noveltyHistory[i];
        }
        return IntAsDouble(novelCount) / IntAsDouble(window);
    }

    /// Compute threshold stability (variance of recent threshold values)
    function ThresholdStability(thresholdHistory : Int[]) : Double {
        if Length(thresholdHistory) <= 1 {
            return 0.0;
        }
        let n = Length(thresholdHistory);
        mutable sum = 0;
        for t in thresholdHistory {
            set sum += t;
        }
        let mean = IntAsDouble(sum) / IntAsDouble(n);
        mutable variance = 0.0;
        for t in thresholdHistory {
            let diff = IntAsDouble(t) - mean;
            set variance += diff * diff;
        }
        return variance / IntAsDouble(n);
    }

    // =========================================================================
    // Threshold Logging Operations
    // =========================================================================

    /// Log threshold update event
    operation LogThresholdUpdate(
        clusterId : Int,
        oldThreshold : Int,
        newThreshold : Int,
        noveltyRate : Double,
        strategy : String
    ) : Unit {
        Message($"[Threshold] Cluster {clusterId}: {oldThreshold} → {newThreshold} " +
                $"(noveltyRate={noveltyRate}, strategy={strategy})");
    }

    /// Log global threshold state
    operation LogGlobalThresholdState(
        globalThreshold : Int,
        noveltyRate : Double,
        targetRate : Double,
        step : Int
    ) : Unit {
        let error = noveltyRate - targetRate;
        Message($"[Global Threshold] step={step} threshold={globalThreshold} " +
                $"noveltyRate={noveltyRate} target={targetRate} error={error}");
    }

    /// Log threshold schedule
    operation LogThresholdSchedule(
        step : Int,
        totalSteps : Int,
        threshold : Int,
        scheduleName : String
    ) : Unit {
        let progress = IntAsDouble(step) / IntAsDouble(totalSteps) * 100.0;
        Message($"[Schedule:{scheduleName}] step={step}/{totalSteps} ({progress}%) threshold={threshold}");
    }

    // =========================================================================
    // Dispatch: Select and Apply Threshold Strategy
    // =========================================================================

    /// Apply the configured threshold strategy to update state
    function ApplyThresholdStrategy(
        state : ThresholdState,
        newDistance : Int,
        isNovel : Bool,
        currentNoveltyRate : Double
    ) : ThresholdState {
        let strategy = state::Config::Strategy;
        if strategy == 0 {
            let (kp, ki, kd) = DefaultPIDParams();
            return PIDThresholdUpdate(state, currentNoveltyRate, kp, ki, kd);
        } elif strategy == 1 {
            return PercentileThresholdUpdate(state, newDistance, 0.75);
        } elif strategy == 2 {
            return EMAThresholdUpdate(state, newDistance);
        } else {
            // Default to EMA
            return EMAThresholdUpdate(state, newDistance);
        }
    }

    /// Batch threshold update from a window of observations
    function BatchThresholdUpdate(
        state : ThresholdState,
        distances : Int[],
        novelFlags : Bool[]
    ) : ThresholdState {
        mutable currentState = state;
        let n = MinI(Length(distances), Length(novelFlags));
        mutable novelCount = 0;
        for i in 0 .. n - 1 {
            if novelFlags[i] {
                set novelCount += 1;
            }
        }
        let noveltyRate = if n > 0 { IntAsDouble(novelCount) / IntAsDouble(n) } else { 0.0 };
        for i in 0 .. n - 1 {
            set currentState = ApplyThresholdStrategy(
                currentState,
                distances[i],
                novelFlags[i],
                noveltyRate
            );
        }
        return currentState;
    }

    // =========================================================================
    // Threshold Export for AutoML
    // =========================================================================

    /// Export threshold state as feature vector for AutoML
    function ThresholdStateToFeatures(state : ThresholdState) : Double[] {
        let config = state::Config;
        let noveltyRate = ComputeNoveltyRate(state::NoveltyHistory, config::WindowSize);
        let stability = ThresholdStability(state::DistanceHistory);
        return [
            IntAsDouble(state::CurrentThreshold),
            IntAsDouble(config::MinThreshold),
            IntAsDouble(config::MaxThreshold),
            config::AdaptRate,
            config::TargetNoveltyRate,
            noveltyRate,
            stability,
            state::ErrorIntegral,
            state::LastError,
            IntAsDouble(state::UpdateCount)
        ];
    }

    /// Suggest threshold from AutoML recommendation
    function ApplyAutoMLThreshold(
        state : ThresholdState,
        recommendedThreshold : Int
    ) : ThresholdState {
        let config = state::Config;
        let clamped = ClampThreshold(recommendedThreshold, config);
        return ThresholdState(
            clamped,
            state::NoveltyHistory,
            state::DistanceHistory,
            state::ErrorIntegral,
            state::LastError,
            state::UpdateCount + 1,
            config
        );
    }
}
