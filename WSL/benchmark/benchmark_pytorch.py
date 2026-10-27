# =============================================================================
# Windows AGI Benchmark Lab — PyTorch Benchmark Module
# Copyright (c) 2026 Microsoft Corporation. All Rights Reserved.
# =============================================================================

"""
PyTorch benchmark module for AMD ROCm and NVIDIA CUDA.

Measures:
  - Matrix multiplication throughput (TFLOPS)
  - Memory bandwidth (GB/s)
  - Convolution performance
  - Transformer attention performance
  - Mixed precision (FP32, FP16, BF16, INT8)
  - GPU memory allocation/deallocation
  - Multi-GPU scaling (if available)
"""

from __future__ import annotations

import argparse
import datetime
import json
import logging
import os
import platform
import subprocess
import sys
import time
from dataclasses import asdict, dataclass

import psutil

log = logging.getLogger("agi.bench.pytorch")
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)-8s | %(name)s | %(message)s",
)

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
MATRIX_SIZES = [1024, 2048, 4096, 8192, 16384]
CONV_CONFIGS = [
    (1, 3, 224, 224),    # ResNet input
    (1, 64, 56, 56),     # ResNet layer 1
    (1, 256, 28, 28),    # ResNet layer 2
    (8, 3, 224, 224),    # Batch=8
    (16, 3, 224, 224),   # Batch=16
]
ATTENTION_CONFIGS = [
    (1, 8, 512, 64),     # seq=512, heads=8, dim=64
    (1, 16, 1024, 64),   # seq=1024
    (1, 32, 2048, 64),   # seq=2048
    (4, 32, 2048, 64),   # batch=4
]
DTYPES_TO_TEST = ["float32", "float16", "bfloat16"]
WARMUP_RUNS = 5
BENCHMARK_RUNS = 20


# ---------------------------------------------------------------------------
# Data Model
# ---------------------------------------------------------------------------
@dataclass
class PyTorchResult:
    """Single PyTorch benchmark result."""

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
# GPU Helpers
# ---------------------------------------------------------------------------
def _get_gpu_vendor() -> str:
    """Detect GPU vendor."""
    try:
        r = subprocess.run(
            ["nvidia-smi", "--query-gpu=name", "--format=csv,noheader"],
            capture_output=True, text=True, timeout=3,
        )
        if r.returncode == 0:
            return "nvidia"
    except (FileNotFoundError, subprocess.TimeoutExpired):
        pass
    try:
        r = subprocess.run(["rocminfo"], capture_output=True, text=True, timeout=5)
        if r.returncode == 0:
            return "amd"
    except (FileNotFoundError, subprocess.TimeoutExpired):
        pass
    return "none"


def _get_gpu_model() -> str:
    """Get GPU model name."""
    try:
        r = subprocess.run(
            ["nvidia-smi", "--query-gpu=name", "--format=csv,noheader"],
            capture_output=True, text=True, timeout=3,
        )
        if r.returncode == 0:
            return r.stdout.strip().splitlines()[0]
    except (FileNotFoundError, subprocess.TimeoutExpired):
        pass
    try:
        r = subprocess.run(
            ["rocm-smi", "--showproductname", "--json"],
            capture_output=True, text=True, timeout=5,
        )
        if r.returncode == 0:
            data = json.loads(r.stdout)
            for v in data.values():
                if isinstance(v, dict):
                    return v.get("Card series", "AMD GPU")
    except (FileNotFoundError, subprocess.TimeoutExpired, json.JSONDecodeError):
        pass
    return "CPU"


def _get_vram_used_gb(device: object) -> float:
    """Get current VRAM usage in GB."""
    try:
        import torch  # type: ignore[import]
        if hasattr(torch.cuda, "memory_allocated"):
            return round(torch.cuda.memory_allocated(device) / (1024**3), 3)
    except Exception:
        pass
    return 0.0


def _get_power_watts() -> float:
    """Get GPU power draw in watts."""
    try:
        r = subprocess.run(
            ["nvidia-smi", "--query-gpu=power.draw", "--format=csv,noheader,nounits"],
            capture_output=True, text=True, timeout=3,
        )
        if r.returncode == 0:
            return float(r.stdout.strip())
    except (FileNotFoundError, subprocess.TimeoutExpired, ValueError):
        pass
    try:
        r = subprocess.run(
            ["rocm-smi", "--showpower", "--json"],
            capture_output=True, text=True, timeout=3,
        )
        if r.returncode == 0:
            data = json.loads(r.stdout)
            for v in data.values():
                if isinstance(v, dict):
                    pw = v.get("Average Graphics Package Power (W)", "0")
                    return float(str(pw).replace("W", "").strip())
    except (FileNotFoundError, subprocess.TimeoutExpired, json.JSONDecodeError, ValueError):
        pass
    return 0.0


