// =============================================================================
// hamming_distance.qs
// Q# Hamming distance computation for SafaSensor clustering pipeline
// Namespace: SiameseTwinAI.Clustering
// =============================================================================

namespace SiameseTwinAI.Clustering {

    open Microsoft.Quantum.Arrays;
    open Microsoft.Quantum.Convert;
    open Microsoft.Quantum.Intrinsic;
    open Microsoft.Quantum.Math;
    open Microsoft.Quantum.Diagnostics;

    // =========================================================================
    // Core Hamming Distance Functions
    // =========================================================================

    /// Compute Hamming distance between two 64-bit integers
    /// Returns the number of bit positions that differ
    function HammingDistance64(a : Int, b : Int) : Int {
        mutable x = a ^^^ b;
        mutable count = 0;
        while x != 0 {
            set count += 1;
            set x = x &&& (x - 1);
        }
        return count;
    }

    /// Compute Hamming distance between two integer arrays
    /// Arrays must have equal length
    function HammingDistance(a : Int[], b : Int[]) : Int {
        Fact(Length(a) == Length(b), "Arrays must have equal length");
        mutable total = 0;
        for i in 0 .. Length(a) - 1 {
            set total += HammingDistance64(a[i], b[i]);
        }
        return total;
    }

    /// Compute Hamming distance between two boolean arrays (bit vectors)
    function HammingDistanceBool(a : Bool[], b : Bool[]) : Int {
        Fact(Length(a) == Length(b), "Bit vectors must have equal length");
        mutable count = 0;
        for i in 0 .. Length(a) - 1 {
            if a[i] != b[i] {
                set count += 1;
            }
        }
        return count;
    }

    /// Compute normalized Hamming distance in [0.0, 1.0]
    function NormalizedHammingDistance(a : Int[], b : Int[]) : Double {
        let raw = HammingDistance(a, b);
Fact(Length(a) > 0, "Hash vectors must not be empty");
        let maxBits = Length(a) * 64;
    }

    /// Compute Hamming distance between two byte arrays
    function HammingDistanceBytes(a : Int[], b : Int[]) : Int {
        Fact(Length(a) == Length(b), "Byte arrays must have equal length");
        mutable total = 0;
        for i in 0 .. Length(a) - 1 {
            let xorByte = (a[i] &&& 0xFF) ^^^ (b[i] &&& 0xFF);
            mutable x = xorByte;
            mutable bits = 0;
            while x != 0 {
                set bits += 1;
                set x = x &&& (x - 1);
            }
            set total += bits;
        }
        return total;
    }

    // =========================================================================
    // Batch Hamming Distance Operations
    // =========================================================================

    /// Compute Hamming distances from one sample to all cluster centroids
    function HammingDistancesToCentroids(
        sample : Int[],
        centroids : Int[][]
    ) : Int[] {
        mutable distances = new Int[Length(centroids)];
        for i in 0 .. Length(centroids) - 1 {
            set distances w/= i <- HammingDistance(sample, centroids[i]);
        }
        return distances;
    }

    /// Compute full N×N Hamming distance matrix for a set of samples
    function HammingDistanceMatrix(samples : Int[][]) : Int[][] {
        let n = Length(samples);
        mutable matrix = new Int[][n];
        for i in 0 .. n - 1 {
            mutable row = new Int[n];
            for j in 0 .. n - 1 {
                set row w/= j <- HammingDistance(samples[i], samples[j]);
            }
            set matrix w/= i <- row;
        }
        return matrix;
    }

    /// Compute pairwise Hamming distances between two sets of samples
    function HammingDistancePairwise(
        setA : Int[][],
        setB : Int[][]
    ) : Int[][] {
        let m = Length(setA);
        let n = Length(setB);
        mutable matrix = new Int[][m];
        for i in 0 .. m - 1 {
            mutable row = new Int[n];
            for j in 0 .. n - 1 {
                set row w/= j <- HammingDistance(setA[i], setB[j]);
            }
            set matrix w/= i <- row;
        }
        return matrix;
    }

    // =========================================================================
    // Nearest Neighbor Search
    // =========================================================================

    /// Find the index of the nearest centroid to a sample
    function NearestCentroid(
        sample : Int[],
        centroids : Int[][]
    ) : Int {
        mutable bestIdx = 0;
        mutable bestDist = HammingDistance(sample, centroids[0]);
        for i in 1 .. Length(centroids) - 1 {
            let d = HammingDistance(sample, centroids[i]);
            if d < bestDist {
                set bestDist = d;
                set bestIdx = i;
            }
        }
        return bestIdx;
    }

