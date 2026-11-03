# =============================================================================
# architecture_search.py
# AutoDL neural architecture search for the AGI mesh pipeline
# Implements NAS for CNN, Transformer, and Embedding architectures
# =============================================================================

from __future__ import annotations

import math
import time
import json
import random
import logging
import hashlib
import statistics
from typing import Any, Dict, List, Optional, Tuple, Callable, Union
from dataclasses import dataclass, field
from collections import defaultdict, deque
from copy import deepcopy
from enum import Enum, auto
from pathlib import Path

logger = logging.getLogger(__name__)


# =============================================================================
# Architecture Primitives
# =============================================================================

class ActivationFn(Enum):
    RELU = "relu"
    GELU = "gelu"
    SWISH = "swish"
    TANH = "tanh"
    SIGMOID = "sigmoid"
    LEAKY_RELU = "leaky_relu"
    ELU = "elu"
    SELU = "selu"


class NormalizationType(Enum):
    BATCH_NORM = "batch_norm"
    LAYER_NORM = "layer_norm"
    GROUP_NORM = "group_norm"
    INSTANCE_NORM = "instance_norm"
    NONE = "none"


class PoolingType(Enum):
    MAX = "max"
    AVG = "avg"
    ADAPTIVE_MAX = "adaptive_max"
    ADAPTIVE_AVG = "adaptive_avg"
    ATTENTION = "attention"


class AttentionType(Enum):
    MULTI_HEAD = "multi_head"
    LINEAR = "linear"
    SPARSE = "sparse"
    LOCAL = "local"
    CROSS = "cross"


# =============================================================================
# Layer Specifications
# =============================================================================

@dataclass
class ConvLayerSpec:
    """Specification for a convolutional layer."""
    out_channels: int = 64
    kernel_size: int = 3
    stride: int = 1
    padding: int = 1
    dilation: int = 1
    groups: int = 1
    bias: bool = True
    activation: ActivationFn = ActivationFn.RELU
    normalization: NormalizationType = NormalizationType.BATCH_NORM
    dropout: float = 0.0

    def n_params(self, in_channels: int) -> int:
        """Estimate number of parameters."""
        kernel_params = (self.kernel_size ** 2) * in_channels * self.out_channels // self.groups
        bias_params = self.out_channels if self.bias else 0
        norm_params = 2 * self.out_channels if self.normalization != NormalizationType.NONE else 0
        return kernel_params + bias_params + norm_params

    def to_dict(self) -> Dict[str, Any]:
        return {
            'out_channels': self.out_channels,
            'kernel_size': self.kernel_size,
            'stride': self.stride,
            'padding': self.padding,
            'dilation': self.dilation,
            'groups': self.groups,
            'bias': self.bias,
            'activation': self.activation.value,
            'normalization': self.normalization.value,
            'dropout': self.dropout,
        }


@dataclass
class TransformerLayerSpec:
    """Specification for a transformer encoder layer."""
    d_model: int = 512
    n_heads: int = 8
    d_ff: int = 2048
    dropout: float = 0.1
    attention_type: AttentionType = AttentionType.MULTI_HEAD
    normalization: NormalizationType = NormalizationType.LAYER_NORM
    activation: ActivationFn = ActivationFn.GELU
    pre_norm: bool = True
    use_rotary_embedding: bool = False
    use_flash_attention: bool = False

    def n_params(self) -> int:
        """Estimate number of parameters."""
        attn_params = 4 * self.d_model * self.d_model  # Q, K, V, O projections
        ff_params = 2 * self.d_model * self.d_ff       # Two linear layers
        norm_params = 4 * self.d_model                  # Two layer norms
        return attn_params + ff_params + norm_params

    def to_dict(self) -> Dict[str, Any]:
        return {
            'd_model': self.d_model,
            'n_heads': self.n_heads,
            'd_ff': self.d_ff,
            'dropout': self.dropout,
            'attention_type': self.attention_type.value,
            'normalization': self.normalization.value,
            'activation': self.activation.value,
            'pre_norm': self.pre_norm,
            'use_rotary_embedding': self.use_rotary_embedding,
            'use_flash_attention': self.use_flash_attention,
        }


