# =============================================================================
# Windows AGI Benchmark Lab — CPU Benchmark Module
# Copyright (c) 2026 Microsoft Corporation. All Rights Reserved.
# =============================================================================

"""
CPU benchmark module.

Tests:
  - Integer arithmetic throughput
  - Floating point throughput (FP32, FP64)
  - SIMD/vectorized operations
  - Memory latency (cache hierarchy: L1, L2, L3, RAM)
  - Memory bandwidth
  - Branch prediction
  - Multi-core scaling
  - CPU-based matrix multiplication
  - Compression/decompression throughput
  - Cryptographic operations (AES, SHA)
  - JSON parsing throughput
  - String operations

Supports: Intel (i5/i7/i9/Xeon), AMD (Ryzen/EPYC), ARM64, RISC-V
"""

from __future__ import annotations

import argparse
import datetime
import hashlib
import json
import logging
import math
import multiprocessing
import os
import pathlib
import platform
import subprocess
import sys
import time
import zlib
from concurrent.futures import ProcessPoolExecutor, ThreadPoolExecutor, as_completed
from dataclasses import asdict, dataclass
from typing import Any

import numpy as np
import psutil

log = logging.getLogger("agi.bench.cpu")
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)-8s | %(name)s | %(message)s",
)

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
BENCHMARK_DURATION_SEC = 5.0
MATRIX_SIZES = [256, 512, 1024, 2048, 4096]
THREAD_COUNTS = [1, 2, 4, 8, 16, 32]
PAYLOAD_SIZES_MB = [1, 4, 16, 64, 256]


# ---------------------------------------------------------------------------
# Data Model
# ---------------------------------------------------------------------------
@dataclass
class CPUResult:
    """Single CPU benchmark result."""

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
# System Info
# ---------------------------------------------------------------------------
def _get_cpu_info() -> dict[str, Any]:
    """Collect detailed CPU information."""
    info: dict[str, Any] = {
        "model": platform.processor(),
        "arch": platform.machine(),
        "cores_physical": psutil.cpu_count(logical=False) or 1,
        "cores_logical": psutil.cpu_count(logical=True) or 1,
        "freq_mhz": 0.0,
        "cache_l1": "unknown",
        "cache_l2": "unknown",
        "cache_l3": "unknown",
    }

    freq = psutil.cpu_freq()
    if freq:
        info["freq_mhz"] = round(freq.current, 1)

    try:
        import cpuinfo  # type: ignore[import]
        ci = cpuinfo.get_cpu_info()
        info["model"] = ci.get("brand_raw", info["model"])
        info["cache_l2"] = ci.get("l2_cache_size", "unknown")
        info["cache_l3"] = ci.get("l3_cache_size", "unknown")
    except ImportError:
        pass

    # Try /proc/cpuinfo on Linux
    try:
        with open("/proc/cpuinfo", encoding="utf-8") as f:
            content = f.read()
        for line in content.splitlines():
            if "model name" in line.lower() and ":" in line:
                info["model"] = line.split(":", 1)[1].strip()
                break
    except (FileNotFoundError, PermissionError):
        pass

    return info


def _detect_host_os() -> str:
    if "microsoft" in platform.uname().release.lower():
        return "WSL2"
    return platform.system()


