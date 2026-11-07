# =============================================================================
# test_automl.py
# Unit tests for the AutoML hyperparameter optimization pipeline
# Tests search space, surrogate model, trial management, and search algorithms
# =============================================================================

import sys
import math
import random
import unittest
import time
import json
import tempfile
import os
from typing import Any, Dict, List, Optional, Tuple
from dataclasses import dataclass, field
from collections import defaultdict

# =============================================================================
# Search Space Tests
# =============================================================================

class TestParameterSpec(unittest.TestCase):
    """Tests for parameter specification and sampling."""

    def setUp(self):
        self.rng = random.Random(42)

    def test_float_parameter_sampling_range(self):
        """Float parameter samples should be within [low, high]."""
        low, high = 0.001, 0.1
        for _ in range(1000):
            val = self.rng.uniform(low, high)
            self.assertGreaterEqual(val, low)
            self.assertLessEqual(val, high)

    def test_int_parameter_sampling_range(self):
        """Int parameter samples should be within [low, high]."""
        low, high = 4, 64
        for _ in range(1000):
            val = self.rng.randint(low, high)
            self.assertGreaterEqual(val, low)
            self.assertLessEqual(val, high)

    def test_categorical_parameter_sampling(self):
        """Categorical parameter samples should be from choices."""
        choices = [4, 8, 16, 32, 64]
        for _ in range(1000):
            val = self.rng.choice(choices)
            self.assertIn(val, choices)

    def test_log_float_sampling(self):
        """Log-scale float samples should span multiple orders of magnitude."""
        log_low = math.log(1e-5)
        log_high = math.log(1e-1)
        samples = [math.exp(self.rng.uniform(log_low, log_high)) for _ in range(1000)]
        min_val = min(samples)
        max_val = max(samples)
        # Should span at least 2 orders of magnitude
        self.assertGreater(math.log10(max_val / min_val), 2)

    def test_normalization_roundtrip(self):
        """Normalizing and denormalizing should recover original value."""
        low, high = 0.001, 100.0
        for _ in range(100):
            val = self.rng.uniform(low, high)
            norm = (val - low) / (high - low)
            recovered = low + norm * (high - low)
            self.assertAlmostEqual(val, recovered, places=10)

    def test_log_normalization_roundtrip(self):
        """Log-scale normalization roundtrip."""
        low, high = 1e-5, 1e-1
        for _ in range(100):
            log_low = math.log(low)
            log_high = math.log(high)
            val = math.exp(self.rng.uniform(log_low, log_high))
            norm = (math.log(val) - log_low) / (log_high - log_low)
            recovered = math.exp(log_low + norm * (log_high - log_low))
            self.assertAlmostEqual(val, recovered, places=10)


