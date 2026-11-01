# =============================================================================
# Windows AGI Benchmark Lab — Master Benchmark Runner
# Copyright (c) 2026 Microsoft Corporation. All Rights Reserved.
# =============================================================================

"""
Master benchmark runner for the Windows AGI Benchmark Lab.

Orchestrates all benchmark modules across GPU vendors, AI runtimes,
CPU architectures, and system metrics. Produces CSV, JSON, and chart outputs.

Usage:
    python benchmark/runner.py --full --export csv json --charts
    python benchmark/runner.py --suite ollama --model llama3
    python benchmark/runner.py --suite pytorch --device cuda
"""

from __future__ import annotations

import argparse
import csv
import datetime
import json
import logging
import os
import pathlib
import platform
import subprocess
import sys
import time
import traceback
import uuid
from dataclasses import asdict, dataclass, field
from typing import Any

import psutil

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)-8s | %(name)s | %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
    handlers=[
        logging.StreamHandler(sys.stdout),
    ],
)
log = logging.getLogger("agi.runner")

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
VERSION = "1.0.0"
PROJECT = "Windows AGI Benchmark Lab"
VENDOR = "Microsoft Corporation"
REPORT_DIR = pathlib.Path(os.environ.get("REPORT_DIR", "benchmark/reports"))
LOG_DIR = pathlib.Path(os.environ.get("LOG_DIR", "benchmark/logs"))

SUITES = [
    "ollama",
    "vllm",
    "onnx",
    "llamacpp",
    "pytorch",
    "tensorflow",
    "tensorrt",
    "cpu",
    "memory",
    "disk",
    "network",
    "gpu_amd",
    "gpu_nvidia",
    "assembly",
    "agents",
]

MODELS = [
    "llama3",
    "llama3:8b",
    "llama3:70b",
    "phi4",
    "phi3",
    "mistral",
    "mixtral",
    "gemma2",
    "qwen2",
    "deepseek-r1",
    "codellama",
    "nomic-embed-text",
]

PROMPTS = {
    "short": "Hello, what is 2+2?",
    "medium": "Explain the difference between supervised and unsupervised machine learning in 3 paragraphs.",
    "long": (
        "Write a comprehensive technical analysis of distributed AI inference architectures, "
        "covering model parallelism, tensor parallelism, pipeline parallelism, and their "
        "trade-offs in terms of latency, throughput, memory efficiency, and hardware utilization. "
        "Include specific examples for transformer-based large language models with billions of parameters."
    ),
    "code": (
        "Write a complete Python implementation of a multi-threaded HTTP server with "
        "connection pooling, request routing, middleware support, and graceful shutdown. "
        "Include full error handling, logging, and unit tests."
    ),
    "math": (
        "Solve the following problems step by step: "
        "1) Find all eigenvalues and eigenvectors of the matrix [[4,1],[2,3]]. "
        "2) Compute the integral of x^3 * sin(x) from 0 to pi. "
        "3) Prove that the sum of the first n odd numbers equals n^2."
    ),
}


