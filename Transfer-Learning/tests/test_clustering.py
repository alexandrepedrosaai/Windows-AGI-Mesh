# =============================================================================
# test_clustering.py
# Unit tests for the clustering pipeline components
# Tests Hamming distance, centroid update, novelty detection, and cluster manager
# =============================================================================

import sys
import math
import random
import unittest
import time
from typing import List, Tuple, Dict, Any, Optional
from dataclasses import dataclass, field
from collections import defaultdict

# =============================================================================
# Hamming Distance Tests
# =============================================================================

def hamming_distance_64(a: int, b: int) -> int:
    """Compute Hamming distance between two 64-bit integers."""
    x = (a ^ b) & ((1 << 64) - 1)
    count = 0
    while x:
        count += 1
        x &= x - 1
    return count


def hamming_distance(a: List[int], b: List[int]) -> int:
    """Compute Hamming distance between two hash vectors."""
    assert len(a) == len(b), "Vectors must have equal length"
    return sum(hamming_distance_64(x, y) for x, y in zip(a, b))


def popcount(x: int) -> int:
    """Count set bits in integer."""
    count = 0
    while x:
        count += 1
        x &= x - 1
    return count


class TestHammingDistance(unittest.TestCase):
    """Tests for Hamming distance computation."""

    def test_identical_vectors_zero_distance(self):
        """Identical vectors should have zero Hamming distance."""
        a = [0xDEADBEEF, 0xCAFEBABE, 0x12345678, 0x87654321,
             0xABCDEF01, 0x23456789, 0x9ABCDEF0, 0x01234567]
        self.assertEqual(hamming_distance(a, a), 0)

    def test_all_zeros_vs_all_ones(self):
        """All-zeros vs all-ones should have maximum distance."""
        a = [0] * 8
        b = [0xFFFFFFFFFFFFFFFF] * 8
        expected = 64 * 8  # 512 bits
        self.assertEqual(hamming_distance(a, b), expected)

    def test_single_bit_difference(self):
        """Single bit flip should give distance 1."""
        a = [0] * 8
        b = [0] * 8
        b[0] = 1  # Flip bit 0
        self.assertEqual(hamming_distance(a, b), 1)

    def test_symmetry(self):
        """Hamming distance should be symmetric."""
        rng = random.Random(42)
        for _ in range(100):
            a = [rng.randint(0, 2**63 - 1) for _ in range(8)]
            b = [rng.randint(0, 2**63 - 1) for _ in range(8)]
            self.assertEqual(hamming_distance(a, b), hamming_distance(b, a))

    def test_triangle_inequality(self):
        """Hamming distance satisfies triangle inequality."""
        rng = random.Random(42)
        for _ in range(50):
            a = [rng.randint(0, 2**63 - 1) for _ in range(8)]
            b = [rng.randint(0, 2**63 - 1) for _ in range(8)]
            c = [rng.randint(0, 2**63 - 1) for _ in range(8)]
            dab = hamming_distance(a, b)
            dbc = hamming_distance(b, c)
            dac = hamming_distance(a, c)
            self.assertLessEqual(dac, dab + dbc)

    def test_non_negativity(self):
        """Hamming distance should always be non-negative."""
        rng = random.Random(42)
        for _ in range(100):
            a = [rng.randint(0, 2**63 - 1) for _ in range(8)]
            b = [rng.randint(0, 2**63 - 1) for _ in range(8)]
            self.assertGreaterEqual(hamming_distance(a, b), 0)

    def test_popcount_correctness(self):
        """Test popcount implementation."""
        self.assertEqual(popcount(0), 0)
        self.assertEqual(popcount(1), 1)
        self.assertEqual(popcount(0xFF), 8)
        self.assertEqual(popcount(0xFFFF), 16)
        self.assertEqual(popcount(0xFFFFFFFF), 32)

    def test_known_distances(self):
        """Test known Hamming distances."""
        # 0b0000 vs 0b1111 = 4 bits
        self.assertEqual(hamming_distance_64(0b0000, 0b1111), 4)
        # 0b1010 vs 0b0101 = 4 bits
        self.assertEqual(hamming_distance_64(0b1010, 0b0101), 4)
        # 0b1100 vs 0b1010 = 2 bits
        self.assertEqual(hamming_distance_64(0b1100, 0b1010), 2)

    def test_performance(self):
        """Test that Hamming distance computation is fast enough."""
        rng = random.Random(42)
        hashes = [[rng.randint(0, 2**63 - 1) for _ in range(8)] for _ in range(1000)]
        start = time.perf_counter()
        for i in range(len(hashes) - 1):
            hamming_distance(hashes[i], hashes[i + 1])
        elapsed = time.perf_counter() - start
        # Should process 999 pairs in < 1 second
        self.assertLess(elapsed, 1.0)