@dataclass
class EmbeddingLayerSpec:
    """Specification for an embedding layer."""
    embedding_dim: int = 512
    vocab_size: int = 0
    max_seq_len: int = 1024
    dropout: float = 0.1
    use_positional: bool = True
    positional_type: str = "sinusoidal"  # sinusoidal, learned, rotary
    padding_idx: int = 0

    def n_params(self) -> int:
        vocab_params = self.vocab_size * self.embedding_dim if self.vocab_size > 0 else 0
        pos_params = self.max_seq_len * self.embedding_dim if self.positional_type == "learned" else 0
        return vocab_params + pos_params

    def to_dict(self) -> Dict[str, Any]:
        return {
            'embedding_dim': self.embedding_dim,
            'vocab_size': self.vocab_size,
            'max_seq_len': self.max_seq_len,
            'dropout': self.dropout,
            'use_positional': self.use_positional,
            'positional_type': self.positional_type,
        }


@dataclass
class LinearLayerSpec:
    """Specification for a linear (fully connected) layer."""
    out_features: int = 512
    bias: bool = True
    activation: Optional[ActivationFn] = ActivationFn.RELU
    normalization: NormalizationType = NormalizationType.NONE
    dropout: float = 0.0

    def n_params(self, in_features: int) -> int:
        return in_features * self.out_features + (self.out_features if self.bias else 0)

    def to_dict(self) -> Dict[str, Any]:
        return {
            'out_features': self.out_features,
            'bias': self.bias,
            'activation': self.activation.value if self.activation else None,
            'normalization': self.normalization.value,
            'dropout': self.dropout,
        }


# =============================================================================
# Architecture Specification
# =============================================================================

@dataclass
class CandidateArchitecture:
    """Complete neural architecture specification."""
    arch_id: str = ""
    arch_type: str = "siamese_cnn_transformer"

    # CNN backbone
    conv_layers: List[ConvLayerSpec] = field(default_factory=list)
    input_channels: int = 1
    use_residual: bool = True
    use_depthwise: bool = False
    pooling: PoolingType = PoolingType.ADAPTIVE_AVG

    # Transformer encoder
    transformer_layers: List[TransformerLayerSpec] = field(default_factory=list)
    embedding_dim: int = 512

    # Embedding head
    embedding_spec: Optional[EmbeddingLayerSpec] = None

    # Output head
    output_layers: List[LinearLayerSpec] = field(default_factory=list)
    output_dim: int = 512

    # Training hyperparameters
    learning_rate: float = 1e-3
    weight_decay: float = 1e-4
    dropout_global: float = 0.1

    # Performance estimates
    score: float = float('inf')
    n_parameters: int = 0
    estimated_flops: int = 0
    estimated_latency_ms: float = 0.0
    validation_loss: Optional[float] = None
    generation: int = 0

    def __post_init__(self):
        if not self.arch_id:
            self.arch_id = self._compute_id()
        self.n_parameters = self._estimate_params()

    def _compute_id(self) -> str:
        """Compute unique architecture ID from spec."""
        spec_str = json.dumps(self.to_dict(), sort_keys=True, default=str)
        return hashlib.md5(spec_str.encode()).hexdigest()[:12]

    def _estimate_params(self) -> int:
        """Estimate total parameter count."""
        total = 0
        in_ch = self.input_channels
        for layer in self.conv_layers:
            total += layer.n_params(in_ch)
            in_ch = layer.out_channels

        for layer in self.transformer_layers:
            total += layer.n_params()

        if self.embedding_spec:
            total += self.embedding_spec.n_params()

        in_feat = self.embedding_dim
        for layer in self.output_layers:
            total += layer.n_params(in_feat)
            in_feat = layer.out_features

        return total

    def _estimate_flops(self, input_size: int = 512) -> int:
        """Estimate FLOPs for forward pass."""
        flops = 0
        spatial = input_size
        in_ch = self.input_channels

        for layer in self.conv_layers:
            flops += 2 * layer.kernel_size ** 2 * in_ch * layer.out_channels * spatial * spatial
            spatial = spatial // layer.stride
            in_ch = layer.out_channels

        seq_len = spatial * spatial
        for layer in self.transformer_layers:
            # Attention: O(seq_len^2 * d_model)
            flops += 2 * seq_len * seq_len * layer.d_model
            # FFN: O(seq_len * d_model * d_ff)
            flops += 2 * seq_len * layer.d_model * layer.d_ff

        return flops

    def to_dict(self) -> Dict[str, Any]:
        return {
            'arch_id': self.arch_id,
            'arch_type': self.arch_type,
            'conv_layers': [l.to_dict() for l in self.conv_layers],
            'input_channels': self.input_channels,
            'use_residual': self.use_residual,
            'use_depthwise': self.use_depthwise,
            'pooling': self.pooling.value,
            'transformer_layers': [l.to_dict() for l in self.transformer_layers],
'embedding_dim': self.embedding_dim,
            'embedding_spec': self.embedding_spec.to_dict() if self.embedding_spec else None,
            'output_layers': [l.to_dict() for l in self.output_layers],
            'output_dim': self.output_dim,
            'learning_rate': self.learning_rate,
            'weight_decay': self.weight_decay,
            'dropout_global': self.dropout_global,
            'score': self.score,
            'n_parameters': self.n_parameters,
            'estimated_flops': self.estimated_flops,
            'generation': self.generation,
        }

    def complexity_score(self) -> float:
        """Compute architecture complexity score."""
        param_score = math.log(max(1, self.n_parameters)) / math.log(1e8)
        depth_score = (len(self.conv_layers) + len(self.transformer_layers)) / 20.0
        return param_score + depth_score

    def is_valid(self) -> bool:
        """Check if architecture is valid."""
        if not self.conv_layers and not self.transformer_layers:
            return False
        if self.embedding_dim <= 0:
            return False
        if self.output_dim <= 0:
            return False
        # Check transformer head divisibility