# ---------------------------------------------------------------------------
# Data Models
# ---------------------------------------------------------------------------
@dataclass
class SystemInfo:
    """Host system information snapshot."""

    run_id: str
    timestamp: str
    hostname: str
    os_name: str
    os_version: str
    kernel: str
    python_version: str
    cpu_model: str
    cpu_cores_physical: int
    cpu_cores_logical: int
    cpu_freq_mhz: float
    ram_total_gb: float
    ram_available_gb: float
    disk_total_gb: float
    disk_free_gb: float
    gpu_vendor: str
    gpu_model: str
    gpu_vram_gb: float
    wsl2: bool
    docker: bool
    rocm_version: str
    cuda_version: str

    @classmethod
    def collect(cls) -> "SystemInfo":
        """Collect current system information."""
        run_id = str(uuid.uuid4())[:8]
        timestamp = datetime.datetime.utcnow().isoformat() + "Z"

        # CPU
        cpu_freq = psutil.cpu_freq()
        freq_mhz = cpu_freq.current if cpu_freq else 0.0

        try:
            import cpuinfo  # type: ignore[import]
            cpu_model = cpuinfo.get_cpu_info().get("brand_raw", platform.processor())
        except ImportError:
            cpu_model = platform.processor()

        # RAM
        mem = psutil.virtual_memory()
        ram_total = round(mem.total / (1024**3), 2)
        ram_avail = round(mem.available / (1024**3), 2)

        # Disk
        disk = psutil.disk_usage("/")
        disk_total = round(disk.total / (1024**3), 2)
        disk_free = round(disk.free / (1024**3), 2)

        # GPU detection
        gpu_vendor, gpu_model, gpu_vram, rocm_ver, cuda_ver = _detect_gpu()

        # WSL2 detection
        is_wsl2 = "microsoft" in platform.uname().release.lower()

        # Docker detection
        is_docker = pathlib.Path("/.dockerenv").exists()

        return cls(
            run_id=run_id,
            timestamp=timestamp,
            hostname=platform.node(),
            os_name=platform.system(),
            os_version=platform.version(),
            kernel=platform.release(),
            python_version=platform.python_version(),
            cpu_model=cpu_model,
            cpu_cores_physical=psutil.cpu_count(logical=False) or 0,
            cpu_cores_logical=psutil.cpu_count(logical=True) or 0,
            cpu_freq_mhz=round(freq_mhz, 1),
            ram_total_gb=ram_total,
            ram_available_gb=ram_avail,
            disk_total_gb=disk_total,
            disk_free_gb=disk_free,
            gpu_vendor=gpu_vendor,
            gpu_model=gpu_model,
            gpu_vram_gb=gpu_vram,
            wsl2=is_wsl2,
            docker=is_docker,
            rocm_version=rocm_ver,
            cuda_version=cuda_ver,
        )


@dataclass
class BenchmarkResult:
    """Single benchmark result record."""

    run_id: str
    timestamp: str
    suite: str
    benchmark: str
    model: str
    prompt_type: str
    prompt_tokens: int
    output_tokens: int
    ttft_ms: float          # Time to first token (ms)
    total_latency_ms: float # Total response latency (ms)
    tokens_per_sec: float   # Throughput
    vram_used_gb: float     # GPU VRAM used
    ram_used_gb: float      # System RAM used
    gpu_util_pct: float     # GPU utilization %
    cpu_util_pct: float     # CPU utilization %
    power_watts: float      # GPU power draw
    temp_celsius: float     # GPU temperature
    context_length: int     # Context window used
    batch_size: int         # Batch size
    quantization: str       # Model quantization (Q4_K_M, fp16, etc.)
    backend: str            # Execution backend
    device: str             # cuda / rocm / cpu / mps
    gpu_vendor: str         # nvidia / amd / intel / none
    gpu_model: str          # GPU model name
    host_os: str            # Linux / Windows / WSL2
    status: str             # success / error / timeout
    error_message: str      # Error details if failed
    notes: str              # Additional notes


@dataclass
class BenchmarkSuite:
    """Collection of benchmark results for a suite."""

    suite_name: str
    run_id: str
    started_at: str
    finished_at: str
    duration_sec: float
    system_info: SystemInfo
    results: list[BenchmarkResult] = field(default_factory=list)
    errors: list[dict[str, Any]] = field(default_factory=list)

    @property
    def success_count(self) -> int:
        return sum(1 for r in self.results if r.status == "success")

    @property
    def error_count(self) -> int:
        return sum(1 for r in self.results if r.status == "error")

    @property
    def avg_tokens_per_sec(self) -> float:
        vals = [r.tokens_per_sec for r in self.results if r.status == "success" and r.tokens_per_sec > 0]
        return round(sum(vals) / len(vals), 2) if vals else 0.0

    @property
    def avg_ttft_ms(self) -> float:
        vals = [r.ttft_ms for r in self.results if r.status == "success" and r.ttft_ms > 0]
        return round(sum(vals) / len(vals), 2) if vals else 0.0


