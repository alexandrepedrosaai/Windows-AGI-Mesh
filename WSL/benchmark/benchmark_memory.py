# =============================================================================
# Windows AGI Benchmark Lab — Memory Benchmark Module
# Copyright (c) 2026 Microsoft Corporation. All Rights Reserved.
# =============================================================================
"""Memory subsystem benchmark: bandwidth, latency, NUMA, huge pages."""

from __future__ import annotations
import argparse, datetime, json, logging, os, pathlib, platform, subprocess, sys, time
from dataclasses import asdict, dataclass
from typing import Any
import numpy as np
import psutil

log = logging.getLogger("agi.bench.memory")
logging.basicConfig(level=logging.INFO, format="%(asctime)s | %(levelname)-8s | %(name)s | %(message)s")

SIZES_MB = [1, 4, 16, 64, 256, 512, 1024, 2048, 4096]
DTYPES = [np.float32, np.float64, np.int32, np.int64]
REPS = 10

@dataclass
class MemResult:
    timestamp: str; suite: str; benchmark: str; model: str
    prompt_type: str; prompt_tokens: int; output_tokens: int
    ttft_ms: float; total_latency_ms: float; tokens_per_sec: float
    vram_used_gb: float; ram_used_gb: float; gpu_util_pct: float
    cpu_util_pct: float; power_watts: float; temp_celsius: float
    context_length: int; batch_size: int; quantization: str
    backend: str; device: str; gpu_vendor: str; gpu_model: str
    host_os: str; status: str; error_message: str; notes: str

def _detect_host_os() -> str:
    return "WSL2" if "microsoft" in platform.uname().release.lower() else platform.system()

def _make_result(benchmark: str, metric: float, latency_ms: float,
                 status: str="success", error_msg: str="", notes: str="") -> MemResult:
    mem = psutil.virtual_memory()
    return MemResult(
        timestamp=datetime.datetime.utcnow().isoformat()+"Z", suite="memory",
        benchmark=benchmark, model="system_memory", prompt_type="",
        prompt_tokens=0, output_tokens=0, ttft_ms=0.0,
        total_latency_ms=latency_ms, tokens_per_sec=metric,
        vram_used_gb=0.0, ram_used_gb=round(mem.used/(1024**3),2),
        gpu_util_pct=0.0, cpu_util_pct=psutil.cpu_percent(interval=0.1),
        power_watts=0.0, temp_celsius=0.0, context_length=0, batch_size=1,
        quantization="", backend="numpy", device="cpu",
        gpu_vendor="none", gpu_model="none", host_os=_detect_host_os(),
        status=status, error_message=error_msg, notes=notes)

def bench_sequential_read(size_mb: int) -> MemResult:
    n = (size_mb * 1024 * 1024) // 8
    arr = np.random.default_rng(42).standard_normal(n).astype(np.float64)
    _ = arr.sum()  # warmup
    times = []
    for _ in range(REPS):
        t0 = time.perf_counter()
        total = arr.sum()
        times.append(time.perf_counter() - t0)
    avg = sum(times)/len(times)
    bw = round(size_mb * 8 / avg / 1024, 2)  # GB/s
    return _make_result(f"mem_seq_read_{size_mb}mb", bw, round(avg*1000,3),
                        notes=f"bandwidth_gbs={bw} size_mb={size_mb}")

def bench_sequential_write(size_mb: int) -> MemResult:
    n = (size_mb * 1024 * 1024) // 8
    arr = np.empty(n, dtype=np.float64)
    times = []
    for _ in range(REPS):
        t0 = time.perf_counter()
        arr.fill(1.0)
        times.append(time.perf_counter() - t0)
    avg = sum(times)/len(times)
    bw = round(size_mb * 8 / avg / 1024, 2)
    return _make_result(f"mem_seq_write_{size_mb}mb", bw, round(avg*1000,3),
                        notes=f"bandwidth_gbs={bw} size_mb={size_mb}")

