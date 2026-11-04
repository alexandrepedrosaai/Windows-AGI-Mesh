// =============================================================================
// centroid_update.qs
// Q# centroid update algorithms for dynamic replay clustering
// Implements online, batch, and weighted centroid update strategies
// Namespace: SiameseTwinAI.Clustering
// =============================================================================

namespace SiameseTwinAI.Clustering {

    open Microsoft.Quantum.Arrays;
    open Microsoft.Quantum.Convert;
    open Microsoft.Quantum.Intrinsic;
    open Microsoft.Quantum.Math;
    open Microsoft.Quantum.Diagnostics;

    // =========================================================================
    // Core Centroid Update Functions
    // =========================================================================

    /// Online centroid update using incremental mean formula
    /// centroid_new = centroid_old + (sample - centroid_old) / (n + 1)
    function UpdateCentroid(
        centroid : Int[],
        sample : Int[],
        n : Int
    ) : Int[] {
        Fact(Length(centroid) == Length(sample), "Centroid and sample must have equal length");
        mutable result = centroid;
        for i in 0 .. Length(centroid) - 1 {
            let old = IntAsDouble(centroid[i]);
            let x = IntAsDouble(sample[i]);
            let v = old + (x - old) / IntAsDouble(n + 1);
            set result w/= i <- Ceiling(v);
        }
        return result;
    }

    /// Update centroid with explicit learning rate (exponential moving average)
    /// centroid_new = (1 - alpha) * centroid_old + alpha * sample
    function UpdateCentroidEMA(
        centroid : Int[],
        sample : Int[],
        alpha : Double
    ) : Int[] {
        Fact(Length(centroid) == Length(sample), "Centroid and sample must have equal length");
        Fact(alpha >= 0.0 and alpha <= 1.0, "Alpha must be in [0.0, 1.0]");
        mutable result = new Int[Length(centroid)];
        let oneMinusAlpha = 1.0 - alpha;
        for i in 0 .. Length(centroid) - 1 {
            let old = IntAsDouble(centroid[i]);
            let x = IntAsDouble(sample[i]);
            let v = oneMinusAlpha * old + alpha * x;
            set result w/= i <- Ceiling(v);
        }
        return result;
    }

    /// Batch centroid update from a set of assigned samples
    /// Computes exact mean of all samples in the cluster
    function BatchUpdateCentroid(
        samples : Int[][]
    ) : Int[] {
        if Length(samples) == 0 {
            return new Int[0];
        }
        let vecLen = Length(samples[0]);
        let n = Length(samples);
        mutable centroid = new Int[vecLen];
        for i in 0 .. vecLen - 1 {
            mutable sum = 0;
            for s in samples {
                set sum += s[i];
            }
            set centroid w/= i <- sum / n;
        }
        return centroid;
    }

    /// Weighted centroid update from samples with importance weights
    function WeightedCentroidUpdate(
        samples : Int[][],
        weights : Double[]
    ) : Int[] {
        Fact(Length(samples) == Length(weights), "Samples and weights must have equal length");
        if Length(samples) == 0 {
            return new Int[0];
        }
        let vecLen = Length(samples[0]);
        mutable centroid = new Int[vecLen];
        mutable totalWeight = 0.0;
        for w in weights {
            set totalWeight += w;
        }
        if totalWeight <= 0.0 {
            return BatchUpdateCentroid(samples);
        }
        for i in 0 .. vecLen - 1 {
            mutable weightedSum = 0.0;
            for j in 0 .. Length(samples) - 1 {
                set weightedSum += weights[j] * IntAsDouble(samples[j][i]);
            }
            set centroid w/= i <- Ceiling(weightedSum / totalWeight);
        }
        return centroid;
    }

    // =========================================================================
    // Cluster State Management
    // =========================================================================

    /// Newtype representing a replay cluster with full state
    newtype ReplayCluster = (
        ClusterId    : Int,
        Centroid     : Int[],
        Samples      : Int,
        MeanHamming  : Double,
        Threshold    : Int,
        NoveltySum   : Double,
        LastUpdated  : Int,
        Priority     : Double
    );

    /// Create a new cluster from the first sample
    function CreateCluster(
        clusterId : Int,
        firstSample : Int[],
        threshold : Int,
        timestamp : Int
    ) : ReplayCluster {
        return ReplayCluster(
            clusterId,
            firstSample,
            1,
            0.0,
            threshold,
            0.0,
            timestamp,
            1.0
        );
    }