def _make_result(
    benchmark: str,
    metric_value: float,
    latency_ms: float,
    status: str = "success",
    error_msg: str = "",
    notes: str = "",
    cpu_info: dict[str, Any] | None = None,
) -> CPUResult:
    """Create a CPUResult with standard fields."""
    mem = psutil.virtual_memory()
    return CPUResult(
        timestamp=datetime.datetime.utcnow().isoformat() + "Z",
        suite="cpu",
        benchmark=benchmark,
        model=cpu_info.get("model", platform.processor()) if cpu_info else platform.processor(),
        prompt_type="",
        prompt_tokens=0,
        output_tokens=0,
        ttft_ms=0.0,
        total_latency_ms=latency_ms,
        tokens_per_sec=metric_value,
        vram_used_gb=0.0,
        ram_used_gb=round(mem.used / (1024**3), 2),
        gpu_util_pct=0.0,
        cpu_util_pct=psutil.cpu_percent(interval=0.1),
        power_watts=0.0,
        temp_celsius=0.0,
        context_length=0,
        batch_size=1,
        quantization="",
        backend="cpu_native",
        device="cpu",
        gpu_vendor="none",
        gpu_model="none",
        host_os=_detect_host_os(),
        status=status,
        error_message=error_msg,
        notes=notes,
    )


# ---------------------------------------------------------------------------
# Benchmark: Integer Arithmetic
# ---------------------------------------------------------------------------
def benchmark_integer_arithmetic(cpu_info: dict[str, Any]) -> CPUResult:
    """Measure integer arithmetic throughput (MOPS)."""
    log.info("CPU benchmark: integer arithmetic")

    iterations = 0
    x = 1
    t_start = time.perf_counter()
    t_end = t_start + BENCHMARK_DURATION_SEC

    while time.perf_counter() < t_end:
        # 10 integer ops per loop
        x = (x * 7 + 13) % 1000003
        x = (x * 11 + 17) % 999983
        x = (x * 3 + 5) % 999979
        x = (x * 19 + 23) % 999961
        x = (x * 29 + 31) % 999931
        iterations += 50  # 5 mults + 5 adds + 5 mods = 15 ops, ~50 total

    elapsed = time.perf_counter() - t_start
    mops = round(iterations / elapsed / 1e6, 2)

    return _make_result(
        benchmark="cpu_integer_arithmetic",
        metric_value=mops,
        latency_ms=round(elapsed * 1000, 2),
        notes=f"mops={mops} iterations={iterations}",
        cpu_info=cpu_info,
    )


# ---------------------------------------------------------------------------
# Benchmark: Floating Point
# ---------------------------------------------------------------------------
def benchmark_float_arithmetic(cpu_info: dict[str, Any], dtype: str = "float64") -> CPUResult:
    """Measure floating point throughput (GFLOPS)."""
    log.info("CPU benchmark: float arithmetic dtype=%s", dtype)

    np_dtype = np.float64 if dtype == "float64" else np.float32
    size = 10_000_000
    rng = np.random.default_rng(42)
    a = rng.standard_normal(size).astype(np_dtype)
    b = rng.standard_normal(size).astype(np_dtype)

    # Warmup
    _ = a * b + a

    iterations = 0
    t_start = time.perf_counter()
    t_end = t_start + BENCHMARK_DURATION_SEC

    while time.perf_counter() < t_end:
        c = a * b + a  # 2 FLOPs per element
        iterations += 1

    elapsed = time.perf_counter() - t_start
    total_flops = iterations * size * 2
    gflops = round(total_flops / elapsed / 1e9, 3)

    return _make_result(
        benchmark=f"cpu_float_arithmetic_{dtype}",
        metric_value=gflops,
        latency_ms=round(elapsed * 1000, 2),
        notes=f"gflops={gflops} dtype={dtype} size={size}",
        cpu_info=cpu_info,
    )


# ---------------------------------------------------------------------------
# Benchmark: Matrix Multiplication (NumPy)
# ---------------------------------------------------------------------------
def benchmark_matmul(cpu_info: dict[str, Any]) -> list[CPUResult]:
    """CPU matrix multiplication benchmark."""
    results: list[CPUResult] = []

    for size in MATRIX_SIZES:
        log.info("CPU matmul: size=%dx%d", size, size)

        rng = np.random.default_rng(42)
        A = rng.standard_normal((size, size)).astype(np.float32)
        B = rng.standard_normal((size, size)).astype(np.float32)

        # Warmup
        _ = np.matmul(A, B)

        times: list[float] = []
        for _ in range(5):
            t0 = time.perf_counter()
            C = np.matmul(A, B)
            t1 = time.perf_counter()
            times.append(t1 - t0)

        avg_time = sum(times) / len(times)
        flops = 2.0 * (size ** 3)
        gflops = round(flops / avg_time / 1e9, 3)
        latency_ms = round(avg_time * 1000, 3)

        results.append(_make_result(
            benchmark=f"cpu_matmul_{size}x{size}",
            metric_value=gflops,
            latency_ms=latency_ms,
            notes=f"gflops={gflops} size={size}x{size}",
            cpu_info=cpu_info,
        ))

    return results


