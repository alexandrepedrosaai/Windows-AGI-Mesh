// =============================================================================
// novelty_detector.qs
// Q# Novelty Detection for SafaSensor replay clustering pipeline
// Implements statistical, distance-based, and ensemble novelty detection
// Namespace: SiameseTwinAI.Clustering
// =============================================================================

namespace SiameseTwinAI.Clustering {

    open Microsoft.Quantum.Arrays;
    open Microsoft.Quantum.Convert;
    open Microsoft.Quantum.Intrinsic;
    open Microsoft.Quantum.Math;
    open Microsoft.Quantum.Diagnostics;

    // =========================================================================
    // Novelty Detector Configuration
    // =========================================================================

    /// Configuration for the novelty detection subsystem
    newtype NoveltyConfig = (
        Method              : Int,      // 0=Distance, 1=Statistical, 2=Isolation, 3=Ensemble
        DistanceThreshold   : Int,
        StatisticalSigma    : Double,
        WindowSize          : Int,
        MinSamplesForModel  : Int,
        EnsembleWeights     : Double[],
        AdaptiveThreshold   : Bool,
        ConfidenceLevel     : Double
    );

    /// Default novelty configuration
    function DefaultNoveltyConfig() : NoveltyConfig {
        return NoveltyConfig(
            3,      // Ensemble method
            24,     // DistanceThreshold
            3.0,    // StatisticalSigma (3-sigma rule)
            500,    // WindowSize
            10,     // MinSamplesForModel
            [0.4, 0.3, 0.3],  // EnsembleWeights [distance, statistical, isolation]
            true,   // AdaptiveThreshold
            0.95    // ConfidenceLevel
        );
    }

    // =========================================================================
    // Novelty Score Types
    // =========================================================================

    /// Detailed novelty assessment result
    newtype NoveltyResult = (
        IsNovel           : Bool,
        NoveltyScore      : Double,
        DistanceScore     : Double,
        StatisticalScore  : Double,
        IsolationScore    : Double,
        EnsembleScore     : Double,
        NearestClusterId  : Int,
        NearestDistance   : Int,
        Confidence        : Double
    );

    /// Create a novelty result indicating a non-novel sample
    function NonNovelResult(
        nearestClusterId : Int,
        nearestDistance : Int
    ) : NoveltyResult {
        return NoveltyResult(
            false, 0.0, 0.0, 0.0, 0.0, 0.0,
            nearestClusterId, nearestDistance, 1.0
        );
    }

    /// Create a novelty result indicating a novel sample
    function NovelResult(
        score : Double,
        nearestClusterId : Int,
        nearestDistance : Int,
        confidence : Double
    ) : NoveltyResult {
        return NoveltyResult(
            true, score, score, score, score, score,
            nearestClusterId, nearestDistance, confidence
        );
    }

    // =========================================================================
    // Method 0: Distance-Based Novelty Detection
    // =========================================================================

    /// Detect novelty based on minimum Hamming distance to cluster centroids
    function DistanceBasedNovelty(
        sample : Int[],
        clusters : ReplayCluster[],
        threshold : Int
    ) : NoveltyResult {
        if Length(clusters) == 0 {
            return NoveltyResult(true, 1.0, 1.0, 0.0, 0.0, 1.0, -1, 2147483647, 0.5);
        }

        let (nearestIdx, nearestDist) = AssignReplayClusterWithDistance(sample, clusters);
        let nearestId = if nearestIdx >= 0 { clusters[nearestIdx]::ClusterId } else { -1 };

        // Normalize distance score to [0, 1]
        let maxPossibleDist = 64 * Length(sample);
        let distScore = IntAsDouble(nearestDist) / IntAsDouble(maxPossibleDist);
        let isNovel = nearestDist > threshold;

        // Confidence based on margin from threshold
        let margin = AbsI(nearestDist - threshold);
        let confidence = MinD(1.0, IntAsDouble(margin) / IntAsDouble(threshold));

        return NoveltyResult(
            isNovel,
            distScore,
            distScore,
            0.0,
            0.0,
            distScore,
            nearestId,
            nearestDist,
            confidence
        );
    }

