// =============================================================================
// replay_cluster_manager.qs
// Q# Replay Cluster Manager — core orchestration for dynamic clustering
// Manages cluster lifecycle: creation, assignment, update, pruning, replay
// Namespace: SiameseTwinAI.Clustering
// =============================================================================

namespace SiameseTwinAI.Clustering {

    open Microsoft.Quantum.Arrays;
    open Microsoft.Quantum.Convert;
    open Microsoft.Quantum.Intrinsic;
    open Microsoft.Quantum.Math;
    open Microsoft.Quantum.Diagnostics;

    // =========================================================================
    // Manager Configuration
    // =========================================================================

    /// Full configuration for the replay cluster manager
    newtype ClusterManagerConfig = (
        MaxClusters        : Int,
        MinClusters        : Int,
        InitialClusters    : Int,
        MaxSamplesPerCluster : Int,
        ReplayBatchSize    : Int,
        NoveltyWeight      : Double,
        LossWeight         : Double,
        MergeThreshold     : Int,
        SplitThreshold     : Int,
        PruneAge           : Int,
        ThresholdConfig    : ThresholdConfig,
        EnableAutoSplit    : Bool,
        EnableAutoMerge    : Bool,
        EnablePruning      : Bool
    );

    /// Default cluster manager configuration
    function DefaultClusterManagerConfig() : ClusterManagerConfig {
        return ClusterManagerConfig(
            64,     // MaxClusters
            2,      // MinClusters
            8,      // InitialClusters
            1024,   // MaxSamplesPerCluster
            32,     // ReplayBatchSize
            0.4,    // NoveltyWeight
            0.6,    // LossWeight
            8,      // MergeThreshold (merge if centroids within 8 bits)
            48,     // SplitThreshold (split if mean distance > 48)
            10000,  // PruneAge (prune if not updated in 10000 steps)
            DefaultThresholdConfig(),
            true,   // EnableAutoSplit
            true,   // EnableAutoMerge
            true    // EnablePruning
        );
    }

    // =========================================================================
    // Manager State
    // =========================================================================

    /// Full state of the replay cluster manager
    newtype ClusterManagerState = (
        Clusters          : ReplayCluster[],
        ThresholdStates   : ClusterThresholdState[],
        GlobalThreshold   : Int,
        NextClusterId     : Int,
        TotalSamples      : Int,
        TotalNovel        : Int,
        CurrentTimestamp  : Int,
        Config            : ClusterManagerConfig
    );

    /// Initialize cluster manager state
    function InitClusterManager(
        config : ClusterManagerConfig
    ) : ClusterManagerState {
        return ClusterManagerState(
            new ReplayCluster[0],
            new ClusterThresholdState[0],
            config::ThresholdConfig::InitialThreshold,
            0,
            0,
            0,
            0,
            config
        );
    }

    // =========================================================================
    // Sample Assignment
    // =========================================================================

    /// Assign a sample to the nearest cluster or create a new cluster
    function AssignReplayCluster(
        sample : Int[],
        clusters : ReplayCluster[]
    ) : Int {
        if Length(clusters) == 0 {
            return -1;  // No clusters yet
        }
        mutable cluster = -1;
        mutable best = 2147483647;
        for idx in 0 .. Length(clusters) - 1 {
            let d = HammingDistance(sample, clusters[idx]::Centroid);
            if d < best {
                set best = d;
                set cluster = idx;
            }
        }
        return cluster;
    }

    /// Assign sample and return (cluster_index, distance) pair
    function AssignReplayClusterWithDistance(
        sample : Int[],
        clusters : ReplayCluster[]
    ) : (Int, Int) {
        if Length(clusters) == 0 {
            return (-1, 2147483647);
        }
        mutable bestIdx = 0;
        mutable bestDist = HammingDistance(sample, clusters[0]::Centroid);
        for idx in 1 .. Length(clusters) - 1 {
            let d = HammingDistance(sample, clusters[idx]::Centroid);
            if d < bestDist {
                set bestDist = d;
                set bestIdx = idx;
            }
        }
        return (bestIdx, bestDist);
    }

    /// Check if a sample should create a new cluster
    function ShouldCreateNewCluster(
        distance : Int,
        threshold : Int,
        currentClusterCount : Int,
        maxClusters : Int
    ) : Bool {
        return distance > threshold and currentClusterCount < maxClusters;
    }

    // =========================================================================
    // Core Manager Operations
    // =========================================================================