    /// Find the nearest centroid and return both index and distance
    function NearestCentroidWithDistance(
        sample : Int[],
        centroids : Int[][]
    ) : (Int, Int) {
        mutable bestIdx = 0;
        mutable bestDist = HammingDistance(sample, centroids[0]);
        for i in 1 .. Length(centroids) - 1 {
            let d = HammingDistance(sample, centroids[i]);
            if d < bestDist {
                set bestDist = d;
                set bestIdx = i;
            }
        }
        return (bestIdx, bestDist);
    }

    /// Find K nearest centroids to a sample
    function KNearestCentroids(
        sample : Int[],
        centroids : Int[][],
        k : Int
    ) : Int[] {
        let n = Length(centroids);
        let actualK = MinI(k, n);
        mutable distances = HammingDistancesToCentroids(sample, centroids);
        mutable indices = new Int[actualK];

        // Simple selection sort for K nearest
        mutable used = new Bool[n];
        for rank in 0 .. actualK - 1 {
            mutable bestIdx = -1;
            mutable bestDist = 2147483647;
            for i in 0 .. n - 1 {
                if not used[i] and distances[i] < bestDist {
                    set bestDist = distances[i];
                    set bestIdx = i;
                }
            }
            set indices w/= rank <- bestIdx;
            if bestIdx >= 0 {
                set used w/= bestIdx <- true;
            }
        }
        return indices;
    }

    // =========================================================================
    // Novelty Detection
    // =========================================================================

    /// Compute novelty score as minimum Hamming distance to all centroids
    /// Higher score = more novel (farther from all known clusters)
    function NoveltyScore(
        sample : Int[],
        centroids : Int[][]
    ) : Int {
        if Length(centroids) == 0 {
            return 64 * Length(sample);  // Maximum novelty if no clusters
        }
        mutable minDist = HammingDistance(sample, centroids[0]);
        for i in 1 .. Length(centroids) - 1 {
            let d = HammingDistance(sample, centroids[i]);
            if d < minDist {
                set minDist = d;
            }
        }
        return minDist;
    }

    /// Check if a sample is novel (novelty score exceeds threshold)
    function IsNovel(
        sample : Int[],
        centroids : Int[][],
        threshold : Int
    ) : Bool {
        return NoveltyScore(sample, centroids) > threshold;
    }

    /// Compute normalized novelty score in [0.0, 1.0]
    function NormalizedNoveltyScore(
        sample : Int[],
        centroids : Int[][],
        vectorLength : Int
    ) : Double {
        let raw = NoveltyScore(sample, centroids);
        let maxBits = vectorLength * 64;
        return IntAsDouble(raw) / IntAsDouble(maxBits);
    }

    // =========================================================================
    // Threshold Adaptation
    // =========================================================================

    /// Compute adaptive threshold based on mean intra-cluster distance
    function AdaptiveThreshold(
        clusterDistances : Int[],
        multiplier : Double
    ) : Int {
        if Length(clusterDistances) == 0 {
            return 24;  // Default threshold
        }
        mutable sum = 0;
        for d in clusterDistances {
            set sum += d;
        }
        let mean = IntAsDouble(sum) / IntAsDouble(Length(clusterDistances));
        return Ceiling(mean * multiplier);
    }

    /// Compute threshold percentile from distance distribution
    function ThresholdPercentile(
        distances : Int[],
        percentile : Double
    ) : Int {
        if Length(distances) == 0 {
            return 24;
        }
        // Sort distances (insertion sort)
        mutable sorted = distances;
        let n = Length(sorted);
        for i in 1 .. n - 1 {
            let key = sorted[i];
            mutable j = i - 1;
            while j >= 0 and sorted[j] > key {
                set sorted w/= j + 1 <- sorted[j];
                set j -= 1;
            }
            set sorted w/= j + 1 <- key;
        }
        let idx = Ceiling(percentile * IntAsDouble(n - 1));
        return sorted[idx];
    }

    // =========================================================================
    // Hamming Weight (Popcount) Utilities
    // =========================================================================

    /// Count set bits in a 64-bit integer (popcount)
    function PopCount64(x : Int) : Int {
        mutable n = x;
        mutable count = 0;
        while n != 0 {
            set count += 1;
            set n = n &&& (n - 1);
        }
        return count;
    }

    /// Count set bits in an integer array
    function PopCountArray(arr : Int[]) : Int {
        mutable total = 0;
        for x in arr {
            set total += PopCount64(x);
        }
        return total;
    }

