"""
fake_service.py — Deterministic fake QuantumService for testing without QDK.
"""
from __future__ import annotations
import math, random, time, uuid
from typing import Any, Dict, List, Optional, Tuple
from .contracts import (
    BenchmarkCase, BenchmarkResult, BrainwaveFPGAResult,
    ExperimentConfig, ExperimentResult, InferenceRequest, InferenceResult,
    MAIA300Result, MajoranaQPUConfig, QECSyndrome,
    PhotonicComputeResult, ResourceEstimate, TrainingConfig, TrainingStep,
    QuantumBackend, HardwareAccelerator,
)

class FakeQuantumService:
    """Deterministic fake for unit testing — no QDK required."""

    def __init__(self, seed: int = 42) -> None:
        self._seed = seed
        self._call_count: Dict[str, int] = {}

    def _rng(self, key: str) -> random.Random:
        return random.Random(hash((self._seed, key)))

    def run_experiment(self, config: ExperimentConfig) -> ExperimentResult:
        rng = self._rng(f"exp-{config.theta_z}-{config.theta_y}")
        base = 0.5 + 0.3*math.sin(config.theta_z)*math.cos(config.theta_y)
        mean = max(0.0, min(1.0, base + rng.gauss(0, 0.02)))
        dev  = abs(rng.gauss(0.1, 0.02))
        return ExperimentResult(experiment_id=config.experiment_id,
            mean=mean, deviation=dev, above_threshold=mean>config.threshold,
            shot_count=config.shot_count, qubit_count=config.qubit_count,
            ancilla_count=config.ancilla_count, theta_z=config.theta_z,
            theta_y=config.theta_y, threshold=config.threshold,
            backend="fake-simulator", timestamp_utc="2026-11-07T00:00:00Z",
            min_sample=max(0.0,mean-2*dev), max_sample=min(1.0,mean+2*dev),
            runtime_ms=rng.uniform(10.0, 100.0))

    def run_batch_experiments(self, configs, parallel=True):
        return [self.run_experiment(c) for c in configs]

    def dispatch_to_maia300(self, request, layer_range=(0,36)):
        rng = self._rng(f"maia-{request.request_id}")
        return MAIA300Result(task_id=request.request_id, shard_id=0,
            output_hidden=[rng.gauss(0,0.02) for _ in range(4096)],
            latency_ms=rng.uniform(5.0,20.0), memory_used_gb=rng.uniform(10.0,50.0),
            compute_tflops_used=rng.uniform(2000.0,3200.0),
            power_watts=rng.uniform(1500.0,2000.0),
            tokens_processed=len(request.input_token_ids), is_successful=True)

    def dispatch_to_maia300_multi_shard(self, request, num_shards=4):
        return [self.dispatch_to_maia300(request) for _ in range(num_shards)]

    def route_to_brainwave(self, request, layer_type="attention"):
        rng = self._rng(f"fpga-{request.request_id}")
        return BrainwaveFPGAResult(task_id=request.request_id,
            output_tensor=[rng.gauss(0,0.01) for _ in range(4096)],
            latency_ms=rng.uniform(0.1,1.0), throughput_tflops=rng.uniform(25.0,35.0),
            mac_utilization=rng.uniform(0.80,0.95), memory_used_mb=rng.uniform(50.0,200.0),
            is_successful=True)

    def send_via_photonic_fiber(self, data_kb, operation="matrix-multiply"):
        rng = self._rng(f"hcf-{data_kb}")
        t_us = rng.uniform(100.0,500.0); c_us = rng.uniform(10.0,50.0)
        return PhotonicComputeResult(task_id=str(uuid.uuid4()), fiber_id="hcf-fake-001",
            compute_latency_us=c_us, transport_latency_us=t_us, total_latency_us=t_us+c_us,
            photonic_ops_done=int(data_kb*1000), energy_pj=data_kb*0.1, is_successful=True)

    def run_inference(self, request):
        rng = self._rng(f"inf-{request.request_id}")
        n = min(request.max_new_tokens, rng.randint(10,64))
        tokens = [rng.randint(100,50000) for _ in range(n)]
        return InferenceResult(request_id=request.request_id, output_token_ids=tokens,
            output_text=f"[Fake: {n} tokens]", input_tokens=len(request.input_token_ids),
            output_tokens=n, total_tokens=len(request.input_token_ids)+n,
            time_to_first_token_ms=rng.uniform(50.0,200.0),
            tokens_per_second=rng.uniform(50.0,200.0),
            total_latency_ms=rng.uniform(500.0,2000.0), backend_used="fake-maia-300",
            model_version=request.model_version, finish_reason="stop",
            quantum_tokens=n if request.use_quantum_sampling else 0,
            photonic_hops=2, maia_shards=4, fpga_layers=6)

    def run_benchmark(self, case):
        rng = self._rng(f"bench-{case.case_id}")
        mean = rng.uniform(case.expected_mean_lo, case.expected_mean_hi)
        return BenchmarkResult(case_id=case.case_id, case_name=case.case_name,
            passed=True, mean=mean, deviation=rng.uniform(0.01,0.1),
            expected_lo=case.expected_mean_lo, expected_hi=case.expected_mean_hi,
            runtime_ms=rng.uniform(100.0,5000.0), backend="fake-simulator",
            shot_count=case.shot_count, qubit_count=case.qubit_count)

    def run_all_benchmarks(self, cases, parallel=True):
        return [self.run_benchmark(c) for c in cases]

    def simulate_training_step(self, step: int, config: TrainingConfig) -> TrainingStep:
        rng = self._rng(f"train-{step}")
        base_loss = 4.0*math.exp(-step/10000.0)+0.5
        loss = max(0.1, base_loss+rng.gauss(0,0.05))
        lr   = config.learning_rate*min(1.0, step/max(1,config.warmup_steps))
        return TrainingStep(step=step, loss=loss, learning_rate=lr,
            gradient_norm=rng.uniform(0.5,2.0), tokens_per_second=rng.uniform(50000,200000),
            mfu=rng.uniform(0.35,0.55), elapsed_ms=rng.uniform(500,2000),
            quantum_loss=rng.uniform(0.0,0.01), photonic_latency_ms=rng.uniform(0.1,1.0),
            maia_utilization=rng.uniform(0.80,0.95), fpga_utilization=rng.uniform(0.75,0.90))

    def estimate_resources(self, algorithm, logical_qubits, error_budget=0.01,
                            backend=QuantumBackend.MAJORANA_1):
        rng = self._rng(f"res-{algorithm}-{logical_qubits}")
        overhead = 2 if backend == QuantumBackend.MAJORANA_1 else 10
        return ResourceEstimate(algorithm_name=algorithm, logical_qubits=logical_qubits,
            physical_qubits=logical_qubits*overhead, t_gate_count=logical_qubits*1000,
            t_factory_count=max(1,logical_qubits//10), t_factory_fraction=rng.uniform(0.1,0.4),
            runtime_seconds=rng.uniform(1.0,3600.0), code_distance=3,
            error_budget=error_budget, physical_error_rate=rng.uniform(1e-4,1e-3),
            logical_error_rate=rng.uniform(1e-10,1e-6), backend=backend)

    def shutdown(self): pass
    def __enter__(self): return self
    def __exit__(self, *a): self.shutdown()