    /// Process a single sample through the cluster manager
    function ProcessSample(
        state : ClusterManagerState,
        sample : Int[],
        loss : Double
    ) : ClusterManagerState {
        let config = state::Config;
        let timestamp = state::CurrentTimestamp + 1;

        // Find nearest cluster
        let (bestIdx, bestDist) = AssignReplayClusterWithDistance(sample, state::Clusters);

        // Determine if novel
        let threshold = state::GlobalThreshold;
        let isNovel = ShouldCreateNewCluster(
            bestDist, threshold,
            Length(state::Clusters), config::MaxClusters
        );

        mutable clusters = state::Clusters;
        mutable nextId = state::NextClusterId;
        mutable totalNovel = state::TotalNovel;

        if isNovel or Length(clusters) == 0 {
            // Create new cluster
            let newCluster = CreateCluster(nextId, sample, threshold, timestamp);
            set clusters += [newCluster];
            set nextId += 1;
            set totalNovel += 1;
        } else {
            // Update existing cluster
            let updated = UpdateCluster(clusters[bestIdx], sample, bestDist, timestamp);
            let withPriority = UpdateClusterPriority(
                updated, loss,
                IntAsDouble(bestDist),
                config::LossWeight,
                config::NoveltyWeight
            );
            set clusters w/= bestIdx <- withPriority;
        }

        // Update global threshold using EMA
        let newGlobalThreshold = if bestDist < 2147483647 {
            let alpha = config::ThresholdConfig::AdaptRate;
            let ema = (1.0 - alpha) * IntAsDouble(threshold) + alpha * IntAsDouble(bestDist);
            MaxI(
                config::ThresholdConfig::MinThreshold,
                MinI(config::ThresholdConfig::MaxThreshold, Ceiling(ema))
            )
        } else {
            threshold
        };

        return ClusterManagerState(
            clusters,
            state::ThresholdStates,
            newGlobalThreshold,
            nextId,
            state::TotalSamples + 1,
            totalNovel,
            timestamp,
            config
        );
    }

    /// Process a batch of samples
    function ProcessBatch(
        state : ClusterManagerState,
        samples : Int[][],
        losses : Double[]
    ) : ClusterManagerState {
        mutable currentState = state;
        let n = MinI(Length(samples), Length(losses));
        for i in 0 .. n - 1 {
            set currentState = ProcessSample(currentState, samples[i], losses[i]);
        }
        return currentState;
    }

    // =========================================================================
    // Replay Buffer Operations
    // =========================================================================

    /// Sample indices from clusters for replay, weighted by priority
    function SampleReplayIndices(
        clusters : ReplayCluster[],
        batchSize : Int,
        seed : Int
    ) : Int[] {
        if Length(clusters) == 0 {
            return new Int[0];
        }

        // Compute priority weights
        mutable totalPriority = 0.0;
        for c in clusters {
            set totalPriority += c::Priority;
        }

        // Allocate samples per cluster proportional to priority
        mutable allocations = new Int[Length(clusters)];
        mutable allocated = 0;
        for i in 0 .. Length(clusters) - 1 {
let share = if totalPriority > 0.0 {
                Ceiling(clusters[i]::Priority / totalPriority * IntAsDouble(batchSize))
            } else {
                batchSize / Length(clusters) + (if i < batchSize % Length(clusters) { 1 } else { 0 })
            };
            set allocations w/= i <- share;
            set allocated += share;
        }

        // Adjust to exactly batchSize
        mutable result = new Int[0];
        for i in 0 .. Length(clusters) - 1 {
            for _ in 0 .. allocations[i] - 1 {
                set result += [clusters[i]::ClusterId];
                if Length(result) >= batchSize {
                    return result;
                }
            }
        }
        return result;
    }

    /// Get replay batch cluster IDs sorted by priority
    function GetReplayBatch(
        state : ClusterManagerState
    ) : Int[] {
        let config = state::Config;
        return SampleReplayIndices(
            state::Clusters,
            config::ReplayBatchSize,
            state::CurrentTimestamp
        );
    }

    /// Compute replay priority for a cluster
    function ReplayPriority(
        cluster : ReplayCluster,
        currentTimestamp : Int,
        agePenalty : Double
    ) : Double {
        let age = IntAsDouble(ClusterAge(cluster, currentTimestamp));
        let ageFactor = E() ^ (-agePenalty * age);
        return cluster::Priority * ageFactor;
    }