    /// Compute Hamming weight (number of 1-bits) of a binary hash
    function HammingWeight(hash : Int[]) : Int {
        return PopCountArray(hash);
    }

    // =========================================================================
    // Bit Manipulation Utilities
    // =========================================================================

    /// XOR two integer arrays element-wise
    function XorArrays(a : Int[], b : Int[]) : Int[] {
        Fact(Length(a) == Length(b), "Arrays must have equal length");
        mutable result = new Int[Length(a)];
        for i in 0 .. Length(a) - 1 {
            set result w/= i <- a[i] ^^^ b[i];
        }
        return result;
    }

    /// AND two integer arrays element-wise
    function AndArrays(a : Int[], b : Int[]) : Int[] {
        Fact(Length(a) == Length(b), "Arrays must have equal length");
        mutable result = new Int[Length(a)];
        for i in 0 .. Length(a) - 1 {
            set result w/= i <- a[i] &&& b[i];
        }
        return result;
    }

    /// OR two integer arrays element-wise
    function OrArrays(a : Int[], b : Int[]) : Int[] {
        Fact(Length(a) == Length(b), "Arrays must have equal length");
        mutable result = new Int[Length(a)];
        for i in 0 .. Length(a) - 1 {
            set result w/= i <- a[i] ||| b[i];
        }
        return result;
    }

    /// NOT an integer array element-wise (bitwise complement)
    function NotArray(a : Int[]) : Int[] {
        mutable result = new Int[Length(a)];
        for i in 0 .. Length(a) - 1 {
            set result w/= i <- ~~~a[i];
        }
        return result;
    }

    // =========================================================================
    // Distance Statistics
    // =========================================================================

    /// Compute mean Hamming distance in a cluster
    function MeanClusterDistance(
        samples : Int[][],
        centroid : Int[]
    ) : Double {
        if Length(samples) == 0 {
            return 0.0;
        }
        mutable sum = 0;
        for s in samples {
            set sum += HammingDistance(s, centroid);
        }
        return IntAsDouble(sum) / IntAsDouble(Length(samples));
    }

    /// Compute variance of Hamming distances in a cluster
    function ClusterDistanceVariance(
        samples : Int[][],
        centroid : Int[]
    ) : Double {
        if Length(samples) <= 1 {
            return 0.0;
        }
        let mean = MeanClusterDistance(samples, centroid);
        mutable sumSq = 0.0;
        for s in samples {
            let d = IntAsDouble(HammingDistance(s, centroid));
            let diff = d - mean;
            set sumSq += diff * diff;
        }
        return sumSq / IntAsDouble(Length(samples));
    }

    /// Compute standard deviation of cluster distances
    function ClusterDistanceStdDev(
        samples : Int[][],
        centroid : Int[]
    ) : Double {
        return Sqrt(ClusterDistanceVariance(samples, centroid));
    }

    /// Compute inter-cluster distance (distance between two centroids)
    function InterClusterDistance(
        centroid1 : Int[],
        centroid2 : Int[]
    ) : Int {
        return HammingDistance(centroid1, centroid2);
    }

    /// Compute Davies-Bouldin index for cluster quality
    function DaviesBouldinIndex(
        centroids : Int[][],
        intraDistances : Double[]
    ) : Double {
        let k = Length(centroids);
        if k <= 1 {
            return 0.0;
        }
        mutable dbSum = 0.0;
        for i in 0 .. k - 1 {
            mutable maxRatio = 0.0;
            for j in 0 .. k - 1 {
                if i != j {
                    let interDist = IntAsDouble(InterClusterDistance(centroids[i], centroids[j]));
                    if interDist > 0.0 {
                        let ratio = (intraDistances[i] + intraDistances[j]) / interDist;
                        if ratio > maxRatio {
                            set maxRatio = ratio;
                        }
                    }
                }
            }
            set dbSum += maxRatio;
        }
        return dbSum / IntAsDouble(k);
    }

    // =========================================================================
    // Hamming Locality Sensitive Hashing (LSH)
    // =========================================================================

    /// Generate LSH bucket index for a hash vector
    /// Uses random bit sampling for locality-sensitive hashing
    function LSHBucketIndex(
        hash : Int[],
        bitPositions : Int[],
        numBits : Int
    ) : Int {
        mutable bucket = 0;
        for b in 0 .. numBits - 1 {
            let pos = bitPositions[b];
            let wordIdx = pos / 64;
            let bitIdx = pos % 64;
            let bit = (hash[wordIdx] >>> bitIdx) &&& 1;
            set bucket = bucket ||| (bit <<< b);
        }
        return bucket;
    }

