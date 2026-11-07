# =============================================================================
# federated_nas.py
# Federated Neural Architecture Search across Windows and Linux mesh nodes
# Implements distributed NAS with privacy-preserving architecture sharing
# =============================================================================

from __future__ import annotations

import math
import time
import json
import random
import logging
import hashlib
import statistics
import threading
from typing import Any, Dict, List, Optional, Tuple, Callable
from dataclasses import dataclass, field
from collections import defaultdict, deque
from copy import deepcopy
from enum import Enum, auto
from pathlib import Path

from architecture_search import (
    CandidateArchitecture, ArchitectureSearchSpace,
    ArchitectureEvaluator, ArchitectureSearch, ArchitectureRegistry
)

logger = logging.getLogger(__name__)


# =============================================================================
# Federated NAS Configuration
# =============================================================================

@dataclass
class FederatedNASConfig:
    """Configuration for federated NAS."""
    n_rounds: int = 20
    n_local_generations: int = 5
    local_population_size: int = 20
    global_population_size: int = 50
    architectures_per_round: int = 5
    aggregation_strategy: str = 'tournament'  # tournament, merge, ensemble
    privacy_noise_std: float = 0.01
    min_nodes_for_aggregation: int = 2
    sync_interval_rounds: int = 2
    elite_fraction: float = 0.2
    mutation_rate: float = 0.3
    crossover_rate: float = 0.5
    enable_differential_privacy: bool = True
    dp_epsilon: float = 1.0
    dp_delta: float = 1e-5
    max_arch_params: int = 100_000_000  # 100M parameter limit
    target_latency_ms: float = 10.0

    def to_dict(self) -> Dict[str, Any]:
        return {
            'n_rounds': self.n_rounds,
            'n_local_generations': self.n_local_generations,
            'local_population_size': self.local_population_size,
            'global_population_size': self.global_population_size,
            'architectures_per_round': self.architectures_per_round,
            'aggregation_strategy': self.aggregation_strategy,
            'privacy_noise_std': self.privacy_noise_std,
            'min_nodes_for_aggregation': self.min_nodes_for_aggregation,
            'sync_interval_rounds': self.sync_interval_rounds,
            'elite_fraction': self.elite_fraction,
            'mutation_rate': self.mutation_rate,
            'crossover_rate': self.crossover_rate,
            'enable_differential_privacy': self.enable_differential_privacy,
            'dp_epsilon': self.dp_epsilon,
            'dp_delta': self.dp_delta,
            'max_arch_params': self.max_arch_params,
            'target_latency_ms': self.target_latency_ms,
        }


# =============================================================================
# Federated NAS Node
# =============================================================================

@dataclass
class FederatedNASNodeInfo:
    """Information about a federated NAS node."""
    node_id: str
    platform: str
    n_gpus: int = 0
    has_maia: bool = False
    local_dataset_size: int = 0
    compute_budget: float = 1.0
    last_contribution: float = field(default_factory=time.time)
    n_rounds_participated: int = 0
    best_local_score: float = float('inf')
    contributed_arch_ids: List[str] = field(default_factory=list)

    def to_dict(self) -> Dict[str, Any]:
        return {
            'node_id': self.node_id,
            'platform': self.platform,
            'n_gpus': self.n_gpus,
            'has_maia': self.has_maia,
            'local_dataset_size': self.local_dataset_size,
            'compute_budget': self.compute_budget,
            'n_rounds_participated': self.n_rounds_participated,
            'best_local_score': self.best_local_score,
        }


# =============================================================================
# Architecture Contribution
# =============================================================================

@dataclass
class ArchitectureContribution:
    """An architecture contribution from a federated node."""
    node_id: str
    round_id: int
    architectures: List[CandidateArchitecture]
    scores: List[float]
    metadata: Dict[str, Any] = field(default_factory=dict)
    timestamp: float = field(default_factory=time.time)
    privacy_budget_used: float = 0.0

    def to_dict(self) -> Dict[str, Any]:
        return {
            'node_id': self.node_id,
            'round_id': self.round_id,
            'n_architectures': len(self.architectures),
            'best_score': min(self.scores) if self.scores else None,
            'mean_score': statistics.mean(self.scores) if self.scores else None,
            'timestamp': self.timestamp,
            'privacy_budget_used': self.privacy_budget_used,
        }


# =============================================================================
# Privacy Mechanism
# =============================================================================