    /// Multi-threshold distance novelty (uses per-cluster thresholds)
    function MultiThresholdNovelty(
        sample : Int[],
        clusters : ReplayCluster[]
    ) : NoveltyResult {
        if Length(clusters) == 0 {
            return NoveltyResult(true, 1.0, 1.0, 0.0, 0.0, 1.0, -1, 2147483647, 0.5);
        }

        mutable bestIdx = 0;
        mutable bestDist = HammingDistance(sample, clusters[0]::Centroid);
        for i in 1 .. Length(clusters) - 1 {
            let d = HammingDistance(sample, clusters[i]::Centroid);
            if d < bestDist {
                set bestDist = d;
                set bestIdx = i;
            }
        }

        let clusterThreshold = clusters[bestIdx]::Threshold;
        let isNovel = bestDist > clusterThreshold;
        let maxDist = 64 * Length(sample);
        let score = IntAsDouble(bestDist) / IntAsDouble(maxDist);

        return NoveltyResult(
            isNovel, score, score, 0.0, 0.0, score,
            clusters[bestIdx]::ClusterId, bestDist,
            MinD(1.0, IntAsDouble(AbsI(bestDist - clusterThreshold)) / IntAsDouble(clusterThreshold))
        );
    }

    // =========================================================================
    // Method 1: Statistical Novelty Detection
    // =========================================================================

    /// Statistical model of distance distribution
    newtype DistanceModel = (
        Mean     : Double,
        StdDev   : Double,
        Min      : Int,
        Max      : Int,
        Count    : Int
    );

    /// Initialize distance model from a set of distances
    function InitDistanceModel(distances : Int[]) : DistanceModel {
        if Length(distances) == 0 {
            return DistanceModel(24.0, 8.0, 0, 64, 0);
        }
        let n = Length(distances);
        mutable sum = 0;
        mutable minD = distances[0];
        mutable maxD = distances[0];
        for d in distances {
            set sum += d;
            if d < minD { set minD = d; }
            if d > maxD { set maxD = d; }
        }
        let mean = IntAsDouble(sum) / IntAsDouble(n);
        mutable variance = 0.0;
        for d in distances {
            let diff = IntAsDouble(d) - mean;
            set variance += diff * diff;
        }
        let stdDev = if n > 1 { Sqrt(variance / IntAsDouble(n - 1)) } else { 0.0 };
        return DistanceModel(mean, stdDev, minD, maxD, n);
    }

    /// Update distance model with a new observation (online update)
    function UpdateDistanceModel(
        model : DistanceModel,
        newDistance : Int
    ) : DistanceModel {
        let n = model::Count + 1;
        let x = IntAsDouble(newDistance);
        let oldMean = model::Mean;
        let newMean = oldMean + (x - oldMean) / IntAsDouble(n);
        // Welford's online variance
        let oldM2 = model::StdDev * model::StdDev * IntAsDouble(model::Count);
        let newM2 = oldM2 + (x - oldMean) * (x - newMean);
        let newStdDev = if n > 1 { Sqrt(newM2 / IntAsDouble(n - 1)) } else { 0.0 };
        return DistanceModel(
            newMean,
            newStdDev,
            MinI(model::Min, newDistance),
            MaxI(model::Max, newDistance),
            n
        );
    }

    /// Compute z-score for a distance observation
    function ZScore(distance : Int, model : DistanceModel) : Double {
        if model::StdDev <= 0.0 {
            return 0.0;
        }
        return (IntAsDouble(distance) - model::Mean) / model::StdDev;
    }

    /// Statistical novelty detection using z-score threshold
    function StatisticalNovelty(
        sample : Int[],
        clusters : ReplayCluster[],
        model : DistanceModel,
        sigmaThreshold : Double
    ) : NoveltyResult {
        if Length(clusters) == 0 or model::Count < 10 {
            return DistanceBasedNovelty(sample, clusters, 24);
        }

        let (nearestIdx, nearestDist) = AssignReplayClusterWithDistance(sample, clusters);
        let nearestId = if nearestIdx >= 0 { clusters[nearestIdx]::ClusterId } else { -1 };

        let z = ZScore(nearestDist, model);
        let isNovel = z > sigmaThreshold;

        // Convert z-score to [0, 1] score using sigmoid
        let score = 1.0 / (1.0 + E() ^ (-z + sigmaThreshold));
        let confidence = MinD(1.0, AbsD(z - sigmaThreshold) / sigmaThreshold);

        return NoveltyResult(
            isNovel, score, 0.0, score, 0.0, score,
            nearestId, nearestDist, confidence
        );
    }

    // =========================================================================
    // Method 2: Isolation-Based Novelty Detection
    // =========================================================================