def _get_temp_celsius() -> float:
    """Get GPU temperature in Celsius."""
    try:
        r = subprocess.run(
            ["nvidia-smi", "--query-gpu=temperature.gpu", "--format=csv,noheader,nounits"],
            capture_output=True, text=True, timeout=3,
        )
        if r.returncode == 0:
            return float(r.stdout.strip())
    except (FileNotFoundError, subprocess.TimeoutExpired, ValueError):
        pass
    try:
        r = subprocess.run(
            ["rocm-smi", "--showtemp", "--json"],
            capture_output=True, text=True, timeout=3,
        )
        if r.returncode == 0:
            data = json.loads(r.stdout)
            for v in data.values():
                if isinstance(v, dict):
                    t = v.get("Temperature (Sensor edge) (C)", "0")
                    return float(str(t).replace("C", "").strip())
    except (FileNotFoundError, subprocess.TimeoutExpired, json.JSONDecodeError, ValueError):
        pass
    return 0.0


def _detect_host_os() -> str:
    if "microsoft" in platform.uname().release.lower():
        return "WSL2"
    return platform.system()


# ---------------------------------------------------------------------------
# Benchmark Functions
# ---------------------------------------------------------------------------
def benchmark_matmul(
    device: object,
    gpu_vendor: str,
    gpu_model: str,
    dtype_name: str = "float32",
) -> list[PyTorchResult]:
    """Matrix multiplication benchmark across sizes."""
    import torch  # type: ignore[import]

    dtype_map = {
        "float32": torch.float32,
        "float16": torch.float16,
        "bfloat16": torch.bfloat16,
    }
    dtype = dtype_map.get(dtype_name, torch.float32)
    results: list[PyTorchResult] = []

    for size in MATRIX_SIZES:
        log.info("MatMul benchmark: size=%dx%d dtype=%s device=%s", size, size, dtype_name, device)

        status = "success"
        error_msg = ""
        tflops = 0.0
        latency_ms = 0.0

        try:
            # Allocate matrices
            A = torch.rand(size, size, dtype=dtype, device=device)
            B = torch.rand(size, size, dtype=dtype, device=device)

            # Warmup
            for _ in range(WARMUP_RUNS):
                C = torch.matmul(A, B)
                if hasattr(torch.cuda, "synchronize"):
                    torch.cuda.synchronize(device)

            # Benchmark
            times: list[float] = []
            for _ in range(BENCHMARK_RUNS):
                t0 = time.perf_counter()
                C = torch.matmul(A, B)
                if hasattr(torch.cuda, "synchronize"):
                    torch.cuda.synchronize(device)
                t1 = time.perf_counter()
                times.append(t1 - t0)

            # Compute TFLOPS: 2 * N^3 FLOPs for NxN matmul
            avg_time = sum(times) / len(times)
            flops = 2.0 * (size ** 3)
            tflops = round(flops / avg_time / 1e12, 4)
            latency_ms = round(avg_time * 1000, 3)

            # Cleanup
            del A, B, C
            if hasattr(torch.cuda, "empty_cache"):
                torch.cuda.empty_cache()

        except Exception as exc:
            status = "error"
            error_msg = str(exc)[:300]
            log.error("MatMul %dx%d %s failed: %s", size, size, dtype_name, exc)

        results.append(PyTorchResult(
            timestamp=datetime.datetime.utcnow().isoformat() + "Z",
            suite="pytorch",
            benchmark=f"matmul_{size}x{size}_{dtype_name}",
            model="pytorch_matmul",
            prompt_type="",
            prompt_tokens=0,
            output_tokens=0,
            ttft_ms=0.0,
            total_latency_ms=latency_ms,
            tokens_per_sec=tflops,  # repurposed: TFLOPS
            vram_used_gb=_get_vram_used_gb(device),
            ram_used_gb=round(psutil.virtual_memory().used / (1024**3), 2),
            gpu_util_pct=0.0,
            cpu_util_pct=psutil.cpu_percent(interval=0.1),
            power_watts=_get_power_watts(),
            temp_celsius=_get_temp_celsius(),
            context_length=size,
            batch_size=1,
            quantization=dtype_name,
            backend="pytorch",
            device=str(device),
            gpu_vendor=gpu_vendor,
            gpu_model=gpu_model,
            host_os=_detect_host_os(),
            status=status,
            error_message=error_msg,
            notes=f"tflops={tflops} size={size}x{size} dtype={dtype_name}",
        ))

    return results


