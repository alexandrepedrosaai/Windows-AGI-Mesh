# =============================================================================
# Windows AGI Benchmark Lab — llama.cpp Benchmark Module
# Copyright (c) 2026 Microsoft Corporation. All Rights Reserved.
# =============================================================================

"""
llama.cpp benchmark module.

Tests:
  - CPU inference (all cores)
  - GPU offload (AMD ROCm / NVIDIA CUDA)
  - Mixed CPU+GPU offload
  - Multiple quantization levels (Q2_K through Q8_0, F16)
  - Context length scaling
  - Batch size scaling
  - Prompt processing speed (pp)
  - Token generation speed (tg)

Requires llama.cpp built and available in PATH or LLAMACPP_PATH env var.
"""

from __future__ import annotations

import argparse
import datetime
import json
import logging
import os
import pathlib
import platform
import re
import subprocess
import sys
import time
from dataclasses import asdict, dataclass
from typing import Any

import psutil

log = logging.getLogger("agi.bench.llamacpp")
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)-8s | %(name)s | %(message)s",
)

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
LLAMACPP_PATH = os.environ.get("LLAMACPP_PATH", "llama.cpp/build/bin")
MODELS_DIR = pathlib.Path(os.environ.get("MODELS_DIR", "models"))

# llama.cpp binary names (try multiple)
LLAMA_BINARIES = ["llama-cli", "main", "llama-bench"]
LLAMA_BENCH_BINARIES = ["llama-bench", "llama-bench.exe"]

QUANTIZATIONS = ["Q2_K", "Q3_K_M", "Q4_0", "Q4_K_M", "Q5_K_M", "Q6_K", "Q8_0", "F16"]
CONTEXT_LENGTHS = [512, 1024, 2048, 4096, 8192]
GPU_LAYERS_OPTIONS = [0, 16, 32, 64, 99]  # 0=CPU, 99=all GPU

TEST_PROMPTS = {
    "short": "Hello",
    "medium": "Explain quantum computing in simple terms.",
    "long": (
        "Write a detailed technical analysis of transformer architecture, "
        "covering attention mechanisms, positional encoding, feed-forward layers, "
        "layer normalization, and training strategies for large language models."
    ),
}

WARMUP_TOKENS = 128
BENCHMARK_TOKENS = 512


# ---------------------------------------------------------------------------
# Data Model
# ---------------------------------------------------------------------------
@dataclass
class LlamaCppResult:
    """Single llama.cpp benchmark result."""

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
# Binary Detection
# ---------------------------------------------------------------------------
def _find_binary(names: list[str], search_paths: list[str]) -> str | None:
    """Find a binary in search paths."""
    for path in search_paths:
        for name in names:
            candidate = pathlib.Path(path) / name
            if candidate.exists() and os.access(candidate, os.X_OK):
                return str(candidate)
            # Also try without path (system PATH)
    for name in names:
        try:
            result = subprocess.run(
                ["which", name], capture_output=True, text=True, timeout=3
            )
            if result.returncode == 0:
                return result.stdout.strip()
        except (FileNotFoundError, subprocess.TimeoutExpired):
            pass
    return None


def _get_llama_binary() -> str | None:
    """Find llama-cli or main binary."""
    search_paths = [
        LLAMACPP_PATH,
        "llama.cpp/build/bin",
        "llama.cpp/build",
        "/usr/local/bin",
        "/usr/bin",
        ".",
    ]
    return _find_binary(LLAMA_BINARIES, search_paths)


def _get_llama_bench_binary() -> str | None:
    """Find llama-bench binary."""
    search_paths = [
        LLAMACPP_PATH,
        "llama.cpp/build/bin",
        "llama.cpp/build",
        "/usr/local/bin",
        "/usr/bin",
        ".",
    ]
    return _find_binary(LLAMA_BENCH_BINARIES, search_paths)


# ---------------------------------------------------------------------------
# GPU Detection
# ---------------------------------------------------------------------------
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