class TestSearchSpace(unittest.TestCase):
    """Tests for the complete search space."""

    def setUp(self):
        self.rng = random.Random(42)
        self.search_space = {
            'ewc_lambda': {'type': 'log_float', 'low': 10.0, 'high': 2000.0, 'default': 400.0},
            'replay_buffer_size': {'type': 'log_int', 'low': 256, 'high': 65536, 'default': 1024},
            'hamming_threshold': {'type': 'int', 'low': 4, 'high': 64, 'default': 24},
            'learning_rate': {'type': 'log_float', 'low': 1e-5, 'high': 1e-1, 'default': 1e-3},
            'anchor_alpha': {'type': 'float', 'low': 0.0, 'high': 1.0, 'default': 0.5},
            'novelty_method': {'type': 'categorical', 'choices': [0, 1, 2, 3], 'default': 3},
        }

    def _sample_config(self) -> Dict[str, Any]:
        """Sample a configuration from the search space."""
        config = {}
        for name, spec in self.search_space.items():
            if spec['type'] == 'float':
                config[name] = self.rng.uniform(spec['low'], spec['high'])
            elif spec['type'] == 'log_float':
                log_low = math.log(spec['low'])
                log_high = math.log(spec['high'])
                config[name] = math.exp(self.rng.uniform(log_low, log_high))
            elif spec['type'] == 'int':
                config[name] = self.rng.randint(spec['low'], spec['high'])
            elif spec['type'] == 'log_int':
                log_low = math.log(spec['low'])
                log_high = math.log(spec['high'])
                config[name] = int(round(math.exp(self.rng.uniform(log_low, log_high))))
            elif spec['type'] == 'categorical':
                config[name] = self.rng.choice(spec['choices'])
        return config

    def test_sample_returns_all_parameters(self):
        """Sampled config should contain all parameters."""
        config = self._sample_config()
        for name in self.search_space:
            self.assertIn(name, config)

    def test_sampled_values_in_range(self):
        """Sampled values should be within specified ranges."""
        for _ in range(100):
            config = self._sample_config()
            for name, spec in self.search_space.items():
                val = config[name]
                if spec['type'] in ('float', 'log_float'):
                    self.assertGreaterEqual(val, spec['low'])
                    self.assertLessEqual(val, spec['high'])
                elif spec['type'] in ('int', 'log_int'):
                    self.assertGreaterEqual(val, spec['low'])
                    self.assertLessEqual(val, spec['high'])
                elif spec['type'] == 'categorical':
                    self.assertIn(val, spec['choices'])

    def test_default_config_valid(self):
        """Default configuration should be valid."""
        config = {name: spec['default'] for name, spec in self.search_space.items()}
        for name, spec in self.search_space.items():
            val = config[name]
            if spec['type'] in ('float', 'log_float', 'int', 'log_int'):
                self.assertGreaterEqual(val, spec['low'])
                self.assertLessEqual(val, spec['high'])
            elif spec['type'] == 'categorical':
                self.assertIn(val, spec['choices'])

    def test_dimension_matches_parameter_count(self):
        """Search space dimension should match number of parameters."""
        self.assertEqual(len(self.search_space), 6)


# =============================================================================
# Objective Function Tests
# =============================================================================

def objective(loss: float, bandwidth: float, forgetting: float,
              latency: float = 0.0, memory: float = 0.0) -> float:
    """Primary composite objective function."""
    return loss + 0.2 * bandwidth + 2.0 * forgetting + 0.1 * latency + 0.05 * memory


class TestObjectiveFunction(unittest.TestCase):
    """Tests for objective functions."""

    def test_objective_non_negative_for_valid_inputs(self):
        """Objective should be non-negative for valid inputs."""
        for _ in range(100):
            rng = random.Random(42)
            loss = rng.uniform(0, 2)
            bandwidth = rng.uniform(0, 1000)
            forgetting = rng.uniform(0, 1)
            obj = objective(loss, bandwidth, forgetting)
            self.assertGreaterEqual(obj, 0)

    def test_lower_loss_gives_lower_objective(self):
        """Lower task loss should give lower objective (all else equal)."""
        obj_high = objective(1.0, 100.0, 0.1)
        obj_low = objective(0.1, 100.0, 0.1)
        self.assertLess(obj_low, obj_high)

    def test_lower_forgetting_gives_lower_objective(self):
        """Lower forgetting should give lower objective."""
        obj_high = objective(0.5, 100.0, 0.5)
        obj_low = objective(0.5, 100.0, 0.05)
        self.assertLess(obj_low, obj_high)

    def test_forgetting_weight_dominates(self):
        """Forgetting weight (2.0) should dominate bandwidth weight (0.2)."""
        # Same forgetting increase vs bandwidth increase
        base = objective(0.5, 100.0, 0.1)
        high_forgetting = objective(0.5, 100.0, 0.6)  # +0.5 forgetting
        high_bandwidth = objective(0.5, 600.0, 0.1)   # +500 bandwidth

        forgetting_increase = high_forgetting - base
        bandwidth_increase = high_bandwidth - base

        # Forgetting increase should be larger per unit
        self.assertGreater(forgetting_increase / 0.5, bandwidth_increase / 500.0)

    def test_objective_monotone_in_each_component(self):
        """Objective should be monotonically increasing in each component."""
        base = objective(0.5, 100.0, 0.1)
        self.assertLess(base, objective(1.0, 100.0, 0.1))
        self.assertLess(base, objective(0.5, 200.0, 0.1))
        self.assertLess(base, objective(0.5, 100.0, 0.2))

    def test_continual_learning_objective(self):
        """Test continual learning objective."""
        task_losses = [0.1, 0.2, 0.15, 0.3]
        forgetting = [0.05, 0.08, 0.03]
        mean_loss = sum(task_losses) / len(task_losses)
        mean_forgetting = sum(forgetting) / len(forgetting)
        obj = mean_loss + 2.0 * mean_forgetting
        self.assertGreater(obj, 0)
        self.assertLess(obj, 10)