for layer in self.transformer_layers:
            if (layer.n_heads <= 0 or
                    layer.d_model != self.embedding_dim or
                    layer.d_model % layer.n_heads != 0):
                return False
        return True


# =============================================================================
# Architecture Search Space
# =============================================================================

class ArchitectureSearchSpace:
    """Defines the search space for neural architecture search."""

    def __init__(self, seed: int = 42):
        self.seed = seed
        self.rng = random.Random(seed)

        # CNN search space
        self.conv_channels = [16, 32, 64, 128, 256, 512]
        self.kernel_sizes = [1, 3, 5, 7]
        self.n_conv_layers = list(range(1, 9))
        self.activations = list(ActivationFn)
        self.normalizations = list(NormalizationType)

        # Transformer search space
        self.d_models = [64, 128, 256, 512, 768, 1024]
        self.n_heads_options = [1, 2, 4, 8, 12, 16]
        self.d_ff_multipliers = [1, 2, 4, 8]
        self.n_transformer_layers = list(range(1, 13))

        # Embedding search space
        self.embedding_dims = [64, 128, 256, 512, 768, 1024]

        # Output head search space
        self.output_dims = [64, 128, 256, 512]
        self.n_output_layers = list(range(1, 5))

    def sample_conv_layer(self, in_channels: int) -> ConvLayerSpec:
        """Sample a random convolutional layer."""
        out_channels = self.rng.choice(self.conv_channels)
        kernel_size = self.rng.choice(self.kernel_sizes)
        return ConvLayerSpec(
            out_channels=out_channels,
            kernel_size=kernel_size,
            stride=self.rng.choice([1, 2]),
            padding=kernel_size // 2,
            activation=self.rng.choice(self.activations),
            normalization=self.rng.choice(self.normalizations),
            dropout=round(self.rng.uniform(0.0, 0.3), 2),
        )

    def sample_transformer_layer(self, d_model: int) -> TransformerLayerSpec:
        """Sample a random transformer layer."""
        # Ensure n_heads divides d_model
        valid_heads = [h for h in self.n_heads_options if d_model % h == 0]
        n_heads = self.rng.choice(valid_heads) if valid_heads else 1
        d_ff_mult = self.rng.choice(self.d_ff_multipliers)
        return TransformerLayerSpec(
            d_model=d_model,
            n_heads=n_heads,
            d_ff=d_model * d_ff_mult,
            dropout=round(self.rng.uniform(0.0, 0.3), 2),
            attention_type=self.rng.choice(list(AttentionType)),
            normalization=NormalizationType.LAYER_NORM,
            activation=self.rng.choice([ActivationFn.RELU, ActivationFn.GELU]),
            pre_norm=self.rng.choice([True, False]),
            use_rotary_embedding=self.rng.choice([True, False]),
        )

    def sample_architecture(self) -> CandidateArchitecture:
        """Sample a random architecture from the search space."""
        # CNN backbone
        n_conv = self.rng.choice(self.n_conv_layers)
        conv_layers = []
        in_ch = 1
        for _ in range(n_conv):
            layer = self.sample_conv_layer(in_ch)
            conv_layers.append(layer)
            in_ch = layer.out_channels

        # Transformer encoder
        d_model = self.rng.choice(self.d_models)
        n_transformer = self.rng.choice(self.n_transformer_layers)
        transformer_layers = [self.sample_transformer_layer(d_model) for _ in range(n_transformer)]

        # Output head
        n_output = self.rng.choice(self.n_output_layers)
        output_dim = self.rng.choice(self.output_dims)
        output_layers = []
        in_feat = d_model
        for i in range(n_output):
            out_feat = output_dim if i == n_output - 1 else self.rng.choice(self.output_dims)
            output_layers.append(LinearLayerSpec(
                out_features=out_feat,
                activation=ActivationFn.RELU if i < n_output - 1 else None,
                dropout=round(self.rng.uniform(0.0, 0.3), 2),
            ))
            in_feat = out_feat

        arch = CandidateArchitecture(
            conv_layers=conv_layers,
            transformer_layers=transformer_layers,
            embedding_dim=d_model,
            output_layers=output_layers,
            output_dim=output_dim,
            use_residual=self.rng.choice([True, False]),
            use_depthwise=self.rng.choice([True, False]),
            pooling=self.rng.choice(list(PoolingType)),
            learning_rate=10 ** self.rng.uniform(-5, -2),
            weight_decay=10 ** self.rng.uniform(-6, -2),
            dropout_global=round(self.rng.uniform(0.0, 0.5), 2),
        )
        return arch

    def sample_batch(self, n: int) -> List[CandidateArchitecture]:
        """Sample a batch of architectures."""
        return [self.sample_architecture() for _ in range(n)]