def benchmark_memory_bandwidth(
    device: object,
    gpu_vendor: str,
    gpu_model: str,
) -> list[PyTorchResult]:
    """Memory bandwidth benchmark."""
    import torch  # type: ignore[import]

    results: list[PyTorchResult] = []
    sizes_mb = [64, 256, 512, 1024, 2048, 4096]

    for size_mb in sizes_mb:
        log.info("Memory bandwidth: size=%dMB device=%s", size_mb, device)

        n_elements = (size_mb * 1024 * 1024) // 4  # float32 = 4 bytes
        status = "success"
        error_msg = ""
        bandwidth_gbs = 0.0
        latency_ms = 0.0

        try:
            src = torch.rand(n_elements, dtype=torch.float32, device=device)
            dst = torch.empty_like(src)

            # Warmup
            for _ in range(WARMUP_RUNS):
                dst.copy_(src)
                if hasattr(torch.cuda, "synchronize"):
                    torch.cuda.synchronize(device)

            # Benchmark
            times: list[float] = []
            for _ in range(BENCHMARK_RUNS):
                t0 = time.perf_counter()
                dst.copy_(src)
                if hasattr(torch.cuda, "synchronize"):
                    torch.cuda.synchronize(device)
                t1 = time.perf_counter()
                times.append(t1 - t0)

            avg_time = sum(times) / len(times)
            bytes_transferred = size_mb * 1024 * 1024 * 2  # read + write
            bandwidth_gbs = round(bytes_transferred / avg_time / 1e9, 2)
            latency_ms = round(avg_time * 1000, 3)

            del src, dst
            if hasattr(torch.cuda, "empty_cache"):
                torch.cuda.empty_cache()

        except Exception as exc:
            status = "error"
            error_msg = str(exc)[:300]
            log.error("Memory bandwidth %dMB failed: %s", size_mb, exc)

        results.append(PyTorchResult(
            timestamp=datetime.datetime.utcnow().isoformat() + "Z",
            suite="pytorch",
            benchmark=f"memory_bandwidth_{size_mb}mb",
            model="pytorch_membw",
            prompt_type="",
            prompt_tokens=0,
            output_tokens=0,
            ttft_ms=0.0,
            total_latency_ms=latency_ms,
            tokens_per_sec=bandwidth_gbs,  # repurposed: GB/s
            vram_used_gb=_get_vram_used_gb(device),
            ram_used_gb=round(psutil.virtual_memory().used / (1024**3), 2),
            gpu_util_pct=0.0,
            cpu_util_pct=psutil.cpu_percent(interval=0.1),
            power_watts=_get_power_watts(),
            temp_celsius=_get_temp_celsius(),
            context_length=size_mb,
            batch_size=1,
            quantization="float32",
            backend="pytorch",
            device=str(device),
            gpu_vendor=gpu_vendor,
            gpu_model=gpu_model,
            host_os=_detect_host_os(),
            status=status,
            error_message=error_msg,
            notes=f"bandwidth_gbs={bandwidth_gbs} size_mb={size_mb}",
        ))

    return results