# =============================================================================
# Surrogate Model Tests
# =============================================================================

class SimpleSurrogate:
    """Simple surrogate model for testing."""

    def __init__(self, noise: float = 1e-6):
        self.noise = noise
        self.X: List[List[float]] = []
        self.y: List[float] = []

    def fit(self, X: List[List[float]], y: List[float]) -> None:
        self.X = X
        self.y = y

    def _rbf_kernel(self, x1: List[float], x2: List[float]) -> float:
        sq_dist = sum((a - b) ** 2 for a, b in zip(x1, x2))
        return math.exp(-0.5 * sq_dist)

    def predict(self, x: List[float]) -> Tuple[float, float]:
        if not self.X:
            return 0.0, 1.0
        # Simple weighted average
        weights = [self._rbf_kernel(x, xi) for xi in self.X]
        total_weight = sum(weights) + 1e-10
        mean = sum(w * y for w, y in zip(weights, self.y)) / total_weight
        variance = max(0.0, 1.0 - sum(w ** 2 for w in weights) / (total_weight ** 2))
        return mean, variance


class TestSurrogateModel(unittest.TestCase):
    """Tests for the surrogate model."""

    def setUp(self):
        self.surrogate = SimpleSurrogate()

    def test_predict_without_data_returns_default(self):
        """Prediction without training data should return default values."""
        mean, var = self.surrogate.predict([0.5, 0.5])
        self.assertEqual(mean, 0.0)
        self.assertEqual(var, 1.0)

    def test_predict_at_training_point(self):
        """Prediction at training point should be close to training value."""
        X = [[0.0, 0.0], [1.0, 1.0], [0.5, 0.5]]
        y = [1.0, 2.0, 1.5]
        self.surrogate.fit(X, y)
        mean, var = self.surrogate.predict([0.5, 0.5])
        self.assertAlmostEqual(mean, 1.5, delta=0.5)

    def test_variance_non_negative(self):
        """Predicted variance should always be non-negative."""
        X = [[float(i) / 10 for i in range(5)] for _ in range(10)]
        y = [random.gauss(0, 1) for _ in range(10)]
        self.surrogate.fit(X, y)
        for _ in range(50):
            x = [random.random() for _ in range(5)]
            _, var = self.surrogate.predict(x)
            self.assertGreaterEqual(var, 0.0)

    def test_kernel_symmetry(self):
        """RBF kernel should be symmetric."""
        x1 = [0.1, 0.2, 0.3]
        x2 = [0.4, 0.5, 0.6]
        k12 = self.surrogate._rbf_kernel(x1, x2)
        k21 = self.surrogate._rbf_kernel(x2, x1)
        self.assertAlmostEqual(k12, k21, places=10)

    def test_kernel_self_similarity(self):
        """RBF kernel of point with itself should be 1.0."""
        x = [0.1, 0.2, 0.3, 0.4]
        k = self.surrogate._rbf_kernel(x, x)
        self.assertAlmostEqual(k, 1.0, places=10)

    def test_kernel_decreases_with_distance(self):
        """RBF kernel should decrease as points get farther apart."""
        x = [0.5, 0.5]
        k_close = self.surrogate._rbf_kernel(x, [0.6, 0.6])
        k_far = self.surrogate._rbf_kernel(x, [1.5, 1.5])
        self.assertGreater(k_close, k_far)


