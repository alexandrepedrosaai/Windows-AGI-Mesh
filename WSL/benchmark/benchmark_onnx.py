# =============================================================================
# Windows AGI Benchmark Lab — ONNX Runtime Benchmark Module
# Copyright (c) 2026 Microsoft Corporation. All Rights Reserved.
# =============================================================================

"""
ONNX Runtime benchmark module.

Tests execution providers:
  - CPUExecutionProvider
  - CUDAExecutionProvider (NVIDIA)
  - ROCMExecutionProvider (AMD)
  - TensorrtExecutionProvider
  - OpenVINOExecutionProvider (Intel)
  - DmlExecutionProvider (DirectML / Windows)

Measures:
  - Inference latency (ms)
  - Throughput (inferences/sec)
  - Memory usage
  - Provider-specific optimizations
"""

from __future__ import annotations

import argparse
import datetime
import json
import logging
import os
import pathlib
import platform
import subprocess
import sys
import time
from dataclasses import asdict, dataclass
from typing import Any

import numpy as np
import psutil

log = logging.getLogger("agi.bench.onnx")
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)-8s | %(name)s | %(message)s",
)

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
PROVIDERS_TO_TEST = [
    "CPUExecutionProvider",
    "CUDAExecutionProvider",
    "ROCMExecutionProvider",
    "TensorrtExecutionProvider",
    "DmlExecutionProvider",
]

WARMUP_RUNS = 10
BENCHMARK_RUNS = 50

# Model shapes for synthetic benchmarks
SYNTHETIC_MODELS = {
    "linear_small":   {"input_shape": (1, 128),    "hidden": 256,  "output": 64},
    "linear_medium":  {"input_shape": (1, 512),    "hidden": 1024, "output": 256},
    "linear_large":   {"input_shape": (1, 2048),   "hidden": 4096, "output": 1024},
    "batch_small":    {"input_shape": (8, 128),    "hidden": 256,  "output": 64},
    "batch_medium":   {"input_shape": (16, 512),   "hidden": 1024, "output": 256},
    "batch_large":    {"input_shape": (32, 2048),  "hidden": 4096, "output": 1024},
    "embedding_sim":  {"input_shape": (1, 768),    "hidden": 3072, "output": 768},
    "bert_like":      {"input_shape": (1, 512),    "hidden": 2048, "output": 512},
}


# ---------------------------------------------------------------------------
# Data Model
# ---------------------------------------------------------------------------
@dataclass
class ONNXResult:
    """Single ONNX Runtime benchmark result."""

    timestamp: str
    suite: str
    benchmark: str
    model: str
    prompt_type: str
    prompt_tokens: int
    output_tokens: int
    ttft_ms: float
    total_latency_ms: float
    tokens_per_sec: float
    vram_used_gb: float
    ram_used_gb: float
    gpu_util_pct: float
    cpu_util_pct: float
    power_watts: float
    temp_celsius: float
    context_length: int
    batch_size: int
    quantization: str
    backend: str
    device: str
    gpu_vendor: str
    gpu_model: str
    host_os: str
    status: str
    error_message: str
    notes: str