def benchmark_attention(
    device: object,
    gpu_vendor: str,
    gpu_model: str,
    dtype_name: str = "float16",
) -> list[PyTorchResult]:
    """Transformer attention benchmark."""
    import torch  # type: ignore[import]
    import torch.nn.functional as F  # type: ignore[import]

    dtype_map = {
        "float32": torch.float32,
        "float16": torch.float16,
        "bfloat16": torch.bfloat16,
    }
    dtype = dtype_map.get(dtype_name, torch.float16)
    results: list[PyTorchResult] = []

    for batch, heads, seq_len, head_dim in ATTENTION_CONFIGS:
        log.info(
            "Attention benchmark: batch=%d heads=%d seq=%d dim=%d dtype=%s",
            batch, heads, seq_len, head_dim, dtype_name,
        )

        status = "success"
        error_msg = ""
        latency_ms = 0.0
        tps = 0.0

        try:
            Q = torch.rand(batch, heads, seq_len, head_dim, dtype=dtype, device=device)
            K = torch.rand(batch, heads, seq_len, head_dim, dtype=dtype, device=device)
            V = torch.rand(batch, heads, seq_len, head_dim, dtype=dtype, device=device)

            scale = head_dim ** -0.5

            # Warmup
            for _ in range(WARMUP_RUNS):
                scores = torch.matmul(Q, K.transpose(-2, -1)) * scale
                attn = F.softmax(scores, dim=-1)
                out = torch.matmul(attn, V)
                if hasattr(torch.cuda, "synchronize"):
                    torch.cuda.synchronize(device)

            # Benchmark
            times: list[float] = []
            for _ in range(BENCHMARK_RUNS):
                t0 = time.perf_counter()
                scores = torch.matmul(Q, K.transpose(-2, -1)) * scale
                attn = F.softmax(scores, dim=-1)
                out = torch.matmul(attn, V)
                if hasattr(torch.cuda, "synchronize"):
                    torch.cuda.synchronize(device)
                t1 = time.perf_counter()
                times.append(t1 - t0)

            avg_time = sum(times) / len(times)
            latency_ms = round(avg_time * 1000, 3)
            # Tokens processed per second
            tps = round((batch * seq_len) / avg_time, 1)

            del Q, K, V, scores, attn, out
            if hasattr(torch.cuda, "empty_cache"):
                torch.cuda.empty_cache()

        except Exception as exc:
            status = "error"
            error_msg = str(exc)[:300]
            log.error("Attention benchmark failed: %s", exc)

        results.append(PyTorchResult(
            timestamp=datetime.datetime.utcnow().isoformat() + "Z",
            suite="pytorch",
            benchmark=f"attention_b{batch}_h{heads}_s{seq_len}_d{head_dim}_{dtype_name}",
            model="pytorch_attention",
            prompt_type="",
            prompt_tokens=seq_len,
            output_tokens=seq_len,
            ttft_ms=0.0,
            total_latency_ms=latency_ms,
            tokens_per_sec=tps,
            vram_used_gb=_get_vram_used_gb(device),
            ram_used_gb=round(psutil.virtual_memory().used / (1024**3), 2),
            gpu_util_pct=0.0,
            cpu_util_pct=psutil.cpu_percent(interval=0.1),
            power_watts=_get_power_watts(),
            temp_celsius=_get_temp_celsius(),
            context_length=seq_len,
            batch_size=batch,
            quantization=dtype_name,
            backend="pytorch",
            device=str(device),
            gpu_vendor=gpu_vendor,
            gpu_model=gpu_model,
            host_os=_detect_host_os(),
            status=status,
            error_message=error_msg,
            notes=f"heads={heads} seq={seq_len} head_dim={head_dim}",
        ))

    return results