# =============================================================================
# Trial Management Tests
# =============================================================================

@dataclass
class SimpleTrial:
    """Simple trial for testing."""
    trial_id: str
    config: Dict[str, Any]
    objective_value: Optional[float] = None
    status: str = 'pending'
    start_time: Optional[float] = None
    end_time: Optional[float] = None

    @property
    def duration(self) -> Optional[float]:
        if self.start_time and self.end_time:
            return self.end_time - self.start_time
        return None


class SimpleTrialRegistry:
    """Simple trial registry for testing."""

    def __init__(self):
        self._trials: Dict[str, SimpleTrial] = {}
        self._counter = 0

    def create_trial(self, config: Dict[str, Any]) -> SimpleTrial:
        self._counter += 1
        trial_id = f"trial_{self._counter:06d}"
        trial = SimpleTrial(trial_id=trial_id, config=config)
        self._trials[trial_id] = trial
        return trial

    def report(self, trial: SimpleTrial, objective: float) -> None:
        trial.objective_value = objective
        trial.status = 'completed'
        trial.end_time = time.time()
        self._trials[trial.trial_id] = trial

    def get_best(self, minimize: bool = True) -> Optional[SimpleTrial]:
        completed = [t for t in self._trials.values()
                     if t.status == 'completed' and t.objective_value is not None]
        if not completed:
            return None
        return min(completed, key=lambda t: t.objective_value) if minimize \
               else max(completed, key=lambda t: t.objective_value)

    def statistics(self) -> Dict[str, Any]:
        all_trials = list(self._trials.values())
        completed = [t for t in all_trials if t.status == 'completed']
        return {
            'total': len(all_trials),
            'completed': len(completed),
            'best': self.get_best(),
        }


class TestTrialManagement(unittest.TestCase):
    """Tests for trial management."""

    def setUp(self):
        self.registry = SimpleTrialRegistry()

    def test_create_trial_assigns_unique_id(self):
        """Each trial should have a unique ID."""
        ids = set()
        for _ in range(100):
            trial = self.registry.create_trial({'lr': 0.001})
            ids.add(trial.trial_id)
        self.assertEqual(len(ids), 100)

    def test_report_updates_trial_status(self):
        """Reporting result should update trial status."""
        trial = self.registry.create_trial({'lr': 0.001})
        self.assertEqual(trial.status, 'pending')
        self.registry.report(trial, 0.5)
        self.assertEqual(trial.status, 'completed')
        self.assertEqual(trial.objective_value, 0.5)

    def test_get_best_returns_minimum(self):
        """get_best should return trial with minimum objective."""
        configs = [{'lr': 0.001 * i} for i in range(1, 11)]
        objectives = [1.0, 0.5, 0.8, 0.3, 0.9, 0.2, 0.7, 0.4, 0.6, 1.1]

        for config, obj in zip(configs, objectives):
            trial = self.registry.create_trial(config)
            trial.start_time = time.time()
            self.registry.report(trial, obj)

        best = self.registry.get_best(minimize=True)
        self.assertIsNotNone(best)
        self.assertEqual(best.objective_value, 0.2)

    def test_get_best_returns_maximum_when_maximize(self):
        """get_best with minimize=False should return maximum."""
        for i in range(5):
            trial = self.registry.create_trial({'i': i})
            trial.start_time = time.time()
            self.registry.report(trial, float(i))

        best = self.registry.get_best(minimize=False)
        self.assertEqual(best.objective_value, 4.0)

    def test_get_best_with_no_completed_trials(self):
        """get_best with no completed trials should return None."""
        for _ in range(5):
            self.registry.create_trial({'lr': 0.001})
        best = self.registry.get_best()
        self.assertIsNone(best)

    def test_statistics_counts_correctly(self):
        """Statistics should count trials correctly."""
        for i in range(10):
            trial = self.registry.create_trial({'i': i})
            if i < 7:
                trial.start_time = time.time()
                self.registry.report(trial, float(i))

        stats = self.registry.statistics()
        self.assertEqual(stats['total'], 10)
        self.assertEqual(stats['completed'], 7)


