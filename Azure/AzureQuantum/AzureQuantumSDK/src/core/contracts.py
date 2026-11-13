"""
contracts.py — Dataclass contracts for the Windows-AGI-Mesh-QuantumSDK.
All inter-module data exchange uses these frozen dataclasses.
Covers: experiments, LLM inference, MAIA-300, Brainwave FPGA,
        Majorana QEC, Hollow-Core Fiber photonics, cluster topology,
        model weights, RLHF, MoE routing, alignment safety.
"""

from __future__ import annotations

import hashlib
import json
import math
import time
import uuid
from dataclasses import asdict, dataclass, field
from enum import Enum, auto
from typing import Any, Dict, List, Optional, Tuple


# ═══════════════════════════════════════════════════════════════════════════════
# Enumerations
# ═══════════════════════════════════════════════════════════════════════════════

class QuantumBackend(str, Enum):
    MAJORANA_1              = "microsoft.majorana-1"
    QUANTINUUM_HELIOS       = "quantinuum.helios"
    QUANTINUUM_H2_1         = "quantinuum.h2-1"
    QUANTINUUM_H2_1E        = "quantinuum.h2-1e"
    IBM_NIGHTHAWK_R2        = "ibm.nighthawk-r2"
    IBM_HERON_R3            = "ibm.heron-r3"
    IBM_EAGLE_R3            = "ibm.eagle-r3"
    IONQ_ARIA_1             = "ionq.aria-1"
    IONQ_ARIA_2             = "ionq.aria-2"
    IONQ_FORTE_1            = "ionq.forte-1"
    RIGETTI_ANKAA           = "rigetti.ankaa-9q-3"
    PASQAL_EMU_TN           = "pasqal.emu-tn"
    AQT_PINE                = "aqt.pine"
    OQC_LUCY                = "oqc.lucy"
    SIMULATOR_FULL_STATE    = "microsoft.simulator.full-state"
    SIMULATOR_SPARSE        = "microsoft.simulator.sparse"
    RESOURCE_ESTIMATOR      = "microsoft.resource-estimator"


class HardwareAccelerator(str, Enum):
    MAIA_300        = "maia-300"
    BRAINWAVE_FPGA  = "brainwave-fpga"
    PHOTONIC_HCF    = "photonic-hollow-core-fiber"
    MAJORANA_QPU    = "majorana-1-qpu"
    GPU_H100        = "nvidia-h100"
    GPU_A100        = "nvidia-a100"
    CPU_GENOA       = "amd-genoa"
    CPU_SAPPHIRE    = "intel-sapphire-rapids"


class QuantizationScheme(str, Enum):
    FP32    = "fp32"
    BF16    = "bf16"
    FP16    = "fp16"
    FP8_E4M3 = "fp8-e4m3"
    FP8_E5M2 = "fp8-e5m2"
    INT8    = "int8"
    INT4    = "int4"
    INT2    = "int2"
    NF4     = "nf4"
    HYBRID_Q4_BF16 = "hybrid-q4-bf16"
    HYBRID_Q8_FP8  = "hybrid-q8-fp8"
    QUANTUM_HYBRID  = "quantum-hybrid"


class ErrorCorrectionCode(str, Enum):
    SURFACE_CODE    = "surface-code"
    TOPOLOGICAL     = "topological-majorana"
    STEANE_7        = "steane-7"
    SHOR_9          = "shor-9"
    REPETITION      = "repetition"
    BACON_SHOR      = "bacon-shor"
    COLOR_CODE      = "color-code"
    TORIC_CODE      = "toric-code"
    NONE            = "none"


class AttentionType(str, Enum):
    MULTI_HEAD          = "multi-head"
    GROUPED_QUERY       = "grouped-query"
    MULTI_QUERY         = "multi-query"
    SLIDING_WINDOW      = "sliding-window"
    FLASH_ATTENTION     = "flash-attention"
    QUANTUM_ATTENTION   = "quantum-attention"
    HYBRID_ATTENTION    = "hybrid-attention"


class ActivationFunction(str, Enum):
    RELU    = "relu"
    GELU    = "gelu"
    SILU    = "silu"
    SWIGLU  = "swiglu"
    GEGLU   = "geglu"
    TANH    = "tanh"
    SIGMOID = "sigmoid"
    MISH    = "mish"


class TrainingPhase(str, Enum):
    PRETRAINING     = "pretraining"
    SUPERVISED_FT   = "supervised-finetuning"
    REWARD_MODELING = "reward-modeling"
    RLHF_PPO        = "rlhf-ppo"
    RLHF_DPO        = "rlhf-dpo"
    ALIGNMENT       = "alignment"
    QUANTUM_HYBRID  = "quantum-hybrid-training"


class NodeRole(str, Enum):
    COORDINATOR     = "coordinator"
    WORKER          = "worker"
    PARAMETER_SERVER = "parameter-server"
    QUANTUM_NODE    = "quantum-node"
    PHOTONIC_RELAY  = "photonic-relay"
    MAIA_NODE       = "maia-node"
    FPGA_NODE       = "fpga-node"


# ═══════════════════════════════════════════════════════════════════════════════
# Core experiment contracts
# ═══════════════════════════════════════════════════════════════════════════════