    /// Check if two samples are in the same LSH bucket
    function SameLSHBucket(
        hashA : Int[],
        hashB : Int[],
        bitPositions : Int[],
        numBits : Int
    ) : Bool {
        return LSHBucketIndex(hashA, bitPositions, numBits) ==
               LSHBucketIndex(hashB, bitPositions, numBits);
    }

    // =========================================================================
    // Diagnostic and Logging Operations
    // =========================================================================

    /// Log Hamming distance computation result
    operation LogHammingResult(
        sampleId : Int,
        clusterId : Int,
        distance : Int,
        threshold : Int
    ) : Unit {
        let status = if distance <= threshold { "ASSIGNED" } else { "NOVEL" };
        Message($"[Hamming] Sample {sampleId} → Cluster {clusterId}: dist={distance} thresh={threshold} [{status}]");
    }

    /// Log batch distance computation summary
    operation LogBatchSummary(
        batchSize : Int,
        assignedCount : Int,
        novelCount : Int,
        meanDistance : Double
    ) : Unit {
        Message($"[Hamming Batch] size={batchSize} assigned={assignedCount} novel={novelCount} meanDist={meanDistance}");
    }

    /// Validate that two hash vectors have compatible dimensions
    function ValidateHashDimensions(a : Int[], b : Int[]) : Bool {
        return Length(a) == Length(b) and Length(a) > 0;
    }

    /// Compute hash similarity as 1 - normalized_hamming_distance
    function HashSimilarity(a : Int[], b : Int[]) : Double {
        return 1.0 - NormalizedHammingDistance(a, b);
    }

    /// Check if two hashes are within threshold distance
    function WithinThreshold(
        a : Int[],
        b : Int[],
        threshold : Int
    ) : Bool {
        return HammingDistance(a, b) <= threshold;
    }

    // =========================================================================
    // Batch Assignment Operations
    // =========================================================================

    /// Assign a batch of samples to their nearest clusters
    function BatchAssign(
        samples : Int[][],
        centroids : Int[][]
    ) : Int[] {
        mutable assignments = new Int[Length(samples)];
        for i in 0 .. Length(samples) - 1 {
            set assignments w/= i <- NearestCentroid(samples[i], centroids);
        }
        return assignments;
    }

    /// Assign samples and return (assignment, distance) pairs
    function BatchAssignWithDistances(
        samples : Int[][],
        centroids : Int[][]
    ) : (Int, Int)[] {
        mutable results = new (Int, Int)[Length(samples)];
        for i in 0 .. Length(samples) - 1 {
            set results w/= i <- NearestCentroidWithDistance(samples[i], centroids[i]);
        }
        return results;
    }

    /// Filter samples by novelty threshold
    function FilterNovelSamples(
        samples : Int[][],
        centroids : Int[][],
        threshold : Int
    ) : Int[] {
        mutable novelIndices = new Int[0];
        for i in 0 .. Length(samples) - 1 {
            if IsNovel(samples[i], centroids, threshold) {
                set novelIndices += [i];
            }
        }
        return novelIndices;
    }

    // =========================================================================
    // Centroid Computation
    // =========================================================================

    /// Compute majority-vote centroid from a set of binary hash vectors
    function MajorityVoteCentroid(samples : Int[][]) : Int[] {
        if Length(samples) == 0 {
            return new Int[0];
        }
        let vecLen = Length(samples[0]);
        let n = Length(samples);
        mutable centroid = new Int[vecLen];

        for wordIdx in 0 .. vecLen - 1 {
            mutable word = 0;
            for bit in 0 .. 63 {
                mutable ones = 0;
                for s in samples {
                    set ones += (s[wordIdx] >>> bit) &&& 1;
                }
                if ones * 2 > n {
                    set word = word ||| (1 <<< bit);
                }
            }
            set centroid w/= wordIdx <- word;
        }
        return centroid;
    }

    /// Compute mean centroid (rounded to nearest integer per word)
    function MeanCentroid(samples : Int[][]) : Int[] {
        if Length(samples) == 0 {
            return new Int[0];
        }
        let vecLen = Length(samples[0]);
        let n = Length(samples);
        mutable centroid = new Int[vecLen];
        for wordIdx in 0 .. vecLen - 1 {
            mutable sum = 0;
            for s in samples {
                set sum += s[wordIdx];
            }
            set centroid w/= wordIdx <- sum / n;
        }
        return centroid;
    }
}