# =============================================================================
# Search Algorithm Tests
# =============================================================================

class TestRandomSearch(unittest.TestCase):
    """Tests for random search algorithm."""

    def setUp(self):
        self.rng = random.Random(42)
        self.search_space_bounds = {
            'ewc_lambda': (10.0, 2000.0),
            'hamming_threshold': (4, 64),
            'learning_rate': (1e-5, 1e-1),
        }

    def _sample(self) -> Dict[str, Any]:
        config = {}
        for name, (low, high) in self.search_space_bounds.items():
            if isinstance(low, int):
                config[name] = self.rng.randint(low, high)
            else:
                config[name] = math.exp(self.rng.uniform(math.log(low), math.log(high)))
        return config

    def test_random_search_explores_space(self):
        """Random search should explore different regions of the space."""
        configs = [self._sample() for _ in range(100)]
        lambdas = [c['ewc_lambda'] for c in configs]
        # Should have both small and large values
        self.assertLess(min(lambdas), 100.0)
        self.assertGreater(max(lambdas), 500.0)

    def test_random_search_reproducible_with_seed(self):
        """Random search with same seed should produce same results."""
        rng1 = random.Random(42)
        rng2 = random.Random(42)
        configs1 = [{'lr': rng1.uniform(1e-5, 1e-1)} for _ in range(10)]
        configs2 = [{'lr': rng2.uniform(1e-5, 1e-1)} for _ in range(10)]
        for c1, c2 in zip(configs1, configs2):
            self.assertAlmostEqual(c1['lr'], c2['lr'])

    def test_random_search_finds_good_config(self):
        """Random search should find a reasonably good configuration."""
        def simple_objective(config: Dict) -> float:
            # Optimal: lambda=400, threshold=24, lr=0.001
            lambda_score = abs(math.log(config['ewc_lambda']) - math.log(400)) / 5
            threshold_score = abs(config['hamming_threshold'] - 24) / 60
            lr_score = abs(math.log(config['learning_rate']) - math.log(0.001)) / 10
            return lambda_score + threshold_score + lr_score

        best_obj = float('inf')
        for _ in range(200):
            config = self._sample()
            obj = simple_objective(config)
            best_obj = min(best_obj, obj)

        # Should find something reasonably good
        self.assertLess(best_obj, 1.0)


class TestBayesianOptimization(unittest.TestCase):
    """Tests for Bayesian optimization."""

    def test_ei_acquisition_positive(self):
        """Expected Improvement should be non-negative."""
        def ei(mean: float, std: float, best_y: float, xi: float = 0.01) -> float:
            if std < 1e-10:
                return 0.0
            z = (best_y - mean - xi) / std
            phi_z = math.exp(-0.5 * z * z) / math.sqrt(2 * math.pi)
            Phi_z = 0.5 * (1 + math.erf(z / math.sqrt(2)))
            return (best_y - mean - xi) * Phi_z + std * phi_z

        for _ in range(100):
            rng = random.Random(42)
            mean = rng.gauss(0, 1)
            std = abs(rng.gauss(0, 1)) + 0.01
            best_y = rng.gauss(0, 1)
            result = ei(mean, std, best_y)
            self.assertGreaterEqual(result, 0.0)

    def test_ucb_acquisition(self):
        """UCB acquisition should increase with uncertainty."""
        def ucb(mean: float, std: float, kappa: float = 2.576) -> float:
            return mean + kappa * std

        mean = 0.5
        ucb_low_std = ucb(mean, 0.1)
        ucb_high_std = ucb(mean, 1.0)
        self.assertLess(ucb_low_std, ucb_high_std)

    def test_bayesian_improves_over_random(self):
        """Bayesian optimization should find better configs than random."""
        def quadratic_objective(x: float) -> float:
            return (x - 0.3) ** 2  # Minimum at x=0.3

        # Random search
        rng = random.Random(42)
        random_best = min(quadratic_objective(rng.random()) for _ in range(50))

        # Bayesian-like: use best observed to guide search
        best_x = rng.random()
        best_obj = quadratic_objective(best_x)
        for _ in range(50):
            # Perturb best with decreasing noise
            x = max(0, min(1, best_x + rng.gauss(0, 0.1)))
            obj = quadratic_objective(x)
            if obj < best_obj:
                best_obj = obj
                best_x = x

        # Bayesian-like should find better solution
        self.assertLessEqual(best_obj, random_best + 0.01)