# ---------------------------------------------------------------------------
# ONNX Model Builder (Synthetic)
# ---------------------------------------------------------------------------
def _build_synthetic_onnx_model(
    input_shape: tuple[int, ...],
    hidden_size: int,
    output_size: int,
    model_path: pathlib.Path,
) -> bool:
    """Build a synthetic ONNX model for benchmarking."""
    try:
        import onnx  # type: ignore[import]
        from onnx import TensorProto, helper  # type: ignore[import]

        batch_size, input_size = input_shape

        # Create nodes
        # Layer 1: Linear (MatMul + Add)
        matmul1 = helper.make_node("MatMul", ["input", "weight1"], ["matmul1_out"])
        add1 = helper.make_node("Add", ["matmul1_out", "bias1"], ["add1_out"])
        relu1 = helper.make_node("Relu", ["add1_out"], ["relu1_out"])

        # Layer 2: Linear
        matmul2 = helper.make_node("MatMul", ["relu1_out", "weight2"], ["matmul2_out"])
        add2 = helper.make_node("Add", ["matmul2_out", "bias2"], ["output"])

        # Create initializers (weights)
        rng = np.random.default_rng(42)
        weight1_data = rng.standard_normal((input_size, hidden_size)).astype(np.float32)
        bias1_data = rng.standard_normal(hidden_size).astype(np.float32)
        weight2_data = rng.standard_normal((hidden_size, output_size)).astype(np.float32)
        bias2_data = rng.standard_normal(output_size).astype(np.float32)

        weight1 = helper.make_tensor("weight1", TensorProto.FLOAT, [input_size, hidden_size], weight1_data.flatten())
        bias1 = helper.make_tensor("bias1", TensorProto.FLOAT, [hidden_size], bias1_data.flatten())
        weight2 = helper.make_tensor("weight2", TensorProto.FLOAT, [hidden_size, output_size], weight2_data.flatten())
        bias2 = helper.make_tensor("bias2", TensorProto.FLOAT, [output_size], bias2_data.flatten())

        # Create graph
        graph = helper.make_graph(
            [matmul1, add1, relu1, matmul2, add2],
            "synthetic_bench",
            [helper.make_tensor_value_info("input", TensorProto.FLOAT, [batch_size, input_size])],
            [helper.make_tensor_value_info("output", TensorProto.FLOAT, [batch_size, output_size])],
            [weight1, bias1, weight2, bias2],
        )

        model = helper.make_model(graph, opset_imports=[helper.make_opsetid("", 17)])
        model.ir_version = 8

        model_path.parent.mkdir(parents=True, exist_ok=True)
        onnx.save(model, str(model_path))
        return True

    except ImportError:
        log.warning("onnx package not installed — cannot build synthetic models")
        return False
    except Exception as exc:
        log.error("Failed to build ONNX model: %s", exc)
        return False


# ---------------------------------------------------------------------------
# Provider Detection
# ---------------------------------------------------------------------------
def _get_available_providers() -> list[str]:
    """Get list of available ONNX Runtime execution providers."""
    try:
        import onnxruntime as ort  # type: ignore[import]
        return ort.get_available_providers()
    except ImportError:
        return []


def _get_gpu_info() -> tuple[str, str]:
    """Return (gpu_vendor, gpu_model)."""
    try:
        r = subprocess.run(
            ["nvidia-smi", "--query-gpu=name", "--format=csv,noheader"],
            capture_output=True, text=True, timeout=3,
        )
        if r.returncode == 0:
            return "nvidia", r.stdout.strip().splitlines()[0]
    except (FileNotFoundError, subprocess.TimeoutExpired):
        pass
    try:
        r = subprocess.run(
            ["rocm-smi", "--showproductname", "--json"],
            capture_output=True, text=True, timeout=3,
        )
        if r.returncode == 0:
            data = json.loads(r.stdout)
            for v in data.values():
                if isinstance(v, dict):
                    return "amd", v.get("Card series", "AMD GPU")
    except (FileNotFoundError, subprocess.TimeoutExpired, json.JSONDecodeError):
        pass
    return "none", "CPU"


def _detect_host_os() -> str:
    if "microsoft" in platform.uname().release.lower():
        return "WSL2"
    return platform.system()