class ArchitecturePrivacyMechanism:
    """
    Differential privacy mechanism for architecture sharing.
    Adds calibrated noise to architecture scores before sharing.
    """

    def __init__(
        self,
        epsilon: float = 1.0,
        delta: float = 1e-5,
        sensitivity: float = 1.0,
        seed: int = 42
    ):
        self.epsilon = epsilon
        self.delta = delta
        self.sensitivity = sensitivity
        self.rng = random.Random(seed)
        self._privacy_budget_used = 0.0

    def _gaussian_noise_std(self) -> float:
        """Compute Gaussian noise std for (epsilon, delta)-DP."""
if self.epsilon <= 0 or not 0 < self.delta < 1:
            raise ValueError("epsilon must be > 0 and delta must be in (0, 1)")
        c = math.sqrt(2 * math.log(1.25 / self.delta))
        return c * self.sensitivity / self.epsilon

    def add_noise_to_score(self, score: float) -> float:
        """Add Gaussian noise to a score for differential privacy."""
        std = self._gaussian_noise_std()
        if std <= 0:
            return score
        noise = self.rng.gauss(0, std)
        self._privacy_budget_used += self.epsilon
        return score + noise

    def add_noise_to_scores(self, scores: List[float]) -> List[float]:
        """Add noise to a list of scores."""
        return [self.add_noise_to_score(s) for s in scores]

    def privatize_architecture(
        self,
        arch: CandidateArchitecture
    ) -> CandidateArchitecture:
        """Create a privacy-preserving version of an architecture."""
        private_arch = deepcopy(arch)
        # Add noise to score
        private_arch.score = self.add_noise_to_score(arch.score)
        # Slightly perturb learning rate (continuous hyperparameter)
        lr_noise = self.rng.gauss(0, arch.learning_rate * 0.01)
        private_arch.learning_rate = max(1e-6, arch.learning_rate + lr_noise)
        return private_arch

    def privatize_contribution(
        self,
        contribution: ArchitectureContribution
    ) -> ArchitectureContribution:
        """Privatize an architecture contribution."""
        private_archs = [self.privatize_architecture(a) for a in contribution.architectures]
        private_scores = self.add_noise_to_scores(contribution.scores)
        return ArchitectureContribution(
            node_id=contribution.node_id,
            round_id=contribution.round_id,
            architectures=private_archs,
            scores=private_scores,
            metadata=contribution.metadata,
            timestamp=contribution.timestamp,
            privacy_budget_used=self._privacy_budget_used,
        )

    @property
    def total_privacy_budget_used(self) -> float:
        return self._privacy_budget_used

    def remaining_budget(self, total_budget: float) -> float:
        return max(0.0, total_budget - self._privacy_budget_used)


# =============================================================================
# Global Architecture Pool
# =============================================================================