@dataclass(frozen=True)
class ExperimentConfig:
    """Configuration for a quantum experiment."""
    qubit_count:    int
    ancilla_count:  int
    theta_z:        float
    theta_y:        float
    shot_count:     int
    threshold:      float               = 0.5
    backend:        QuantumBackend      = QuantumBackend.SIMULATOR_FULL_STATE
    braid_depth:    int                 = 0
    use_qec:        bool                = False
    qec_code:       ErrorCorrectionCode = ErrorCorrectionCode.NONE
    code_distance:  int                 = 3
    experiment_id:  str                 = field(default_factory=lambda: str(uuid.uuid4()))
    tags:           List[str]           = field(default_factory=list)

    def validate(self) -> None:
        if self.qubit_count <= 0:
            raise ValueError(f"qubit_count must be > 0, got {self.qubit_count}")
        if self.qubit_count > 1_000_000:
            raise ValueError(f"qubit_count exceeds Majorana-1 limit of 1,000,000")
        if self.ancilla_count < 0:
            raise ValueError(f"ancilla_count must be >= 0, got {self.ancilla_count}")
        if self.shot_count <= 0:
            raise ValueError(f"shot_count must be > 0, got {self.shot_count}")
        if not 0.0 <= self.threshold <= 1.0:
            raise ValueError(f"threshold must be in [0,1], got {self.threshold}")
        if not -2 * math.pi <= self.theta_z <= 2 * math.pi:
            raise ValueError(f"theta_z must be in [-2π, 2π], got {self.theta_z}")
        if not -2 * math.pi <= self.theta_y <= 2 * math.pi:
            raise ValueError(f"theta_y must be in [-2π, 2π], got {self.theta_y}")
        if self.use_qec and self.code_distance < 3:
            raise ValueError(f"code_distance must be >= 3 for QEC, got {self.code_distance}")
        if self.use_qec and self.code_distance % 2 == 0:
            raise ValueError(f"code_distance must be odd for surface codes")

    def to_dict(self) -> Dict[str, Any]:
        d = asdict(self)
        d["backend"] = self.backend.value
        d["qec_code"] = self.qec_code.value
        return d

    @classmethod
    def from_dict(cls, d: Dict[str, Any]) -> "ExperimentConfig":
        d = dict(d)
        d["backend"] = QuantumBackend(d.get("backend", QuantumBackend.SIMULATOR_FULL_STATE.value))
        d["qec_code"] = ErrorCorrectionCode(d.get("qec_code", ErrorCorrectionCode.NONE.value))
        return cls(**d)


@dataclass(frozen=True)
class ExperimentResult:
    """Result of a quantum experiment."""
    experiment_id:  str
    mean:           float
    deviation:      float
    above_threshold: bool
    shot_count:     int
    qubit_count:    int
    ancilla_count:  int
    theta_z:        float
    theta_y:        float
    threshold:      float
    backend:        str
    timestamp_utc:  str
    min_sample:     float   = 0.0
    max_sample:     float   = 1.0
    skewness:       float   = 0.0
    kurtosis:       float   = 0.0
    ci_95_lo:       float   = 0.0
    ci_95_hi:       float   = 1.0
    runtime_ms:     float   = 0.0
    error_rate:     float   = 0.0
    qec_cycles:     int     = 0

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)

    def to_json(self) -> str:
        return json.dumps(self.to_dict(), indent=2)

    @property
    def is_valid(self) -> bool:
        return 0.0 <= self.mean <= 1.0 and self.deviation >= 0.0

    @property
    def snr(self) -> float:
        """Signal-to-noise ratio."""
        return self.mean / (self.deviation + 1e-12)

    @property
    def coefficient_of_variation(self) -> float:
        return self.deviation / (self.mean + 1e-12)


@dataclass(frozen=True)
class SamplingStats:
    """Detailed sampling statistics."""
    mean:       float
    variance:   float
    std_dev:    float
    minimum:    float
    maximum:    float
    median:     float
    skewness:   float
    kurtosis:   float
    ci_95_lo:   float
    ci_95_hi:   float
    sample_count: int

    @property
    def range(self) -> float:
        return self.maximum - self.minimum

    @property
    def iqr(self) -> float:
        """Approximate IQR from normal distribution."""
        return 1.349 * self.std_dev

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


# ═══════════════════════════════════════════════════════════════════════════════
# LLM model architecture contracts
# ═══════════════════════════════════════════════════════════════════════════════

@dataclass(frozen=True)
class LLMArchitectureConfig:
    """5B-parameter LLM architecture configuration."""
    model_name:             str     = "windows-agi-mesh-5b"
    vocab_size:             int     = 131072
    hidden_dim:             int     = 4096
    num_layers:             int     = 36
    num_attention_heads:    int     = 32
    num_kv_heads:           int     = 8          # GQA: 8 KV heads
    head_dim:               int     = 128
    ffn_dim:                int     = 14336       # SwiGLU: 14336
    max_seq_len:            int     = 131072
    rope_theta:             float   = 500000.0    # RoPE base
    rope_scaling_factor:    float   = 8.0
    attention_type:         AttentionType = AttentionType.GROUPED_QUERY
    activation:             ActivationFunction = ActivationFunction.SWIGLU
    norm_eps:               float   = 1e-5
    tie_embeddings:         bool    = False
    use_bias:               bool    = False
    sliding_window_size:    int     = 4096
    num_experts:            int     = 8           # MoE
    num_active_experts:     int     = 2           # Top-2 routing
    expert_capacity_factor: float   = 1.25
    quantum_layers:         List[int] = field(default_factory=lambda: [0, 6, 12, 18, 24, 30])
    quantum_head_dim:       int     = 8
    hybrid_quantization:    QuantizationScheme = QuantizationScheme.HYBRID_Q4_BF16

    @property
    def total_parameters(self) -> int:
        """Approximate parameter count."""
        embed = self.vocab_size * self.hidden_dim
        attn  = self.num_layers * (
            self.hidden_dim * self.num_attention_heads * self.head_dim +  # Q
            self.hidden_dim * self.num_kv_heads * self.head_dim * 2 +     # K, V
            self.num_attention_heads * self.head_dim * self.hidden_dim    # O
        )
        ffn   = self.num_layers * (
            self.hidden_dim * self.ffn_dim * 3  # gate, up, down (SwiGLU)
        )
        norm  = self.num_layers * self.hidden_dim * 2 + self.hidden_dim
        lm_head = 0 if self.tie_embeddings else self.vocab_size * self.hidden_dim
        return embed + attn + ffn + norm + lm_head

    @property
    def model_size_gb(self) -> float:
        """Model size in GB at BF16."""
        return self.total_parameters * 2 / 1e9

    def validate(self) -> None:
        if self.hidden_dim % self.num_attention_heads != 0:
            raise ValueError(
                f"hidden_dim {self.hidden_dim} must be divisible by "
                f"num_attention_heads {self.num_attention_heads}"
            )
        if self.num_attention_heads % self.num_kv_heads != 0:
            raise ValueError(
                f"num_attention_heads {self.num_attention_heads} must be divisible by "
                f"num_kv_heads {self.num_kv_heads}"
            )
        if self.num_active_experts > self.num_experts:
            raise ValueError(
                f"num_active_experts {self.num_active_experts} > num_experts {self.num_experts}"
            )

    def to_dict(self) -> Dict[str, Any]:
        d = asdict(self)
        d["attention_type"] = self.attention_type.value
        d["activation"] = self.activation.value
        d["hybrid_quantization"] = self.hybrid_quantization.value
        return d


