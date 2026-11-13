"""
validation.py — Python-side validation mirroring Q# Validation.qs.
"""
from __future__ import annotations
import math
from .contracts import (
    ExperimentConfig, InferenceRequest, TrainingConfig,
    MAIA300Config, BrainwaveFPGAConfig, HollowCoreFiberConfig,
    MajoranaQPUConfig, MoERoutingConfig, RLHFConfig,
    WeightShardConfig, HybridQuantizationConfig,
    ClusterNodeConfig, BenchmarkCase,
)

class ValidationError(ValueError):
    pass

def _check(cond: bool, msg: str) -> None:
    if not cond: raise ValidationError(msg)

def validate_experiment_config(c: ExperimentConfig) -> None:
    _check(c.qubit_count > 0, f"qubit_count must be > 0, got {c.qubit_count}")
    _check(c.qubit_count <= 1_000_000, "qubit_count exceeds Majorana-1 limit of 1,000,000")
    _check(c.ancilla_count >= 0, f"ancilla_count must be >= 0, got {c.ancilla_count}")
    _check(c.shot_count > 0, f"shot_count must be > 0, got {c.shot_count}")
    _check(c.shot_count <= 10_000_000, "shot_count exceeds maximum of 10,000,000")
    _check(0.0 <= c.threshold <= 1.0, f"threshold must be in [0,1], got {c.threshold}")
    _check(-2*math.pi <= c.theta_z <= 2*math.pi, f"theta_z out of [-2π,2π]: {c.theta_z}")
    _check(-2*math.pi <= c.theta_y <= 2*math.pi, f"theta_y out of [-2π,2π]: {c.theta_y}")
    if c.use_qec:
        _check(c.code_distance >= 3, f"code_distance must be >= 3 for QEC, got {c.code_distance}")
        _check(c.code_distance % 2 == 1, f"code_distance must be odd, got {c.code_distance}")
    _check(c.braid_depth >= 0, f"braid_depth must be >= 0, got {c.braid_depth}")

def validate_inference_request(r: InferenceRequest) -> None:
    _check(bool(r.input_token_ids), "input_token_ids must not be empty")
    _check(len(r.input_token_ids) <= 131072, f"Input exceeds 131072 tokens: {len(r.input_token_ids)}")
    _check(r.max_new_tokens > 0, f"max_new_tokens must be > 0, got {r.max_new_tokens}")
    _check(r.temperature >= 0.0, f"temperature must be >= 0, got {r.temperature}")
    _check(0.0 < r.top_p <= 1.0, f"top_p must be in (0,1], got {r.top_p}")
    _check(r.beam_width >= 1, f"beam_width must be >= 1, got {r.beam_width}")
    _check(r.timeout_ms > 0, f"timeout_ms must be > 0, got {r.timeout_ms}")

def validate_training_config(c: TrainingConfig) -> None:
    _check(c.learning_rate > 0, f"learning_rate must be > 0, got {c.learning_rate}")
    _check(c.learning_rate <= 1.0, f"learning_rate must be <= 1.0, got {c.learning_rate}")
    _check(c.total_steps > 0, f"total_steps must be > 0, got {c.total_steps}")
    _check(c.batch_size > 0, f"batch_size must be > 0, got {c.batch_size}")
    _check(c.gradient_clipping > 0, f"gradient_clipping must be > 0, got {c.gradient_clipping}")
    _check(0.0 < c.adam_beta1 < 1.0, f"adam_beta1 must be in (0,1), got {c.adam_beta1}")
    _check(0.0 < c.adam_beta2 < 1.0, f"adam_beta2 must be in (0,1), got {c.adam_beta2}")
    _check(c.warmup_steps >= 0, f"warmup_steps must be >= 0, got {c.warmup_steps}")
    _check(c.warmup_steps < c.total_steps, "warmup_steps must be < total_steps")
    _check(c.zero_stage in (0,1,2,3), f"zero_stage must be 0/1/2/3, got {c.zero_stage}")