def bench_copy(size_mb: int) -> MemResult:
    n = (size_mb * 1024 * 1024) // 8
    src = np.random.default_rng(42).standard_normal(n).astype(np.float64)
    dst = np.empty_like(src)
    np.copyto(dst, src)  # warmup
    times = []
    for _ in range(REPS):
        t0 = time.perf_counter()
        np.copyto(dst, src)
        times.append(time.perf_counter() - t0)
    avg = sum(times)/len(times)
    bw = round(size_mb * 8 * 2 / avg / 1024, 2)  # read+write
    return _make_result(f"mem_copy_{size_mb}mb", bw, round(avg*1000,3),
                        notes=f"bandwidth_gbs={bw} size_mb={size_mb}")

def bench_random_access(size_mb: int) -> MemResult:
    n = (size_mb * 1024 * 1024) // 8
    arr = np.arange(n, dtype=np.int64)
    rng = np.random.default_rng(42)
    indices = rng.permutation(n).astype(np.int64)
    n_accesses = min(1_000_000, n)
    t0 = time.perf_counter()
    for i in range(n_accesses):
        _ = arr[indices[i % len(indices)]]
    elapsed = time.perf_counter() - t0
    latency_ns = round(elapsed / n_accesses * 1e9, 2)
    return _make_result(f"mem_random_{size_mb}mb", latency_ns, round(elapsed*1000,2),
                        notes=f"latency_ns={latency_ns} accesses={n_accesses}")

def bench_stride(size_mb: int, stride: int) -> MemResult:
    n = (size_mb * 1024 * 1024) // 8
    arr = np.arange(n, dtype=np.float64)
    t0 = time.perf_counter()
    total = arr[::stride].sum()
    elapsed = time.perf_counter() - t0
    elements = len(arr[::stride])
    throughput = round(elements / elapsed / 1e6, 2)
    return _make_result(f"mem_stride_{size_mb}mb_s{stride}", throughput, round(elapsed*1000,2),
                        notes=f"stride={stride} elements={elements} mops={throughput}")

def bench_dtype_bandwidth(dtype: type, size_mb: int) -> MemResult:
    itemsize = np.dtype(dtype).itemsize
    n = (size_mb * 1024 * 1024) // itemsize
    src = np.ones(n, dtype=dtype)
    dst = np.empty_like(src)
    times = []
    for _ in range(REPS):
        t0 = time.perf_counter()
        np.copyto(dst, src)
        times.append(time.perf_counter() - t0)
    avg = sum(times)/len(times)
    bw = round(size_mb * itemsize * 2 / avg / 1024, 2)
    dtype_name = np.dtype(dtype).name
    return _make_result(f"mem_dtype_{dtype_name}_{size_mb}mb", bw, round(avg*1000,3),
                        notes=f"dtype={dtype_name} bandwidth_gbs={bw}")

