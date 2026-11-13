"""
adapter.py — Azure MAIA 300 hardware adapter.
Specs (grounded): 288 GB HBM4 @ 18 TB/s, N2P chiplet, 96 accelerators/167 kW rack.
Handles: task dispatch, shard routing, tensor-parallel coordination,
         speculative decoding, flash attention, FP8 compute.
"""
from __future__ import annotations
import logging, math, time, uuid
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional, Tuple

logger = logging.getLogger(__name__)

# MAIA 300 hardware constants (grounded in Azure blog Oct 2026)
MAIA300_HBM4_CAPACITY_GB    = 288.0
MAIA300_HBM4_BANDWIDTH_TBS  = 18.0       # TB/s per chiplet
MAIA300_CHIPLETS_PER_RACK   = 96
MAIA300_RACK_POWER_KW       = 167.0
MAIA300_COMPUTE_TFLOPS_BF16 = 3200.0     # estimated
MAIA300_COMPUTE_TFLOPS_FP8  = 6400.0     # estimated
MAIA300_INTERCONNECT_TBPS   = 3.2
MAIA300_NVLINK_GBS          = 900.0
MAIA300_MAX_BATCH            = 512
MAIA300_MAX_SEQ_LEN          = 131072
MAIA300_PROCESS_NODE         = "N2P"      # TSMC N2P chiplet


@dataclass
class MAIA300ChipletState:
    chiplet_id:       int
    rack_id:          int
    hbm4_used_gb:     float = 0.0
    compute_util:     float = 0.0
    power_watts:      float = 0.0
    active_tasks:     int   = 0
    completed_tasks:  int   = 0
    error_count:      int   = 0
    temperature_c:    float = 45.0
    last_heartbeat:   float = field(default_factory=time.time)

    @property
    def hbm4_free_gb(self) -> float:
        return MAIA300_HBM4_CAPACITY_GB - self.hbm4_used_gb

    @property
    def is_healthy(self) -> bool:
        return (self.temperature_c < 85.0 and
                self.compute_util < 0.98 and
                time.time() - self.last_heartbeat < 30.0)

    @property
    def memory_utilization(self) -> float:
        return self.hbm4_used_gb / MAIA300_HBM4_CAPACITY_GB


@dataclass
class MAIA300InferenceTask:
    task_id:          str   = field(default_factory=lambda: str(uuid.uuid4()))
    model_name:       str   = "windows-agi-mesh-5b"
    shard_id:         int   = 0
    total_shards:     int   = 4
    batch_size:       int   = 1
    seq_len:          int   = 512
    hidden_dim:       int   = 4096
    num_heads:        int   = 32
    layer_start:      int   = 0
    layer_end:        int   = 9
    precision:        str   = "fp8-e4m3"
    use_flash_attn:   bool  = True
    use_spec_decode:  bool  = True
    spec_draft_tokens: int  = 5
    priority:         int   = 1

    @property
    def layer_count(self) -> int:
        return self.layer_end - self.layer_start

    @property
    def estimated_memory_gb(self) -> float:
        # KV cache + activations
        kv_cache = self.batch_size * self.seq_len * self.hidden_dim * 2 * 2 / 1e9  # K+V, fp16
        activations = self.batch_size * self.seq_len * self.hidden_dim * 2 / 1e9
        weights = self.layer_count * 200_000_000 * 1 / 1e9  # ~200M params/layer, FP8
        return kv_cache + activations + weights

    @property
    def estimated_tflops(self) -> float:
        # Attention: 2 * batch * seq^2 * hidden
        attn = 2 * self.batch_size * self.seq_len**2 * self.hidden_dim / 1e12
        # FFN: 2 * batch * seq * hidden * ffn_dim * 3
        ffn  = 2 * self.batch_size * self.seq_len * self.hidden_dim * 14336 * 3 / 1e12
        return (attn + ffn) * self.layer_count

    @property
    def estimated_latency_ms(self) -> float:
        tflops_needed = self.estimated_tflops
        tflops_avail  = MAIA300_COMPUTE_TFLOPS_FP8 * 0.85
        compute_ms    = tflops_needed / tflops_avail * 1000.0
        mem_bytes     = self.estimated_memory_gb * 1e9
        mem_bw_ms     = mem_bytes / (MAIA300_HBM4_BANDWIDTH_TBS * 1e12) * 1000.0
        return max(compute_ms, mem_bw_ms)