def validate_maia300_config(c: MAIA300Config) -> None:
    _check(0 <= c.chiplet_id < c.total_chiplets_per_rack,
           f"chiplet_id {c.chiplet_id} out of range [0,{c.total_chiplets_per_rack})")
    _check(c.hbm4_capacity_gb > 0, f"hbm4_capacity_gb must be > 0")
    _check(c.hbm4_bandwidth_tbs > 0, f"hbm4_bandwidth_tbs must be > 0")
    _check(c.compute_tflops_bf16 > 0, f"compute_tflops_bf16 must be > 0")
    _check(c.tensor_parallel_degree * c.pipeline_parallel_degree <= c.total_chiplets_per_rack,
           "TP * PP exceeds chiplet count per rack")

def validate_brainwave_config(c: BrainwaveFPGAConfig) -> None:
    _check(c.mac_units > 0, f"mac_units must be > 0, got {c.mac_units}")
    _check(c.peak_tflops_bf16 > 0, f"peak_tflops_bf16 must be > 0")
    _check(c.latency_target_ms > 0, f"latency_target_ms must be > 0")

def validate_hcf_config(c: HollowCoreFiberConfig) -> None:
    _check(c.length_km > 0, f"length_km must be > 0, got {c.length_km}")
    _check(c.bandwidth_tbps > 0, f"bandwidth_tbps must be > 0")
    _check(0 <= c.latency_reduction_pct <= 100, f"latency_reduction_pct must be in [0,100]")
    _check(c.refractive_index >= 1.0, f"refractive_index must be >= 1.0")

def validate_majorana_config(c: MajoranaQPUConfig) -> None:
    _check(c.physical_qubits > 0, f"physical_qubits must be > 0")
    _check(c.logical_qubits > 0, f"logical_qubits must be > 0")
    _check(c.physical_qubits >= c.logical_qubits, "physical_qubits must be >= logical_qubits")
    _check(0.0 <= c.gate_fidelity_1q <= 1.0, f"gate_fidelity_1q must be in [0,1]")
    _check(0.0 <= c.gate_fidelity_2q <= 1.0, f"gate_fidelity_2q must be in [0,1]")
    _check(c.t1_time_us > 0, f"t1_time_us must be > 0")
    _check(c.code_distance >= 3, f"code_distance must be >= 3")
    _check(c.protection_gap_mev > 0, f"protection_gap_mev must be > 0")

def validate_moe_config(c: MoERoutingConfig) -> None:
    _check(c.num_experts > 0, f"num_experts must be > 0")
    _check(0 < c.top_k <= c.num_experts, f"top_k must be in (0,{c.num_experts}]")
    _check(c.capacity_factor >= 1.0, f"capacity_factor must be >= 1.0")

def validate_rlhf_config(c: RLHFConfig) -> None:
    _check(c.kl_coeff >= 0, f"kl_coeff must be >= 0")
    _check(0 < c.clip_range < 1, f"clip_range must be in (0,1)")
    _check(c.ppo_epochs > 0, f"ppo_epochs must be > 0")
    _check(0 < c.gamma <= 1.0, f"gamma must be in (0,1]")
    _check(0 < c.lam <= 1.0, f"lam must be in (0,1]")

def validate_cluster_node(n: ClusterNodeConfig) -> None:
    _check(0 <= n.rank < n.world_size, f"rank {n.rank} out of range [0,{n.world_size})")
    _check(n.gpu_count >= 0, f"gpu_count must be >= 0")
    _check(n.cpu_cores > 0, f"cpu_cores must be > 0")
    _check(n.memory_gb > 0, f"memory_gb must be > 0")
    _check(0.0 <= n.health_score <= 1.0, f"health_score must be in [0,1]")

def validate_benchmark_case(c: BenchmarkCase) -> None:
    _check(bool(c.case_id), "case_id must not be empty")
    _check(c.qubit_count > 0, f"qubit_count must be > 0")
    _check(c.shot_count > 0, f"shot_count must be > 0")
    _check(c.expected_mean_lo <= c.expected_mean_hi,
           f"expected_mean_lo {c.expected_mean_lo} > expected_mean_hi {c.expected_mean_hi}")
    _check(0.0 <= c.expected_mean_lo <= 1.0, "expected_mean_lo must be in [0,1]")
    _check(0.0 <= c.expected_mean_hi <= 1.0, "expected_mean_hi must be in [0,1]")
    _check(c.timeout_seconds > 0, f"timeout_seconds must be > 0")