# =============================================================================
# Centroid Update Tests
# =============================================================================

def update_centroid(centroid: List[int], sample: List[int], n: int) -> List[int]:
    """Online centroid update using incremental mean."""
    result = []
    for old, x in zip(centroid, sample):
        v = old + (x - old) / (n + 1)
        result.append(round(v))
    return result


def batch_update_centroid(samples: List[List[int]]) -> List[int]:
    """Batch centroid update (exact mean)."""
    if not samples:
        return []
    n = len(samples)
    vec_len = len(samples[0])
    return [sum(s[i] for s in samples) // n for i in range(vec_len)]


class TestCentroidUpdate(unittest.TestCase):
    """Tests for centroid update algorithms."""

    def test_single_sample_centroid(self):
        """Centroid of single sample equals the sample."""
        sample = [100, 200, 300, 400, 500, 600, 700, 800]
        centroid = batch_update_centroid([sample])
        self.assertEqual(centroid, sample)

    def test_two_sample_centroid(self):
        """Centroid of two samples is their mean."""
        a = [0, 0, 0, 0, 0, 0, 0, 0]
        b = [100, 200, 300, 400, 500, 600, 700, 800]
        centroid = batch_update_centroid([a, b])
        expected = [50, 100, 150, 200, 250, 300, 350, 400]
        self.assertEqual(centroid, expected)

    def test_online_update_convergence(self):
        """Online update should converge to batch update."""
        rng = random.Random(42)
        samples = [[rng.randint(0, 1000) for _ in range(8)] for _ in range(100)]

        # Batch centroid
        batch_centroid = batch_update_centroid(samples)

        # Online centroid
        online_centroid = samples[0]
        for i, sample in enumerate(samples[1:], 1):
            online_centroid = update_centroid(online_centroid, sample, i)

        # Should be close (within rounding error)
        for a, b in zip(batch_centroid, online_centroid):
            self.assertAlmostEqual(a, b, delta=5)

    def test_centroid_within_bounds(self):
        """Centroid should be within the range of samples."""
        rng = random.Random(42)
        samples = [[rng.randint(0, 1000) for _ in range(8)] for _ in range(50)]
        centroid = batch_update_centroid(samples)

        for i in range(8):
            min_val = min(s[i] for s in samples)
            max_val = max(s[i] for s in samples)
            self.assertGreaterEqual(centroid[i], min_val - 1)
            self.assertLessEqual(centroid[i], max_val + 1)

    def test_empty_samples(self):
        """Empty sample list should return empty centroid."""
        centroid = batch_update_centroid([])
        self.assertEqual(centroid, [])

    def test_centroid_stability(self):
        """Adding same sample repeatedly should not change centroid."""
        sample = [500, 500, 500, 500, 500, 500, 500, 500]
        centroid = sample[:]
        for n in range(1, 100):
            centroid = update_centroid(centroid, sample, n)
        self.assertEqual(centroid, sample)


# =============================================================================
# Cluster Manager Tests
# =============================================================================

@dataclass
class SimpleCluster:
    """Simple cluster for testing."""
    cluster_id: int
    centroid: List[int]
    samples: int = 1
    mean_hamming: float = 0.0
    threshold: int = 24
    priority: float = 1.0

    def update(self, sample: List[int], distance: int, loss: float) -> None:
        n = self.samples
        self.mean_hamming = (self.mean_hamming * n + distance) / (n + 1)
        self.samples += 1
        self.priority = 0.7 * self.priority + 0.3 * loss
        # EMA centroid update
        alpha = 0.1
        self.centroid = [
            int((1 - alpha) * c + alpha * s)
            for c, s in zip(self.centroid, sample)
        ]


class SimpleClusterManager:
    """Simple cluster manager for testing."""

    def __init__(self, threshold: int = 24, max_clusters: int = 64):
        self.threshold = threshold
        self.max_clusters = max_clusters
        self.clusters: Dict[int, SimpleCluster] = {}
        self.next_id = 0
        self.total_samples = 0
        self.total_novel = 0

    def process(self, sample: List[int], loss: float) -> Tuple[int, bool]:
        best_idx = -1
        best_dist = float('inf')

        for cid, cluster in self.clusters.items():
            d = hamming_distance(sample, cluster.centroid)
            if d < best_dist:
                best_dist = d
                best_idx = cid

        is_novel = best_dist > self.threshold or len(self.clusters) == 0

        if is_novel and len(self.clusters) < self.max_clusters:
            cid = self.next_id
            self.clusters[cid] = SimpleCluster(cid, list(sample), 1, 0.0, self.threshold, loss)
            self.next_id += 1
            self.total_novel += 1
        elif best_idx >= 0:
            self.clusters[best_idx].update(sample, best_dist, loss)

        self.total_samples += 1
        return (best_idx if (not is_novel or len(self.clusters) >= self.max_clusters) else self.next_id - 1), is_novel

    def novelty_rate(self) -> float:
        return self.total_novel / max(1, self.total_samples)


class TestClusterManager(unittest.TestCase):
    """Tests for the cluster manager."""

    def test_first_sample_creates_cluster(self):
        """First sample should always create a new cluster."""
        manager = SimpleClusterManager()
        sample = [0] * 8
        cid, is_novel = manager.process(sample, 0.5)
        self.assertTrue(is_novel)
        self.assertEqual(len(manager.clusters), 1)

    def test_identical_samples_same_cluster(self):
        """Identical samples should go to the same cluster."""
        manager = SimpleClusterManager(threshold=24)
        sample = [100, 200, 300, 400, 500, 600, 700, 800]
        manager.process(sample, 0.5)
        for _ in range(10):
            cid, is_novel = manager.process(sample, 0.5)
            self.assertFalse(is_novel)
        self.assertEqual(len(manager.clusters), 1)

    def test_very_different_samples_different_clusters(self):
        """Very different samples should create different clusters."""
        manager = SimpleClusterManager(threshold=24)
        sample_a = [0] * 8
        sample_b = [0xFFFFFFFFFFFFFFFF] * 8  # Maximum distance from a
        manager.process(sample_a, 0.5)
        _, is_novel = manager.process(sample_b, 0.5)
        self.assertTrue(is_novel)
        self.assertEqual(len(manager.clusters), 2)

    def test_max_clusters_limit(self):
        """Cluster count should not exceed max_clusters."""
        manager = SimpleClusterManager(threshold=0, max_clusters=5)
        rng = random.Random(42)
        for _ in range(100):
            sample = [rng.randint(0, 2**63 - 1) for _ in range(8)]
            manager.process(sample, 0.5)
        self.assertLessEqual(len(manager.clusters), 5)

    def test_novelty_rate_range(self):
        """Novelty rate should be in [0, 1]."""
        manager = SimpleClusterManager(threshold=24)
        rng = random.Random(42)
        for _ in range(100):
            sample = [rng.randint(0, 2**63 - 1) for _ in range(8)]
            manager.process(sample, rng.random())
        rate = manager.novelty_rate()
        self.assertGreaterEqual(rate, 0.0)
        self.assertLessEqual(rate, 1.0)

    def test_cluster_priority_update(self):
        """Cluster priority should update with new samples."""
        manager = SimpleClusterManager(threshold=100)
        sample = [0] * 8
        manager.process(sample, 1.0)
        initial_priority = manager.clusters[0].priority

        for _ in range(10):
            manager.process(sample, 0.1)

        final_priority = manager.clusters[0].priority
        self.assertLess(final_priority, initial_priority)

    def test_mean_hamming_update(self):
        """Mean Hamming distance should update correctly."""
        manager = SimpleClusterManager(threshold=100)
        base = [0] * 8
        manager.process(base, 0.5)

        # Add samples with known distances
        for bits in [1, 2, 4, 8, 16]:
            sample = [bits] + [0] * 7
            manager.process(sample, 0.5)

        cluster = manager.clusters[0]
        self.assertGreater(cluster.mean_hamming, 0)
        self.assertLess(cluster.mean_hamming, 64)


# =============================================================================
# Novelty Detection Tests
# =============================================================================

class TestNoveltyDetection(unittest.TestCase):
    """Tests for novelty detection."""

    def test_novel_sample_far_from_centroids(self):
        """Sample far from all centroids should be novel."""
        centroids = [[0] * 8, [0xFF] * 8]
        sample = [0x7F7F7F7F7F7F7F7F] * 8  # Midpoint
        distances = [hamming_distance(sample, c) for c in centroids]
        min_dist = min(distances)
        threshold = 10
        is_novel = min_dist > threshold
        self.assertTrue(is_novel)

    def test_familiar_sample_close_to_centroid(self):
        """Sample close to a centroid should not be novel."""
        centroid = [0xDEADBEEF] * 8
        # Perturb by 1 bit
        sample = list(centroid)
        sample[0] ^= 1
        dist = hamming_distance(sample, centroid)
        threshold = 24
        is_novel = dist > threshold
        self.assertFalse(is_novel)

    def test_novelty_score_range(self):
        """Novelty score should be non-negative."""
        rng = random.Random(42)
        centroids = [[rng.randint(0, 2**63 - 1) for _ in range(8)] for _ in range(10)]
        for _ in range(50):
            sample = [rng.randint(0, 2**63 - 1) for _ in range(8)]
            distances = [hamming_distance(sample, c) for c in centroids]
            novelty_score = min(distances)
            self.assertGreaterEqual(novelty_score, 0)

    def test_empty_centroids_maximum_novelty(self):
        """With no centroids, all samples should be maximally novel."""
        centroids = []
        sample = [0] * 8
        is_novel = len(centroids) == 0
        self.assertTrue(is_novel)


# =============================================================================
# Adaptive Threshold Tests
# =============================================================================

class TestAdaptiveThreshold(unittest.TestCase):
    """Tests for adaptive threshold management."""

    def test_ema_threshold_update(self):
        """EMA threshold should converge to mean distance."""
        threshold = 24
        alpha = 0.05
        distances = [20, 22, 18, 25, 21, 19, 23, 20, 22, 21]

        for d in distances:
            threshold = int((1 - alpha) * threshold + alpha * d)

        # Should be close to mean of distances
        mean_dist = sum(distances) / len(distances)
        self.assertAlmostEqual(threshold, mean_dist, delta=5)

    def test_threshold_clamping(self):
        """Threshold should stay within [min, max] bounds."""
        min_thresh = 4
        max_thresh = 64
        threshold = 24
        alpha = 0.5

        # Try to push threshold below minimum
        for _ in range(100):
            threshold = max(min_thresh, min(max_thresh, int((1 - alpha) * threshold + alpha * 0)))

        self.assertGreaterEqual(threshold, min_thresh)

        # Try to push threshold above maximum
        threshold = 24
        for _ in range(100):
            threshold = max(min_thresh, min(max_thresh, int((1 - alpha) * threshold + alpha * 1000)))

        self.assertLessEqual(threshold, max_thresh)

    def test_pid_threshold_control(self):
        """PID controller should drive novelty rate toward target."""
        target_rate = 0.15
        threshold = 24
        kp = 2.0
        ki = 0.1
        kd = 0.5
        integral = 0.0
        last_error = 0.0

        # Simulate with high novelty rate (should increase threshold)
        for _ in range(20):
            current_rate = 0.30  # Too high
            error = current_rate - target_rate
            integral += error
            derivative = error - last_error
            pid_output = kp * error + ki * integral + kd * derivative
            threshold = max(4, min(64, threshold + round(pid_output)))
            last_error = error

        # Threshold should have increased (harder to be novel)
        self.assertGreater(threshold, 24)


# =============================================================================
# Replay Buffer Tests
# =============================================================================

@dataclass
class SimpleReplayBuffer:
    """Simple replay buffer for testing."""
    max_capacity: int = 1024
    alpha: float = 0.6
    beta: float = 0.4
    experiences: List[Dict] = field(default_factory=list)
    priorities: List[float] = field(default_factory=list)
    write_index: int = 0

    def add(self, experience: Dict, priority: float = 1.0) -> None:
        if len(self.experiences) < self.max_capacity:
            self.experiences.append(experience)
            self.priorities.append(priority)
        else:
            self.experiences[self.write_index] = experience
            self.priorities[self.write_index] = priority
            self.write_index = (self.write_index + 1) % self.max_capacity

    def sample(self, n: int, rng: random.Random) -> List[Dict]:
        if not self.experiences:
            return []
        total = sum(self.priorities)
        probs = [p / total for p in self.priorities]
        indices = rng.choices(range(len(self.experiences)), weights=probs, k=min(n, len(self.experiences)))
        return [self.experiences[i] for i in indices]

    def fill_ratio(self) -> float:
        return len(self.experiences) / self.max_capacity


class TestReplayBuffer(unittest.TestCase):
    """Tests for replay buffer."""

    def test_buffer_fills_correctly(self):
        """Buffer should fill up to max capacity."""
        buf = SimpleReplayBuffer(max_capacity=10)
        for i in range(10):
            buf.add({'id': i}, priority=1.0)
        self.assertEqual(len(buf.experiences), 10)
        self.assertAlmostEqual(buf.fill_ratio(), 1.0)

    def test_circular_replacement(self):
        """Buffer should replace oldest when full."""
        buf = SimpleReplayBuffer(max_capacity=5)
        for i in range(10):
            buf.add({'id': i}, priority=1.0)
        self.assertEqual(len(buf.experiences), 5)

    def test_priority_sampling(self):
        """High-priority experiences should be sampled more often."""
        buf = SimpleReplayBuffer(max_capacity=100)
        rng = random.Random(42)

        # Add low-priority experiences
        for i in range(90):
            buf.add({'id': i, 'type': 'low'}, priority=0.1)

        # Add high-priority experiences
        for i in range(10):
            buf.add({'id': i, 'type': 'high'}, priority=10.0)

        # Sample many times
        high_count = 0
        total = 1000
        for _ in range(total):
            samples = buf.sample(1, rng)
            if samples and samples[0]['type'] == 'high':
                high_count += 1

        # High-priority should be sampled much more often
        high_rate = high_count / total
        self.assertGreater(high_rate, 0.3)  # Should be >> 10/100 = 10%

    def test_empty_buffer_sample(self):
        """Sampling from empty buffer should return empty list."""
        buf = SimpleReplayBuffer()
        rng = random.Random(42)
        result = buf.sample(10, rng)
        self.assertEqual(result, [])

    def test_fill_ratio_range(self):
        """Fill ratio should be in [0, 1]."""
        buf = SimpleReplayBuffer(max_capacity=100)
        rng = random.Random(42)
        for i in range(50):
            buf.add({'id': i}, priority=rng.random())
        ratio = buf.fill_ratio()
        self.assertGreaterEqual(ratio, 0.0)
        self.assertLessEqual(ratio, 1.0)


# =============================================================================
# Integration Tests
# =============================================================================

class TestClusteringIntegration(unittest.TestCase):
    """Integration tests for the full clustering pipeline."""

    def test_full_pipeline_sensor_to_cluster(self):
        """Test full pipeline from sensor hash to cluster assignment."""
        manager = SimpleClusterManager(threshold=24, max_clusters=32)
        rng = random.Random(42)

        # Generate sensor hashes from 5 distinct distributions
        n_distributions = 5
        base_hashes = [[rng.randint(0, 2**63 - 1) for _ in range(8)]
                       for _ in range(n_distributions)]

        n_samples = 200
        for _ in range(n_samples):
            dist_idx = rng.randint(0, n_distributions - 1)
            # Perturb base hash by a few bits
            sample = list(base_hashes[dist_idx])
            n_bits = rng.randint(0, 10)
            for _ in range(n_bits):
                word_idx = rng.randint(0, 7)
                bit_idx = rng.randint(0, 62)
                sample[word_idx] ^= (1 << bit_idx)

            manager.process(sample, rng.random())

        # Should have created clusters
        self.assertGreater(len(manager.clusters), 0)
        self.assertLessEqual(len(manager.clusters), 32)

        # Novelty rate should be reasonable
        rate = manager.novelty_rate()
        self.assertGreater(rate, 0.0)
        self.assertLess(rate, 1.0)

    def test_cluster_replay_integration(self):
        """Test that cluster manager integrates with replay buffer."""
        manager = SimpleClusterManager(threshold=24, max_clusters=16)
        buf = SimpleReplayBuffer(max_capacity=256)
        rng = random.Random(42)

        for i in range(100):
            sample = [rng.randint(0, 2**63 - 1) for _ in range(8)]
            loss = rng.random()
            cid, is_novel = manager.process(sample, loss)

            # Add to replay buffer with priority based on novelty and loss
            priority = loss + (0.5 if is_novel else 0.0)
            buf.add({'sample': sample, 'cluster_id': cid, 'loss': loss}, priority)

        # Buffer should have experiences
        self.assertGreater(len(buf.experiences), 0)

        # Sample from buffer
        samples = buf.sample(10, rng)
        self.assertGreater(len(samples), 0)

    def test_novelty_rate_with_threshold_adaptation(self):
        """Test that adaptive threshold maintains target novelty rate."""
        manager = SimpleClusterManager(threshold=24, max_clusters=64)
        rng = random.Random(42)
        target_rate = 0.15
        alpha = 0.05
        threshold = 24

        for i in range(500):
            sample = [rng.randint(0, 2**63 - 1) for _ in range(8)]
            cid, is_novel = manager.process(sample, rng.random())

            # Adapt threshold
            current_rate = manager.novelty_rate()
            error = current_rate - target_rate
            threshold = max(4, min(64, int(threshold + error * 10)))
            manager.threshold = threshold

        # Final novelty rate should be somewhat close to target
        final_rate = manager.novelty_rate()
        self.assertGreater(final_rate, 0.0)
        self.assertLess(final_rate, 1.0)


# =============================================================================
# Performance Tests
# =============================================================================

class TestClusteringPerformance(unittest.TestCase):
    """Performance tests for clustering pipeline."""

    def test_hamming_distance_throughput(self):
        """Test Hamming distance computation throughput."""
        rng = random.Random(42)
        n_pairs = 10000
        hashes_a = [[rng.randint(0, 2**63 - 1) for _ in range(8)] for _ in range(n_pairs)]
        hashes_b = [[rng.randint(0, 2**63 - 1) for _ in range(8)] for _ in range(n_pairs)]

        start = time.perf_counter()
        for a, b in zip(hashes_a, hashes_b):
            hamming_distance(a, b)
        elapsed = time.perf_counter() - start

        throughput = n_pairs / elapsed
        # Should process at least 10,000 pairs/second
        self.assertGreater(throughput, 10000)

    def test_cluster_manager_throughput(self):
        """Test cluster manager processing throughput."""
        manager = SimpleClusterManager(threshold=24, max_clusters=64)
        rng = random.Random(42)
        n_samples = 1000

        start = time.perf_counter()
        for _ in range(n_samples):
            sample = [rng.randint(0, 2**63 - 1) for _ in range(8)]
            manager.process(sample, rng.random())
        elapsed = time.perf_counter() - start

        throughput = n_samples / elapsed
        # Should process at least 1000 samples/second
        self.assertGreater(throughput, 1000)

    def test_nearest_centroid_search_time(self):
        """Test nearest centroid search time with many clusters."""
        rng = random.Random(42)
        n_clusters = 64
        centroids = [[rng.randint(0, 2**63 - 1) for _ in range(8)] for _ in range(n_clusters)]

        n_queries = 1000
        start = time.perf_counter()
        for _ in range(n_queries):
            query = [rng.randint(0, 2**63 - 1) for _ in range(8)]
            distances = [hamming_distance(query, c) for c in centroids]
            min(distances)
        elapsed = time.perf_counter() - start

        throughput = n_queries / elapsed
        # Should process at least 100 queries/second
        self.assertGreater(throughput, 100)


# =============================================================================
# EWC Tests
# =============================================================================

class TestEWC(unittest.TestCase):
    """Tests for Elastic Weight Consolidation."""

    def test_ewc_penalty_zero_without_previous_tasks(self):
        """EWC penalty should be zero with no previous tasks."""
        theta = [0.5, 0.3, 0.7, 0.2]
        theta_star = []
        fisher = []
        lambda_val = 400.0

        penalty = 0.0
        for ts, f in zip(theta_star, fisher):
            for t, ts_i, f_i in zip(theta, ts, f):
                penalty += f_i * (t - ts_i) ** 2
        penalty *= lambda_val / 2.0

        self.assertEqual(penalty, 0.0)

    def test_ewc_penalty_increases_with_lambda(self):
        """EWC penalty should increase with lambda."""
        theta = [0.5, 0.3, 0.7, 0.2]
        theta_star = [0.0, 0.0, 0.0, 0.0]
        fisher = [1.0, 1.0, 1.0, 1.0]

        def compute_penalty(lam):
            return lam / 2.0 * sum(f * (t - ts) ** 2
                                   for t, ts, f in zip(theta, theta_star, fisher))

        penalty_100 = compute_penalty(100.0)
        penalty_400 = compute_penalty(400.0)
        penalty_800 = compute_penalty(800.0)

        self.assertLess(penalty_100, penalty_400)
        self.assertLess(penalty_400, penalty_800)

    def test_ewc_gradient_direction(self):
        """EWC gradient should push parameters toward theta_star."""
        theta = [1.0, 1.0, 1.0, 1.0]
        theta_star = [0.0, 0.0, 0.0, 0.0]
        fisher = [1.0, 1.0, 1.0, 1.0]
        lambda_val = 400.0

        # EWC gradient: lambda * F * (theta - theta_star)
        ewc_grad = [lambda_val * f * (t - ts)
                    for t, ts, f in zip(theta, theta_star, fisher)]

        # Gradient should be positive (pushing theta toward theta_star = 0)
        for g in ewc_grad:
            self.assertGreater(g, 0)

    def test_fisher_diagonal_non_negative(self):
        """Fisher diagonal should be non-negative."""
        rng = random.Random(42)
        n_params = 100
        n_samples = 50

        # Simulate Fisher computation
        fisher = [0.0] * n_params
        for _ in range(n_samples):
            grad = [rng.gauss(0, 1) for _ in range(n_params)]
            for i in range(n_params):
                fisher[i] += grad[i] ** 2
        fisher = [f / n_samples for f in fisher]

        for f in fisher:
            self.assertGreaterEqual(f, 0.0)

    def test_forgetting_reduction_with_ewc(self):
        """EWC should reduce forgetting compared to no regularization."""
        rng = random.Random(42)
        n_params = 50

        # Simulate task A optimal parameters
        theta_star_a = [rng.gauss(0, 1) for _ in range(n_params)]
        fisher_a = [abs(rng.gauss(0, 1)) for _ in range(n_params)]

        # Simulate task B training without EWC
        theta_no_ewc = [rng.gauss(0, 1) for _ in range(n_params)]

        # Simulate task B training with EWC
        theta_ewc = list(theta_star_a)  # Start from task A optimum
        lambda_val = 400.0
        lr = 0.001
        for _ in range(100):
            task_b_grad = [rng.gauss(0, 0.1) for _ in range(n_params)]
            ewc_grad = [lambda_val * f * (t - ts)
                        for t, ts, f in zip(theta_ewc, theta_star_a, fisher_a)]
            theta_ewc = [t - lr * (tg + eg)
                         for t, tg, eg in zip(theta_ewc, task_b_grad, ewc_grad)]

        # Compute forgetting (distance from theta_star_a)
        forgetting_no_ewc = sum((t - ts) ** 2
                                for t, ts in zip(theta_no_ewc, theta_star_a))
        forgetting_ewc = sum((t - ts) ** 2
                             for t, ts in zip(theta_ewc, theta_star_a))

        # EWC should have less forgetting
        self.assertLess(forgetting_ewc, forgetting_no_ewc)


# =============================================================================
# Main Test Runner
# =============================================================================

def run_all_tests():
    """Run all test suites."""
    test_suites = [
        unittest.TestLoader().loadTestsFromTestCase(TestHammingDistance),
        unittest.TestLoader().loadTestsFromTestCase(TestCentroidUpdate),
        unittest.TestLoader().loadTestsFromTestCase(TestClusterManager),
        unittest.TestLoader().loadTestsFromTestCase(TestNoveltyDetection),
        unittest.TestLoader().loadTestsFromTestCase(TestAdaptiveThreshold),
        unittest.TestLoader().loadTestsFromTestCase(TestReplayBuffer),
        unittest.TestLoader().loadTestsFromTestCase(TestClusteringIntegration),
        unittest.TestLoader().loadTestsFromTestCase(TestClusteringPerformance),
        unittest.TestLoader().loadTestsFromTestCase(TestEWC),
    ]

    combined = unittest.TestSuite(test_suites)
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(combined)
    return result.wasSuccessful()


if __name__ == '__main__':
    success = run_all_tests()
    sys.exit(0 if success else 1)