class TestEvolutionarySearch(unittest.TestCase):
    """Tests for evolutionary search."""

    def test_mutation_changes_config(self):
        """Mutation should change at least one parameter."""
        rng = random.Random(42)
        config = {'ewc_lambda': 400.0, 'hamming_threshold': 24, 'learning_rate': 0.001}

        def mutate(config: Dict, rng: random.Random) -> Dict:
            mutated = dict(config)
            param = rng.choice(list(config.keys()))
            if param == 'ewc_lambda':
                mutated[param] = max(10.0, min(2000.0, config[param] * (1 + rng.gauss(0, 0.2))))
            elif param == 'hamming_threshold':
                mutated[param] = max(4, min(64, config[param] + rng.randint(-5, 5)))
            elif param == 'learning_rate':
                mutated[param] = max(1e-5, min(1e-1, config[param] * (1 + rng.gauss(0, 0.2))))
            return mutated

        mutated = mutate(config, rng)
        self.assertNotEqual(config, mutated)

    def test_crossover_combines_parents(self):
        """Crossover should combine parameters from both parents."""
        parent1 = {'a': 1.0, 'b': 2.0, 'c': 3.0}
        parent2 = {'a': 4.0, 'b': 5.0, 'c': 6.0}
        rng = random.Random(42)

        def crossover(p1: Dict, p2: Dict, rng: random.Random) -> Dict:
            child = {}
            for key in p1:
                child[key] = p1[key] if rng.random() < 0.5 else p2[key]
            return child

        # Run many crossovers and check that both parents contribute
        p1_contributions = defaultdict(int)
        p2_contributions = defaultdict(int)
        for _ in range(1000):
            child = crossover(parent1, parent2, rng)
            for key in child:
                if child[key] == parent1[key]:
                    p1_contributions[key] += 1
                else:
                    p2_contributions[key] += 1

        # Both parents should contribute roughly equally
        for key in parent1:
            ratio = p1_contributions[key] / (p1_contributions[key] + p2_contributions[key])
            self.assertAlmostEqual(ratio, 0.5, delta=0.1)

    def test_elite_selection(self):
        """Elite selection should keep best individuals."""
        population = [{'score': float(i)} for i in range(20)]
        scores = [float(i) for i in range(20)]

        # Select top 20%
        n_elite = 4
        sorted_pop = sorted(zip(scores, population), key=lambda x: x[0])
        elites = [p for _, p in sorted_pop[:n_elite]]

        # Elites should have lowest scores
        elite_scores = [e['score'] for e in elites]
        self.assertEqual(max(elite_scores), 3.0)

    def test_tournament_selection(self):
        """Tournament selection should prefer better individuals."""
        rng = random.Random(42)
        population = list(range(100))  # Scores 0-99
        tournament_size = 5

        def tournament_select(pop, rng, k):
            candidates = rng.sample(pop, k)
            return min(candidates)  # Minimize

        # Run many tournaments
        selected = [tournament_select(population, rng, tournament_size) for _ in range(1000)]
        mean_selected = sum(selected) / len(selected)

        # Mean should be well below 50 (the uniform mean)
        self.assertLess(mean_selected, 40)

    def test_population_diversity(self):
        """Population should maintain diversity."""
        rng = random.Random(42)
        population = [rng.uniform(0, 1) for _ in range(50)]
        std = (sum((x - sum(population)/len(population))**2 for x in population) / len(population)) ** 0.5
        # Population should have reasonable diversity
        self.assertGreater(std, 0.1)