# ---------------------------------------------------------------------------
# Benchmark Functions
# ---------------------------------------------------------------------------
def benchmark_provider(
    model_path: pathlib.Path,
    provider: str,
    model_name: str,
    input_shape: tuple[int, ...],
    gpu_vendor: str,
    gpu_model: str,
    provider_options: dict[str, Any] | None = None,
) -> ONNXResult:
    """Benchmark a single ONNX model with a specific execution provider."""
    log.info("ONNX benchmark: model=%s provider=%s", model_name, provider)

    status = "success"
    error_msg = ""
    latency_ms = 0.0
    throughput = 0.0
    p50_ms = 0.0
    p95_ms = 0.0
    p99_ms = 0.0

    try:
        import onnxruntime as ort  # type: ignore[import]

        # Session options
        sess_opts = ort.SessionOptions()
        sess_opts.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL
        sess_opts.execution_mode = ort.ExecutionMode.ORT_SEQUENTIAL
        sess_opts.log_severity_level = 3  # ERROR only

        # Provider options
        providers: list[Any]
        if provider_options:
            providers = [(provider, provider_options)]
        else:
            providers = [provider]

        # Add CPU fallback
        if "CPUExecutionProvider" not in providers:
            providers.append("CPUExecutionProvider")

        # Create session
        session = ort.InferenceSession(
            str(model_path),
            sess_options=sess_opts,
            providers=providers,
        )

        # Prepare input
        input_name = session.get_inputs()[0].name
        batch_size = input_shape[0]
        input_size = input_shape[1]
        rng = np.random.default_rng(42)
        input_data = rng.standard_normal(input_shape).astype(np.float32)
        feed = {input_name: input_data}

        # Warmup
        for _ in range(WARMUP_RUNS):
            session.run(None, feed)

        # Benchmark
        times: list[float] = []
        for _ in range(BENCHMARK_RUNS):
            t0 = time.perf_counter()
            session.run(None, feed)
            t1 = time.perf_counter()
            times.append((t1 - t0) * 1000)

        times_sorted = sorted(times)
        latency_ms = round(sum(times) / len(times), 3)
        p50_ms = round(times_sorted[len(times_sorted) // 2], 3)
        p95_ms = round(times_sorted[int(len(times_sorted) * 0.95)], 3)
        p99_ms = round(times_sorted[int(len(times_sorted) * 0.99)], 3)
        throughput = round(1000.0 / latency_ms * batch_size, 1)

        # Actual provider used
        actual_provider = session.get_providers()[0]
        if actual_provider != provider:
            log.warning("Requested %s but got %s", provider, actual_provider)

    except Exception as exc:
        status = "error"
        error_msg = str(exc)[:300]
        log.error("ONNX benchmark failed: provider=%s model=%s error=%s", provider, model_name, exc)

    mem = psutil.virtual_memory()

    return ONNXResult(
        timestamp=datetime.datetime.utcnow().isoformat() + "Z",
        suite="onnx",
        benchmark=f"onnx_{model_name}_{provider.replace('ExecutionProvider', '').lower()}",
        model=model_name,
        prompt_type="",
        prompt_tokens=input_shape[1] if len(input_shape) > 1 else 0,
        output_tokens=0,
        ttft_ms=0.0,
        total_latency_ms=latency_ms,
        tokens_per_sec=throughput,
        vram_used_gb=0.0,
        ram_used_gb=round(mem.used / (1024**3), 2),
        gpu_util_pct=0.0,
        cpu_util_pct=psutil.cpu_percent(interval=0.1),
        power_watts=0.0,
        temp_celsius=0.0,
        context_length=input_shape[1] if len(input_shape) > 1 else 0,
        batch_size=input_shape[0],
        quantization="float32",
        backend=f"onnxruntime_{provider.replace('ExecutionProvider', '').lower()}",
        device=provider.replace("ExecutionProvider", "").lower(),
        gpu_vendor=gpu_vendor,
        gpu_model=gpu_model,
        host_os=_detect_host_os(),
        status=status,
        error_message=error_msg,
        notes=f"p50={p50_ms}ms p95={p95_ms}ms p99={p99_ms}ms throughput={throughput}/s",
    )


def benchmark_all_providers(
    model_dir: pathlib.Path,
    gpu_vendor: str,
    gpu_model: str,
) -> list[ONNXResult]:
    """Benchmark all synthetic models across all available providers."""
    available_providers = _get_available_providers()
    log.info("Available ONNX providers: %s", available_providers)

    results: list[ONNXResult] = []

    for model_name, config in SYNTHETIC_MODELS.items():
        input_shape = config["input_shape"]
        hidden = config["hidden"]
        output = config["output"]

        model_path = model_dir / f"{model_name}.onnx"

        # Build model if needed
        if not model_path.exists():
            log.info("Building synthetic model: %s", model_name)
            if not _build_synthetic_onnx_model(input_shape, hidden, output, model_path):
                log.warning("Skipping model %s — build failed", model_name)
                continue

        # Test each provider
        for provider in PROVIDERS_TO_TEST:
            if provider not in available_providers:
                log.debug("Provider %s not available — skipping", provider)
                continue

            result = benchmark_provider(
                model_path=model_path,
                provider=provider,
                model_name=model_name,
                input_shape=input_shape,
                gpu_vendor=gpu_vendor,
                gpu_model=gpu_model,
            )
            results.append(result)

    return results


def benchmark_quantization_comparison(
    model_dir: pathlib.Path,
    gpu_vendor: str,
    gpu_model: str,
) -> list[ONNXResult]:
    """Compare FP32 vs INT8 quantized models."""
    results: list[ONNXResult] = []

    try:
        from onnxruntime.quantization import QuantType, quantize_dynamic  # type: ignore[import]
    except ImportError:
        log.warning("onnxruntime.quantization not available — skipping quantization comparison")
        return results

    model_name = "linear_large"
    config = SYNTHETIC_MODELS[model_name]
    fp32_path = model_dir / f"{model_name}.onnx"
    int8_path = model_dir / f"{model_name}_int8.onnx"

    if not fp32_path.exists():
        if not _build_synthetic_onnx_model(
            config["input_shape"], config["hidden"], config["output"], fp32_path
        ):
            return results

    # Quantize to INT8
    if not int8_path.exists():
        try:
            log.info("Quantizing model to INT8: %s", model_name)
            quantize_dynamic(
                str(fp32_path),
                str(int8_path),
                weight_type=QuantType.QInt8,
            )
        except Exception as exc:
            log.error("Quantization failed: %s", exc)
            return results

    gpu_vendor_local, gpu_model_local = gpu_vendor, gpu_model

    # Benchmark FP32
    result_fp32 = benchmark_provider(
        model_path=fp32_path,
        provider="CPUExecutionProvider",
        model_name=f"{model_name}_fp32",
        input_shape=config["input_shape"],
        gpu_vendor=gpu_vendor_local,
        gpu_model=gpu_model_local,
    )
    result_fp32.quantization = "float32"
    results.append(result_fp32)

    # Benchmark INT8
    result_int8 = benchmark_provider(
        model_path=int8_path,
        provider="CPUExecutionProvider",
        model_name=f"{model_name}_int8",
        input_shape=config["input_shape"],
        gpu_vendor=gpu_vendor_local,
        gpu_model=gpu_model_local,
    )
    result_int8.quantization = "int8"
    results.append(result_int8)

    return results


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main() -> int:
    """Run ONNX Runtime benchmarks."""
    parser = argparse.ArgumentParser(description="ONNX Runtime Benchmark — Microsoft AGI Lab")
    parser.add_argument("--provider", choices=PROVIDERS_TO_TEST + ["all"], default="all")
    parser.add_argument("--model-dir", type=pathlib.Path, default=pathlib.Path("benchmark/models/onnx"))
    parser.add_argument("--output", default="benchmark/reports/onnx_results.json")
    parser.add_argument("--quantization", action="store_true", help="Run quantization comparison")
    parser.add_argument("--verbose", "-v", action="store_true")
    args = parser.parse_args()

    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)

    try:
        import onnxruntime as ort  # type: ignore[import]
        log.info("ONNX Runtime version: %s", ort.__version__)
    except ImportError:
        log.error("onnxruntime not installed. Install with: pip install onnxruntime")
        return 1

    gpu_vendor, gpu_model = _get_gpu_info()
    log.info("GPU: %s — %s", gpu_vendor, gpu_model)

    args.model_dir.mkdir(parents=True, exist_ok=True)

    all_results: list[ONNXResult] = []

    # Main provider benchmarks
    results = benchmark_all_providers(args.model_dir, gpu_vendor, gpu_model)
    all_results.extend(results)

    # Quantization comparison
    if args.quantization:
        quant_results = benchmark_quantization_comparison(args.model_dir, gpu_vendor, gpu_model)
        all_results.extend(quant_results)

    # Export
    out_path = pathlib.Path(args.output)
    out_path.parent.mkdir(parents=True, exist_ok=True)

    output_data = {
        "suite": "onnx",
        "timestamp": datetime.datetime.utcnow().isoformat() + "Z",
        "gpu_vendor": gpu_vendor,
        "gpu_model": gpu_model,
        "available_providers": _get_available_providers(),
        "total_results": len(all_results),
        "results": [asdict(r) for r in all_results],
    }

    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(output_data, f, indent=2)

    log.info("Results saved: %s (%d records)", out_path, len(all_results))
    print(json.dumps([asdict(r) for r in all_results]))

    return 0


if __name__ == "__main__":
    sys.exit(main())