# =============================================================================
# Architecture Evaluator
# =============================================================================

class ArchitectureEvaluator:
    """
    Evaluates candidate architectures using proxy metrics.
    Implements zero-shot, few-shot, and full evaluation strategies.
    """

    def __init__(
        self,
        evaluation_strategy: str = 'proxy',
        proxy_budget: int = 100,
        full_budget: int = 1000,
        seed: int = 42
    ):
        self.evaluation_strategy = evaluation_strategy
        self.proxy_budget = proxy_budget
        self.full_budget = full_budget
        self.rng = random.Random(seed)
        self._eval_cache: Dict[str, float] = {}

    def evaluate_proxy(self, arch: CandidateArchitecture) -> float:
        """
        Fast proxy evaluation using architecture properties.
        Estimates performance without full training.
        """
        if arch.arch_id in self._eval_cache:
            return self._eval_cache[arch.arch_id]

        # Proxy metrics
        param_score = self._param_efficiency_score(arch)
        depth_score = self._depth_score(arch)
        diversity_score = self._diversity_score(arch)
        complexity_penalty = arch.complexity_score() * 0.1

        # Simulate training noise
        noise = self.rng.gauss(0, 0.05)

        score = param_score + depth_score + diversity_score + complexity_penalty + noise
        self._eval_cache[arch.arch_id] = score
        return score

    def _param_efficiency_score(self, arch: CandidateArchitecture) -> float:
        """Score based on parameter efficiency."""
        n_params = arch.n_parameters
        # Optimal range: 1M - 100M parameters
        if n_params < 1e5:
            return 1.0  # Too small
        elif n_params < 1e6:
            return 0.5
        elif n_params < 1e8:
            return 0.0  # Optimal
        else:
            return math.log(n_params / 1e8)  # Too large

    def _depth_score(self, arch: CandidateArchitecture) -> float:
        """Score based on network depth."""
        total_depth = len(arch.conv_layers) + len(arch.transformer_layers)
        # Optimal depth: 6-12 layers
        if total_depth < 3:
            return 0.5
        elif total_depth <= 12:
            return 0.0
        else:
            return (total_depth - 12) * 0.1

    def _diversity_score(self, arch: CandidateArchitecture) -> float:
        """Score based on architectural diversity (variety of operations)."""
        activations = set(l.activation for l in arch.conv_layers)
        norms = set(l.normalization for l in arch.conv_layers)
        diversity = len(activations) + len(norms)
        return max(0.0, 0.5 - diversity * 0.1)

    def evaluate_zero_shot(self, arch: CandidateArchitecture) -> float:
        """Zero-shot evaluation using gradient signal metrics."""
        # Simulate gradient norm at initialization
        grad_norm = self.rng.gauss(1.0, 0.3)
        # Simulate activation statistics
        activation_std = self.rng.gauss(0.5, 0.1)
        # Score: good initialization has unit gradient norm and activation std
        score = abs(grad_norm - 1.0) + abs(activation_std - 0.5)
        return score + self.evaluate_proxy(arch) * 0.5

    def evaluate_few_shot(
        self,
        arch: CandidateArchitecture,
        n_steps: int = 100
    ) -> float:
        """Few-shot evaluation with limited training steps."""
        # Simulate training curve
        initial_loss = 2.0 + self.rng.gauss(0, 0.2)
        lr = arch.learning_rate
        decay = 1.0 - lr * 0.1

        loss = initial_loss
        for _ in range(n_steps):
            loss *= decay
            loss += self.rng.gauss(0, 0.01)

        return max(0.0, loss)

    def evaluate(self, arch: CandidateArchitecture) -> float:
        """Evaluate architecture using configured strategy."""
        if self.evaluation_strategy == 'proxy':
            return self.evaluate_proxy(arch)
        elif self.evaluation_strategy == 'zero_shot':
            return self.evaluate_zero_shot(arch)
        elif self.evaluation_strategy == 'few_shot':
            return self.evaluate_few_shot(arch, self.proxy_budget)
        else:
            return self.evaluate_proxy(arch)

    def evaluate_batch(
        self,
        architectures: List[CandidateArchitecture]
    ) -> List[float]:
        """Evaluate a batch of architectures."""
        return [self.evaluate(arch) for arch in architectures]