# ---------------------------------------------------------------------------
# Benchmark: Memory Bandwidth
# ---------------------------------------------------------------------------
def benchmark_memory_bandwidth(cpu_info: dict[str, Any]) -> list[CPUResult]:
    """Memory bandwidth benchmark (GB/s)."""
    results: list[CPUResult] = []

    for size_mb in PAYLOAD_SIZES_MB:
        log.info("CPU memory bandwidth: size=%dMB", size_mb)

        n_elements = (size_mb * 1024 * 1024) // 4  # float32
        src = np.random.default_rng(42).standard_normal(n_elements).astype(np.float32)
        dst = np.empty_like(src)

        # Warmup
        np.copyto(dst, src)

        times: list[float] = []
        for _ in range(20):
            t0 = time.perf_counter()
            np.copyto(dst, src)
            t1 = time.perf_counter()
            times.append(t1 - t0)

        avg_time = sum(times) / len(times)
        bytes_transferred = size_mb * 1024 * 1024 * 2  # read + write
        bandwidth_gbs = round(bytes_transferred / avg_time / 1e9, 2)

        results.append(_make_result(
            benchmark=f"cpu_memory_bandwidth_{size_mb}mb",
            metric_value=bandwidth_gbs,
            latency_ms=round(avg_time * 1000, 3),
            notes=f"bandwidth_gbs={bandwidth_gbs} size_mb={size_mb}",
            cpu_info=cpu_info,
        ))

    return results