    /// Isolation tree node
    newtype IsolationNode = (
        IsLeaf      : Bool,
        SplitBit    : Int,      // Bit position used for split
        SplitWord   : Int,      // Word index in hash vector
        LeftChild   : Int,      // Index into node array (-1 if leaf)
        RightChild  : Int,
        Depth       : Int,
        SampleCount : Int
    );

    /// Compute isolation score for a sample
    /// Approximated using path length in random binary partitioning
    function IsolationScore(
        sample : Int[],
        centroids : Int[][],
        numTrees : Int,
        seed : Int
    ) : Double {
        if Length(centroids) == 0 {
            return 1.0;
        }

        // Approximate isolation using random bit sampling
        mutable totalPathLength = 0.0;
        mutable s = seed;

        for tree in 0 .. numTrees - 1 {
            mutable depth = 0;
            mutable remaining = centroids;
            mutable isolated = false;

            while Length(remaining) > 1 and depth < 20 {
                // Random bit selection
                set s = (s * 1664525 + 1013904223) &&& 0x7FFFFFFF;
                let wordIdx = s % Length(sample);
                set s = (s * 1664525 + 1013904223) &&& 0x7FFFFFFF;
                let bitIdx = s % 64;

                // Get sample bit
                let sampleBit = (sample[wordIdx] >>> bitIdx) &&& 1;

                // Partition centroids by this bit
                mutable left = new Int[][0];
                mutable right = new Int[][0];
                for c in remaining {
                    let cBit = (c[wordIdx] >>> bitIdx) &&& 1;
                    if cBit == sampleBit {
                        set left += [c];
                    } else {
                        set right += [c];
                    }
                }

                set remaining = left;
                set depth += 1;

                if Length(remaining) == 0 {
                    set isolated = true;
                    set remaining = new Int[][0];
                }
            }

            set totalPathLength += IntAsDouble(depth);
        }

        let avgPathLength = totalPathLength / IntAsDouble(numTrees);
        // Normalize: shorter path = more isolated = more novel
        let maxPath = 20.0;
        let score = 1.0 - avgPathLength / maxPath;
        return MaxD(0.0, MinD(1.0, score));
    }

    // =========================================================================
    // Method 3: Ensemble Novelty Detection
    // =========================================================================

    /// Ensemble novelty detection combining multiple methods
    function EnsembleNovelty(
        sample : Int[],
        clusters : ReplayCluster[],
        model : DistanceModel,
        config : NoveltyConfig
    ) : NoveltyResult {
        // Method 0: Distance-based
        let distResult = DistanceBasedNovelty(sample, clusters, config::DistanceThreshold);

        // Method 1: Statistical
        let statResult = StatisticalNovelty(
            sample, clusters, model, config::StatisticalSigma
        );

        // Method 2: Isolation (simplified)
        let centroids = Mapped(c -> c::Centroid, clusters);
        let isoScore = IsolationScore(sample, centroids, 10, 42);

        // Weighted ensemble
        let weights = config::EnsembleWeights;
        let w0 = if Length(weights) > 0 { weights[0] } else { 0.33 };
        let w1 = if Length(weights) > 1 { weights[1] } else { 0.33 };
        let w2 = if Length(weights) > 2 { weights[2] } else { 0.34 };

        let ensembleScore = w0 * distResult::DistanceScore +
                            w1 * statResult::StatisticalScore +
                            w2 * isoScore;

        let isNovel = ensembleScore > (1.0 - config::ConfidenceLevel);
        let confidence = AbsD(ensembleScore - 0.5) * 2.0;

        return NoveltyResult(
            isNovel,
            ensembleScore,
            distResult::DistanceScore,
            statResult::StatisticalScore,
            isoScore,
            ensembleScore,
            distResult::NearestClusterId,
            distResult::NearestDistance,
            confidence
        );
    }

    // =========================================================================
    // Novelty History and Tracking
    // =========================================================================

    /// Novelty detection history for trend analysis
    newtype NoveltyHistory = (
        Scores      : Double[],
        IsNovel     : Bool[],
        Timestamps  : Int[],
        WindowSize  : Int
    );

    /// Initialize novelty history
    function InitNoveltyHistory(windowSize : Int) : NoveltyHistory {
        return NoveltyHistory(new Double[0], new Bool[0], new Int[0], windowSize);
    }