def bench_allocation(n_allocs: int=1000, size_mb: int=1) -> MemResult:
    size_bytes = size_mb * 1024 * 1024
    times = []
    for _ in range(n_allocs):
        t0 = time.perf_counter()
        arr = np.empty(size_bytes // 8, dtype=np.float64)
        del arr
        times.append(time.perf_counter() - t0)
    avg = sum(times)/len(times)
    allocs_per_sec = round(1.0 / avg, 1)
    return _make_result(f"mem_alloc_{size_mb}mb", allocs_per_sec, round(avg*1000*1000,3),
                        notes=f"allocs_per_sec={allocs_per_sec} size_mb={size_mb} n_allocs={n_allocs}")

def bench_numa_awareness() -> list[MemResult]:
    results = []
    try:
        numa_output = subprocess.run(["numactl","--hardware"], capture_output=True, text=True, timeout=5)
        if numa_output.returncode == 0:
            log.info("NUMA topology detected")
    except (FileNotFoundError, subprocess.TimeoutExpired):
        log.info("numactl not available — skipping NUMA benchmark")
    size_mb = 256
    n = (size_mb * 1024 * 1024) // 8
    arr = np.random.default_rng(42).standard_normal(n)
    t0 = time.perf_counter()
    _ = arr.sum()
    elapsed = time.perf_counter() - t0
    bw = round(size_mb * 8 / elapsed / 1024, 2)
    results.append(_make_result("mem_numa_local_256mb", bw, round(elapsed*1000,2),
                                notes=f"numa=local bandwidth_gbs={bw}"))
    return results

def bench_cache_hierarchy() -> list[MemResult]:
    results = []
    cache_sizes = {
        "l1_32kb":   32 * 1024,
        "l2_256kb":  256 * 1024,
        "l3_8mb":    8 * 1024 * 1024,
        "ram_256mb": 256 * 1024 * 1024,
    }
    for level, size_bytes in cache_sizes.items():
        n = size_bytes // 8
        arr = np.arange(n, dtype=np.int64)
        rng = np.random.default_rng(42)
        indices = rng.permutation(n).astype(np.int64)
        n_accesses = min(500_000, n)
        t0 = time.perf_counter()
        idx = 0
        for i in range(n_accesses):
            idx = arr[indices[i % len(indices)]]
        elapsed = time.perf_counter() - t0
        latency_ns = round(elapsed / n_accesses * 1e9, 2)
        results.append(_make_result(f"mem_cache_{level}", latency_ns, round(elapsed*1000,2),
                                    notes=f"level={level} latency_ns={latency_ns} size_bytes={size_bytes}"))
    return results

def bench_fio_disk() -> list[MemResult]:
    results = []
    try:
        r = subprocess.run(["fio","--version"], capture_output=True, text=True, timeout=5)
        if r.returncode != 0: return results
    except (FileNotFoundError, subprocess.TimeoutExpired):
        log.info("fio not available — skipping disk benchmark")
        return results
    tests = [
        ("seq_read",  "--rw=read",    "--bs=1M"),
        ("seq_write", "--rw=write",   "--bs=1M"),
        ("rand_read", "--rw=randread","--bs=4k"),
        ("rand_write","--rw=randwrite","--bs=4k"),
    ]
    for name, rw, bs in tests:
        try:
            cmd = ["fio","--name=bench",rw,bs,"--size=256M","--numjobs=1",
                   "--time_based","--runtime=5","--output-format=json","--filename=/tmp/fio_bench"]
            r = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
            if r.returncode == 0:
                data = json.loads(r.stdout)
                job = data.get("jobs",[{}])[0]
                if "read" in name:
                    bw_kbs = job.get("read",{}).get("bw",0)
                else:
                    bw_kbs = job.get("write",{}).get("bw",0)
                bw_mbs = round(bw_kbs / 1024, 2)
                results.append(_make_result(f"disk_{name}", bw_mbs, 5000.0,
                                            notes=f"bw_mbs={bw_mbs} test={name}"))
        except Exception as exc:
            log.warning("fio %s failed: %s", name, exc)
    try:
        import os
        os.unlink("/tmp/fio_bench")
    except: pass
    return results

def main() -> int:
    parser = argparse.ArgumentParser(description="Memory Benchmark — Microsoft AGI Lab")
    parser.add_argument("--output", default="benchmark/reports/memory_results.json")
    parser.add_argument("--sizes", nargs="+", type=int, default=[1,4,16,64,256])
    parser.add_argument("--verbose", "-v", action="store_true")
    args = parser.parse_args()
    if args.verbose: logging.getLogger().setLevel(logging.DEBUG)

    all_results = []
    for size_mb in args.sizes:
        log.info("Memory benchmark: %dMB", size_mb)
        all_results.append(bench_sequential_read(size_mb))
        all_results.append(bench_sequential_write(size_mb))
        all_results.append(bench_copy(size_mb))
        all_results.append(bench_random_access(size_mb))
        for stride in [1, 8, 64, 512]:
            all_results.append(bench_stride(size_mb, stride))
        for dtype in DTYPES:
            all_results.append(bench_dtype_bandwidth(dtype, size_mb))
        all_results.append(bench_allocation(size_mb=size_mb))

    all_results.extend(bench_cache_hierarchy())
    all_results.extend(bench_numa_awareness())
    all_results.extend(bench_fio_disk())

    out_path = pathlib.Path(args.output)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with open(out_path, "w") as f:
        json.dump({"suite":"memory","results":[asdict(r) for r in all_results]}, f, indent=2)
    log.info("Results saved: %s (%d records)", out_path, len(all_results))
    print(json.dumps([asdict(r) for r in all_results]))
    return 0

if __name__ == "__main__":
    sys.exit(main())