class GlobalArchitecturePool:
    """
    Global pool of architectures aggregated from all federated nodes.
    Implements tournament selection and diversity maintenance.
    """

    def __init__(
        self,
        max_size: int = 200,
        diversity_threshold: float = 0.1,
        seed: int = 42
    ):
        self.max_size = max_size
        self.diversity_threshold = diversity_threshold
        self.rng = random.Random(seed)
        self._pool: List[CandidateArchitecture] = []
        self._lock = threading.Lock()
        self._contribution_counts: Dict[str, int] = defaultdict(int)

    def add(self, arch: CandidateArchitecture, node_id: str) -> bool:
        """Add architecture to pool if it improves diversity or quality."""
        with self._lock:
            if len(self._pool) < self.max_size:
                self._pool.append(arch)
                self._contribution_counts[node_id] += 1
                return True

            # Replace worst architecture if new one is better
            worst_idx = max(range(len(self._pool)), key=lambda i: self._pool[i].score)
            if arch.score < self._pool[worst_idx].score:
                self._pool[worst_idx] = arch
                self._contribution_counts[node_id] += 1
                return True

            return False

    def add_batch(
        self,
        architectures: List[CandidateArchitecture],
        node_id: str
    ) -> int:
        """Add a batch of architectures."""
        added = 0
        for arch in architectures:
            if self.add(arch, node_id):
                added += 1
        return added

    def tournament_select(self, k: int = 5) -> CandidateArchitecture:
        """Tournament selection from pool."""
        with self._lock:
            if not self._pool:
                return None
            candidates = self.rng.sample(self._pool, min(k, len(self._pool)))
            return min(candidates, key=lambda a: a.score)

    def get_top_k(self, k: int) -> List[CandidateArchitecture]:
        """Get top-k architectures by score."""
        with self._lock:
            return sorted(self._pool, key=lambda a: a.score)[:k]

    def get_diverse_sample(self, k: int) -> List[CandidateArchitecture]:
        """Get diverse sample from pool using greedy diversity selection."""
        with self._lock:
            if len(self._pool) <= k:
                return list(self._pool)

            # Start with best architecture
            selected = [min(self._pool, key=lambda a: a.score)]
            remaining = [a for a in self._pool if a.arch_id != selected[0].arch_id]

            while len(selected) < k and remaining:
                # Select architecture most different from already selected
                best_diversity = -1.0
                best_arch = None

                for arch in remaining:
                    # Compute min distance to selected set
                    min_dist = min(
                        self._arch_distance(arch, s) for s in selected
                    )
                    if min_dist > best_diversity:
                        best_diversity = min_dist
                        best_arch = arch

                if best_arch:
                    selected.append(best_arch)
                    remaining = [a for a in remaining if a.arch_id != best_arch.arch_id]

            return selected

    def _arch_distance(
        self,
        arch1: CandidateArchitecture,
        arch2: CandidateArchitecture
    ) -> float:
        """Compute distance between two architectures."""
        # Structural distance
        depth_diff = abs(
            (len(arch1.conv_layers) + len(arch1.transformer_layers)) -
            (len(arch2.conv_layers) + len(arch2.transformer_layers))
        ) / 20.0

        # Parameter count distance
        param_diff = abs(
            math.log(max(1, arch1.n_parameters)) -
            math.log(max(1, arch2.n_parameters))
        ) / 10.0

        # Embedding dim distance
        emb_diff = abs(arch1.embedding_dim - arch2.embedding_dim) / 1024.0

        return depth_diff + param_diff + emb_diff

    def prune_dominated(self) -> int:
        """Remove architectures dominated by others (Pareto pruning)."""
        with self._lock:
            n_before = len(self._pool)
            non_dominated = []
            for i, arch in enumerate(self._pool):
                dominated = False
                for j, other in enumerate(self._pool):
                    if i != j:
                        # Check if other dominates arch (better score, fewer params)
                        if (other.score <= arch.score and
                                other.n_parameters <= arch.n_parameters and
                                (other.score < arch.score or other.n_parameters < arch.n_parameters)):
                            dominated = True
                            break
                if not dominated:
                    non_dominated.append(arch)
            self._pool = non_dominated
            return n_before - len(self._pool)

    def statistics(self) -> Dict[str, Any]:
        with self._lock:
            scores = [a.score for a in self._pool if a.score < float('inf')]
            params = [a.n_parameters for a in self._pool]
            return {
                'pool_size': len(self._pool),
                'max_size': self.max_size,
                'best_score': min(scores) if scores else None,
                'mean_score': statistics.mean(scores) if scores else None,
                'mean_params': statistics.mean(params) if params else None,
                'contribution_counts': dict(self._contribution_counts),
            }

    def __len__(self) -> int:
        return len(self._pool)


# =============================================================================
# Federated NAS Aggregator
# =============================================================================