    /// Add observation to novelty history
    function AddNoveltyObservation(
        history : NoveltyHistory,
        score : Double,
        isNovel : Bool,
        timestamp : Int
    ) : NoveltyHistory {
        let ws = history::WindowSize;
        mutable scores = history::Scores + [score];
        mutable flags = history::IsNovel + [isNovel];
        mutable times = history::Timestamps + [timestamp];

        if Length(scores) > ws {
            set scores = scores[Length(scores) - ws .. Length(scores) - 1];
            set flags = flags[Length(flags) - ws .. Length(flags) - 1];
            set times = times[Length(times) - ws .. Length(times) - 1];
        }

        return NoveltyHistory(scores, flags, times, ws);
    }

    /// Compute recent novelty rate from history
    function RecentNoveltyRate(history : NoveltyHistory) : Double {
        if Length(history::IsNovel) == 0 {
            return 0.0;
        }
        mutable count = 0;
        for f in history::IsNovel {
            if f { set count += 1; }
        }
        return IntAsDouble(count) / IntAsDouble(Length(history::IsNovel));
    }

    /// Compute novelty trend (positive = increasing novelty)
    function NoveltyTrend(history : NoveltyHistory) : Double {
        let n = Length(history::Scores);
        if n < 2 {
            return 0.0;
        }
        let half = n / 2;
        mutable firstHalf = 0.0;
        mutable secondHalf = 0.0;
        for i in 0 .. half - 1 {
            set firstHalf += history::Scores[i];
        }
        for i in half .. n - 1 {
            set secondHalf += history::Scores[i];
        }
        let firstMean = firstHalf / IntAsDouble(half);
        let secondMean = secondHalf / IntAsDouble(n - half);
        return secondMean - firstMean;
    }

    /// Detect novelty burst (sudden increase in novelty rate)
    function IsNoveltyBurst(
        history : NoveltyHistory,
        burstThreshold : Double
    ) : Bool {
        let trend = NoveltyTrend(history);
        return trend > burstThreshold;
    }

    // =========================================================================
    // Novelty-Based Curriculum Learning
    // =========================================================================

    /// Compute curriculum weight for a sample based on novelty
    function CurriculumWeight(
        noveltyScore : Double,
        trainingStep : Int,
        warmupSteps : Int
    ) : Double {
        // During warmup: focus on novel samples
        // After warmup: balance novel and familiar
        let warmupFraction = MinD(1.0, IntAsDouble(trainingStep) / IntAsDouble(warmupSteps));
        let noveltyBias = 1.0 - warmupFraction * 0.5;  // Decreases from 1.0 to 0.5
        return noveltyBias * noveltyScore + (1.0 - noveltyBias) * (1.0 - noveltyScore);
    }

    /// Rank samples by curriculum priority
    function RankByCurriculum(
        noveltyScores : Double[],
        trainingStep : Int,
        warmupSteps : Int
    ) : Int[] {
        let n = Length(noveltyScores);
        mutable weights = new Double[n];
        for i in 0 .. n - 1 {
            set weights w/= i <- CurriculumWeight(noveltyScores[i], trainingStep, warmupSteps);
        }

        // Sort indices by weight (descending)
        mutable indices = new Int[n];
        for i in 0 .. n - 1 {
            set indices w/= i <- i;
        }

        // Insertion sort
        for i in 1 .. n - 1 {
            let key = indices[i];
            let keyWeight = weights[key];
            mutable j = i - 1;
            while j >= 0 and weights[indices[j]] < keyWeight {
                set indices w/= j + 1 <- indices[j];
                set j -= 1;
            }
            set indices w/= j + 1 <- key;
        }
        return indices;
    }

    // =========================================================================
    // Novelty-Driven Cluster Creation
    // =========================================================================

    /// Decide whether to create a new cluster for a novel sample
    function ShouldCreateCluster(
        noveltyResult : NoveltyResult,
        currentClusterCount : Int,
        maxClusters : Int,
        minNoveltyScore : Double
    ) : Bool {
        return noveltyResult::IsNovel and
               noveltyResult::NoveltyScore >= minNoveltyScore and
               currentClusterCount < maxClusters;
    }

    /// Compute optimal cluster count based on novelty distribution
    function OptimalClusterCount(
        noveltyHistory : NoveltyHistory,
        minClusters : Int,
        maxClusters : Int
    ) : Int {
        let rate = RecentNoveltyRate(noveltyHistory);
        // Higher novelty rate → more clusters needed
        let rawCount = Ceiling(IntAsDouble(minClusters) +
                               rate * IntAsDouble(maxClusters - minClusters));
        return MaxI(minClusters, MinI(maxClusters, rawCount));
    }