# ---------------------------------------------------------------------------
# GPU Detection
# ---------------------------------------------------------------------------
def _detect_gpu() -> tuple[str, str, float, str, str]:
    """Detect GPU vendor, model, VRAM, ROCm version, CUDA version."""
    gpu_vendor = "none"
    gpu_model = "unknown"
    gpu_vram = 0.0
    rocm_ver = "n/a"
    cuda_ver = "n/a"

    # Try NVIDIA
    try:
        result = subprocess.run(
            ["nvidia-smi",
             "--query-gpu=name,memory.total",
             "--format=csv,noheader,nounits"],
            capture_output=True, text=True, timeout=5
        )
        if result.returncode == 0 and result.stdout.strip():
            parts = result.stdout.strip().split(",")
            gpu_vendor = "nvidia"
            gpu_model = parts[0].strip()
            gpu_vram = round(float(parts[1].strip()) / 1024, 2)

        # CUDA version
        cuda_result = subprocess.run(
            ["nvcc", "--version"],
            capture_output=True, text=True, timeout=5
        )
        if cuda_result.returncode == 0:
            for line in cuda_result.stdout.splitlines():
                if "release" in line.lower():
                    cuda_ver = line.split("release")[-1].strip().split(",")[0].strip()
                    break
    except (FileNotFoundError, subprocess.TimeoutExpired, ValueError):
        pass

    # Try AMD ROCm
    if gpu_vendor == "none":
        try:
            result = subprocess.run(
                ["rocm-smi", "--showproductname", "--json"],
                capture_output=True, text=True, timeout=5
            )
            if result.returncode == 0:
                data = json.loads(result.stdout)
                for card_data in data.values():
                    if isinstance(card_data, dict):
                        gpu_vendor = "amd"
                        gpu_model = card_data.get("Card series", "AMD GPU")
                        break

            # VRAM
            vram_result = subprocess.run(
                ["rocm-smi", "--showmeminfo", "vram", "--json"],
                capture_output=True, text=True, timeout=5
            )
            if vram_result.returncode == 0:
                vram_data = json.loads(vram_result.stdout)
                for card_data in vram_data.values():
                    if isinstance(card_data, dict):
                        total = card_data.get("VRAM Total Memory (B)", 0)
                        gpu_vram = round(int(total) / (1024**3), 2)
                        break

            # ROCm version
            rocm_result = subprocess.run(
                ["rocminfo"],
                capture_output=True, text=True, timeout=10
            )
            if rocm_result.returncode == 0:
                for line in rocm_result.stdout.splitlines():
                    if "ROCm" in line and "Version" in line:
                        rocm_ver = line.split(":")[-1].strip()
                        break
        except (FileNotFoundError, subprocess.TimeoutExpired, json.JSONDecodeError, ValueError):
            pass

    return gpu_vendor, gpu_model, gpu_vram, rocm_ver, cuda_ver


# ---------------------------------------------------------------------------
# Individual Suite Runners
# ---------------------------------------------------------------------------
def _run_subprocess_suite(
    name: str,
    script: str,
    args: list[str],
    run_id: str,
    system_info: SystemInfo,
) -> BenchmarkSuite:
    """Run a benchmark suite as a subprocess and collect results."""
    started = datetime.datetime.utcnow().isoformat() + "Z"
    t0 = time.perf_counter()

    suite = BenchmarkSuite(
        suite_name=name,
        run_id=run_id,
        started_at=started,
        finished_at="",
        duration_sec=0.0,
        system_info=system_info,
    )

    cmd = [sys.executable, script] + args
    log.info("Running suite: %s → %s", name, " ".join(cmd))

    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=600,
        )

        if result.returncode == 0:
            # Try to parse JSON output from subprocess
            try:
                output_data = json.loads(result.stdout)
                if isinstance(output_data, list):
                    for item in output_data:
                        item["run_id"] = run_id
                        item["suite"] = name
                        suite.results.append(_dict_to_result(item))
                elif isinstance(output_data, dict) and "results" in output_data:
                    for item in output_data["results"]:
                        item["run_id"] = run_id
                        item["suite"] = name
                        suite.results.append(_dict_to_result(item))
            except json.JSONDecodeError:
                # Subprocess didn't return JSON — create a summary result
                suite.results.append(_make_summary_result(
                    run_id=run_id,
                    suite=name,
                    benchmark=name,
                    status="success",
                    notes=result.stdout[:500],
                    system_info=system_info,
                ))
        else:
            suite.errors.append({
                "suite": name,
                "returncode": result.returncode,
                "stderr": result.stderr[:1000],
            })
            suite.results.append(_make_summary_result(
                run_id=run_id,
                suite=name,
                benchmark=name,
                status="error",
                error_message=result.stderr[:500],
                system_info=system_info,
            ))

    except subprocess.TimeoutExpired:
        log.warning("Suite %s timed out after 600s", name)
        suite.errors.append({"suite": name, "error": "timeout"})
        suite.results.append(_make_summary_result(
            run_id=run_id,
            suite=name,
            benchmark=name,
            status="timeout",
            error_message="Subprocess timed out after 600 seconds",
            system_info=system_info,
        ))
    except Exception as exc:
        log.error("Suite %s failed: %s", name, exc)
        suite.errors.append({"suite": name, "error": str(exc)})
        suite.results.append(_make_summary_result(
            run_id=run_id,
            suite=name,
            benchmark=name,
            status="error",
            error_message=str(exc),
            system_info=system_info,
        ))

    elapsed = time.perf_counter() - t0
    suite.finished_at = datetime.datetime.utcnow().isoformat() + "Z"
    suite.duration_sec = round(elapsed, 3)

    log.info(
        "Suite %s complete: %d results, %d errors, %.1fs",
        name, len(suite.results), len(suite.errors), elapsed
    )
    return suite