    /// Get top-K clusters by replay priority
    function TopKReplayClusters(
        clusters : ReplayCluster[],
        k : Int,
        currentTimestamp : Int
    ) : Int[] {
        let n = Length(clusters);
        let actualK = MinI(k, n);
        mutable priorities = new Double[n];
        for i in 0 .. n - 1 {
            set priorities w/= i <- ReplayPriority(clusters[i], currentTimestamp, 0.001);
        }

        // Selection sort for top-K
        mutable selected = new Int[actualK];
        mutable used = new Bool[n];
        for rank in 0 .. actualK - 1 {
            mutable bestIdx = -1;
            mutable bestPri = -1.0;
            for i in 0 .. n - 1 {
                if not used[i] and priorities[i] > bestPri {
                    set bestPri = priorities[i];
                    set bestIdx = i;
                }
            }
            if bestIdx >= 0 {
                set selected w/= rank <- bestIdx;
                set used w/= bestIdx <- true;
            }
        }
        return selected;
    }

    // =========================================================================
    // Auto-Split and Auto-Merge
    // =========================================================================

    /// Check if any cluster should be split
    function FindSplitCandidates(
        clusters : ReplayCluster[],
        splitThreshold : Int
    ) : Int[] {
        mutable candidates = new Int[0];
        for i in 0 .. Length(clusters) - 1 {
            if Ceiling(clusters[i]::MeanHamming) > splitThreshold and
               clusters[i]::Samples >= 4 {
                set candidates += [i];
            }
        }
        return candidates;
    }

    /// Check if any pair of clusters should be merged
    function FindMergeCandidates(
        clusters : ReplayCluster[],
        mergeThreshold : Int
    ) : (Int, Int)[] {
        mutable candidates = new (Int, Int)[0];
        let n = Length(clusters);
        for i in 0 .. n - 2 {
            for j in i + 1 .. n - 1 {
                let d = HammingDistance(clusters[i]::Centroid, clusters[j]::Centroid);
                if d <= mergeThreshold {
                    set candidates += [(i, j)];
                }
            }
        }
        return candidates;
    }

    /// Apply auto-merge to cluster collection
    function AutoMergeClusters(
        state : ClusterManagerState
    ) : ClusterManagerState {
        let config = state::Config;
        if not config::EnableAutoMerge or Length(state::Clusters) <= config::MinClusters {
            return state;
        }

        let mergePairs = FindMergeCandidates(state::Clusters, config::MergeThreshold);
        if Length(mergePairs) == 0 {
            return state;
        }

        // Merge first candidate pair
        let (idxA, idxB) = mergePairs[0];
        let merged = MergeClusters(
            state::Clusters[idxA],
            state::Clusters[idxB],
            state::NextClusterId,
            state::CurrentTimestamp
        );

        // Remove old clusters and add merged
        mutable newClusters = new ReplayCluster[0];
        for i in 0 .. Length(state::Clusters) - 1 {
            if i != idxA and i != idxB {
                set newClusters += [state::Clusters[i]];
            }
        }
        set newClusters += [merged];

        return ClusterManagerState(
            newClusters,
            state::ThresholdStates,
            state::GlobalThreshold,
            state::NextClusterId + 1,
            state::TotalSamples,
            state::TotalNovel,
            state::CurrentTimestamp,
            config
        );
    }

    /// Apply auto-pruning to remove stale clusters
    function AutoPruneClusters(
        state : ClusterManagerState
    ) : ClusterManagerState {
        let config = state::Config;
        if not config::EnablePruning or Length(state::Clusters) <= config::MinClusters {
            return state;
        }

        let pruned = PruneStaleClusters(
            state::Clusters,
            state::CurrentTimestamp,
            config::PruneAge
        );

        // Ensure minimum cluster count
        let finalClusters = if Length(pruned) < config::MinClusters {
            state::Clusters  // Keep original if pruning would go below minimum
        } else {
            pruned
        };

        return ClusterManagerState(
            finalClusters,
            state::ThresholdStates,
            state::GlobalThreshold,
            state::NextClusterId,
            state::TotalSamples,
            state::TotalNovel,
            state::CurrentTimestamp,
            config
        );
    }

    // =========================================================================
    // Statistics and Metrics
    // =========================================================================

    /// Compute overall novelty rate
    function NoveltyRate(state : ClusterManagerState) : Double {
        if state::TotalSamples == 0 {
            return 0.0;
        }
        return IntAsDouble(state::TotalNovel) / IntAsDouble(state::TotalSamples);
    }

    /// Compute mean cluster size
    function MeanClusterSize(state : ClusterManagerState) : Double {
        if Length(state::Clusters) == 0 {
            return 0.0;
        }
        mutable total = 0;
        for c in state::Clusters {
            set total += c::Samples;
        }
        return IntAsDouble(total) / IntAsDouble(Length(state::Clusters));
    }