# =============================================================================
# Architecture Search Algorithm
# =============================================================================

class ArchitectureSearch:
    """
    Main neural architecture search algorithm.
    Implements evolutionary search with proxy evaluation.
    """

    def __init__(
        self,
        search_space: ArchitectureSearchSpace,
        evaluator: ArchitectureEvaluator,
        population_size: int = 50,
        n_generations: int = 20,
        elite_fraction: float = 0.2,
        mutation_rate: float = 0.3,
        crossover_rate: float = 0.5,
        tournament_size: int = 5,
        seed: int = 42,
        verbose: bool = True
    ):
        self.search_space = search_space
        self.evaluator = evaluator
        self.population_size = population_size
        self.n_generations = n_generations
        self.elite_fraction = elite_fraction
        self.mutation_rate = mutation_rate
        self.crossover_rate = crossover_rate
        self.tournament_size = tournament_size
        self.seed = seed
        self.verbose = verbose
        self.rng = random.Random(seed)

        self._population: List[CandidateArchitecture] = []
        self._generation = 0
        self._best_arch: Optional[CandidateArchitecture] = None
        self._history: List[Dict[str, Any]] = []

    def initialize_population(self) -> None:
        """Initialize random population."""
        self._population = self.search_space.sample_batch(self.population_size)
        logger.info(f"Initialized population: {self.population_size} architectures")

    def evaluate_population(self) -> None:
        """Evaluate all architectures in population."""
        scores = self.evaluator.evaluate_batch(self._population)
        for arch, score in zip(self._population, scores):
            arch.score = score
            arch.generation = self._generation

        self._population.sort(key=lambda a: a.score)

        if self._best_arch is None or self._population[0].score < self._best_arch.score:
            self._best_arch = deepcopy(self._population[0])
            logger.info(f"Gen {self._generation}: new best score={self._best_arch.score:.4f} "
                        f"params={self._best_arch.n_parameters:,}")

    def tournament_select(self) -> CandidateArchitecture:
        """Tournament selection."""
        candidates = self.rng.sample(self._population, min(self.tournament_size, len(self._population)))
        return min(candidates, key=lambda a: a.score)

    def mutate(self, arch: CandidateArchitecture) -> CandidateArchitecture:
        """Mutate an architecture."""
        mutated = deepcopy(arch)
        mutation_type = self.rng.choice([
            'add_conv', 'remove_conv', 'modify_conv',
            'add_transformer', 'remove_transformer', 'modify_transformer',
            'modify_output', 'modify_training'
        ])

        if mutation_type == 'add_conv' and len(mutated.conv_layers) < 8:
            in_ch = mutated.conv_layers[-1].out_channels if mutated.conv_layers else 1
            mutated.conv_layers.append(self.search_space.sample_conv_layer(in_ch))

        elif mutation_type == 'remove_conv' and len(mutated.conv_layers) > 1:
            idx = self.rng.randint(0, len(mutated.conv_layers) - 1)
            mutated.conv_layers.pop(idx)

        elif mutation_type == 'modify_conv' and mutated.conv_layers:
            idx = self.rng.randint(0, len(mutated.conv_layers) - 1)
            in_ch = mutated.conv_layers[idx - 1].out_channels if idx > 0 else 1
            mutated.conv_layers[idx] = self.search_space.sample_conv_layer(in_ch)

        elif mutation_type == 'add_transformer' and len(mutated.transformer_layers) < 12:
            mutated.transformer_layers.append(
                self.search_space.sample_transformer_layer(mutated.embedding_dim)
            )

        elif mutation_type == 'remove_transformer' and len(mutated.transformer_layers) > 1:
            idx = self.rng.randint(0, len(mutated.transformer_layers) - 1)
            mutated.transformer_layers.pop(idx)

        elif mutation_type == 'modify_transformer' and mutated.transformer_layers:
            idx = self.rng.randint(0, len(mutated.transformer_layers) - 1)
            mutated.transformer_layers[idx] = self.search_space.sample_transformer_layer(
                mutated.embedding_dim
            )

        elif mutation_type == 'modify_output':
            mutated.output_dim = self.rng.choice(self.search_space.output_dims)
            if mutated.output_layers:
                mutated.output_layers[-1].out_features = mutated.output_dim
        elif mutation_type == 'modify_training':
            mutated.learning_rate = 10 ** self.rng.uniform(-5, -2)
            mutated.weight_decay = 10 ** self.rng.uniform(-6, -2)
            mutated.dropout_global = round(self.rng.uniform(0.0, 0.5), 2)

        mutated.arch_id = mutated._compute_id()
        mutated.n_parameters = mutated._estimate_params()
        return mutated

    def crossover(
        self,
        parent1: CandidateArchitecture,
        parent2: CandidateArchitecture
    ) -> CandidateArchitecture:
        """Crossover two architectures."""
        child = deepcopy(parent1)

        # Crossover conv layers
        if parent2.conv_layers and self.rng.random() < 0.5:
            split = self.rng.randint(0, len(child.conv_layers))
            child.conv_layers = child.conv_layers[:split] + parent2.conv_layers[split:]

        # Crossover transformer layers
        if parent2.transformer_layers and self.rng.random() < 0.5:
            split = self.rng.randint(0, len(child.transformer_layers))
            child.transformer_layers = child.transformer_layers[:split] + \
                                       parent2.transformer_layers[split:]

        # Crossover training hyperparameters
        if self.rng.random() < 0.5:
            child.learning_rate = parent2.learning_rate
        if self.rng.random() < 0.5:
            child.weight_decay = parent2.weight_decay

        child.arch_id = child._compute_id()
        child.n_parameters = child._estimate_params()
        return child

    def evolve(self) -> None:
        """Evolve population to next generation."""
        n_elite = max(1, int(len(self._population) * self.elite_fraction))
        elites = self._population[:n_elite]

        new_population = list(elites)

        while len(new_population) < self.population_size:
            if self.rng.random() < self.crossover_rate:
                parent1 = self.tournament_select()
                parent2 = self.tournament_select()
                child = self.crossover(parent1, parent2)
            else:
                parent = self.tournament_select()
                child = deepcopy(parent)

            if self.rng.random() < self.mutation_rate:
                child = self.mutate(child)

            if child.is_valid():
                new_population.append(child)
            else:
                new_population.append(self.search_space.sample_architecture())

        self._population = new_population[:self.population_size]
        self._generation += 1

    def search(self) -> CandidateArchitecture:
        """Run the full architecture search."""
        logger.info(f"Starting architecture search: {self.n_generations} generations, "
                    f"population={self.population_size}")

        self.initialize_population()

        for gen in range(self.n_generations):
            self.evaluate_population()

            gen_stats = {
                'generation': gen,
                'best_score': self._population[0].score,
                'mean_score': statistics.mean(a.score for a in self._population),
                'best_params': self._population[0].n_parameters,
            }
            self._history.append(gen_stats)

            if self.verbose:
                logger.info(f"Gen {gen}: best={gen_stats['best_score']:.4f} "
                            f"mean={gen_stats['mean_score']:.4f} "
                            f"params={gen_stats['best_params']:,}")

            if gen < self.n_generations - 1:
                self.evolve()

        logger.info(f"Search complete. Best score: {self._best_arch.score:.4f}")
        return self._best_arch

    def get_top_k(self, k: int) -> List[CandidateArchitecture]:
        """Return top-k architectures from current population."""
        return sorted(self._population, key=lambda a: a.score)[:k]

    def get_history(self) -> List[Dict[str, Any]]:
        return self._history

    def get_statistics(self) -> Dict[str, Any]:
        return {
            'n_generations': self._generation,
            'population_size': len(self._population),
            'best_score': self._best_arch.score if self._best_arch else None,
            'best_arch_id': self._best_arch.arch_id if self._best_arch else None,
            'best_n_params': self._best_arch.n_parameters if self._best_arch else None,
            'history': self._history,
        }