@dataclass(frozen=True)
class LayerConfig:
    """Configuration for a single transformer layer."""
    layer_id:           int
    hidden_dim:         int
    num_heads:          int
    num_kv_heads:       int
    head_dim:           int
    ffn_dim:            int
    attention_type:     AttentionType
    activation:         ActivationFunction
    norm_eps:           float
    use_bias:           bool
    is_quantum_layer:   bool    = False
    quantum_head_dim:   int     = 8
    is_moe_layer:       bool    = False
    num_experts:        int     = 1
    num_active_experts: int     = 1
    quantization:       QuantizationScheme = QuantizationScheme.BF16

    @property
    def attention_params(self) -> int:
        q = self.hidden_dim * self.num_heads * self.head_dim
        kv = self.hidden_dim * self.num_kv_heads * self.head_dim * 2
        o = self.num_heads * self.head_dim * self.hidden_dim
        return q + kv + o

    @property
    def ffn_params(self) -> int:
        if self.is_moe_layer:
            return self.num_experts * self.hidden_dim * self.ffn_dim * 3
        return self.hidden_dim * self.ffn_dim * 3

    @property
    def total_params(self) -> int:
        return self.attention_params + self.ffn_params + self.hidden_dim * 2


# ═══════════════════════════════════════════════════════════════════════════════
# Inference contracts
# ═══════════════════════════════════════════════════════════════════════════════

@dataclass(frozen=True)
class InferenceRequest:
    """LLM inference request."""
    request_id:         str     = field(default_factory=lambda: str(uuid.uuid4()))
    model_version:      str     = "windows-agi-mesh-5b-v1.0"
    input_token_ids:    List[int] = field(default_factory=list)
    max_new_tokens:     int     = 512
    temperature:        float   = 0.7
    top_p:              float   = 0.9
    top_k:              int     = 50
    repetition_penalty: float   = 1.1
    beam_width:         int     = 1
    use_quantum_sampling: bool  = False
    target_backend:     HardwareAccelerator = HardwareAccelerator.MAIA_300
    priority:           int     = 1
    timeout_ms:         int     = 30000
    stream:             bool    = True
    stop_sequences:     List[str] = field(default_factory=list)
    system_prompt:      str     = ""
    user_prompt:        str     = ""

    def validate(self) -> None:
        if not self.input_token_ids:
            raise ValueError("input_token_ids must not be empty")
        if len(self.input_token_ids) > 131072:
            raise ValueError(f"Input exceeds context window of 131072 tokens")
        if self.max_new_tokens <= 0:
            raise ValueError(f"max_new_tokens must be > 0, got {self.max_new_tokens}")
        if self.temperature < 0.0:
            raise ValueError(f"temperature must be >= 0, got {self.temperature}")
        if not 0.0 < self.top_p <= 1.0:
            raise ValueError(f"top_p must be in (0,1], got {self.top_p}")
        if self.beam_width < 1:
            raise ValueError(f"beam_width must be >= 1, got {self.beam_width}")

    @property
    def input_length(self) -> int:
        return len(self.input_token_ids)

    def to_dict(self) -> Dict[str, Any]:
        d = asdict(self)
        d["target_backend"] = self.target_backend.value
        return d


@dataclass(frozen=True)
class InferenceResult:
    """LLM inference result."""
    request_id:         str
    output_token_ids:   List[int]
    output_text:        str
    input_tokens:       int
    output_tokens:      int
    total_tokens:       int
    time_to_first_token_ms: float
    tokens_per_second:  float
    total_latency_ms:   float
    backend_used:       str
    model_version:      str
    finish_reason:      str     = "stop"
    logprobs:           Optional[List[float]] = None
    quantum_tokens:     int     = 0
    photonic_hops:      int     = 0
    maia_shards:        int     = 0
    fpga_layers:        int     = 0

    @property
    def throughput_tokens_per_sec(self) -> float:
        return self.output_tokens / (self.total_latency_ms / 1000.0 + 1e-9)

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)

    def to_json(self) -> str:
        return json.dumps(self.to_dict(), indent=2)


# ═══════════════════════════════════════════════════════════════════════════════
# MAIA 300 contracts
# ═══════════════════════════════════════════════════════════════════════════════

@dataclass(frozen=True)
class MAIA300Config:
    """
    Azure MAIA 300 accelerator configuration.
    Specs: 288 GB HBM4 at 18 TB/s, N2P chiplet, 96 accelerators per 167 kW rack.
    """
    chiplet_id:             int     = 0
    rack_id:                int     = 0
    total_chiplets_per_rack: int    = 96
    hbm4_capacity_gb:       float   = 288.0
    hbm4_bandwidth_tbs:     float   = 18.0      # TB/s
    compute_tflops_bf16:    float   = 3200.0     # estimated BF16 TFLOPS
    compute_tflops_fp8:     float   = 6400.0     # estimated FP8 TFLOPS
    rack_power_kw:          float   = 167.0
    interconnect_bandwidth_tbps: float = 3.2
    nvlink_bandwidth_gbs:   float   = 900.0
    max_batch_size:         int     = 512
    max_seq_len:            int     = 131072
    tensor_parallel_degree: int     = 8
    pipeline_parallel_degree: int   = 4
    data_parallel_degree:   int     = 12
    quantization:           QuantizationScheme = QuantizationScheme.FP8_E4M3
    enable_flash_attention: bool    = True
    enable_speculative_decoding: bool = True
    speculative_draft_tokens: int   = 5

    @property
    def total_rack_memory_gb(self) -> float:
        return self.hbm4_capacity_gb * self.total_chiplets_per_rack

    @property
    def total_rack_bandwidth_tbs(self) -> float:
        return self.hbm4_bandwidth_tbs * self.total_chiplets_per_rack

    @property
    def memory_bandwidth_utilization(self) -> float:
        """Estimated utilization for LLM inference."""
        return 0.85

    def validate(self) -> None:
        if not 0 <= self.chiplet_id < self.total_chiplets_per_rack:
            raise ValueError(
                f"chiplet_id {self.chiplet_id} out of range "
                f"[0, {self.total_chiplets_per_rack})"
            )
        if self.tensor_parallel_degree * self.pipeline_parallel_degree > self.total_chiplets_per_rack:
            raise ValueError("TP * PP exceeds chiplet count per rack")