def _dict_to_result(d: dict[str, Any]) -> BenchmarkResult:
    """Convert a dictionary to a BenchmarkResult, filling defaults."""
    defaults: dict[str, Any] = {
        "run_id": "",
        "timestamp": datetime.datetime.utcnow().isoformat() + "Z",
        "suite": "",
        "benchmark": "",
        "model": "",
        "prompt_type": "",
        "prompt_tokens": 0,
        "output_tokens": 0,
        "ttft_ms": 0.0,
        "total_latency_ms": 0.0,
        "tokens_per_sec": 0.0,
        "vram_used_gb": 0.0,
        "ram_used_gb": 0.0,
        "gpu_util_pct": 0.0,
        "cpu_util_pct": 0.0,
        "power_watts": 0.0,
        "temp_celsius": 0.0,
        "context_length": 0,
        "batch_size": 1,
        "quantization": "unknown",
        "backend": "unknown",
        "device": "unknown",
        "gpu_vendor": "unknown",
        "gpu_model": "unknown",
        "host_os": platform.system(),
        "status": "success",
        "error_message": "",
        "notes": "",
    }
    defaults.update(d)
    return BenchmarkResult(**{k: defaults[k] for k in BenchmarkResult.__dataclass_fields__})


def _make_summary_result(
    run_id: str,
    suite: str,
    benchmark: str,
    status: str,
    system_info: SystemInfo,
    error_message: str = "",
    notes: str = "",
) -> BenchmarkResult:
    """Create a minimal summary result record."""
    return BenchmarkResult(
        run_id=run_id,
        timestamp=datetime.datetime.utcnow().isoformat() + "Z",
        suite=suite,
        benchmark=benchmark,
        model="",
        prompt_type="",
        prompt_tokens=0,
        output_tokens=0,
        ttft_ms=0.0,
        total_latency_ms=0.0,
        tokens_per_sec=0.0,
        vram_used_gb=0.0,
        ram_used_gb=0.0,
        gpu_util_pct=0.0,
        cpu_util_pct=0.0,
        power_watts=0.0,
        temp_celsius=0.0,
        context_length=0,
        batch_size=1,
        quantization="",
        backend="",
        device="",
        gpu_vendor=system_info.gpu_vendor,
        gpu_model=system_info.gpu_model,
        host_os=system_info.os_name,
        status=status,
        error_message=error_message,
        notes=notes,
    )