    /// Update a cluster with a new sample
    function UpdateCluster(
        cluster : ReplayCluster,
        sample : Int[],
        distance : Int,
        timestamp : Int
    ) : ReplayCluster {
        let newN = cluster::Samples + 1;
        let newCentroid = UpdateCentroid(cluster::Centroid, sample, cluster::Samples);
        let oldMean = cluster::MeanHamming;
        let newMean = oldMean + (IntAsDouble(distance) - oldMean) / IntAsDouble(newN);
        return ReplayCluster(
            cluster::ClusterId,
            newCentroid,
            newN,
            newMean,
            cluster::Threshold,
            cluster::NoveltySum,
            timestamp,
            cluster::Priority
        );
    }

    /// Update cluster threshold based on current mean distance
    function UpdateClusterThreshold(
        cluster : ReplayCluster,
        multiplier : Double,
        minThreshold : Int,
        maxThreshold : Int
    ) : ReplayCluster {
        let rawThreshold = Ceiling(cluster::MeanHamming * multiplier);
        let clampedThreshold = MaxI(minThreshold, MinI(maxThreshold, rawThreshold));
        return ReplayCluster(
            cluster::ClusterId,
            cluster::Centroid,
            cluster::Samples,
            cluster::MeanHamming,
            clampedThreshold,
            cluster::NoveltySum,
            cluster::LastUpdated,
            cluster::Priority
        );
    }

    /// Update cluster priority based on loss and novelty
    function UpdateClusterPriority(
        cluster : ReplayCluster,
        recentLoss : Double,
        noveltyScore : Double,
        lossWeight : Double,
        noveltyWeight : Double
    ) : ReplayCluster {
        let newPriority = lossWeight * recentLoss + noveltyWeight * noveltyScore;
        return ReplayCluster(
            cluster::ClusterId,
            cluster::Centroid,
            cluster::Samples,
            cluster::MeanHamming,
            cluster::Threshold,
            cluster::NoveltySum + noveltyScore,
            cluster::LastUpdated,
            newPriority
        );
    }

    // =========================================================================
    // Cluster Collection Operations
    // =========================================================================

    /// Find the cluster with highest priority for replay
    function HighestPriorityCluster(clusters : ReplayCluster[]) : Int {
        if Length(clusters) == 0 {
            return -1;
        }
        mutable bestIdx = 0;
        mutable bestPriority = clusters[0]::Priority;
        for i in 1 .. Length(clusters) - 1 {
            if clusters[i]::Priority > bestPriority {
                set bestPriority = clusters[i]::Priority;
                set bestIdx = i;
            }
        }
        return bestIdx;
    }

    /// Find the cluster with lowest sample count (least explored)
    function LeastExploredCluster(clusters : ReplayCluster[]) : Int {
        if Length(clusters) == 0 {
            return -1;
        }
        mutable bestIdx = 0;
        mutable minSamples = clusters[0]::Samples;
        for i in 1 .. Length(clusters) - 1 {
            if clusters[i]::Samples < minSamples {
                set minSamples = clusters[i]::Samples;
                set bestIdx = i;
            }
        }
        return bestIdx;
    }

    /// Find the cluster with highest mean Hamming distance (most spread)
    function MostSpreadCluster(clusters : ReplayCluster[]) : Int {
        if Length(clusters) == 0 {
            return -1;
        }
        mutable bestIdx = 0;
        mutable maxMean = clusters[0]::MeanHamming;
        for i in 1 .. Length(clusters) - 1 {
            if clusters[i]::MeanHamming > maxMean {
                set maxMean = clusters[i]::MeanHamming;
                set bestIdx = i;
            }
        }
        return bestIdx;
    }