@dataclass(frozen=True)
class MAIA300Task:
    """A single inference task dispatched to MAIA 300."""
    task_id:            str     = field(default_factory=lambda: str(uuid.uuid4()))
    model_shard_id:     int     = 0
    total_shards:       int     = 1
    batch_size:         int     = 1
    sequence_length:    int     = 512
    hidden_dim:         int     = 4096
    num_heads:          int     = 32
    layer_range:        Tuple[int, int] = (0, 36)
    hbm4_bandwidth_gbs: float   = 18000.0
    compute_tflops:     float   = 3200.0
    estimated_latency_ms: float = 0.0
    power_watts:        float   = 0.0
    chiplet_id:         int     = 0
    rack_id:            int     = 0
    priority:           int     = 1

    def estimate_latency_ms(self, params_per_layer: int = 200_000_000) -> float:
        """Rough latency estimate based on memory bandwidth."""
        bytes_per_param = 1.0  # FP8
        total_bytes = params_per_layer * (self.layer_range[1] - self.layer_range[0]) * bytes_per_param
        bandwidth_bytes_per_ms = self.hbm4_bandwidth_gbs * 1e9 / 1000.0
        return total_bytes / bandwidth_bytes_per_ms

    def to_dict(self) -> Dict[str, Any]:
        d = asdict(self)
        d["layer_range"] = list(self.layer_range)
        return d


@dataclass(frozen=True)
class MAIA300Result:
    """Result from a MAIA 300 inference task."""
    task_id:            str
    shard_id:           int
    output_hidden:      List[float]     # flattened hidden states
    latency_ms:         float
    memory_used_gb:     float
    compute_tflops_used: float
    power_watts:        float
    tokens_processed:   int
    is_successful:      bool
    error_message:      str = ""

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


# ═══════════════════════════════════════════════════════════════════════════════
# Brainwave FPGA contracts
# ═══════════════════════════════════════════════════════════════════════════════

@dataclass(frozen=True)
class BrainwaveFPGAConfig:
    """
    Project Brainwave FPGA configuration.
    Intel Stratix 10 280: 96,000 MAC units, 7M ops/instruction, 10-35 TFLOPS.
    """
    fpga_model:             str     = "intel-stratix-10-280"
    mac_units:              int     = 96_000
    simd_width:             int     = 512
    native_precision:       str     = "bf16"
    on_chip_memory_mb:      int     = 256
    fabric_bandwidth_gbs:   float   = 512.0
    peak_tflops_bf16:       float   = 35.0
    peak_tflops_int8:       float   = 70.0
    max_batch_size:         int     = 1         # Real-time AI: batch=1
    latency_target_ms:      float   = 1.0       # Sub-millisecond target
    model_name:             str     = "windows-agi-mesh-5b"
    enable_real_time_ai:    bool    = True
    enable_synthesis_specialization: bool = True
    fpga_count_per_node:    int     = 8
    interconnect_type:      str     = "catapult-fabric"
    catapult_bandwidth_gbs: float   = 200.0

    @property
    def ops_per_instruction(self) -> int:
        return 7_000_000

    @property
    def effective_tflops(self) -> float:
        """Effective TFLOPS accounting for utilization."""
        return self.peak_tflops_bf16 * 0.85

    def validate(self) -> None:
        if self.mac_units <= 0:
            raise ValueError(f"mac_units must be > 0, got {self.mac_units}")
        if self.latency_target_ms <= 0:
            raise ValueError(f"latency_target_ms must be > 0")


@dataclass(frozen=True)
class BrainwaveFPGATask:
    """Task dispatched to Brainwave FPGA."""
    task_id:            str     = field(default_factory=lambda: str(uuid.uuid4()))
    model_name:         str     = "windows-agi-mesh-5b"
    batch_size:         int     = 1
    sequence_length:    int     = 512
    layer_type:         str     = "attention"
    hidden_dim:         int     = 4096
    num_heads:          int     = 32
    estimated_latency_ms: float = 0.0
    throughput_tflops:  float   = 0.0
    is_real_time:       bool    = True
    fpga_id:            int     = 0

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


@dataclass(frozen=True)
class BrainwaveFPGAResult:
    """Result from Brainwave FPGA inference."""
    task_id:            str
    output_tensor:      List[float]
    latency_ms:         float
    throughput_tflops:  float
    mac_utilization:    float
    memory_used_mb:     float
    is_successful:      bool
    error_message:      str = ""

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


# ═══════════════════════════════════════════════════════════════════════════════
# Hollow-Core Fiber photonic contracts
# ═══════════════════════════════════════════════════════════════════════════════