# ---------------------------------------------------------------------------
# Export Functions
# ---------------------------------------------------------------------------
def export_csv(all_results: list[BenchmarkResult], path: pathlib.Path) -> None:
    """Export all results to CSV."""
    if not all_results:
        log.warning("No results to export to CSV.")
        return

    path.parent.mkdir(parents=True, exist_ok=True)
    fieldnames = list(BenchmarkResult.__dataclass_fields__.keys())

    with open(path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        for r in all_results:
            writer.writerow(asdict(r))

    log.info("CSV exported: %s (%d rows)", path, len(all_results))


def export_json(
    all_results: list[BenchmarkResult],
    system_info: SystemInfo,
    path: pathlib.Path,
) -> None:
    """Export all results to JSON."""
    path.parent.mkdir(parents=True, exist_ok=True)

    payload = {
        "meta": {
            "project": PROJECT,
            "vendor": VENDOR,
            "version": VERSION,
            "exported_at": datetime.datetime.utcnow().isoformat() + "Z",
            "total_results": len(all_results),
        },
        "system": asdict(system_info),
        "results": [asdict(r) for r in all_results],
    }

    with open(path, "w", encoding="utf-8") as f:
        json.dump(payload, f, indent=2, ensure_ascii=False)

    log.info("JSON exported: %s (%d results)", path, len(all_results))


def export_summary(
    suites: list[BenchmarkSuite],
    system_info: SystemInfo,
    path: pathlib.Path,
) -> None:
    """Export a human-readable summary JSON."""
    path.parent.mkdir(parents=True, exist_ok=True)

    summary = {
        "project": PROJECT,
        "vendor": VENDOR,
        "version": VERSION,
        "run_date": datetime.datetime.utcnow().isoformat() + "Z",
        "system": {
            "hostname": system_info.hostname,
            "os": system_info.os_name,
            "cpu": system_info.cpu_model,
            "cores": system_info.cpu_cores_logical,
            "ram_gb": system_info.ram_total_gb,
            "gpu_vendor": system_info.gpu_vendor,
            "gpu_model": system_info.gpu_model,
            "gpu_vram_gb": system_info.gpu_vram_gb,
            "wsl2": system_info.wsl2,
            "rocm": system_info.rocm_version,
            "cuda": system_info.cuda_version,
        },
        "suites": [
            {
                "name": s.suite_name,
                "duration_sec": s.duration_sec,
                "results": s.success_count,
                "errors": s.error_count,
                "avg_tokens_per_sec": s.avg_tokens_per_sec,
                "avg_ttft_ms": s.avg_ttft_ms,
            }
            for s in suites
        ],
        "totals": {
            "suites_run": len(suites),
            "total_results": sum(s.success_count for s in suites),
            "total_errors": sum(s.error_count for s in suites),
        },
    }

    with open(path, "w", encoding="utf-8") as f:
        json.dump(summary, f, indent=2)

    log.info("Summary exported: %s", path)


# ---------------------------------------------------------------------------
# Main Runner
# ---------------------------------------------------------------------------
class BenchmarkRunner:
    """Master benchmark orchestrator."""

    def __init__(
        self,
        suites: list[str],
        models: list[str],
        export_formats: list[str],
        generate_charts: bool,
        report_dir: pathlib.Path,
        verbose: bool = False,
    ) -> None:
        self.suites = suites
        self.models = models
        self.export_formats = export_formats
        self.generate_charts = generate_charts
        self.report_dir = report_dir
        self.verbose = verbose
        self.run_id = str(uuid.uuid4())[:8]
        self.system_info = SystemInfo.collect()

        if verbose:
            logging.getLogger().setLevel(logging.DEBUG)

    def _print_header(self) -> None:
        """Print run header."""
        print("\n" + "=" * 70)
        print(f"  {PROJECT}")
        print(f"  {VENDOR} — Exclusive License")
        print(f"  Version: {VERSION}")
        print("=" * 70)
        print(f"  Run ID:      {self.run_id}")
        print(f"  Timestamp:   {self.system_info.timestamp}")
        print(f"  Host:        {self.system_info.hostname}")
        print(f"  OS:          {self.system_info.os_name} {self.system_info.kernel}")
        print(f"  WSL2:        {self.system_info.wsl2}")
        print(f"  CPU:         {self.system_info.cpu_model}")
        print(f"  Cores:       {self.system_info.cpu_cores_physical}P / {self.system_info.cpu_cores_logical}L")
        print(f"  RAM:         {self.system_info.ram_total_gb} GB")
        print(f"  GPU Vendor:  {self.system_info.gpu_vendor.upper()}")
        print(f"  GPU Model:   {self.system_info.gpu_model}")
        print(f"  GPU VRAM:    {self.system_info.gpu_vram_gb} GB")
        print(f"  ROCm:        {self.system_info.rocm_version}")
        print(f"  CUDA:        {self.system_info.cuda_version}")
        print(f"  Suites:      {', '.join(self.suites)}")
        print(f"  Models:      {', '.join(self.models)}")
        print(f"  Export:      {', '.join(self.export_formats)}")
        print(f"  Charts:      {self.generate_charts}")
        print("=" * 70 + "\n")

    def run(self) -> list[BenchmarkSuite]:
        """Execute all configured benchmark suites."""
        self._print_header()

        all_suites: list[BenchmarkSuite] = []
        all_results: list[BenchmarkResult] = []

        suite_scripts = {
            "ollama":      ("benchmark/benchmark_ollama.py",    ["--models"] + self.models),
            "vllm":        ("benchmark/benchmark_vllm.py",      ["--models"] + self.models),
            "onnx":        ("benchmark/benchmark_onnx.py",      []),
            "llamacpp":    ("benchmark/benchmark_llamacpp.py",  []),
            "pytorch":     ("benchmark/benchmark_pytorch.py",   []),
            "tensorflow":  ("benchmark/benchmark_tensorflow.py",[]),
            "tensorrt":    ("benchmark/benchmark_tensorrt.py",  []),
            "cpu":         ("benchmark/benchmark_cpu.py",       []),
            "memory":      ("benchmark/benchmark_memory.py",    []),
            "disk":        ("benchmark/benchmark_disk.py",      []),
            "network":     ("benchmark/benchmark_network.py",   []),
            "gpu_amd":     ("collectors/amd_rocm.py",           ["--benchmark"]),
            "gpu_nvidia":  ("collectors/nvidia_cuda.py",        ["--benchmark"]),
            "assembly":    ("benchmark/benchmark_assembly.py",  []),
            "agents":      ("benchmark/benchmark_agents.py",    []),
        }

        for suite_name in self.suites:
            if suite_name not in suite_scripts:
                log.warning("Unknown suite: %s — skipping", suite_name)
                continue

            script, args = suite_scripts[suite_name]
            script_path = pathlib.Path(script)

            if not script_path.exists():
                log.warning("Script not found: %s — skipping suite %s", script, suite_name)
                # Create a placeholder result
                suite = BenchmarkSuite(
                    suite_name=suite_name,
                    run_id=self.run_id,
                    started_at=datetime.datetime.utcnow().isoformat() + "Z",
                    finished_at=datetime.datetime.utcnow().isoformat() + "Z",
                    duration_sec=0.0,
                    system_info=self.system_info,
                )
                suite.results.append(_make_summary_result(
                    run_id=self.run_id,
                    suite=suite_name,
                    benchmark=suite_name,
                    status="skipped",
                    system_info=self.system_info,
                    notes=f"Script {script} not found",
                ))
                all_suites.append(suite)
                continue

            suite = _run_subprocess_suite(
                name=suite_name,
                script=script,
                args=args,
                run_id=self.run_id,
                system_info=self.system_info,
            )
            all_suites.append(suite)
            all_results.extend(suite.results)

        # Export results
        self._export(all_results, all_suites)

        # Generate charts
        if self.generate_charts:
            self._generate_charts()

        # Print summary
        self._print_summary(all_suites)

        return all_suites

    def _export(
        self,
        all_results: list[BenchmarkResult],
        all_suites: list[BenchmarkSuite],
    ) -> None:
        """Export results in configured formats."""
        ts = datetime.datetime.utcnow().strftime("%Y%m%d_%H%M%S")
        self.report_dir.mkdir(parents=True, exist_ok=True)

        if "csv" in self.export_formats:
            export_csv(all_results, self.report_dir / f"benchmark_{ts}.csv")
            export_csv(all_results, self.report_dir / "benchmark_latest.csv")

        if "json" in self.export_formats:
            export_json(all_results, self.system_info, self.report_dir / f"benchmark_{ts}.json")
            export_json(all_results, self.system_info, self.report_dir / "benchmark_latest.json")

        export_summary(all_suites, self.system_info, self.report_dir / "summary_latest.json")

    def _generate_charts(self) -> None:
        """Invoke chart generation script."""
        chart_script = pathlib.Path("benchmark/generate_charts.py")
        if chart_script.exists():
            log.info("Generating charts...")
            try:
                subprocess.run(
                    [sys.executable, str(chart_script),
                     "--input", str(self.report_dir / "benchmark_latest.csv"),
                     "--output", str(self.report_dir)],
                    timeout=120,
                    check=False,
                )
            except subprocess.TimeoutExpired:
                log.warning("Chart generation timed out.")
        else:
            log.warning("Chart script not found: %s", chart_script)

    def _print_summary(self, suites: list[BenchmarkSuite]) -> None:
        """Print final summary table."""
        print("\n" + "=" * 70)
        print("  BENCHMARK SUMMARY")
        print("=" * 70)
        print(f"  {'Suite':<20} {'Results':>8} {'Errors':>8} {'Tok/s':>10} {'TTFT ms':>10} {'Duration':>10}")
        print("  " + "-" * 68)
        for s in suites:
            print(
                f"  {s.suite_name:<20} "
                f"{s.success_count:>8} "
                f"{s.error_count:>8} "
                f"{s.avg_tokens_per_sec:>10.1f} "
                f"{s.avg_ttft_ms:>10.1f} "
                f"{s.duration_sec:>9.1f}s"
            )
        print("  " + "-" * 68)
        total_results = sum(s.success_count for s in suites)
        total_errors = sum(s.error_count for s in suites)
        total_duration = sum(s.duration_sec for s in suites)
        print(f"  {'TOTAL':<20} {total_results:>8} {total_errors:>8} {'':>10} {'':>10} {total_duration:>9.1f}s")
        print("=" * 70)
        print(f"\n  Reports saved to: {self.report_dir.resolve()}")
        print(f"  Run ID: {self.run_id}")
        print(f"  {VENDOR} — {PROJECT} v{VERSION}")
        print()


# ---------------------------------------------------------------------------
# CLI Entry Point
# ---------------------------------------------------------------------------
def build_parser() -> argparse.ArgumentParser:
    """Build CLI argument parser."""
    parser = argparse.ArgumentParser(
        prog="agi-bench",
        description=f"{PROJECT} — {VENDOR}",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Run full benchmark suite
  python benchmark/runner.py --full

  # Run specific suites
  python benchmark/runner.py --suite ollama pytorch

  # Run with specific models
  python benchmark/runner.py --suite ollama --models llama3 phi4

  # Export to CSV and JSON with charts
  python benchmark/runner.py --full --export csv json --charts

  # Quick smoke test
  python benchmark/runner.py --suite cpu memory --export json
        """,
    )

    parser.add_argument(
        "--full",
        action="store_true",
        help="Run all benchmark suites",
    )
    parser.add_argument(
        "--suite",
        nargs="+",
        choices=SUITES,
        metavar="SUITE",
        help=f"Suites to run: {', '.join(SUITES)}",
    )
    parser.add_argument(
        "--models",
        nargs="+",
        default=["llama3", "phi4"],
        metavar="MODEL",
        help="LLM models to benchmark",
    )
    parser.add_argument(
        "--export",
        nargs="+",
        choices=["csv", "json"],
        default=["csv", "json"],
        metavar="FORMAT",
        help="Export formats: csv, json",
    )
    parser.add_argument(
        "--charts",
        action="store_true",
        help="Generate benchmark charts",
    )
    parser.add_argument(
        "--report-dir",
        type=pathlib.Path,
        default=REPORT_DIR,
        help="Directory for reports",
    )
    parser.add_argument(
        "--verbose", "-v",
        action="store_true",
        help="Verbose logging",
    )
    parser.add_argument(
        "--version",
        action="version",
        version=f"%(prog)s {VERSION} — {VENDOR}",
    )

    return parser


def main() -> int:
    """CLI entry point."""
    parser = build_parser()
    args = parser.parse_args()

    # Determine suites to run
    if args.full:
        selected_suites = SUITES
    elif args.suite:
        selected_suites = args.suite
    else:
        # Default: run lightweight suites
        selected_suites = ["cpu", "memory", "ollama"]
        log.info("No suite specified. Running default suites: %s", selected_suites)

    runner = BenchmarkRunner(
        suites=selected_suites,
        models=args.models,
        export_formats=args.export,
        generate_charts=args.charts,
        report_dir=args.report_dir,
        verbose=args.verbose,
    )

    try:
        runner.run()
        return 0
    except KeyboardInterrupt:
        log.info("Benchmark interrupted by user.")
        return 130
    except Exception as exc:
        log.error("Fatal error: %s", exc)
        if args.verbose:
            traceback.print_exc()
        return 1


if __name__ == "__main__":
    sys.exit(main())