    /// Merge two clusters into one
    function MergeClusters(
        clusterA : ReplayCluster,
        clusterB : ReplayCluster,
        newId : Int,
        timestamp : Int
    ) : ReplayCluster {
        let totalSamples = clusterA::Samples + clusterB::Samples;
        let wA = IntAsDouble(clusterA::Samples) / IntAsDouble(totalSamples);
        let wB = IntAsDouble(clusterB::Samples) / IntAsDouble(totalSamples);

        // Weighted centroid merge
        let vecLen = Length(clusterA::Centroid);
        mutable newCentroid = new Int[vecLen];
        for i in 0 .. vecLen - 1 {
            let v = wA * IntAsDouble(clusterA::Centroid[i]) +
                    wB * IntAsDouble(clusterB::Centroid[i]);
            set newCentroid w/= i <- Ceiling(v);
        }

        let newMean = wA * clusterA::MeanHamming + wB * clusterB::MeanHamming;
        let newThreshold = MaxI(clusterA::Threshold, clusterB::Threshold);
        let newPriority = MaxD(clusterA::Priority, clusterB::Priority);

        return ReplayCluster(
            newId,
            newCentroid,
            totalSamples,
            newMean,
            newThreshold,
            clusterA::NoveltySum + clusterB::NoveltySum,
            timestamp,
            newPriority
        );
    }

    /// Split a cluster into two by finding the two most distant samples
    function SplitCluster(
        cluster : ReplayCluster,
        samples : Int[][],
        newIdA : Int,
        newIdB : Int,
        timestamp : Int
    ) : (ReplayCluster, ReplayCluster) {
        if Length(samples) < 2 {
            return (cluster, cluster);
        }

        // Find two most distant samples as seeds
        mutable maxDist = 0;
        mutable seedA = 0;
        mutable seedB = 1;
        for i in 0 .. Length(samples) - 2 {
            for j in i + 1 .. Length(samples) - 1 {
                let d = HammingDistance(samples[i], samples[j]);
                if d > maxDist {
                    set maxDist = d;
                    set seedA = i;
                    set seedB = j;
                }
            }
        }

        // Assign samples to nearest seed
        mutable samplesA = new Int[][0];
        mutable samplesB = new Int[][0];
        for s in samples {
            let dA = HammingDistance(s, samples[seedA]);
            let dB = HammingDistance(s, samples[seedB]);
            if dA <= dB {
                set samplesA += [s];
            } else {
                set samplesB += [s];
            }
        }

        let centroidA = if Length(samplesA) > 0 { BatchUpdateCentroid(samplesA) } else { samples[seedA] };
        let centroidB = if Length(samplesB) > 0 { BatchUpdateCentroid(samplesB) } else { samples[seedB] };

        let clusterA = ReplayCluster(
            newIdA, centroidA, Length(samplesA),
            cluster::MeanHamming, cluster::Threshold,
            0.0, timestamp, cluster::Priority
        );
        let clusterB = ReplayCluster(
            newIdB, centroidB, Length(samplesB),
            cluster::MeanHamming, cluster::Threshold,
            0.0, timestamp, cluster::Priority
        );

        return (clusterA, clusterB);
    }

    // =========================================================================
    // Centroid Drift Detection
    // =========================================================================

    /// Compute centroid drift between old and new centroid
    function CentroidDrift(
        oldCentroid : Int[],
        newCentroid : Int[]
    ) : Int {
        return HammingDistance(oldCentroid, newCentroid);
    }

    /// Check if centroid has drifted beyond acceptable threshold
    function HasCentroidDrifted(
        oldCentroid : Int[],
        newCentroid : Int[],
        driftThreshold : Int
    ) : Bool {
        return CentroidDrift(oldCentroid, newCentroid) > driftThreshold;
    }

    /// Compute drift rate (drift per sample update)
    function CentroidDriftRate(
        driftHistory : Int[],
        windowSize : Int
    ) : Double {
        if Length(driftHistory) == 0 {
            return 0.0;
        }
        let window = MinI(windowSize, Length(driftHistory));
        let start = Length(driftHistory) - window;
        mutable sum = 0;
        for i in start .. Length(driftHistory) - 1 {
            set sum += driftHistory[i];
        }
        return IntAsDouble(sum) / IntAsDouble(window);
    }

    // =========================================================================
    // Cluster Quality Metrics
    // =========================================================================

    /// Compute intra-cluster cohesion (lower = more cohesive)
    function ClusterCohesion(cluster : ReplayCluster) : Double {
        return cluster::MeanHamming;
    }

    /// Compute cluster age (samples since last update)
    function ClusterAge(
        cluster : ReplayCluster,
        currentTimestamp : Int
    ) : Int {
        return currentTimestamp - cluster::LastUpdated;
    }