    // =========================================================================
    // Novelty Score Calibration
    // =========================================================================

    /// Calibrate novelty scores using Platt scaling
    function PlattCalibration(
        rawScore : Double,
        plattA : Double,
        plattB : Double
    ) : Double {
        return 1.0 / (1.0 + E() ^ (plattA * rawScore + plattB));
    }

    /// Compute Platt scaling parameters from calibration data
    function FitPlattScaling(
        scores : Double[],
        labels : Bool[]
    ) : (Double, Double) {
        // Simplified: use mean positive and negative scores
        if Length(scores) == 0 {
            return (-1.0, 0.0);
        }
        mutable posSum = 0.0;
        mutable negSum = 0.0;
        mutable posCount = 0;
        mutable negCount = 0;
        for i in 0 .. Length(scores) - 1 {
            if labels[i] {
                set posSum += scores[i];
                set posCount += 1;
            } else {
                set negSum += scores[i];
                set negCount += 1;
            }
        }
        let posMean = if posCount > 0 { posSum / IntAsDouble(posCount) } else { 0.8 };
        let negMean = if negCount > 0 { negSum / IntAsDouble(negCount) } else { 0.2 };
        let a = -4.0 / (posMean - negMean);
        let b = 2.0 * (posMean + negMean) / (posMean - negMean);
        return (a, b);
    }

    // =========================================================================
    // Dispatch: Main Novelty Detection Entry Point
    // =========================================================================

    /// Detect novelty using configured method
    function DetectNovelty(
        sample : Int[],
        clusters : ReplayCluster[],
        model : DistanceModel,
        config : NoveltyConfig
    ) : NoveltyResult {
        let method = config::Method;
        if method == 0 {
            return DistanceBasedNovelty(sample, clusters, config::DistanceThreshold);
        } elif method == 1 {
            return StatisticalNovelty(sample, clusters, model, config::StatisticalSigma);
        } elif method == 2 {
            let centroids = Mapped(c -> c::Centroid, clusters);
            let isoScore = IsolationScore(sample, centroids, 10, 42);
            let (nearestIdx, nearestDist) = AssignReplayClusterWithDistance(sample, clusters);
            let nearestId = if nearestIdx >= 0 { clusters[nearestIdx]::ClusterId } else { -1 };
            return NoveltyResult(
                isoScore > 0.5, isoScore, 0.0, 0.0, isoScore, isoScore,
                nearestId, nearestDist, AbsD(isoScore - 0.5) * 2.0
            );
        } else {
            return EnsembleNovelty(sample, clusters, model, config);
        }
    }

    /// Batch novelty detection
    function BatchDetectNovelty(
        samples : Int[][],
        clusters : ReplayCluster[],
        model : DistanceModel,
        config : NoveltyConfig
    ) : NoveltyResult[] {
        mutable results = new NoveltyResult[Length(samples)];
        for i in 0 .. Length(samples) - 1 {
            set results w/= i <- DetectNovelty(samples[i], clusters, model, config);
        }
        return results;
    }

    // =========================================================================
    // Logging Operations
    // =========================================================================

    /// Log novelty detection result
    operation LogNoveltyResult(
        sampleId : Int,
        result : NoveltyResult
    ) : Unit {
        let status = if result::IsNovel { "NOVEL" } else { "FAMILIAR" };
        Message($"[Novelty] sample={sampleId} [{status}] score={result::NoveltyScore} " +
                $"dist={result::NearestDistance} cluster={result::NearestClusterId} " +
                $"confidence={result::Confidence}");
    }

    /// Log novelty history summary
    operation LogNoveltyHistory(history : NoveltyHistory) : Unit {
        let rate = RecentNoveltyRate(history);
        let trend = NoveltyTrend(history);
        Message($"[Novelty History] rate={rate} trend={trend} window={history::WindowSize}");
    }

    /// Log ensemble novelty breakdown
    operation LogEnsembleBreakdown(result : NoveltyResult) : Unit {
        Message($"[Ensemble] dist={result::DistanceScore} stat={result::StatisticalScore} " +
                $"iso={result::IsolationScore} ensemble={result::EnsembleScore} " +
                $"novel={result::IsNovel}");
    }
}