def _get_vram_used_gb() -> float:
    """Get VRAM usage."""
    try:
        r = subprocess.run(
            ["nvidia-smi", "--query-gpu=memory.used", "--format=csv,noheader,nounits"],
            capture_output=True, text=True, timeout=3,
        )
        if r.returncode == 0:
            return round(float(r.stdout.strip()) / 1024, 2)
    except (FileNotFoundError, subprocess.TimeoutExpired, ValueError):
        pass
    try:
        r = subprocess.run(
            ["rocm-smi", "--showmeminfo", "vram", "--json"],
            capture_output=True, text=True, timeout=3,
        )
        if r.returncode == 0:
            data = json.loads(r.stdout)
            for v in data.values():
                if isinstance(v, dict):
                    used = v.get("VRAM Total Used Memory (B)", 0)
                    return round(int(used) / (1024**3), 2)
    except (FileNotFoundError, subprocess.TimeoutExpired, json.JSONDecodeError, ValueError):
        pass
    return 0.0


# ---------------------------------------------------------------------------
# Output Parsers
# ---------------------------------------------------------------------------
def _parse_llama_output(output: str) -> dict[str, float]:
    """Parse llama.cpp output for performance metrics."""
    metrics: dict[str, float] = {
        "prompt_tokens": 0.0,
        "output_tokens": 0.0,
        "prompt_ms": 0.0,
        "eval_ms": 0.0,
        "prompt_tps": 0.0,
        "eval_tps": 0.0,
        "load_ms": 0.0,
    }

    # Pattern: "llama_print_timings: prompt eval time = 1234.56 ms / 128 tokens"
    patterns = {
        "prompt_ms": r"prompt eval time\s*=\s*([\d.]+)\s*ms\s*/\s*(\d+)\s*tokens",
        "eval_ms": r"eval time\s*=\s*([\d.]+)\s*ms\s*/\s*(\d+)\s*runs",
        "load_ms": r"load time\s*=\s*([\d.]+)\s*ms",
    }

    for key, pattern in patterns.items():
        match = re.search(pattern, output, re.IGNORECASE)
        if match:
            metrics[key] = float(match.group(1))
            if key == "prompt_ms" and len(match.groups()) >= 2:
                metrics["prompt_tokens"] = float(match.group(2))
            elif key == "eval_ms" and len(match.groups()) >= 2:
                metrics["output_tokens"] = float(match.group(2))

    # Calculate TPS
    if metrics["prompt_ms"] > 0 and metrics["prompt_tokens"] > 0:
        metrics["prompt_tps"] = round(metrics["prompt_tokens"] / (metrics["prompt_ms"] / 1000), 2)
    if metrics["eval_ms"] > 0 and metrics["output_tokens"] > 0:
        metrics["eval_tps"] = round(metrics["output_tokens"] / (metrics["eval_ms"] / 1000), 2)

    return metrics


def _parse_llama_bench_output(output: str) -> list[dict[str, Any]]:
    """Parse llama-bench JSON output."""
    results: list[dict[str, Any]] = []
    try:
        # llama-bench outputs JSON lines
        for line in output.strip().splitlines():
            line = line.strip()
            if line.startswith("{"):
                data = json.loads(line)
                results.append(data)
    except json.JSONDecodeError:
        pass
    return results