# =============================================================================
# Architecture Registry
# =============================================================================

class ArchitectureRegistry:
    """Registry for storing and retrieving evaluated architectures."""

    def __init__(self, registry_dir: str = "arch_registry"):
        self.registry_dir = Path(registry_dir)
        self.registry_dir.mkdir(parents=True, exist_ok=True)
        self._architectures: Dict[str, CandidateArchitecture] = {}
        self._load_registry()

    def register(self, arch: CandidateArchitecture) -> None:
        """Register an architecture."""
        self._architectures[arch.arch_id] = arch
        self._save_arch(arch)

    def get(self, arch_id: str) -> Optional[CandidateArchitecture]:
        return self._architectures.get(arch_id)

    def get_best(self, n: int = 1) -> List[CandidateArchitecture]:
        """Get top-n architectures by score."""
        sorted_archs = sorted(self._architectures.values(), key=lambda a: a.score)
        return sorted_archs[:n]

    def _save_arch(self, arch: CandidateArchitecture) -> None:
        path = self.registry_dir / f"{arch.arch_id}.json"
        with open(path, 'w') as f:
            json.dump(arch.to_dict(), f, indent=2)

    def _load_registry(self) -> None:
        for path in self.registry_dir.glob("*.json"):
            try:
                with open(path, 'r') as f:
                    data = json.load(f)
                arch = CandidateArchitecture(**{
                    k: v for k, v in data.items()
                    if k in CandidateArchitecture.__dataclass_fields__
                })
                self._architectures[arch.arch_id] = arch
            except Exception as e:
                logger.warning(f"Failed to load arch {path}: {e}")

    def statistics(self) -> Dict[str, Any]:
        archs = list(self._architectures.values())
        scores = [a.score for a in archs if a.score < float('inf')]
        return {
            'total_architectures': len(archs),
            'best_score': min(scores) if scores else None,
            'mean_score': statistics.mean(scores) if scores else None,
        }

    def __len__(self) -> int:
        return len(self._architectures)