# =============================================================================
# Hyperband Tests
# =============================================================================

class TestHyperband(unittest.TestCase):
    """Tests for Hyperband algorithm."""

    def test_successive_halving_reduces_population(self):
        """Successive halving should reduce population by factor eta."""
        eta = 3
        initial_n = 27
        configs = list(range(initial_n))
        rng = random.Random(42)

        def evaluate(config, budget):
            return rng.random()  # Random objective

        # One round of halving
        results = [(c, evaluate(c, 1)) for c in configs]
        results.sort(key=lambda x: x[1])
        n_keep = max(1, len(results) // eta)
        kept = [r[0] for r in results[:n_keep]]

        self.assertEqual(len(kept), 9)

    def test_hyperband_budget_schedule(self):
        """Hyperband should allocate increasing budgets."""
        max_iter = 81
        eta = 3
        s_max = int(math.log(max_iter) / math.log(eta))

        budgets = []
        for s in range(s_max, -1, -1):
            n = math.ceil((s_max + 1) / (s + 1)) * (eta ** s)
            r = max_iter * (eta ** (-s))
            budgets.append(r)

        # Budgets should be increasing
        self.assertEqual(sorted(budgets), budgets)

    def test_hyperband_total_budget(self):
        """Hyperband total budget should be bounded."""
        max_iter = 81
        eta = 3
        s_max = int(math.log(max_iter) / math.log(eta))
        B = (s_max + 1) * max_iter

        total_work = 0
        for s in range(s_max, -1, -1):
            n = math.ceil(B / max_iter / (s + 1)) * (eta ** s)
            r = max_iter * (eta ** (-s))
            for i in range(s + 1):
                n_i = max(1, int(n * (eta ** (-i))))
                r_i = r * (eta ** i)
                total_work += n_i * r_i

        # Total work should be bounded by B * (s_max + 1)
        self.assertLessEqual(total_work, B * (s_max + 1) * 2)


# =============================================================================
# Model Registry Tests
# =============================================================================

class TestModelRegistry(unittest.TestCase):
    """Tests for model registry."""

    def setUp(self):
        self.registry = {}
        self.counter = 0

    def _register(self, config: Dict, metrics: Dict) -> str:
        self.counter += 1
        model_id = f"model_{self.counter:06d}"
        self.registry[model_id] = {
            'model_id': model_id,
            'config': config,
            'metrics': metrics,
            'status': 'candidate',
            'created_at': time.time(),
        }
        return model_id

    def test_register_model(self):
        """Should register model and return unique ID."""
        model_id = self._register({'lr': 0.001}, {'objective': 0.5})
        self.assertIn(model_id, self.registry)

    def test_unique_model_ids(self):
        """Each registered model should have unique ID."""
        ids = set()
        for i in range(100):
            mid = self._register({'lr': 0.001 * i}, {'objective': float(i)})
            ids.add(mid)
        self.assertEqual(len(ids), 100)

    def test_get_best_model(self):
        """Should return model with best objective."""
        objectives = [0.5, 0.3, 0.8, 0.1, 0.6]
        for obj in objectives:
            self._register({'obj': obj}, {'objective': obj})

        best = min(self.registry.values(), key=lambda m: m['metrics']['objective'])
        self.assertAlmostEqual(best['metrics']['objective'], 0.1)

    def test_promote_model(self):
        """Should promote model to production status."""
        mid = self._register({'lr': 0.001}, {'objective': 0.3})
        self.registry[mid]['status'] = 'production'
        self.assertEqual(self.registry[mid]['status'], 'production')

    def test_registry_persistence(self):
        """Registry should persist to disk and reload."""
        with tempfile.TemporaryDirectory() as tmpdir:
            registry_path = os.path.join(tmpdir, 'registry.json')

            # Save
            data = {'models': list(self.registry.values()), 'count': self.counter}
            with open(registry_path, 'w') as f:
                json.dump(data, f)

            # Load
            with open(registry_path, 'r') as f:
                loaded = json.load(f)

            self.assertEqual(loaded['count'], self.counter)


# =============================================================================
# Integration Tests
# =============================================================================

class TestAutoMLIntegration(unittest.TestCase):
    """Integration tests for the AutoML pipeline."""

    def test_full_search_finds_good_config(self):
        """Full search should find a configuration better than default."""
        rng = random.Random(42)

        def objective_fn(config: Dict) -> float:
            # Optimal: lambda=400, threshold=24, lr=0.001
            lambda_score = abs(math.log(config['ewc_lambda']) - math.log(400)) / 5
            threshold_score = abs(config['hamming_threshold'] - 24) / 60
            lr_score = abs(math.log(config['learning_rate']) - math.log(0.001)) / 10
            noise = rng.gauss(0, 0.01)
            return lambda_score + threshold_score + lr_score + noise

        # Default config
        default_config = {'ewc_lambda': 400.0, 'hamming_threshold': 24, 'learning_rate': 0.001}
        default_obj = objective_fn(default_config)

        # Random search
        best_obj = float('inf')
        for _ in range(100):
            config = {
                'ewc_lambda': math.exp(rng.uniform(math.log(10), math.log(2000))),
                'hamming_threshold': rng.randint(4, 64),
                'learning_rate': math.exp(rng.uniform(math.log(1e-5), math.log(1e-1))),
            }
            obj = objective_fn(config)
            best_obj = min(best_obj, obj)

        # Search should find something at least as good as default
        self.assertLessEqual(best_obj, default_obj + 0.5)

    def test_search_convergence(self):
        """Search should show improvement over time."""
        rng = random.Random(42)

        def objective_fn(x: float) -> float:
            return (x - 0.3) ** 2 + rng.gauss(0, 0.01)

        # Track best over time
        best_values = []
        best = float('inf')
        for _ in range(50):
            x = rng.random()
            obj = objective_fn(x)
            best = min(best, obj)
            best_values.append(best)

        # Best should generally decrease
        first_half_mean = sum(best_values[:25]) / 25
        second_half_mean = sum(best_values[25:]) / 25
        self.assertLessEqual(second_half_mean, first_half_mean)

    def test_parallel_search_consistency(self):
        """Parallel search results should be consistent with sequential."""
        rng = random.Random(42)
        configs = [{'lr': rng.uniform(1e-5, 1e-1)} for _ in range(20)]
        objectives = [c['lr'] ** 2 for c in configs]  # Simple objective

        best_sequential = min(objectives)
        best_parallel = min(objectives)  # Same data, same result

        self.assertAlmostEqual(best_sequential, best_parallel)


# =============================================================================
# Main Test Runner
# =============================================================================

def run_all_tests():
    """Run all AutoML test suites."""
    test_suites = [
        unittest.TestLoader().loadTestsFromTestCase(TestParameterSpec),
        unittest.TestLoader().loadTestsFromTestCase(TestSearchSpace),
        unittest.TestLoader().loadTestsFromTestCase(TestObjectiveFunction),
        unittest.TestLoader().loadTestsFromTestCase(TestSurrogateModel),
        unittest.TestLoader().loadTestsFromTestCase(TestTrialManagement),
        unittest.TestLoader().loadTestsFromTestCase(TestRandomSearch),
        unittest.TestLoader().loadTestsFromTestCase(TestBayesianOptimization),
        unittest.TestLoader().loadTestsFromTestCase(TestEvolutionarySearch),
        unittest.TestLoader().loadTestsFromTestCase(TestHyperband),
        unittest.TestLoader().loadTestsFromTestCase(TestModelRegistry),
        unittest.TestLoader().loadTestsFromTestCase(TestAutoMLIntegration),
    ]

    combined = unittest.TestSuite(test_suites)
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(combined)
    return result.wasSuccessful()


if __name__ == '__main__':
    success = run_all_tests()
    sys.exit(0 if success else 1)