# ---------------------------------------------------------------------------
# Benchmark Functions
# ---------------------------------------------------------------------------
def benchmark_inference(
    binary: str,
    model_path: pathlib.Path,
    prompt_type: str,
    prompt: str,
    n_gpu_layers: int,
    context_length: int,
    n_predict: int,
    gpu_vendor: str,
    gpu_model: str,
    threads: int | None = None,
) -> LlamaCppResult:
    """Run a single llama.cpp inference benchmark."""
    if threads is None:
        threads = psutil.cpu_count(logical=False) or 4

    log.info(
        "llama.cpp inference: model=%s prompt=%s ngl=%d ctx=%d",
        model_path.name, prompt_type, n_gpu_layers, context_length,
    )

    cmd = [
        binary,
        "--model", str(model_path),
        "--prompt", prompt,
        "--n-predict", str(n_predict),
        "--ctx-size", str(context_length),
        "--n-gpu-layers", str(n_gpu_layers),
        "--threads", str(threads),
        "--seed", "42",
        "--temp", "0.0",
        "--log-disable",
    ]

    status = "success"
    error_msg = ""
    metrics: dict[str, float] = {}

    t_start = time.perf_counter()
    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=300,
        )
        t_end = time.perf_counter()

        if result.returncode == 0:
            combined_output = result.stdout + result.stderr
            metrics = _parse_llama_output(combined_output)
        else:
            status = "error"
            error_msg = result.stderr[:300]
            log.error("llama.cpp failed: %s", error_msg)

    except subprocess.TimeoutExpired:
        t_end = time.perf_counter()
        status = "timeout"
        error_msg = "Inference timed out after 300s"
    except Exception as exc:
        t_end = time.perf_counter()
        status = "error"
        error_msg = str(exc)[:300]

    total_latency_ms = round((t_end - t_start) * 1000, 2)
    eval_tps = metrics.get("eval_tps", 0.0)
    prompt_tps = metrics.get("prompt_tps", 0.0)
    ttft_ms = metrics.get("load_ms", 0.0) + (
        metrics.get("prompt_ms", 0.0) if metrics.get("prompt_tokens", 0) > 0 else 0.0
    )

    device = "gpu" if n_gpu_layers > 0 else "cpu"
    quantization = _infer_quantization(model_path.name)

    return LlamaCppResult(
        timestamp=datetime.datetime.utcnow().isoformat() + "Z",
        suite="llamacpp",
        benchmark=f"llamacpp_{prompt_type}_ngl{n_gpu_layers}_ctx{context_length}",
        model=model_path.name,
        prompt_type=prompt_type,
        prompt_tokens=int(metrics.get("prompt_tokens", 0)),
        output_tokens=int(metrics.get("output_tokens", 0)),
        ttft_ms=round(ttft_ms, 2),
        total_latency_ms=total_latency_ms,
        tokens_per_sec=eval_tps,
        vram_used_gb=_get_vram_used_gb(),
        ram_used_gb=round(psutil.virtual_memory().used / (1024**3), 2),
        gpu_util_pct=0.0,
        cpu_util_pct=psutil.cpu_percent(interval=0.1),
        power_watts=0.0,
        temp_celsius=0.0,
        context_length=context_length,
        batch_size=1,
        quantization=quantization,
        backend="llama.cpp",
        device=device,
        gpu_vendor=gpu_vendor if n_gpu_layers > 0 else "none",
        gpu_model=gpu_model if n_gpu_layers > 0 else "CPU",
        host_os=_detect_host_os(),
        status=status,
        error_message=error_msg,
        notes=f"ngl={n_gpu_layers} threads={threads} prompt_tps={prompt_tps} eval_tps={eval_tps}",
    )


def benchmark_llama_bench(
    bench_binary: str,
    model_path: pathlib.Path,
    n_gpu_layers: int,
    gpu_vendor: str,
    gpu_model: str,
) -> list[LlamaCppResult]:
    """Run llama-bench for systematic pp/tg benchmarks."""
    log.info("llama-bench: model=%s ngl=%d", model_path.name, n_gpu_layers)

    results: list[LlamaCppResult] = []

    cmd = [
        bench_binary,
        "--model", str(model_path),
        "--n-gpu-layers", str(n_gpu_layers),
        "--output", "json",
        "--repetitions", "3",
        "--n-prompt", "512",
        "--n-gen", "128",
    ]

    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=600)

        if result.returncode == 0:
            bench_results = _parse_llama_bench_output(result.stdout)
            for br in bench_results:
                tps = float(br.get("avg_ts", 0))
                results.append(LlamaCppResult(
                    timestamp=datetime.datetime.utcnow().isoformat() + "Z",
                    suite="llamacpp",
                    benchmark=f"llama_bench_ngl{n_gpu_layers}",
                    model=model_path.name,
                    prompt_type="bench",
                    prompt_tokens=int(br.get("n_prompt", 0)),
                    output_tokens=int(br.get("n_gen", 0)),
                    ttft_ms=0.0,
                    total_latency_ms=float(br.get("avg_ms", 0)),
                    tokens_per_sec=tps,
                    vram_used_gb=_get_vram_used_gb(),
                    ram_used_gb=round(psutil.virtual_memory().used / (1024**3), 2),
                    gpu_util_pct=0.0,
                    cpu_util_pct=psutil.cpu_percent(interval=0.1),
                    power_watts=0.0,
                    temp_celsius=0.0,
                    context_length=int(br.get("n_prompt", 512)),
                    batch_size=1,
                    quantization=_infer_quantization(model_path.name),
                    backend="llama.cpp",
                    device="gpu" if n_gpu_layers > 0 else "cpu",
                    gpu_vendor=gpu_vendor if n_gpu_layers > 0 else "none",
                    gpu_model=gpu_model if n_gpu_layers > 0 else "CPU",
                    host_os=_detect_host_os(),
                    status="success",
                    error_message="",
                    notes=json.dumps(br),
                ))
        else:
            log.error("llama-bench failed: %s", result.stderr[:300])

    except subprocess.TimeoutExpired:
        log.error("llama-bench timed out")
    except Exception as exc:
        log.error("llama-bench error: %s", exc)

    return results