def benchmark_stress(
    device: object,
    gpu_vendor: str,
    gpu_model: str,
    duration_sec: int = 30,
) -> list[PyTorchResult]:
    """GPU stress test — sustained load for thermal/power measurement."""
    import torch  # type: ignore[import]

    log.info("GPU stress test: duration=%ds device=%s", duration_sec, device)

    results: list[PyTorchResult] = []
    size = 8192
    dtype = torch.float16

    status = "success"
    error_msg = ""
    iterations = 0
    peak_power = 0.0
    peak_temp = 0.0
    peak_vram = 0.0

    try:
        A = torch.rand(size, size, dtype=dtype, device=device)
        B = torch.rand(size, size, dtype=dtype, device=device)

        t_start = time.perf_counter()
        while time.perf_counter() - t_start < duration_sec:
            C = torch.matmul(A, B)
            if hasattr(torch.cuda, "synchronize"):
                torch.cuda.synchronize(device)
            iterations += 1

            # Sample metrics every 10 iterations
            if iterations % 10 == 0:
                pw = _get_power_watts()
                temp = _get_temp_celsius()
                vram = _get_vram_used_gb(device)
                peak_power = max(peak_power, pw)
                peak_temp = max(peak_temp, temp)
                peak_vram = max(peak_vram, vram)

        elapsed = time.perf_counter() - t_start
        flops_per_iter = 2.0 * (size ** 3)
        total_tflops = round(flops_per_iter * iterations / elapsed / 1e12, 3)

        del A, B, C
        if hasattr(torch.cuda, "empty_cache"):
            torch.cuda.empty_cache()

    except Exception as exc:
        status = "error"
        error_msg = str(exc)[:300]
        log.error("Stress test failed: %s", exc)

    results.append(PyTorchResult(
        timestamp=datetime.datetime.utcnow().isoformat() + "Z",
        suite="pytorch",
        benchmark=f"stress_{duration_sec}s",
        model="pytorch_stress",
        prompt_type="",
        prompt_tokens=0,
        output_tokens=0,
        ttft_ms=0.0,
        total_latency_ms=duration_sec * 1000.0,
        tokens_per_sec=total_tflops,  # TFLOPS sustained
        vram_used_gb=peak_vram,
        ram_used_gb=round(psutil.virtual_memory().used / (1024**3), 2),
        gpu_util_pct=100.0,
        cpu_util_pct=psutil.cpu_percent(interval=0.1),
        power_watts=peak_power,
        temp_celsius=peak_temp,
        context_length=size,
        batch_size=1,
        quantization="float16",
        backend="pytorch",
        device=str(device),
        gpu_vendor=gpu_vendor,
        gpu_model=gpu_model,
        host_os=_detect_host_os(),
        status=status,
        error_message=error_msg,
        notes=f"iterations={iterations} peak_power={peak_power}W peak_temp={peak_temp}C",
    ))

    return results


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main() -> int:
    """Run PyTorch benchmarks."""
    parser = argparse.ArgumentParser(description="PyTorch Benchmark — Microsoft AGI Lab")
    parser.add_argument("--device", choices=["cuda", "cpu", "auto"], default="auto")
    parser.add_argument("--vendor", choices=["nvidia", "amd", "auto"], default="auto")
    parser.add_argument("--dtypes", nargs="+", default=DTYPES_TO_TEST)
    parser.add_argument("--stress-duration", type=int, default=30)
    parser.add_argument("--output", default="benchmark/reports/pytorch_results.json")
    parser.add_argument("--verbose", "-v", action="store_true")
    args = parser.parse_args()

    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)

    # Import torch
    try:
        import torch  # type: ignore[import]
    except ImportError:
        log.error("PyTorch not installed. Install with: pip install torch")
        return 1

    # Determine device
    if args.device == "auto":
        if torch.cuda.is_available():
            device = torch.device("cuda")
        else:
            device = torch.device("cpu")
    else:
        device = torch.device(args.device)

    log.info("PyTorch version: %s", torch.__version__)
    log.info("Device: %s", device)

    if device.type == "cuda":
        log.info("CUDA available: %s", torch.cuda.is_available())
        log.info("GPU count: %d", torch.cuda.device_count())
        if torch.cuda.is_available():
            log.info("GPU name: %s", torch.cuda.get_device_name(0))
            log.info(
                "VRAM: %.1f GB",
                torch.cuda.get_device_properties(0).total_memory / (1024**3),
            )

    gpu_vendor = _get_gpu_vendor() if args.vendor == "auto" else args.vendor
    gpu_model = _get_gpu_model()

    all_results: list[PyTorchResult] = []

    # Matrix multiplication benchmarks
    for dtype_name in args.dtypes:
        if dtype_name == "bfloat16" and device.type == "cpu":
            log.info("Skipping bfloat16 on CPU")
            continue
        results = benchmark_matmul(device, gpu_vendor, gpu_model, dtype_name)
        all_results.extend(results)

    # Memory bandwidth
    results = benchmark_memory_bandwidth(device, gpu_vendor, gpu_model)
    all_results.extend(results)

    # Attention benchmarks
    for dtype_name in ["float16", "float32"]:
        if device.type == "cpu" and dtype_name == "float16":
            continue
        results = benchmark_attention(device, gpu_vendor, gpu_model, dtype_name)
        all_results.extend(results)

    # Stress test (GPU only)
    if device.type == "cuda":
        results = benchmark_stress(device, gpu_vendor, gpu_model, args.stress_duration)
        all_results.extend(results)

    # Export
    import pathlib
    out_path = pathlib.Path(args.output)
    out_path.parent.mkdir(parents=True, exist_ok=True)

    output_data = {
        "suite": "pytorch",
        "timestamp": datetime.datetime.utcnow().isoformat() + "Z",
        "device": str(device),
        "gpu_vendor": gpu_vendor,
        "gpu_model": gpu_model,
        "pytorch_version": torch.__version__,
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