@dataclass(frozen=True)
class HollowCoreFiberConfig:
    """
    Microsoft Hollow-Core Fiber (HCF) configuration.
    47% lower latency vs standard SMF. In-transit AI compute enabled.
    Manufactured by Heraeus Covantics for Azure datacenters.
    """
    fiber_id:               str     = field(default_factory=lambda: f"hcf-{uuid.uuid4().hex[:8]}")
    length_km:              float   = 100.0
    bandwidth_tbps:         float   = 100.0
    latency_reduction_pct:  float   = 47.0      # vs standard SMF
    refractive_index:       float   = 1.0003    # near vacuum (air core)
    core_diameter_um:       float   = 30.0
    wavelength_nm:          float   = 1550.0
    photon_loss_db_per_km:  float   = 0.1       # ultra-low loss
    is_hollow_core:         bool    = True
    in_transit_compute:     bool    = True       # AI compute during transport
    photonic_acceleration:  bool    = True
    datacenter_a:           str     = "azure-eastus2"
    datacenter_b:           str     = "azure-westus3"
    fiber_manufacturer:     str     = "heraeus-covantics"

    @property
    def latency_us(self) -> float:
        """One-way latency in microseconds."""
        c_vacuum = 299_792.458  # km/s
        c_fiber  = c_vacuum / self.refractive_index
        base_us  = (self.length_km / c_fiber) * 1e6
        return base_us * (1.0 - self.latency_reduction_pct / 100.0)

    @property
    def smf_latency_us(self) -> float:
        """Standard SMF latency for comparison."""
        c_vacuum = 299_792.458
        c_smf    = c_vacuum / 1.4682  # SMF refractive index
        return (self.length_km / c_smf) * 1e6

    @property
    def total_loss_db(self) -> float:
        return self.photon_loss_db_per_km * self.length_km

    def validate(self) -> None:
        if self.length_km <= 0:
            raise ValueError(f"length_km must be > 0, got {self.length_km}")
        if self.bandwidth_tbps <= 0:
            raise ValueError(f"bandwidth_tbps must be > 0")
        if not 0 <= self.latency_reduction_pct <= 100:
            raise ValueError(f"latency_reduction_pct must be in [0,100]")


@dataclass(frozen=True)
class PhotonicComputeTask:
    """In-transit photonic compute task (AI during data transport)."""
    task_id:            str     = field(default_factory=lambda: str(uuid.uuid4()))
    fiber_id:           str     = ""
    operation_type:     str     = "matrix-multiply"
    input_data_kb:      float   = 0.0
    output_data_kb:     float   = 0.0
    photonic_ops:       int     = 0
    energy_pj:          float   = 0.0
    is_lossless:        bool    = True

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


@dataclass(frozen=True)
class PhotonicComputeResult:
    """Result of in-transit photonic compute."""
    task_id:            str
    fiber_id:           str
    compute_latency_us: float
    transport_latency_us: float
    total_latency_us:   float
    photonic_ops_done:  int
    energy_pj:          float
    is_successful:      bool
    error_message:      str = ""

    @property
    def speedup_vs_electronic(self) -> float:
        """Approximate speedup vs electronic compute."""
        return 10.0  # photonic ops ~10x faster for matrix ops

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


# ═══════════════════════════════════════════════════════════════════════════════
# Majorana QEC contracts
# ═══════════════════════════════════════════════════════════════════════════════