    /// Compute mean intra-cluster Hamming distance
    function MeanIntraClusterDistance(state : ClusterManagerState) : Double {
        if Length(state::Clusters) == 0 {
            return 0.0;
        }
        mutable total = 0.0;
        for c in state::Clusters {
            set total += c::MeanHamming;
        }
        return total / IntAsDouble(Length(state::Clusters));
    }

    /// Compute cluster count statistics
    function ClusterCountStats(state : ClusterManagerState) : (Int, Int, Int) {
        let total = Length(state::Clusters);
        mutable active = 0;
        mutable stale = 0;
        for c in state::Clusters {
            if ClusterAge(c, state::CurrentTimestamp) <= state::Config::PruneAge {
                set active += 1;
            } else {
                set stale += 1;
            }
        }
        return (total, active, stale);
    }

    /// Compute total replay buffer capacity
    function TotalReplayCapacity(state : ClusterManagerState) : Int {
        return Length(state::Clusters) * state::Config::MaxSamplesPerCluster;
    }

    /// Compute replay buffer utilization
    function ReplayBufferUtilization(state : ClusterManagerState) : Double {
        let capacity = TotalReplayCapacity(state);
        if capacity == 0 {
            return 0.0;
        }
        return IntAsDouble(state::TotalSamples) / IntAsDouble(capacity);
    }

    // =========================================================================
    // Serialization for WebTransport
    // =========================================================================

    /// Serialize cluster state for Stream 6 (replay_clusters)
    function SerializeClusterForTransport(
        cluster : ReplayCluster
    ) : (Int, Int, Double, Int) {
        return (
            cluster::ClusterId,
            cluster::Samples,
            cluster::MeanHamming,
            cluster::Threshold
        );
    }

    /// Serialize all clusters for transport
    function SerializeAllClusters(
        clusters : ReplayCluster[]
    ) : (Int, Int, Double, Int)[] {
        mutable result = new (Int, Int, Double, Int)[Length(clusters)];
        for i in 0 .. Length(clusters) - 1 {
            set result w/= i <- SerializeClusterForTransport(clusters[i]);
        }
        return result;
    }

    /// Deserialize cluster from transport payload
    function DeserializeCluster(
        clusterId : Int,
        samples : Int,
        meanHamming : Double,
        threshold : Int,
        centroid : Int[],
        timestamp : Int
    ) : ReplayCluster {
        return ReplayCluster(
            clusterId,
            centroid,
            samples,
            meanHamming,
            threshold,
            0.0,
            timestamp,
            1.0
        );
    }

    // =========================================================================
    // Federated Cluster Synchronization
    // =========================================================================

    /// Merge cluster states from multiple nodes (federated aggregation)
    function FederatedClusterMerge(
        localClusters : ReplayCluster[],
        remoteClusters : ReplayCluster[],
        timestamp : Int
    ) : ReplayCluster[] {
        // Strategy: for each remote cluster, find nearest local cluster
        // If within merge threshold, merge; otherwise add as new cluster
        mutable result = localClusters;
        let mergeThreshold = 16;  // Default federated merge threshold

        for remote in remoteClusters {
            mutable bestIdx = -1;
            mutable bestDist = 2147483647;

            for i in 0 .. Length(result) - 1 {
                let d = HammingDistance(remote::Centroid, result[i]::Centroid);
                if d < bestDist {
                    set bestDist = d;
                    set bestIdx = i;
                }
            }

            if bestIdx >= 0 and bestDist <= mergeThreshold {
                // Merge with nearest local cluster
                let merged = MergeClusters(result[bestIdx], remote, result[bestIdx]::ClusterId, timestamp);
                set result w/= bestIdx <- merged;
            } else {
                // Add as new cluster
                set result += [remote];
            }
        }
        return result;
    }

    /// Compute cluster consensus across multiple nodes
    function ClusterConsensus(
        nodeClusterSets : ReplayCluster[][],
        minNodeAgreement : Int
    ) : ReplayCluster[] {
        if Length(nodeClusterSets) == 0 {
            return new ReplayCluster[0];
        }

        // Start with first node's clusters
        mutable consensus = nodeClusterSets[0];

        // For each subsequent node, merge clusters
        for nodeIdx in 1 .. Length(nodeClusterSets) - 1 {
            set consensus = FederatedClusterMerge(
                consensus,
                nodeClusterSets[nodeIdx],
                nodeIdx * 1000
            );
        }

        // Filter clusters that appear in at least minNodeAgreement nodes
        // (simplified: keep all merged clusters)
        return consensus;
    }

    // =========================================================================
    // AutoML Interface
    // =========================================================================