    /// Compute cluster utilization (samples / max_capacity)
    function ClusterUtilization(
        cluster : ReplayCluster,
        maxCapacity : Int
    ) : Double {
        return IntAsDouble(cluster::Samples) / IntAsDouble(maxCapacity);
    }

    /// Compute cluster entropy based on distance distribution
    function ClusterEntropy(
        distances : Int[],
        maxDistance : Int
    ) : Double {
        if Length(distances) == 0 or maxDistance == 0 {
            return 0.0;
        }
        // Bin distances into 8 buckets
        let numBuckets = 8;
        mutable counts = new Int[numBuckets];
        for d in distances {
            let bucket = MinI(numBuckets - 1, d * numBuckets / maxDistance);
            set counts w/= bucket <- counts[bucket] + 1;
        }
        let n = Length(distances);
        mutable entropy = 0.0;
        for c in counts {
            if c > 0 {
                let p = IntAsDouble(c) / IntAsDouble(n);
                set entropy -= p * Log(p);
            }
        }
        return entropy;
    }

    // =========================================================================
    // Centroid Initialization Strategies
    // =========================================================================

    /// Initialize centroids using K-Means++ strategy
    function KMeansPlusPlusInit(
        samples : Int[][],
        k : Int,
        seed : Int
    ) : Int[][] {
        if Length(samples) == 0 or k <= 0 {
            return new Int[][0];
        }
        let n = Length(samples);
        let actualK = MinI(k, n);
        mutable centroids = new Int[][actualK];

        // Choose first centroid randomly (using seed)
        let firstIdx = seed % n;
        set centroids w/= 0 <- samples[firstIdx];

        // Choose remaining centroids with probability proportional to distance^2
        for c in 1 .. actualK - 1 {
            mutable distances = new Double[n];
            mutable totalDist = 0.0;

            for i in 0 .. n - 1 {
                mutable minDist = 2147483647;
                for j in 0 .. c - 1 {
                    let d = HammingDistance(samples[i], centroids[j]);
                    if d < minDist {
                        set minDist = d;
                    }
                }
                let distSq = IntAsDouble(minDist) * IntAsDouble(minDist);
                set distances w/= i <- distSq;
                set totalDist += distSq;
            }

            // Select next centroid (simplified: pick max distance)
            mutable bestIdx = 0;
            mutable bestDist = distances[0];
            for i in 1 .. n - 1 {
                if distances[i] > bestDist {
                    set bestDist = distances[i];
                    set bestIdx = i;
                }
            }
            set centroids w/= c <- samples[bestIdx];
        }
        return centroids;
    }

    /// Initialize centroids using random sampling
    function RandomCentroidInit(
        samples : Int[][],
        k : Int,
        seed : Int
    ) : Int[][] {
        let n = Length(samples);
        let actualK = MinI(k, n);
        mutable centroids = new Int[][actualK];
        mutable used = new Bool[n];

        mutable s = seed;
        for c in 0 .. actualK - 1 {
            // LCG random
            set s = (s * 1664525 + 1013904223) &&& 0x7FFFFFFF;
            mutable idx = s % n;
            // Find unused index
            mutable attempts = 0;
            while used[idx] and attempts < n {
                set s = (s * 1664525 + 1013904223) &&& 0x7FFFFFFF;
                set idx = s % n;
                set attempts += 1;
            }
            set centroids w/= c <- samples[idx];
            set used w/= idx <- true;
        }
        return centroids;
    }

    // =========================================================================
    // Centroid Serialization
    // =========================================================================

    /// Serialize a cluster to a string for logging
    function ClusterToString(cluster : ReplayCluster) : String {
        return $"Cluster(id={cluster::ClusterId}, samples={cluster::Samples}, " +
               $"meanHamming={cluster::MeanHamming}, threshold={cluster::Threshold}, " +
               $"priority={cluster::Priority})";
    }

    /// Log cluster state
    operation LogClusterState(cluster : ReplayCluster) : Unit {
        Message(ClusterToString(cluster));
    }

    /// Log all clusters in a collection
    operation LogAllClusters(clusters : ReplayCluster[]) : Unit {
        Message($"[Clusters] Total: {Length(clusters)}");
        for c in clusters {
            LogClusterState(c);
        }
    }

    // =========================================================================
    // Centroid Update Operations (with side effects)
    // =========================================================================