class FederatedNASAggregator:
    """
    Aggregates architecture contributions from federated nodes.
    Implements multiple aggregation strategies.
    """

    def __init__(
        self,
        config: FederatedNASConfig,
        global_pool: GlobalArchitecturePool,
        seed: int = 42
    ):
        self.config = config
        self.global_pool = global_pool
        self.rng = random.Random(seed)
        self._round_contributions: Dict[int, List[ArchitectureContribution]] = defaultdict(list)
        self._aggregation_history: List[Dict[str, Any]] = []

    def receive_contribution(
        self,
        contribution: ArchitectureContribution
    ) -> None:
        """Receive and store a contribution from a node."""
        self._round_contributions[contribution.round_id].append(contribution)
        logger.info(f"Received contribution from {contribution.node_id}: "
                    f"{len(contribution.architectures)} architectures "
                    f"(round {contribution.round_id})")

    def aggregate_round(self, round_id: int) -> List[CandidateArchitecture]:
        """Aggregate contributions for a round."""
        contributions = self._round_contributions.get(round_id, [])
        if len(contributions) < self.config.min_nodes_for_aggregation:
            logger.warning(f"Round {round_id}: insufficient contributions "
                           f"({len(contributions)} < {self.config.min_nodes_for_aggregation})")
            return []

        strategy = self.config.aggregation_strategy
        if strategy == 'tournament':
            return self._tournament_aggregation(contributions)
        elif strategy == 'merge':
            return self._merge_aggregation(contributions)
        elif strategy == 'ensemble':
            return self._ensemble_aggregation(contributions)
        else:
            return self._tournament_aggregation(contributions)

    def _tournament_aggregation(
        self,
        contributions: List[ArchitectureContribution]
    ) -> List[CandidateArchitecture]:
        """Select best architectures via tournament across all contributions."""
        all_archs = []
        for contrib in contributions:
            for arch, score in zip(contrib.architectures, contrib.scores):
                arch.score = score
                all_archs.append(arch)

        # Add to global pool
        for arch in all_archs:
            self.global_pool.add(arch, "aggregator")

        # Return top-k from global pool
        return self.global_pool.get_top_k(self.config.architectures_per_round)

    def _merge_aggregation(
        self,
        contributions: List[ArchitectureContribution]
    ) -> List[CandidateArchitecture]:
        """Merge architectures from all nodes."""
        all_archs = []
        for contrib in contributions:
            all_archs.extend(contrib.architectures)

        # Sort by score and return top-k
        selected = all_archs[:self.config.architectures_per_round]
        self.global_pool.add_batch(selected, "aggregator")
        return selected

    def _ensemble_aggregation(
        self,
        contributions: List[ArchitectureContribution]
    ) -> List[CandidateArchitecture]:
        """Create ensemble architectures by combining contributions."""
        # Get best from each node
        best_per_node = []
        for contrib in contributions:
            if contrib.architectures:
                best_idx = min(range(len(contrib.scores)), key=lambda i: contrib.scores[i])
                best_per_node.append(contrib.architectures[best_idx])

        # Return diverse sample
        return self.global_pool.get_diverse_sample(self.config.architectures_per_round)

    def get_global_best(self) -> Optional[CandidateArchitecture]:
        """Get globally best architecture."""
        top = self.global_pool.get_top_k(1)
        return top[0] if top else None

    def statistics(self) -> Dict[str, Any]:
        return {
            'n_rounds': len(self._round_contributions),
            'total_contributions': sum(len(v) for v in self._round_contributions.values()),
            'global_pool': self.global_pool.statistics(),
        }


# =============================================================================
# Federated NAS Local Node
# =============================================================================