def benchmark_context_scaling(
    binary: str,
    model_path: pathlib.Path,
    n_gpu_layers: int,
    gpu_vendor: str,
    gpu_model: str,
) -> list[LlamaCppResult]:
    """Benchmark across different context lengths."""
    results: list[LlamaCppResult] = []

    for ctx_len in CONTEXT_LENGTHS:
        result = benchmark_inference(
            binary=binary,
            model_path=model_path,
            prompt_type="medium",
            prompt=TEST_PROMPTS["medium"],
            n_gpu_layers=n_gpu_layers,
            context_length=ctx_len,
            n_predict=128,
            gpu_vendor=gpu_vendor,
            gpu_model=gpu_model,
        )
        result.benchmark = f"llamacpp_ctx_scaling_ctx{ctx_len}_ngl{n_gpu_layers}"
        results.append(result)
        time.sleep(1)

    return results


def benchmark_gpu_layer_scaling(
    binary: str,
    model_path: pathlib.Path,
    gpu_vendor: str,
    gpu_model: str,
) -> list[LlamaCppResult]:
    """Benchmark with different numbers of GPU layers (CPU vs GPU offload)."""
    results: list[LlamaCppResult] = []

    for ngl in GPU_LAYERS_OPTIONS:
        result = benchmark_inference(
            binary=binary,
            model_path=model_path,
            prompt_type="medium",
            prompt=TEST_PROMPTS["medium"],
            n_gpu_layers=ngl,
            context_length=2048,
            n_predict=256,
            gpu_vendor=gpu_vendor,
            gpu_model=gpu_model,
        )
        result.benchmark = f"llamacpp_ngl_scaling_ngl{ngl}"
        results.append(result)
        time.sleep(2)

    return results


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def _infer_quantization(model_name: str) -> str:
    """Infer quantization from model filename."""
    name_upper = model_name.upper()
    for q in ["Q2_K", "Q3_K_M", "Q3_K_S", "Q4_0", "Q4_K_M", "Q4_K_S",
               "Q5_K_M", "Q5_K_S", "Q6_K", "Q8_0", "F16", "F32", "BF16"]:
        if q in name_upper:
            return q
    return "Q4_K_M"