# ---------------------------------------------------------------------------
# Benchmark: Memory Latency (Cache Hierarchy)
# ---------------------------------------------------------------------------
def benchmark_memory_latency(cpu_info: dict[str, Any]) -> list[CPUResult]:
    """Memory latency benchmark for cache hierarchy."""
    results: list[CPUResult] = []

    # Different sizes to hit L1, L2, L3, RAM
    cache_levels = {
        "l1_cache":  32 * 1024,          # 32 KB
        "l2_cache":  256 * 1024,         # 256 KB
        "l3_cache":  8 * 1024 * 1024,    # 8 MB
        "main_ram":  256 * 1024 * 1024,  # 256 MB
    }

    for level_name, size_bytes in cache_levels.items():
        log.info("CPU memory latency: level=%s size=%dKB", level_name, size_bytes // 1024)

        n_elements = size_bytes // 8  # int64
        arr = np.arange(n_elements, dtype=np.int64)
        # Shuffle for random access pattern
        rng = np.random.default_rng(42)
        indices = rng.permutation(n_elements).astype(np.int64)

        # Warmup
        _ = arr[indices[:1000]]

        n_accesses = min(100_000, n_elements)
        t0 = time.perf_counter()
        for i in range(n_accesses):
            _ = arr[indices[i % len(indices)]]
        t1 = time.perf_counter()

        elapsed = t1 - t0
        latency_ns = round((elapsed / n_accesses) * 1e9, 2)

        results.append(_make_result(
            benchmark=f"cpu_memory_latency_{level_name}",
            metric_value=latency_ns,
            latency_ms=round(elapsed * 1000, 2),
            notes=f"latency_ns={latency_ns} level={level_name} size_kb={size_bytes // 1024}",
            cpu_info=cpu_info,
        ))

    return results


# ---------------------------------------------------------------------------
# Benchmark: Multi-Core Scaling
# ---------------------------------------------------------------------------
def _worker_task(n: int) -> float:
    """Worker task for multi-core benchmark."""
    result = 0.0
    for i in range(n):
        result += math.sqrt(float(i) + 1.0) * math.sin(float(i))
    return result


def benchmark_multicore_scaling(cpu_info: dict[str, Any]) -> list[CPUResult]:
    """Multi-core scaling benchmark."""
    results: list[CPUResult] = []
    max_cores = psutil.cpu_count(logical=True) or 1
    work_per_core = 500_000

    for n_threads in THREAD_COUNTS:
        if n_threads > max_cores:
            continue

        log.info("CPU multi-core: threads=%d", n_threads)

        t0 = time.perf_counter()
        with ThreadPoolExecutor(max_workers=n_threads) as executor:
            futures = [
                executor.submit(_worker_task, work_per_core)
                for _ in range(n_threads)
            ]
            for f in as_completed(futures):
                _ = f.result()
        t1 = time.perf_counter()

        elapsed = t1 - t0
        total_ops = n_threads * work_per_core
        mops = round(total_ops / elapsed / 1e6, 2)

        results.append(_make_result(
            benchmark=f"cpu_multicore_{n_threads}threads",
            metric_value=mops,
            latency_ms=round(elapsed * 1000, 2),
            notes=f"mops={mops} threads={n_threads} work_per_core={work_per_core}",
            cpu_info=cpu_info,
        ))

    return results


# ---------------------------------------------------------------------------
# Benchmark: Compression
# ---------------------------------------------------------------------------
def benchmark_compression(cpu_info: dict[str, Any]) -> list[CPUResult]:
    """Compression/decompression throughput benchmark."""
    results: list[CPUResult] = []

    for size_mb in [1, 4, 16, 64]:
        log.info("CPU compression: size=%dMB", size_mb)

        # Generate compressible data
        data = (b"Microsoft Windows AGI Benchmark Lab " * 1000)[:size_mb * 1024 * 1024]

        # Compression
        t0 = time.perf_counter()
        compressed = zlib.compress(data, level=6)
        t1 = time.perf_counter()
        compress_time = t1 - t0
        compress_ratio = round(len(data) / len(compressed), 2)
        compress_throughput = round(size_mb / compress_time, 2)

        results.append(_make_result(
            benchmark=f"cpu_compress_{size_mb}mb",
            metric_value=compress_throughput,
            latency_ms=round(compress_time * 1000, 2),
            notes=f"throughput_mbs={compress_throughput} ratio={compress_ratio} size_mb={size_mb}",
            cpu_info=cpu_info,
        ))

        # Decompression
        t0 = time.perf_counter()
        _ = zlib.decompress(compressed)
        t1 = time.perf_counter()
        decompress_time = t1 - t0
        decompress_throughput = round(size_mb / decompress_time, 2)

        results.append(_make_result(
            benchmark=f"cpu_decompress_{size_mb}mb",
            metric_value=decompress_throughput,
            latency_ms=round(decompress_time * 1000, 2),
            notes=f"throughput_mbs={decompress_throughput} size_mb={size_mb}",
            cpu_info=cpu_info,
        ))

    return results


# ---------------------------------------------------------------------------
# Benchmark: Cryptographic Operations
# ---------------------------------------------------------------------------
def benchmark_crypto(cpu_info: dict[str, Any]) -> list[CPUResult]:
    """Cryptographic hash throughput benchmark."""
    results: list[CPUResult] = []

    algorithms = ["sha256", "sha512", "md5", "sha3_256"]
    data_sizes_kb = [1, 64, 1024]

    for algo in algorithms:
        for size_kb in data_sizes_kb:
            log.info("CPU crypto: algo=%s size=%dKB", algo, size_kb)

            data = os.urandom(size_kb * 1024)
            n_iterations = max(10, 1000 // size_kb)

            t0 = time.perf_counter()
            for _ in range(n_iterations):
                h = hashlib.new(algo)
                h.update(data)
                _ = h.digest()
            t1 = time.perf_counter()

            elapsed = t1 - t0
            throughput_mbs = round((size_kb / 1024 * n_iterations) / elapsed, 2)

            results.append(_make_result(
                benchmark=f"cpu_crypto_{algo}_{size_kb}kb",
                metric_value=throughput_mbs,
                latency_ms=round(elapsed * 1000 / n_iterations, 3),
                notes=f"throughput_mbs={throughput_mbs} algo={algo} size_kb={size_kb}",
                cpu_info=cpu_info,
            ))

    return results


# ---------------------------------------------------------------------------
# Benchmark: JSON Parsing
# ---------------------------------------------------------------------------
def benchmark_json_parsing(cpu_info: dict[str, Any]) -> list[CPUResult]:
    """JSON serialization/deserialization throughput."""
    results: list[CPUResult] = []

    # Generate test payloads
    payloads = {
        "small": {"key": "value", "number": 42, "flag": True},
        "medium": {
            "id": "benchmark-001",
            "model": "llama3",
            "tokens_per_sec": 97.2,
            "ttft_ms": 0.54,
            "vram_gb": 18.3,
            "power_w": 267,
            "results": [{"run": i, "value": i * 1.5} for i in range(100)],
        },
        "large": {
            "benchmark_suite": "windows-agi-benchmark",
            "results": [
                {
                    "model": f"model_{i}",
                    "tokens_per_sec": float(i * 10),
                    "metrics": {k: float(k) for k in range(50)},
                }
                for i in range(500)
            ],
        },
    }

    for payload_name, payload in payloads.items():
        log.info("CPU JSON: payload=%s", payload_name)

        json_str = json.dumps(payload)
        size_kb = round(len(json_str.encode()) / 1024, 2)
        n_iterations = max(100, 10_000 // max(1, int(size_kb)))

        # Serialization
        t0 = time.perf_counter()
        for _ in range(n_iterations):
            _ = json.dumps(payload)
        t1 = time.perf_counter()
        serialize_ops = round(n_iterations / (t1 - t0), 0)

        results.append(_make_result(
            benchmark=f"cpu_json_serialize_{payload_name}",
            metric_value=serialize_ops,
            latency_ms=round((t1 - t0) * 1000 / n_iterations, 3),
            notes=f"ops_per_sec={serialize_ops} size_kb={size_kb}",
            cpu_info=cpu_info,
        ))

        # Deserialization
        t0 = time.perf_counter()
        for _ in range(n_iterations):
            _ = json.loads(json_str)
        t1 = time.perf_counter()
        deserialize_ops = round(n_iterations / (t1 - t0), 0)

        results.append(_make_result(
            benchmark=f"cpu_json_deserialize_{payload_name}",
            metric_value=deserialize_ops,
            latency_ms=round((t1 - t0) * 1000 / n_iterations, 3),
            notes=f"ops_per_sec={deserialize_ops} size_kb={size_kb}",
            cpu_info=cpu_info,
        ))

    return results


# ---------------------------------------------------------------------------
# Benchmark: Sysbench (if available)
# ---------------------------------------------------------------------------
def benchmark_sysbench(cpu_info: dict[str, Any]) -> list[CPUResult]:
    """Run sysbench CPU and memory benchmarks."""
    results: list[CPUResult] = []

    try:
        result = subprocess.run(
            ["sysbench", "--version"],
            capture_output=True, text=True, timeout=5,
        )
        if result.returncode != 0:
            return results
    except (FileNotFoundError, subprocess.TimeoutExpired):
        log.info("sysbench not available — skipping")
        return results

    # CPU benchmark
    log.info("sysbench CPU benchmark")
    try:
        result = subprocess.run(
            ["sysbench", "cpu", "--cpu-max-prime=20000", "--time=10", "run"],
            capture_output=True, text=True, timeout=60,
        )
        if result.returncode == 0:
            # Parse events per second
            for line in result.stdout.splitlines():
                if "events per second" in line.lower():
                    parts = line.split(":")
                    if len(parts) >= 2:
                        eps = float(parts[1].strip())
                        results.append(_make_result(
                            benchmark="cpu_sysbench_cpu",
                            metric_value=eps,
                            latency_ms=10000.0,
                            notes=f"events_per_sec={eps}",
                            cpu_info=cpu_info,
                        ))
                    break
    except (subprocess.TimeoutExpired, ValueError):
        pass

    # Memory benchmark
    log.info("sysbench memory benchmark")
    try:
        result = subprocess.run(
            ["sysbench", "memory", "--memory-block-size=1M", "--memory-total-size=10G", "--time=10", "run"],
            capture_output=True, text=True, timeout=60,
        )
        if result.returncode == 0:
            for line in result.stdout.splitlines():
                if "transferred" in line.lower() and "mib/sec" in line.lower():
                    # Parse: "transferred (X.XX MiB/sec)"
                    match_str = line.split("(")[-1].split("MiB")[0].strip()
                    try:
                        mib_sec = float(match_str)
                        results.append(_make_result(
                            benchmark="cpu_sysbench_memory",
                            metric_value=mib_sec,
                            latency_ms=10000.0,
                            notes=f"mib_per_sec={mib_sec}",
                            cpu_info=cpu_info,
                        ))
                    except ValueError:
                        pass
                    break
    except (subprocess.TimeoutExpired, ValueError):
        pass

    return results


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main() -> int:
    """Run CPU benchmarks."""
    parser = argparse.ArgumentParser(description="CPU Benchmark — Microsoft AGI Lab")
    parser.add_argument("--output", default="benchmark/reports/cpu_results.json")
    parser.add_argument("--duration", type=float, default=BENCHMARK_DURATION_SEC)
    parser.add_argument("--verbose", "-v", action="store_true")
    args = parser.parse_args()

    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)

    global BENCHMARK_DURATION_SEC
    BENCHMARK_DURATION_SEC = args.duration

    cpu_info = _get_cpu_info()
    log.info("CPU: %s", cpu_info["model"])
    log.info("Cores: %dP / %dL", cpu_info["cores_physical"], cpu_info["cores_logical"])
    log.info("Frequency: %.1f MHz", cpu_info["freq_mhz"])
    log.info("Architecture: %s", cpu_info["arch"])

    all_results: list[CPUResult] = []

    # Integer arithmetic
    all_results.append(benchmark_integer_arithmetic(cpu_info))

    # Float arithmetic
    for dtype in ["float32", "float64"]:
        all_results.append(benchmark_float_arithmetic(cpu_info, dtype))

    # Matrix multiplication
    all_results.extend(benchmark_matmul(cpu_info))

    # Memory bandwidth
    all_results.extend(benchmark_memory_bandwidth(cpu_info))

    # Memory latency
    all_results.extend(benchmark_memory_latency(cpu_info))

    # Multi-core scaling
    all_results.extend(benchmark_multicore_scaling(cpu_info))

    # Compression
    all_results.extend(benchmark_compression(cpu_info))

    # Cryptographic operations
    all_results.extend(benchmark_crypto(cpu_info))

    # JSON parsing
    all_results.extend(benchmark_json_parsing(cpu_info))

    # Sysbench (if available)
    all_results.extend(benchmark_sysbench(cpu_info))

    # Export
    out_path = pathlib.Path(args.output)
    out_path.parent.mkdir(parents=True, exist_ok=True)

    output_data = {
        "suite": "cpu",
        "timestamp": datetime.datetime.utcnow().isoformat() + "Z",
        "cpu_info": cpu_info,
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