class FederatedNASLocalNode:
    """
    Local NAS node that participates in federated architecture search.
    Runs local search and contributes best architectures to global pool.
    """

    def __init__(
        self,
        node_info: FederatedNASNodeInfo,
        config: FederatedNASConfig,
        search_space: ArchitectureSearchSpace,
        evaluator: ArchitectureEvaluator,
        privacy_mechanism: Optional[ArchitecturePrivacyMechanism] = None,
        seed: int = 42
    ):
        self.node_info = node_info
        self.config = config
        self.search_space = search_space
        self.evaluator = evaluator
        self.privacy_mechanism = privacy_mechanism
        self.seed = seed
        self.rng = random.Random(seed)

        self._local_search = ArchitectureSearch(
            search_space=search_space,
            evaluator=evaluator,
            population_size=config.local_population_size,
            n_generations=config.n_local_generations,
            elite_fraction=config.elite_fraction,
            mutation_rate=config.mutation_rate,
            crossover_rate=config.crossover_rate,
            seed=seed,
            verbose=False,
        )
        self._local_population: List[CandidateArchitecture] = []
        self._round_history: List[Dict[str, Any]] = []
        self._current_round = 0

    def initialize(self) -> None:
        """Initialize local search."""
        self._local_search.initialize_population()
        self._local_population = self._local_search._population

    def run_local_search(self) -> List[CandidateArchitecture]:
        """Run local NAS for configured number of generations."""
        for generation in range(self.config.n_local_generations):
            self._local_search.evaluate_population()
            if generation < self.config.n_local_generations - 1:
                self._local_search.evolve()

        self._local_population = self._local_search._population
        return self._local_search.get_top_k(self.config.architectures_per_round)

    def incorporate_global_architectures(
        self,
        global_archs: List[CandidateArchitecture]
    ) -> None:
        """Incorporate architectures from global pool into local population."""
        if not global_archs:
            return

        # Replace worst local architectures with global ones
        self._local_population.sort(key=lambda a: a.score)
        n_replace = min(len(global_archs), len(self._local_population) // 4)

        for i, arch in enumerate(global_archs[:n_replace]):
            replace_idx = len(self._local_population) - 1 - i
            if replace_idx >= 0:
                self._local_population[replace_idx] = deepcopy(arch)

        self._local_search._population = self._local_population

    def create_contribution(self, round_id: int) -> ArchitectureContribution:
        """Create architecture contribution for this round."""
        top_archs = self._local_search.get_top_k(self.config.architectures_per_round)
        scores = [a.score for a in top_archs]

        contribution = ArchitectureContribution(
            node_id=self.node_info.node_id,
            round_id=round_id,
            architectures=top_archs,
            scores=scores,
            metadata={
                'platform': self.node_info.platform,
                'local_dataset_size': self.node_info.local_dataset_size,
                'compute_budget': self.node_info.compute_budget,
            }
        )

        # Apply privacy if configured
        if self.privacy_mechanism and self.config.enable_differential_privacy:
            contribution = self.privacy_mechanism.privatize_contribution(contribution)

        self.node_info.n_rounds_participated += 1
        self.node_info.last_contribution = time.time()
        if scores:
            self.node_info.best_local_score = min(self.node_info.best_local_score, min(scores))

        return contribution

    def get_local_best(self) -> Optional[CandidateArchitecture]:
        """Get best local architecture."""
        return self._local_search._best_arch

    def statistics(self) -> Dict[str, Any]:
        return {
            'node_id': self.node_info.node_id,
            'platform': self.node_info.platform,
            'n_rounds': self.node_info.n_rounds_participated,
            'best_local_score': self.node_info.best_local_score,
            'local_population_size': len(self._local_population),
        }


# =============================================================================
# Federated NAS Coordinator
# =============================================================================

class FederatedNAS:
    """
    Main federated NAS coordinator.
    Orchestrates distributed architecture search across the AGI mesh.
    """

    def __init__(
        self,
        config: FederatedNASConfig,
        search_space: Optional[ArchitectureSearchSpace] = None,
        evaluator: Optional[ArchitectureEvaluator] = None,
        registry: Optional[ArchitectureRegistry] = None,
        seed: int = 42,
        verbose: bool = True
    ):
        self.config = config
        self.search_space = search_space or ArchitectureSearchSpace(seed=seed)
        self.evaluator = evaluator or ArchitectureEvaluator(seed=seed)
        self.registry = registry or ArchitectureRegistry()
        self.seed = seed
        self.verbose = verbose
        self.rng = random.Random(seed)

        self.global_pool = GlobalArchitecturePool(
            max_size=config.global_population_size * 4,
            seed=seed
        )
        self.aggregator = FederatedNASAggregator(config, self.global_pool, seed)

        self._nodes: Dict[str, FederatedNASLocalNode] = {}
        self._current_round = 0
        self._global_best: Optional[CandidateArchitecture] = None
        self._round_history: List[Dict[str, Any]] = []
        self._lock = threading.Lock()

    def register_node(
        self,
        node_id: str,
        platform: str = "linux",
        n_gpus: int = 0,
        has_maia: bool = False,
        local_dataset_size: int = 1000,
        compute_budget: float = 1.0
    ) -> FederatedNASLocalNode:
        """Register a new federated NAS node."""
        node_info = FederatedNASNodeInfo(
            node_id=node_id,
            platform=platform,
            n_gpus=n_gpus,
            has_maia=has_maia,
            local_dataset_size=local_dataset_size,
            compute_budget=compute_budget,
        )

node_seed = int.from_bytes(
            hashlib.sha256(node_id.encode("utf-8")).digest()[:4],
            "big"
        ) % (2**31)

        privacy_mechanism = ArchitecturePrivacyMechanism(
            epsilon=self.config.dp_epsilon,
            delta=self.config.dp_delta,
            seed=node_seed
        ) if self.config.enable_differential_privacy else None

        node = FederatedNASLocalNode(
            node_info=node_info,
            config=self.config,
            search_space=self.search_space,
            evaluator=self.evaluator,
            privacy_mechanism=privacy_mechanism,
            seed=node_seed,
        )
        node.initialize()

        with self._lock:
            self._nodes[node_id] = node

        logger.info(f"Registered federated NAS node: {node_id} ({platform})")
        return node

    def run_round(self) -> Dict[str, Any]:
        """Run one round of federated NAS."""
        round_id = self._current_round
        logger.info(f"Starting federated NAS round {round_id}")

        # Get global architectures to distribute
        global_archs = self.global_pool.get_diverse_sample(
            self.config.architectures_per_round
        )

        # Run local search on each node
        contributions = []
        for node_id, node in self._nodes.items():
            # Incorporate global architectures
            node.incorporate_global_architectures(global_archs)

            # Run local search
            node.run_local_search()

            # Create contribution
            contribution = node.create_contribution(round_id)
            contributions.append(contribution)
            self.aggregator.receive_contribution(contribution)

        # Aggregate contributions
        aggregated = self.aggregator.aggregate_round(round_id)

        # Update global best
        global_best = self.aggregator.get_global_best()
        if global_best and (self._global_best is None or
                            global_best.score < self._global_best.score):
            self._global_best = deepcopy(global_best)
            if self.registry:
                self.registry.register(self._global_best)
            logger.info(f"Round {round_id}: new global best score={self._global_best.score:.4f} "
                        f"params={self._global_best.n_parameters:,}")

        # Record round statistics
        round_stats = {
            'round_id': round_id,
            'n_nodes': len(self._nodes),
            'n_contributions': len(contributions),
            'n_aggregated': len(aggregated),
            'global_best_score': self._global_best.score if self._global_best else None,
            'global_pool_size': len(self.global_pool),
            'timestamp': time.time(),
        }
        self._round_history.append(round_stats)
        self._current_round += 1

        if self.verbose:
            best = round_stats['global_best_score']
            best_text = f"{best:.4f}" if best is not None else "N/A"
            logger.info(f"Round {round_id} complete: best={best_text} "
                        f"pool={round_stats['global_pool_size']}")

        return round_stats

    def evolve(self, candidates: List[CandidateArchitecture]) -> List[CandidateArchitecture]:
        """Evolve a set of candidate architectures."""
        if not candidates:
            return self.search_space.sample_batch(self.config.architectures_per_round)

        evolved = sorted(candidates, key=lambda x: x.score)
        return evolved

    def run(self) -> CandidateArchitecture:
        """Run the full federated NAS."""
        logger.info(f"Starting federated NAS: {self.config.n_rounds} rounds, "
                    f"{len(self._nodes)} nodes")

        if not self._nodes:
            # Register default local nodes
            self.register_node("local_windows", "windows")
            self.register_node("local_linux", "linux")

        for round_idx in range(self.config.n_rounds):
            self.run_round()

        logger.info(f"Federated NAS complete. "
                    f"Best score: {self._global_best.score if self._global_best else 'N/A'}")
        return self._global_best or self.search_space.sample_architecture()

    def get_global_best(self) -> Optional[CandidateArchitecture]:
        return self._global_best

    def get_top_k_global(self, k: int) -> List[CandidateArchitecture]:
        return self.global_pool.get_top_k(k)

    def get_statistics(self) -> Dict[str, Any]:
        return {
            'n_rounds_completed': self._current_round,
            'n_nodes': len(self._nodes),
            'global_best_score': self._global_best.score if self._global_best else None,
            'global_pool': self.global_pool.statistics(),
            'aggregator': self.aggregator.statistics(),
            'node_stats': {nid: n.statistics() for nid, n in self._nodes.items()},
            'round_history': self._round_history,
        }

    def save_results(self, path: str) -> None:
        """Save federated NAS results to file."""
        results = {
            'config': self.config.to_dict(),
            'statistics': self.get_statistics(),
            'global_best': self._global_best.to_dict() if self._global_best else None,
            'top_10': [a.to_dict() for a in self.get_top_k_global(10)],
            'timestamp': time.time(),
        }
        with open(path, 'w') as f:
            json.dump(results, f, indent=2, default=str)
        logger.info(f"Federated NAS results saved: {path}")

    def __repr__(self) -> str:
        return (f"FederatedNAS(rounds={self._current_round}/{self.config.n_rounds}, "
                f"nodes={len(self._nodes)}, "
                f"best={self._global_best.score if self._global_best else 'N/A'})")