@dataclass(frozen=True)
class MajoranaQPUConfig:
    """
    Microsoft Majorana 1 QPU configuration.
    World's first topological QPU (Feb 2025).
    Topoconductor material. Target: 1M qubits on single chip.
    """
    qpu_id:                 str     = "majorana-1-alpha"
    physical_qubits:        int     = 8           # current gen
    logical_qubits:         int     = 1
    target_physical_qubits: int     = 1_000_000   # roadmap
    qubit_type:             str     = "topological-majorana"
    topoconductor_material: str     = "indium-arsenide-aluminum"
    t1_time_us:             float   = 1000.0      # topological protection
    t2_time_us:             float   = 500.0
    gate_fidelity_1q:       float   = 0.9999
    gate_fidelity_2q:       float   = 0.999
    readout_fidelity:       float   = 0.9995
    gate_time_ns:           float   = 100.0       # fast digital control
    error_correction:       ErrorCorrectionCode = ErrorCorrectionCode.TOPOLOGICAL
    code_distance:          int     = 3
    mzm_pairs:              int     = 4           # Majorana zero mode pairs
    braid_operations_per_sec: float = 1e6
    protection_gap_mev:     float   = 0.5         # topological gap
    operating_temp_mk:      float   = 50.0        # millikelvin
    darpa_us2qc_phase:      str     = "fault-tolerant-prototype"

    @property
    def overhead_ratio(self) -> float:
        """Physical-to-logical qubit overhead."""
        return self.physical_qubits / max(1, self.logical_qubits)

    @property
    def logical_error_rate(self) -> float:
        """Estimated logical error rate with topological protection."""
        phys_rate = 1.0 - self.gate_fidelity_2q
        return phys_rate ** (self.code_distance // 2 + 1)

    def validate(self) -> None:
        if self.physical_qubits <= 0:
            raise ValueError(f"physical_qubits must be > 0")
        if self.logical_qubits <= 0:
            raise ValueError(f"logical_qubits must be > 0")
        if self.physical_qubits < self.logical_qubits:
            raise ValueError("physical_qubits must be >= logical_qubits")


@dataclass(frozen=True)
class QECSyndrome:
    """Quantum error correction syndrome measurement."""
    syndrome_id:        str     = field(default_factory=lambda: str(uuid.uuid4()))
    x_syndrome:         List[int] = field(default_factory=list)
    z_syndrome:         List[int] = field(default_factory=list)
    error_type:         str     = "none"
    error_locations:    List[int] = field(default_factory=list)
    correction_op:      str     = "I"
    logical_error_rate: float   = 0.0
    physical_error_rate: float  = 0.0
    code_distance:      int     = 3
    cycle_count:        int     = 0
    is_correctable:     bool    = True

    @property
    def syndrome_weight(self) -> int:
        return sum(self.x_syndrome) + sum(self.z_syndrome)

    @property
    def is_trivial(self) -> bool:
        return all(s == 0 for s in self.x_syndrome + self.z_syndrome)

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


@dataclass(frozen=True)
class TopologicalQubitState:
    """State of a Majorana topological qubit."""
    physical_index:     int
    logical_index:      int
    parity_value:       int         # 0 or 1
    fusion_outcome:     bool
    error_syndrome:     List[int]
    correction_applied: bool
    fidelity:           float
    coherence_time_us:  float
    topoconductor_id:   str

    @property
    def is_error_free(self) -> bool:
        return all(s == 0 for s in self.error_syndrome)

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


# ═══════════════════════════════════════════════════════════════════════════════
# Cluster topology contracts
# ═══════════════════════════════════════════════════════════════════════════════

@dataclass(frozen=True)
class ClusterNodeConfig:
    """Configuration for a distributed training/inference cluster node."""
    node_id:            str     = field(default_factory=lambda: str(uuid.uuid4()))
    rank:               int     = 0
    world_size:         int     = 1
    local_rank:         int     = 0
    hostname:           str     = "localhost"
    ip_address:         str     = "127.0.0.1"
    gpu_count:          int     = 8
    cpu_cores:          int     = 96
    memory_gb:          int     = 512
    nvlink_bandwidth_gbs: float = 900.0
    infiniband_gbps:    float   = 400.0
    role:               NodeRole = NodeRole.WORKER
    accelerator:        HardwareAccelerator = HardwareAccelerator.GPU_H100
    maia_300_count:     int     = 0
    fpga_count:         int     = 0
    quantum_enabled:    bool    = False
    photonic_enabled:   bool    = False
    health_score:       float   = 1.0
    region:             str     = "eastus2"
    datacenter:         str     = "azure-dc-1"

    def validate(self) -> None:
        if not 0 <= self.rank < self.world_size:
            raise ValueError(f"rank {self.rank} out of range [0, {self.world_size})")
        if self.gpu_count < 0:
            raise ValueError(f"gpu_count must be >= 0")
        if not 0.0 <= self.health_score <= 1.0:
            raise ValueError(f"health_score must be in [0,1]")

    def to_dict(self) -> Dict[str, Any]:
        d = asdict(self)
        d["role"] = self.role.value
        d["accelerator"] = self.accelerator.value
        return d


@dataclass(frozen=True)
class ClusterTopology:
    """Full cluster topology for distributed LLM training."""
    topology_id:        str     = field(default_factory=lambda: str(uuid.uuid4()))
    nodes:              List[ClusterNodeConfig] = field(default_factory=list)
    tensor_parallel:    int     = 8
    pipeline_parallel:  int     = 4
    data_parallel:      int     = 16
    gradient_checkpointing: bool = True
    zero_stage:         int     = 3
    mixed_precision:    bool    = True
    communication_backend: str  = "nccl"
    photonic_links:     List[str] = field(default_factory=list)

    @property
    def total_gpus(self) -> int:
        return sum(n.gpu_count for n in self.nodes)

    @property
    def total_maia_chips(self) -> int:
        return sum(n.maia_300_count for n in self.nodes)

    @property
    def world_size(self) -> int:
        return len(self.nodes)

    @property
    def total_memory_gb(self) -> int:
        return sum(n.memory_gb for n in self.nodes)

    def get_coordinator(self) -> Optional[ClusterNodeConfig]:
        for node in self.nodes:
            if node.role == NodeRole.COORDINATOR:
                return node
        return None

    def get_quantum_nodes(self) -> List[ClusterNodeConfig]:
        return [n for n in self.nodes if n.quantum_enabled]

    def to_dict(self) -> Dict[str, Any]:
        return {
            "topology_id": self.topology_id,
            "nodes": [n.to_dict() for n in self.nodes],
            "tensor_parallel": self.tensor_parallel,
            "pipeline_parallel": self.pipeline_parallel,
            "data_parallel": self.data_parallel,
            "total_gpus": self.total_gpus,
            "total_maia_chips": self.total_maia_chips,
            "world_size": self.world_size,
        }


# ═══════════════════════════════════════════════════════════════════════════════
# Training contracts
# ═══════════════════════════════════════════════════════════════════════════════

@dataclass(frozen=True)
class TrainingConfig:
    """Training configuration for the 5B-parameter LLM."""
    workload_id:            str     = field(default_factory=lambda: str(uuid.uuid4()))
    model_name:             str     = "windows-agi-mesh-5b"
    phase:                  TrainingPhase = TrainingPhase.PRETRAINING
    batch_size:             int     = 2048
    micro_batch_size:       int     = 4
    gradient_accum_steps:   int     = 512
    learning_rate:          float   = 3e-4
    min_learning_rate:      float   = 3e-5
    warmup_steps:           int     = 2000
    total_steps:            int     = 500_000
    checkpoint_every:       int     = 1000
    eval_every:             int     = 500
    mixed_precision:        bool    = True
    gradient_checkpointing: bool    = True
    gradient_clipping:      float   = 1.0
    weight_decay:           float   = 0.1
    adam_beta1:             float   = 0.9
    adam_beta2:             float   = 0.95
    adam_epsilon:           float   = 1e-8
    lr_schedule:            str     = "cosine"
    tensor_parallel:        int     = 8
    pipeline_parallel:      int     = 4
    data_parallel:          int     = 16
    zero_stage:             int     = 3
    quantum_assisted_layers: List[int] = field(default_factory=lambda: [0, 6, 12, 18, 24, 30])
    maia_300_shards:        int     = 96
    fpga_layers:            List[int] = field(default_factory=list)
    photonic_links:         List[str] = field(default_factory=list)
    dataset_tokens:         int     = 15_000_000_000_000  # 15T tokens
    context_length:         int     = 131072
    packing:                bool    = True

    @property
    def global_batch_size(self) -> int:
        return self.micro_batch_size * self.gradient_accum_steps * self.data_parallel

    @property
    def tokens_per_step(self) -> int:
        return self.global_batch_size * self.context_length

    @property
    def total_tokens(self) -> int:
        return self.tokens_per_step * self.total_steps

    def validate(self) -> None:
        if self.learning_rate <= 0:
            raise ValueError(f"learning_rate must be > 0")
        if self.total_steps <= 0:
            raise ValueError(f"total_steps must be > 0")
        if self.batch_size <= 0:
            raise ValueError(f"batch_size must be > 0")
        if self.gradient_clipping <= 0:
            raise ValueError(f"gradient_clipping must be > 0")

    def to_dict(self) -> Dict[str, Any]:
        d = asdict(self)
        d["phase"] = self.phase.value
        return d


@dataclass(frozen=True)
class TrainingStep:
    """Result of a single training step."""
    step:               int
    loss:               float
    learning_rate:      float
    gradient_norm:      float
    tokens_per_second:  float
    mfu:                float       # Model FLOP utilization
    elapsed_ms:         float
    quantum_loss:       float   = 0.0
    photonic_latency_ms: float  = 0.0
    maia_utilization:   float   = 0.0
    fpga_utilization:   float   = 0.0

    @property
    def is_healthy(self) -> bool:
        return (
            math.isfinite(self.loss) and
            self.loss > 0 and
            math.isfinite(self.gradient_norm) and
            self.gradient_norm < 100.0
        )

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


# ═══════════════════════════════════════════════════════════════════════════════
# RLHF contracts
# ═══════════════════════════════════════════════════════════════════════════════

@dataclass(frozen=True)
class RLHFConfig:
    """RLHF (PPO/DPO) training configuration."""
    algorithm:          str     = "ppo"
    kl_coeff:           float   = 0.1
    clip_range:         float   = 0.2
    value_clip_range:   float   = 0.2
    entropy_coeff:      float   = 0.01
    gamma:              float   = 1.0
    lam:                float   = 0.95
    ppo_epochs:         int     = 4
    mini_batch_size:    int     = 64
    max_grad_norm:      float   = 1.0
    reward_model_name:  str     = "windows-agi-reward-1b"
    reference_model:    str     = "windows-agi-mesh-5b-sft"
    target_kl:          float   = 0.01
    adaptive_kl:        bool    = True
    use_quantum_reward: bool    = False

    def validate(self) -> None:
        if self.kl_coeff < 0:
            raise ValueError(f"kl_coeff must be >= 0")
        if not 0 < self.clip_range < 1:
            raise ValueError(f"clip_range must be in (0,1)")
        if self.ppo_epochs <= 0:
            raise ValueError(f"ppo_epochs must be > 0")


@dataclass(frozen=True)
class RLHFRewardSignal:
    """Reward signal from RLHF training."""
    response_id:        str
    reward_score:       float
    kl_divergence:      float
    policy_loss:        float
    value_loss:         float
    entropy_bonus:      float
    clip_fraction:      float
    approx_kl:          float
    is_preferred:       bool
    human_rating:       int     = -1    # -1 if not human-rated

    @property
    def total_loss(self) -> float:
        return self.policy_loss + self.value_loss - self.entropy_bonus

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


# ═══════════════════════════════════════════════════════════════════════════════
# MoE routing contracts
# ═══════════════════════════════════════════════════════════════════════════════

@dataclass(frozen=True)
class MoERoutingConfig:
    """Mixture-of-Experts routing configuration."""
    num_experts:        int     = 8
    top_k:              int     = 2
    capacity_factor:    float   = 1.25
    load_balance_coeff: float   = 0.01
    router_type:        str     = "top-k-softmax"
    use_quantum_router: bool    = False
    expert_dropout:     float   = 0.0
    jitter_noise:       float   = 0.0

    def validate(self) -> None:
        if self.num_experts <= 0:
            raise ValueError(f"num_experts must be > 0")
        if not 0 < self.top_k <= self.num_experts:
            raise ValueError(f"top_k must be in (0, {self.num_experts}]")
        if self.capacity_factor < 1.0:
            raise ValueError(f"capacity_factor must be >= 1.0")


@dataclass(frozen=True)
class MoERoutingResult:
    """Result of MoE routing for a batch of tokens."""
    token_count:        int
    expert_assignments: List[List[int]]     # [token_idx] -> [expert_ids]
    expert_weights:     List[List[float]]   # [token_idx] -> [weights]
    load_balance_loss:  float
    auxiliary_loss:     float
    expert_utilization: List[float]         # per-expert utilization
    overflow_tokens:    int
    is_quantum_routed:  bool = False

    @property
    def avg_expert_utilization(self) -> float:
        if not self.expert_utilization:
            return 0.0
        return sum(self.expert_utilization) / len(self.expert_utilization)

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


# ═══════════════════════════════════════════════════════════════════════════════
# Alignment safety contracts
# ═══════════════════════════════════════════════════════════════════════════════

@dataclass(frozen=True)
class AlignmentSafetyConfig:
    """Alignment and safety configuration."""
    policy_version:     str     = "v2.0"
    harm_threshold:     float   = 0.5
    refusal_threshold:  float   = 0.8
    redaction_enabled:  bool    = True
    categories:         List[str] = field(default_factory=lambda: [
        "violence", "hate_speech", "sexual_content",
        "self_harm", "illegal_activity", "misinformation",
        "privacy_violation", "cybersecurity_threat"
    ])
    use_quantum_safety: bool    = False
    latency_budget_ms:  float   = 50.0


@dataclass(frozen=True)
class AlignmentSafetyResult:
    """Result of alignment safety check."""
    request_id:         str
    is_safe:            bool
    harm_category:      str
    harm_score:         float
    refusal_required:   bool
    redaction_applied:  bool
    policy_version:     str
    check_latency_ms:   float
    category_scores:    Dict[str, float] = field(default_factory=dict)

    @property
    def max_harm_score(self) -> float:
        if self.category_scores:
            return max(self.category_scores.values())
        return self.harm_score

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


# ═══════════════════════════════════════════════════════════════════════════════
# Weight shard contracts
# ═══════════════════════════════════════════════════════════════════════════════

@dataclass(frozen=True)
class WeightShardConfig:
    """Configuration for a model weight shard."""
    shard_id:           int
    layer_start:        int
    layer_end:          int
    parameter_count:    int
    size_bytes:         int
    precision:          QuantizationScheme
    is_quantized:       bool
    quantization_bits:  int
    storage_backend:    str     = "azure-blob"
    blob_url:           str     = ""
    checksum_sha256:    str     = ""
    is_loaded:          bool    = False

    @property
    def size_gb(self) -> float:
        return self.size_bytes / 1e9

    @property
    def layer_count(self) -> int:
        return self.layer_end - self.layer_start

    def compute_checksum(self, data: bytes) -> str:
        return hashlib.sha256(data).hexdigest()

    def to_dict(self) -> Dict[str, Any]:
        d = asdict(self)
        d["precision"] = self.precision.value
        return d


# ═══════════════════════════════════════════════════════════════════════════════
# Benchmark contracts
# ═══════════════════════════════════════════════════════════════════════════════

@dataclass(frozen=True)
class BenchmarkCase:
    """A single benchmark test case."""
    case_id:            str
    case_name:          str
    qubit_count:        int
    ancilla_count:      int
    theta_z:            float
    theta_y:            float
    shot_count:         int
    threshold:          float
    expected_mean_lo:   float
    expected_mean_hi:   float
    backend:            QuantumBackend = QuantumBackend.SIMULATOR_FULL_STATE
    timeout_seconds:    int     = 300
    tags:               List[str] = field(default_factory=list)

    def validate(self) -> None:
        if not self.case_id:
            raise ValueError("case_id must not be empty")
        if self.expected_mean_lo > self.expected_mean_hi:
            raise ValueError(
                f"expected_mean_lo {self.expected_mean_lo} > "
                f"expected_mean_hi {self.expected_mean_hi}"
            )
        if not 0.0 <= self.expected_mean_lo <= 1.0:
            raise ValueError(f"expected_mean_lo must be in [0,1]")
        if not 0.0 <= self.expected_mean_hi <= 1.0:
            raise ValueError(f"expected_mean_hi must be in [0,1]")

    def to_dict(self) -> Dict[str, Any]:
        d = asdict(self)
        d["backend"] = self.backend.value
        return d


@dataclass(frozen=True)
class BenchmarkResult:
    """Result of a benchmark run."""
    case_id:            str
    case_name:          str
    passed:             bool
    mean:               float
    deviation:          float
    expected_lo:        float
    expected_hi:        float
    runtime_ms:         float
    backend:            str
    error_message:      str     = ""
    shot_count:         int     = 0
    qubit_count:        int     = 0

    @property
    def within_bounds(self) -> bool:
        return self.expected_lo <= self.mean <= self.expected_hi

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


# ═══════════════════════════════════════════════════════════════════════════════
# Resource estimation contracts
# ═══════════════════════════════════════════════════════════════════════════════

@dataclass(frozen=True)
class ResourceEstimate:
    """Quantum resource estimate for an algorithm."""
    algorithm_name:     str
    logical_qubits:     int
    physical_qubits:    int
    t_gate_count:       int
    t_factory_count:    int
    t_factory_fraction: float
    runtime_seconds:    float
    code_distance:      int
    error_budget:       float
    physical_error_rate: float
    logical_error_rate: float
    backend:            QuantumBackend = QuantumBackend.MAJORANA_1

    @property
    def overhead_ratio(self) -> float:
        return self.physical_qubits / max(1, self.logical_qubits)

    @property
    def runtime_hours(self) -> float:
        return self.runtime_seconds / 3600.0

    @property
    def runtime_days(self) -> float:
        return self.runtime_hours / 24.0

    def to_dict(self) -> Dict[str, Any]:
        d = asdict(self)
        d["backend"] = self.backend.value
        return d


# ═══════════════════════════════════════════════════════════════════════════════
# Hybrid quantization contracts
# ═══════════════════════════════════════════════════════════════════════════════

@dataclass(frozen=True)
class HybridQuantizationConfig:
    """Hybrid classical-quantum quantization configuration."""
    classical_bits:     int     = 4
    quantum_bits:       int     = 8
    scheme:             QuantizationScheme = QuantizationScheme.HYBRID_Q4_BF16
    calibration_samples: int    = 512
    per_channel:        bool    = True
    symmetric:          bool    = True
    mixed_precision:    bool    = True
    fp8_enabled:        bool    = True
    int4_enabled:       bool    = True
    bf16_enabled:       bool    = True
    quantum_layers:     List[int] = field(default_factory=list)
    classical_layers:   List[int] = field(default_factory=list)
    scale_factors:      List[float] = field(default_factory=list)
    zero_points:        List[int]   = field(default_factory=list)

    def validate(self) -> None:
        if self.classical_bits not in (2, 4, 8, 16, 32):
            raise ValueError(f"classical_bits must be 2/4/8/16/32, got {self.classical_bits}")
        if self.quantum_bits not in (2, 4, 8, 16, 32):
            raise ValueError(f"quantum_bits must be 2/4/8/16/32, got {self.quantum_bits}")

    def to_dict(self) -> Dict[str, Any]:
        d = asdict(self)
        d["scheme"] = self.scheme.value
        return d


# ═══════════════════════════════════════════════════════════════════════════════
# Mesh node contracts
# ═══════════════════════════════════════════════════════════════════════════════

@dataclass(frozen=True)
class MeshNodeConfig:
    """AGI mesh node configuration."""
    node_id:            str     = field(default_factory=lambda: str(uuid.uuid4()))
    node_type:          str     = "compute"
    region_id:          str     = "eastus2"
    datacenter_id:      str     = "azure-dc-1"
    hardware_backend:   HardwareAccelerator = HardwareAccelerator.MAIA_300
    available_qubits:   int     = 0
    available_gpus:     int     = 8
    available_fpgas:    int     = 0
    maia_300_count:     int     = 96
    network_bandwidth_gbps: float = 400.0
    quantum_enabled:    bool    = False
    photonic_enabled:   bool    = True
    health_score:       float   = 1.0
    load_factor:        float   = 0.0

    @property
    def is_available(self) -> bool:
        return self.health_score > 0.5 and self.load_factor < 0.95

    def to_dict(self) -> Dict[str, Any]:
        d = asdict(self)
        d["hardware_backend"] = self.hardware_backend.value
        return d