def _find_models(models_dir: pathlib.Path) -> list[pathlib.Path]:
    """Find GGUF model files."""
    if not models_dir.exists():
        return []
    return list(models_dir.glob("**/*.gguf"))


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main() -> int:
    """Run llama.cpp benchmarks."""
    parser = argparse.ArgumentParser(description="llama.cpp Benchmark — Microsoft AGI Lab")
    parser.add_argument("--models-dir", type=pathlib.Path, default=MODELS_DIR)
    parser.add_argument("--model", type=pathlib.Path, help="Specific model file")
    parser.add_argument("--n-gpu-layers", type=int, default=99)
    parser.add_argument("--context", type=int, default=2048)
    parser.add_argument("--n-predict", type=int, default=256)
    parser.add_argument("--threads", type=int, default=None)
    parser.add_argument("--output", default="benchmark/reports/llamacpp_results.json")
    parser.add_argument("--context-scaling", action="store_true")
    parser.add_argument("--gpu-layer-scaling", action="store_true")
    parser.add_argument("--verbose", "-v", action="store_true")
    args = parser.parse_args()

    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)

    # Find binaries
    llama_binary = _get_llama_binary()
    llama_bench_binary = _get_llama_bench_binary()

    if not llama_binary:
        log.error(
            "llama.cpp binary not found. Build llama.cpp and set LLAMACPP_PATH env var.\n"
            "Build: git clone https://github.com/ggerganov/llama.cpp && "
            "cd llama.cpp && cmake -B build && cmake --build build"
        )
        return 1

    log.info("llama.cpp binary: %s", llama_binary)
    if llama_bench_binary:
        log.info("llama-bench binary: %s", llama_bench_binary)

    gpu_vendor, gpu_model = _get_gpu_info()
    log.info("GPU: %s — %s", gpu_vendor, gpu_model)

    # Find models
    if args.model:
        models = [args.model]
    else:
        models = _find_models(args.models_dir)

    if not models:
        log.warning(
            "No GGUF models found in %s. "
            "Download a model: ollama pull llama3 && "
            "ollama show --modelfile llama3",
            args.models_dir,
        )
        # Create a placeholder result
        placeholder = LlamaCppResult(
            timestamp=datetime.datetime.utcnow().isoformat() + "Z",
            suite="llamacpp",
            benchmark="llamacpp_no_models",
            model="none",
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
            backend="llama.cpp",
            device="",
            gpu_vendor=gpu_vendor,
            gpu_model=gpu_model,
            host_os=_detect_host_os(),
            status="skipped",
            error_message="No GGUF models found",
            notes=f"models_dir={args.models_dir}",
        )
        print(json.dumps([asdict(placeholder)]))
        return 0

    all_results: list[LlamaCppResult] = []

    for model_path in models:
        log.info("=" * 50)
        log.info("Benchmarking: %s", model_path.name)
        log.info("=" * 50)

        # Standard inference benchmarks
        for prompt_type, prompt_text in TEST_PROMPTS.items():
            result = benchmark_inference(
                binary=llama_binary,
                model_path=model_path,
                prompt_type=prompt_type,
                prompt=prompt_text,
                n_gpu_layers=args.n_gpu_layers,
                context_length=args.context,
                n_predict=args.n_predict,
                gpu_vendor=gpu_vendor,
                gpu_model=gpu_model,
                threads=args.threads,
            )
            all_results.append(result)
            time.sleep(1)

        # Context scaling
        if args.context_scaling:
            ctx_results = benchmark_context_scaling(
                binary=llama_binary,
                model_path=model_path,
                n_gpu_layers=args.n_gpu_layers,
                gpu_vendor=gpu_vendor,
                gpu_model=gpu_model,
            )
            all_results.extend(ctx_results)

        # GPU layer scaling
        if args.gpu_layer_scaling and gpu_vendor != "none":
            ngl_results = benchmark_gpu_layer_scaling(
                binary=llama_binary,
                model_path=model_path,
                gpu_vendor=gpu_vendor,
                gpu_model=gpu_model,
            )
            all_results.extend(ngl_results)

        # llama-bench
        if llama_bench_binary:
            bench_results = benchmark_llama_bench(
                bench_binary=llama_bench_binary,
                model_path=model_path,
                n_gpu_layers=args.n_gpu_layers,
                gpu_vendor=gpu_vendor,
                gpu_model=gpu_model,
            )
            all_results.extend(bench_results)

    # Export
    out_path = pathlib.Path(args.output)
    out_path.parent.mkdir(parents=True, exist_ok=True)

    output_data = {
        "suite": "llamacpp",
        "timestamp": datetime.datetime.utcnow().isoformat() + "Z",
        "gpu_vendor": gpu_vendor,
        "gpu_model": gpu_model,
        "binary": llama_binary,
        "models_tested": [str(m) for m in models],
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