    /// Export manager state as feature vector for AutoML
    function ManagerStateToFeatures(state : ClusterManagerState) : Double[] {
        let (total, active, stale) = ClusterCountStats(state);
        return [
            IntAsDouble(Length(state::Clusters)),
            IntAsDouble(total),
            IntAsDouble(active),
            IntAsDouble(stale),
            NoveltyRate(state),
            MeanClusterSize(state),
            MeanIntraClusterDistance(state),
            IntAsDouble(state::GlobalThreshold),
            IntAsDouble(state::TotalSamples),
            IntAsDouble(state::TotalNovel),
            ReplayBufferUtilization(state),
            IntAsDouble(state::Config::MaxClusters),
            IntAsDouble(state::Config::ReplayBatchSize),
            state::Config::NoveltyWeight,
            state::Config::LossWeight
        ];
    }

    /// Apply AutoML hyperparameter update to manager config
    function ApplyAutoMLConfig(
        state : ClusterManagerState,
        newReplayBatchSize : Int,
        newNoveltyWeight : Double,
        newLossWeight : Double,
        newMergeThreshold : Int,
        newSplitThreshold : Int
    ) : ClusterManagerState {
        let oldConfig = state::Config;
        let newConfig = ClusterManagerConfig(
            oldConfig::MaxClusters,
            oldConfig::MinClusters,
            oldConfig::InitialClusters,
            oldConfig::MaxSamplesPerCluster,
            newReplayBatchSize,
            newNoveltyWeight,
            newLossWeight,
            newMergeThreshold,
            newSplitThreshold,
            oldConfig::PruneAge,
            oldConfig::ThresholdConfig,
            oldConfig::EnableAutoSplit,
            oldConfig::EnableAutoMerge,
            oldConfig::EnablePruning
        );
        return ClusterManagerState(
            state::Clusters,
            state::ThresholdStates,
            state::GlobalThreshold,
            state::NextClusterId,
            state::TotalSamples,
            state::TotalNovel,
            state::CurrentTimestamp,
            newConfig
        );
    }

    // =========================================================================
    // Logging Operations
    // =========================================================================

    /// Log manager state summary
    operation LogManagerState(state : ClusterManagerState) : Unit {
        let (total, active, stale) = ClusterCountStats(state);
        Message($"[ClusterManager] clusters={total} active={active} stale={stale} " +
                $"noveltyRate={NoveltyRate(state)} globalThreshold={state::GlobalThreshold} " +
                $"totalSamples={state::TotalSamples}");
    }

    /// Log replay batch selection
    operation LogReplayBatch(
        batchClusterIds : Int[],
        timestamp : Int
    ) : Unit {
        Message($"[Replay] t={timestamp} batch_size={Length(batchClusterIds)} " +
                $"clusters={batchClusterIds}");
    }

    /// Log cluster creation event
    operation LogClusterCreation(
        clusterId : Int,
        centroidHash : Int[],
        threshold : Int,
        timestamp : Int
    ) : Unit {
        Message($"[New Cluster] id={clusterId} threshold={threshold} t={timestamp}");
    }

    /// Log merge event
    operation LogMergeEvent(
        idA : Int,
        idB : Int,
        newId : Int,
        distance : Int
    ) : Unit {
        Message($"[Merge] clusters {idA}+{idB} → {newId} (centroid_dist={distance})");
    }

    /// Log prune event
    operation LogPruneEvent(
        prunedIds : Int[],
        remainingCount : Int
    ) : Unit {
        Message($"[Prune] removed={Length(prunedIds)} remaining={remainingCount}");
    }

    // =========================================================================
    // Entry Point for Cluster Manager
    // =========================================================================

    /// Run cluster manager for one step (process sample + maintenance)
    operation RunClusterManagerStep(
        state : ClusterManagerState,
        sample : Int[],
        loss : Double
    ) : ClusterManagerState {
        // Process sample
        mutable newState = ProcessSample(state, sample, loss);

        // Periodic maintenance
        let config = newState::Config;
        if newState::CurrentTimestamp % 100 == 0 {
            // Auto-merge
            set newState = AutoMergeClusters(newState);
            // Auto-prune
            set newState = AutoPruneClusters(newState);
            // Rebalance priorities
            let rebalanced = RebalancePriorities(newState::Clusters);
            set newState = ClusterManagerState(
                rebalanced,
                newState::ThresholdStates,
                newState::GlobalThreshold,
                newState::NextClusterId,
                newState::TotalSamples,
                newState::TotalNovel,
                newState::CurrentTimestamp,
                newState::Config
            );
            LogManagerState(newState);
        }

        return newState;
    }
}