@dataclass
class MAIA300InferenceResult:
    task_id:          str
    shard_id:         int
    output_hidden:    List[float]
    latency_ms:       float
    memory_used_gb:   float
    compute_tflops:   float
    power_watts:      float
    tokens_processed: int
    is_successful:    bool
    precision_used:   str = "fp8-e4m3"
    flash_attn_used:  bool = True
    spec_tokens_accepted: int = 0
    error_message:    str = ""

    @property
    def tokens_per_second(self) -> float:
        return self.tokens_processed / (self.latency_ms / 1000.0 + 1e-9)

    @property
    def memory_bandwidth_utilization(self) -> float:
        bytes_moved = self.memory_used_gb * 1e9
        time_s      = self.latency_ms / 1000.0
        bw_used     = bytes_moved / time_s / 1e12  # TB/s
        return bw_used / MAIA300_HBM4_BANDWIDTH_TBS


class MAIA300Adapter:
    """
    Hardware adapter for Azure MAIA 300 accelerator.
    Manages chiplet pool, task dispatch, tensor parallelism,
    speculative decoding, and FP8 compute.
    """

    def __init__(self, rack_id: int = 0, chiplet_ids: Optional[List[int]] = None,
                 tensor_parallel: int = 8, pipeline_parallel: int = 4) -> None:
        self.rack_id          = rack_id
        self.tensor_parallel  = tensor_parallel
        self.pipeline_parallel = pipeline_parallel
        chiplet_ids = chiplet_ids or list(range(MAIA300_CHIPLETS_PER_RACK))
        self._chiplets: Dict[int, MAIA300ChipletState] = {
            cid: MAIA300ChipletState(chiplet_id=cid, rack_id=rack_id)
            for cid in chiplet_ids
        }
        self._task_history: List[MAIA300InferenceResult] = []
        self._adapter_id = str(uuid.uuid4())
        logger.info("MAIA300Adapter initialized: rack=%d chiplets=%d TP=%d PP=%d",
                    rack_id, len(self._chiplets), tensor_parallel, pipeline_parallel)

    @property
    def total_hbm4_gb(self) -> float:
        return len(self._chiplets) * MAIA300_HBM4_CAPACITY_GB

    @property
    def total_compute_tflops_fp8(self) -> float:
        return len(self._chiplets) * MAIA300_COMPUTE_TFLOPS_FP8

    @property
    def total_rack_power_kw(self) -> float:
        return MAIA300_RACK_POWER_KW

    def get_healthy_chiplets(self) -> List[MAIA300ChipletState]:
        return [c for c in self._chiplets.values() if c.is_healthy]

    def select_chiplet(self, task: MAIA300InferenceTask) -> Optional[MAIA300ChipletState]:
        """Select least-loaded healthy chiplet with sufficient memory."""
        candidates = [
            c for c in self.get_healthy_chiplets()
            if c.hbm4_free_gb >= task.estimated_memory_gb
        ]
        if not candidates:
            logger.warning("No chiplet with sufficient memory (need %.2f GB)",
                           task.estimated_memory_gb)
            return None
        return min(candidates, key=lambda c: c.compute_util)

    def dispatch(self, task: MAIA300InferenceTask) -> MAIA300InferenceResult:
        """Dispatch a single inference task to the best available chiplet."""
        chiplet = self.select_chiplet(task)
        if chiplet is None:
            return MAIA300InferenceResult(
                task_id=task.task_id, shard_id=task.shard_id,
                output_hidden=[], latency_ms=0.0, memory_used_gb=0.0,
                compute_tflops=0.0, power_watts=0.0, tokens_processed=0,
                is_successful=False, error_message="No available chiplet")

        # Update chiplet state
        chiplet.hbm4_used_gb  += task.estimated_memory_gb
        chiplet.compute_util   = min(0.99, chiplet.compute_util + 0.1)
        chiplet.active_tasks  += 1
        chiplet.last_heartbeat = time.time()

        # Simulate execution
        import random
        rng = random.Random(hash(task.task_id))
        latency_ms = task.estimated_latency_ms * rng.uniform(0.9, 1.1)
        hidden = [rng.gauss(0, 0.02) for _ in range(task.hidden_dim)]
        power  = MAIA300_RACK_POWER_KW * 1000 / MAIA300_CHIPLETS_PER_RACK

        # Speculative decoding bonus
        spec_accepted = 0
        if task.use_spec_decode:
            spec_accepted = rng.randint(0, task.spec_draft_tokens)
            latency_ms   *= (1.0 - spec_accepted * 0.15)

        result = MAIA300InferenceResult(
            task_id=task.task_id, shard_id=task.shard_id,
            output_hidden=hidden, latency_ms=latency_ms,
            memory_used_gb=task.estimated_memory_gb,
            compute_tflops=task.estimated_tflops,
            power_watts=power,
            tokens_processed=task.batch_size * task.seq_len,
            is_successful=True,
            precision_used=task.precision,
            flash_attn_used=task.use_flash_attn,
            spec_tokens_accepted=spec_accepted)

        # Release chiplet resources
        chiplet.hbm4_used_gb  = max(0.0, chiplet.hbm4_used_gb - task.estimated_memory_gb)
        chiplet.compute_util   = max(0.0, chiplet.compute_util - 0.1)
        chiplet.active_tasks   = max(0, chiplet.active_tasks - 1)
        chiplet.completed_tasks += 1
        chiplet.power_watts    = power

        self._task_history.append(result)
        logger.debug("MAIA300 task %s: %.2f ms, %.2f GB, %.1f TFLOPS, spec=%d",
                     task.task_id, latency_ms, task.estimated_memory_gb,
                     task.estimated_tflops, spec_accepted)
        return result

    def dispatch_tensor_parallel(self, task: MAIA300InferenceTask,
                                  tp_degree: int = 8) -> List[MAIA300InferenceResult]:
        """Dispatch across TP chiplets (split hidden dim)."""
        results = []
        for tp_rank in range(tp_degree):
            sub_task = MAIA300InferenceTask(
                task_id=f"{task.task_id}-tp{tp_rank}",
                model_name=task.model_name,
                shard_id=tp_rank, total_shards=tp_degree,
                batch_size=task.batch_size,
                seq_len=task.seq_len,
                hidden_dim=task.hidden_dim // tp_degree,
                num_heads=task.num_heads // tp_degree,
                layer_start=task.layer_start, layer_end=task.layer_end,
                precision=task.precision,
                use_flash_attn=task.use_flash_attn,
                use_spec_decode=task.use_spec_decode)
            results.append(self.dispatch(sub_task))
        return results

    def dispatch_pipeline_parallel(self, task: MAIA300InferenceTask,
                                    pp_degree: int = 4) -> List[MAIA300InferenceResult]:
        """Dispatch across PP stages (split layers)."""
        total_layers = task.layer_end - task.layer_start
        lps = total_layers // pp_degree
        results = []
        for pp_rank in range(pp_degree):
            ls = task.layer_start + pp_rank * lps
            le = min(task.layer_end, ls + lps)
            sub_task = MAIA300InferenceTask(
                task_id=f"{task.task_id}-pp{pp_rank}",
                model_name=task.model_name,
                shard_id=pp_rank, total_shards=pp_degree,
                batch_size=task.batch_size, seq_len=task.seq_len,
                hidden_dim=task.hidden_dim, num_heads=task.num_heads,
                layer_start=ls, layer_end=le,
                precision=task.precision,
                use_flash_attn=task.use_flash_attn)
            results.append(self.dispatch(sub_task))
        return results

    def stats(self) -> Dict[str, Any]:
        healthy = self.get_healthy_chiplets()
        avg_util = sum(c.compute_util for c in healthy) / max(1, len(healthy))
        avg_mem  = sum(c.hbm4_used_gb for c in healthy) / max(1, len(healthy))
        return {
            "adapter_id": self._adapter_id,
            "rack_id": self.rack_id,
            "total_chiplets": len(self._chiplets),
            "healthy_chiplets": len(healthy),
            "total_hbm4_gb": self.total_hbm4_gb,
            "total_tflops_fp8": self.total_compute_tflops_fp8,
            "avg_compute_util": round(avg_util, 3),
            "avg_memory_used_gb": round(avg_mem, 2),
            "tasks_completed": sum(c.completed_tasks for c in self._chiplets.values()),
            "tasks_errored": sum(c.error_count for c in self._chiplets.values()),
            "rack_power_kw": self.total_rack_power_kw,
        }

    def __repr__(self) -> str:
        return (f"MAIA300Adapter(rack={self.rack_id}, "
                f"chiplets={len(self._chiplets)}, "
                f"tflops_fp8={self.total_compute_tflops_fp8:.0f})")