    /// Perform online centroid update and log result
    operation OnlineCentroidUpdate(
        cluster : ReplayCluster,
        sample : Int[],
        distance : Int,
        timestamp : Int
    ) : ReplayCluster {
        let updated = UpdateCluster(cluster, sample, distance, timestamp);
        Message($"[Centroid] Cluster {cluster::ClusterId}: " +
                $"samples {cluster::Samples} → {updated::Samples}, " +
                $"meanDist {cluster::MeanHamming} → {updated::MeanHamming}");
        return updated;
    }

    /// Perform batch centroid update from assigned samples
    operation BatchCentroidUpdate(
        cluster : ReplayCluster,
        assignedSamples : Int[][],
        timestamp : Int
    ) : ReplayCluster {
        if Length(assignedSamples) == 0 {
            return cluster;
        }
        let newCentroid = BatchUpdateCentroid(assignedSamples);
        let drift = CentroidDrift(cluster::Centroid, newCentroid);
        Message($"[Centroid Batch] Cluster {cluster::ClusterId}: " +
                $"drift={drift}, newSamples={Length(assignedSamples)}");
        return ReplayCluster(
            cluster::ClusterId,
            newCentroid,
            cluster::Samples + Length(assignedSamples),
            cluster::MeanHamming,
            cluster::Threshold,
            cluster::NoveltySum,
            timestamp,
            cluster::Priority
        );
    }

    // =========================================================================
    // Global Cluster Manager Operations
    // =========================================================================

    /// Run one epoch of K-Means clustering
    operation KMeansEpoch(
        samples : Int[][],
        clusters : ReplayCluster[],
        timestamp : Int
    ) : ReplayCluster[] {
        let k = Length(clusters);
        let centroids = Mapped(c -> c::Centroid, clusters);

        // Assignment step
        let assignments = BatchAssign(samples, centroids);

        // Update step: collect samples per cluster
        mutable updatedClusters = clusters;
        for c in 0 .. k - 1 {
            mutable clusterSamples = new Int[][0];
            for i in 0 .. Length(samples) - 1 {
                if assignments[i] == c {
                    set clusterSamples += [samples[i]];
                }
            }
            if Length(clusterSamples) > 0 {
                let newCentroid = BatchUpdateCentroid(clusterSamples);
                let updated = ReplayCluster(
                    clusters[c]::ClusterId,
                    newCentroid,
                    clusters[c]::Samples + Length(clusterSamples),
                    clusters[c]::MeanHamming,
                    clusters[c]::Threshold,
                    clusters[c]::NoveltySum,
                    timestamp,
                    clusters[c]::Priority
                );
                set updatedClusters w/= c <- updated;
            }
        }
        return updatedClusters;
    }

    /// Prune stale clusters (not updated recently)
    function PruneStaleClusters(
        clusters : ReplayCluster[],
        currentTimestamp : Int,
        maxAge : Int
    ) : ReplayCluster[] {
        mutable active = new ReplayCluster[0];
        for c in clusters {
            if ClusterAge(c, currentTimestamp) <= maxAge {
                set active += [c];
            }
        }
        return active;
    }

    /// Rebalance cluster priorities using softmax normalization
    function RebalancePriorities(clusters : ReplayCluster[]) : ReplayCluster[] {
        if Length(clusters) == 0 {
            return clusters;
        }
        mutable maxPriority = clusters[0]::Priority;
        for c in clusters {
            if c::Priority > maxPriority {
                set maxPriority = c::Priority;
            }
        }
        mutable expSum = 0.0;
        mutable expValues = new Double[Length(clusters)];
        for i in 0 .. Length(clusters) - 1 {
            let e = E() ^ (clusters[i]::Priority - maxPriority);
            set expValues w/= i <- e;
            set expSum += e;
        }
        mutable result = clusters;
        for i in 0 .. Length(clusters) - 1 {
            let softmax = expValues[i] / expSum;
            set result w/= i <- ReplayCluster(
                clusters[i]::ClusterId,
                clusters[i]::Centroid,
                clusters[i]::Samples,
                clusters[i]::MeanHamming,
                clusters[i]::Threshold,
                clusters[i]::NoveltySum,
                clusters[i]::LastUpdated,
                softmax
            );
        }
        return result;
    }
}