# =============================================================================
# Windows AGI Benchmark Lab — Ollama Benchmark Module
# Copyright (c) 2026 Microsoft Corporation. All Rights Reserved.
# =============================================================================

"""
Ollama inference benchmark module.

Measures:
  - Time to First Token (TTFT)
  - Tokens per second (throughput)
  - Total latency
  - VRAM usage
  - RAM usage
  - GPU utilization
  - Power draw

Supports streaming and non-streaming modes.
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
from typing import Any, Generator

import psutil
import requests

log = logging.getLogger("agi.bench.ollama")
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)-8s | %(name)s | %(message)s",
)

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
OLLAMA_URL = os.environ.get("OLLAMA_URL", "http://localhost:11434")
DEFAULT_MODELS = ["llama3", "phi4", "mistral", "gemma2"]
DEFAULT_TIMEOUT = 300  # seconds

PROMPTS: dict[str, str] = {
    "short": "What is 2 + 2?",
    "medium": (
        "Explain the concept of transformer attention mechanisms in machine learning. "
        "Cover self-attention, multi-head attention, and their computational complexity."
    ),
    "long": (
        "Write a comprehensive technical analysis of distributed AI inference architectures. "
        "Cover model parallelism, tensor parallelism, pipeline parallelism, and their trade-offs "
        "in terms of latency, throughput, memory efficiency, and hardware utilization. "
        "Include specific examples for transformer-based large language models with billions of parameters. "
        "Discuss quantization strategies (INT4, INT8, FP16, BF16) and their impact on accuracy and speed. "
        "Conclude with recommendations for different hardware configurations."
    ),
    "code": (
        "Write a complete, production-ready Python implementation of an async HTTP client "
        "with connection pooling, retry logic with exponential backoff, circuit breaker pattern, "
        "request/response logging, and comprehensive error handling. Include type hints and docstrings."
    ),
    "reasoning": (
        "A train leaves Station A at 9:00 AM traveling at 80 km/h toward Station B. "
        "Another train leaves Station B at 10:00 AM traveling at 100 km/h toward Station A. "
        "The distance between stations is 360 km. "
        "At what time do the trains meet, and how far from Station A? "
        "Show all steps of your reasoning."
    ),
}

CONTEXT_LENGTHS = [512, 1024, 2048, 4096, 8192]


# ---------------------------------------------------------------------------
# Data Models
# ---------------------------------------------------------------------------
@dataclass
class OllamaResult:
    """Single Ollama benchmark result."""

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
# GPU Metrics Helpers
# ---------------------------------------------------------------------------
def _get_amd_metrics() -> dict[str, float]:
    """Collect AMD GPU metrics via rocm-smi."""
    metrics: dict[str, float] = {
        "vram_used_gb": 0.0,
        "gpu_util_pct": 0.0,
        "power_watts": 0.0,
        "temp_celsius": 0.0,
    }
    try:
        result = subprocess.run(
            ["rocm-smi", "--showuse", "--showtemp", "--showpower", "--showmemuse", "--json"],
            capture_output=True, text=True, timeout=5,
        )
        if result.returncode == 0:
            data = json.loads(result.stdout)
            for card_data in data.values():
                if not isinstance(card_data, dict):
                    continue
                # GPU utilization
                util_str = card_data.get("GPU use (%)", "0")
                metrics["gpu_util_pct"] = float(str(util_str).replace("%", "").strip() or 0)
                # Temperature
                temp_str = card_data.get("Temperature (Sensor edge) (C)", "0")
                metrics["temp_celsius"] = float(str(temp_str).replace("C", "").strip() or 0)
                # Power
                power_str = card_data.get("Average Graphics Package Power (W)", "0")
                metrics["power_watts"] = float(str(power_str).replace("W", "").strip() or 0)
                # VRAM
                vram_str = card_data.get("VRAM Total Used Memory (B)", "0")
                metrics["vram_used_gb"] = round(int(vram_str) / (1024**3), 2)
                break
    except (FileNotFoundError, subprocess.TimeoutExpired, json.JSONDecodeError, ValueError, KeyError):
        pass
    return metrics


def _get_nvidia_metrics() -> dict[str, float]:
    """Collect NVIDIA GPU metrics via nvidia-smi."""
    metrics: dict[str, float] = {
        "vram_used_gb": 0.0,
        "gpu_util_pct": 0.0,
        "power_watts": 0.0,
        "temp_celsius": 0.0,
    }
    try:
        result = subprocess.run(
            [
                "nvidia-smi",
                "--query-gpu=utilization.gpu,temperature.gpu,power.draw,memory.used",
                "--format=csv,noheader,nounits",
            ],
            capture_output=True, text=True, timeout=5,
        )
        if result.returncode == 0 and result.stdout.strip():
            parts = result.stdout.strip().split(",")
            if len(parts) >= 4:
                metrics["gpu_util_pct"] = float(parts[0].strip())
                metrics["temp_celsius"] = float(parts[1].strip())
                metrics["power_watts"] = float(parts[2].strip())
                metrics["vram_used_gb"] = round(float(parts[3].strip()) / 1024, 2)
    except (FileNotFoundError, subprocess.TimeoutExpired, ValueError):
        pass
    return metrics


def _get_gpu_metrics() -> dict[str, float]:
    """Auto-detect GPU vendor and collect metrics."""
    # Try NVIDIA first
    try:
        result = subprocess.run(
            ["nvidia-smi", "--query-gpu=name", "--format=csv,noheader"],
            capture_output=True, text=True, timeout=3,
        )
        if result.returncode == 0:
            return _get_nvidia_metrics()
    except (FileNotFoundError, subprocess.TimeoutExpired):
        pass

    # Try AMD
    try:
        result = subprocess.run(
            ["rocm-smi", "--showproductname"],
            capture_output=True, text=True, timeout=3,
        )
        if result.returncode == 0:
            return _get_amd_metrics()
    except (FileNotFoundError, subprocess.TimeoutExpired):
        pass

    return {"vram_used_gb": 0.0, "gpu_util_pct": 0.0, "power_watts": 0.0, "temp_celsius": 0.0}


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


# ---------------------------------------------------------------------------
# Ollama API Client
# ---------------------------------------------------------------------------
class OllamaClient:
    """Minimal Ollama API client."""

    def __init__(self, base_url: str = OLLAMA_URL, timeout: int = DEFAULT_TIMEOUT) -> None:
        self.base_url = base_url.rstrip("/")
        self.timeout = timeout
        self.session = requests.Session()
        self.session.headers.update({"Content-Type": "application/json"})

    def is_available(self) -> bool:
        """Check if Ollama server is reachable."""
        try:
            r = self.session.get(f"{self.base_url}/api/tags", timeout=5)
            return r.status_code == 200
        except requests.RequestException:
            return False

    def list_models(self) -> list[str]:
        """List available models."""
        try:
            r = self.session.get(f"{self.base_url}/api/tags", timeout=10)
            r.raise_for_status()
            data = r.json()
            return [m["name"] for m in data.get("models", [])]
        except requests.RequestException:
            return []

    def pull_model(self, model: str) -> bool:
        """Pull a model if not present."""
        log.info("Pulling model: %s", model)
        try:
            r = self.session.post(
                f"{self.base_url}/api/pull",
                json={"name": model, "stream": False},
                timeout=600,
            )
            return r.status_code == 200
        except requests.RequestException as exc:
            log.error("Failed to pull model %s: %s", model, exc)
            return False

    def generate_stream(
        self,
        model: str,
        prompt: str,
        options: dict[str, Any] | None = None,
    ) -> Generator[dict[str, Any], None, None]:
        """Stream generation responses."""
        payload: dict[str, Any] = {
            "model": model,
            "prompt": prompt,
            "stream": True,
            "options": options or {},
        }
        with self.session.post(
            f"{self.base_url}/api/generate",
            json=payload,
            stream=True,
            timeout=self.timeout,
        ) as response:
            response.raise_for_status()
            for line in response.iter_lines():
                if line:
                    yield json.loads(line)

    def generate(
        self,
        model: str,
        prompt: str,
        options: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        """Non-streaming generation."""
        payload: dict[str, Any] = {
            "model": model,
            "prompt": prompt,
            "stream": False,
            "options": options or {},
        }
        r = self.session.post(
            f"{self.base_url}/api/generate",
            json=payload,
            timeout=self.timeout,
        )
        r.raise_for_status()
        return r.json()  # type: ignore[no-any-return]

    def get_model_info(self, model: str) -> dict[str, Any]:
        """Get model metadata."""
        try:
            r = self.session.post(
                f"{self.base_url}/api/show",
                json={"name": model},
                timeout=10,
            )
            r.raise_for_status()
            return r.json()  # type: ignore[no-any-return]
        except requests.RequestException:
            return {}


# ---------------------------------------------------------------------------
# Benchmark Functions
# ---------------------------------------------------------------------------
def benchmark_streaming(
    client: OllamaClient,
    model: str,
    prompt_type: str,
    prompt: str,
    gpu_vendor: str,
    gpu_model: str,
    context_length: int = 2048,
    num_runs: int = 3,
) -> list[OllamaResult]:
    """Benchmark streaming inference — measures TTFT accurately."""
    results: list[OllamaResult] = []

    options = {
        "num_ctx": context_length,
        "num_predict": 512,
        "temperature": 0.0,
        "seed": 42,
    }

    for run_idx in range(num_runs):
        log.info(
            "Streaming benchmark: model=%s prompt=%s run=%d/%d ctx=%d",
            model, prompt_type, run_idx + 1, num_runs, context_length,
        )

        # Baseline system metrics
        cpu_before = psutil.cpu_percent(interval=None)
        mem_before = psutil.virtual_memory().used / (1024**3)

        first_token_time: float = 0.0
        total_tokens = 0
        response_text = ""
        status = "success"
        error_msg = ""
        prompt_tokens = 0
        eval_count = 0
        eval_duration_ns = 0

        t_start = time.perf_counter()

        try:
            for chunk in client.generate_stream(model, prompt, options):
                t_now = time.perf_counter()

                if first_token_time == 0.0 and chunk.get("response"):
                    first_token_time = t_now

                response_text += chunk.get("response", "")

                if chunk.get("done"):
                    prompt_tokens = chunk.get("prompt_eval_count", 0)
                    eval_count = chunk.get("eval_count", 0)
                    eval_duration_ns = chunk.get("eval_duration", 0)
                    total_tokens = eval_count
                    break

        except requests.RequestException as exc:
            status = "error"
            error_msg = str(exc)[:300]
            log.error("Streaming error: %s", exc)
        except Exception as exc:
            status = "error"
            error_msg = str(exc)[:300]
            log.error("Unexpected error: %s", exc)

        t_end = time.perf_counter()
        total_latency_ms = round((t_end - t_start) * 1000, 2)
        ttft_ms = round((first_token_time - t_start) * 1000, 2) if first_token_time > 0 else 0.0

        # Tokens per second from Ollama's own measurement
        if eval_duration_ns > 0 and eval_count > 0:
            tps = round(eval_count / (eval_duration_ns / 1e9), 2)
        elif total_latency_ms > 0 and total_tokens > 0:
            tps = round(total_tokens / (total_latency_ms / 1000), 2)
        else:
            tps = 0.0

        # Post-run metrics
        cpu_after = psutil.cpu_percent(interval=0.1)
        mem_after = psutil.virtual_memory().used / (1024**3)
        gpu_metrics = _get_gpu_metrics()

        results.append(OllamaResult(
            timestamp=datetime.datetime.utcnow().isoformat() + "Z",
            suite="ollama",
            benchmark=f"ollama_stream_{prompt_type}_ctx{context_length}_run{run_idx}",
            model=model,
            prompt_type=prompt_type,
            prompt_tokens=prompt_tokens,
            output_tokens=total_tokens,
            ttft_ms=ttft_ms,
            total_latency_ms=total_latency_ms,
            tokens_per_sec=tps,
            vram_used_gb=gpu_metrics["vram_used_gb"],
            ram_used_gb=round(mem_after - mem_before, 3),
            gpu_util_pct=gpu_metrics["gpu_util_pct"],
            cpu_util_pct=round((cpu_before + cpu_after) / 2, 1),
            power_watts=gpu_metrics["power_watts"],
            temp_celsius=gpu_metrics["temp_celsius"],
            context_length=context_length,
            batch_size=1,
            quantization=_detect_quantization(model),
            backend="ollama",
            device=gpu_vendor if gpu_vendor != "none" else "cpu",
            gpu_vendor=gpu_vendor,
            gpu_model=gpu_model,
            host_os=_detect_host_os(),
            status=status,
            error_message=error_msg,
            notes=f"run={run_idx + 1}/{num_runs} tokens={total_tokens}",
        ))

        # Cool-down between runs
        if run_idx < num_runs - 1:
            time.sleep(2)

    return results


def benchmark_throughput(
    client: OllamaClient,
    model: str,
    gpu_vendor: str,
    gpu_model: str,
    num_requests: int = 5,
) -> list[OllamaResult]:
    """Benchmark throughput with multiple concurrent-style requests."""
    results: list[OllamaResult] = []
    prompt = PROMPTS["medium"]

    for i in range(num_requests):
        log.info("Throughput benchmark: model=%s request=%d/%d", model, i + 1, num_requests)

        t_start = time.perf_counter()
        status = "success"
        error_msg = ""
        tps = 0.0
        ttft_ms = 0.0
        output_tokens = 0
        prompt_tokens = 0

        try:
            response = client.generate(model, prompt, {"temperature": 0.0, "seed": 42})
            t_end = time.perf_counter()
            elapsed = t_end - t_start

            output_tokens = response.get("eval_count", 0)
            prompt_tokens = response.get("prompt_eval_count", 0)
            eval_dur_ns = response.get("eval_duration", 0)
            load_dur_ns = response.get("load_duration", 0)

            ttft_ms = round(load_dur_ns / 1e6, 2)
            if eval_dur_ns > 0 and output_tokens > 0:
                tps = round(output_tokens / (eval_dur_ns / 1e9), 2)
            elif elapsed > 0 and output_tokens > 0:
                tps = round(output_tokens / elapsed, 2)

        except requests.RequestException as exc:
            t_end = time.perf_counter()
            status = "error"
            error_msg = str(exc)[:300]

        gpu_metrics = _get_gpu_metrics()
        mem = psutil.virtual_memory()

        results.append(OllamaResult(
            timestamp=datetime.datetime.utcnow().isoformat() + "Z",
            suite="ollama",
            benchmark=f"ollama_throughput_req{i}",
            model=model,
            prompt_type="medium",
            prompt_tokens=prompt_tokens,
            output_tokens=output_tokens,
            ttft_ms=ttft_ms,
            total_latency_ms=round((t_end - t_start) * 1000, 2),
            tokens_per_sec=tps,
            vram_used_gb=gpu_metrics["vram_used_gb"],
            ram_used_gb=round(mem.used / (1024**3), 2),
            gpu_util_pct=gpu_metrics["gpu_util_pct"],
            cpu_util_pct=psutil.cpu_percent(interval=0.1),
            power_watts=gpu_metrics["power_watts"],
            temp_celsius=gpu_metrics["temp_celsius"],
            context_length=2048,
            batch_size=1,
            quantization=_detect_quantization(model),
            backend="ollama",
            device=gpu_vendor if gpu_vendor != "none" else "cpu",
            gpu_vendor=gpu_vendor,
            gpu_model=gpu_model,
            host_os=_detect_host_os(),
            status=status,
            error_message=error_msg,
            notes=f"throughput_request_{i + 1}",
        ))

        time.sleep(1)

    return results


def benchmark_context_scaling(
    client: OllamaClient,
    model: str,
    gpu_vendor: str,
    gpu_model: str,
) -> list[OllamaResult]:
    """Benchmark performance across different context lengths."""
    results: list[OllamaResult] = []

    for ctx_len in CONTEXT_LENGTHS:
        log.info("Context scaling: model=%s ctx=%d", model, ctx_len)

        prompt = PROMPTS["medium"]
        t_start = time.perf_counter()
        status = "success"
        error_msg = ""
        tps = 0.0
        ttft_ms = 0.0
        output_tokens = 0
        prompt_tokens = 0

        try:
            response = client.generate(
                model, prompt,
                {"num_ctx": ctx_len, "temperature": 0.0, "seed": 42},
            )
            t_end = time.perf_counter()

            output_tokens = response.get("eval_count", 0)
            prompt_tokens = response.get("prompt_eval_count", 0)
            eval_dur_ns = response.get("eval_duration", 0)
            load_dur_ns = response.get("load_duration", 0)

            ttft_ms = round(load_dur_ns / 1e6, 2)
            if eval_dur_ns > 0 and output_tokens > 0:
                tps = round(output_tokens / (eval_dur_ns / 1e9), 2)

        except requests.RequestException as exc:
            t_end = time.perf_counter()
            status = "error"
            error_msg = str(exc)[:300]

        gpu_metrics = _get_gpu_metrics()

        results.append(OllamaResult(
            timestamp=datetime.datetime.utcnow().isoformat() + "Z",
            suite="ollama",
            benchmark=f"ollama_ctx_scaling_ctx{ctx_len}",
            model=model,
            prompt_type="medium",
            prompt_tokens=prompt_tokens,
            output_tokens=output_tokens,
            ttft_ms=ttft_ms,
            total_latency_ms=round((t_end - t_start) * 1000, 2),
            tokens_per_sec=tps,
            vram_used_gb=gpu_metrics["vram_used_gb"],
            ram_used_gb=round(psutil.virtual_memory().used / (1024**3), 2),
            gpu_util_pct=gpu_metrics["gpu_util_pct"],
            cpu_util_pct=psutil.cpu_percent(interval=0.1),
            power_watts=gpu_metrics["power_watts"],
            temp_celsius=gpu_metrics["temp_celsius"],
            context_length=ctx_len,
            batch_size=1,
            quantization=_detect_quantization(model),
            backend="ollama",
            device=gpu_vendor if gpu_vendor != "none" else "cpu",
            gpu_vendor=gpu_vendor,
            gpu_model=gpu_model,
            host_os=_detect_host_os(),
            status=status,
            error_message=error_msg,
            notes=f"context_scaling_ctx={ctx_len}",
        ))

        time.sleep(2)

    return results


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def _detect_quantization(model_name: str) -> str:
    """Infer quantization from model name."""
    name_lower = model_name.lower()
    for q in ["q2_k", "q3_k_m", "q4_0", "q4_k_m", "q5_k_m", "q6_k", "q8_0", "fp16", "bf16"]:
        if q in name_lower:
            return q.upper()
    return "Q4_K_M"  # Ollama default


def _detect_host_os() -> str:
    """Detect host OS including WSL2."""
    if "microsoft" in platform.uname().release.lower():
        return "WSL2"
    return platform.system()


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main() -> int:
    """Run Ollama benchmarks."""
    parser = argparse.ArgumentParser(description="Ollama Benchmark — Microsoft AGI Lab")
    parser.add_argument("--models", nargs="+", default=DEFAULT_MODELS)
    parser.add_argument("--url", default=OLLAMA_URL)
    parser.add_argument("--runs", type=int, default=3)
    parser.add_argument("--output", default="benchmark/reports/ollama_results.json")
    parser.add_argument("--pull", action="store_true", help="Pull models if not present")
    parser.add_argument("--verbose", "-v", action="store_true")
    args = parser.parse_args()

    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)

    client = OllamaClient(base_url=args.url)

    if not client.is_available():
        log.error("Ollama not available at %s", args.url)
        log.error("Start Ollama with: ollama serve")
        return 1

    log.info("Ollama available at %s", args.url)
    available_models = client.list_models()
    log.info("Available models: %s", available_models)

    gpu_vendor, gpu_model = _get_gpu_info()
    log.info("GPU: %s — %s", gpu_vendor, gpu_model)

    all_results: list[OllamaResult] = []

    for model in args.models:
        # Check if model is available
        model_available = any(model in m for m in available_models)

        if not model_available:
            if args.pull:
                log.info("Pulling model: %s", model)
                if not client.pull_model(model):
                    log.warning("Failed to pull %s — skipping", model)
                    continue
            else:
                log.warning("Model %s not available — skipping (use --pull to auto-pull)", model)
                continue

        log.info("=" * 50)
        log.info("Benchmarking model: %s", model)
        log.info("=" * 50)

        # Streaming benchmarks for each prompt type
        for prompt_type, prompt_text in PROMPTS.items():
            results = benchmark_streaming(
                client=client,
                model=model,
                prompt_type=prompt_type,
                prompt=prompt_text,
                gpu_vendor=gpu_vendor,
                gpu_model=gpu_model,
                context_length=2048,
                num_runs=args.runs,
            )
            all_results.extend(results)

        # Throughput benchmark
        throughput_results = benchmark_throughput(
            client=client,
            model=model,
            gpu_vendor=gpu_vendor,
            gpu_model=gpu_model,
            num_requests=5,
        )
        all_results.extend(throughput_results)

        # Context scaling benchmark
        ctx_results = benchmark_context_scaling(
            client=client,
            model=model,
            gpu_vendor=gpu_vendor,
            gpu_model=gpu_model,
        )
        all_results.extend(ctx_results)

    # Output results as JSON
    output_data = {
        "suite": "ollama",
        "timestamp": datetime.datetime.utcnow().isoformat() + "Z",
        "gpu_vendor": gpu_vendor,
        "gpu_model": gpu_model,
        "total_results": len(all_results),
        "results": [asdict(r) for r in all_results],
    }

    import pathlib
    out_path = pathlib.Path(args.output)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(output_data, f, indent=2)

    log.info("Results saved: %s (%d records)", out_path, len(all_results))

    # Print to stdout for runner.py to capture
    print(json.dumps([asdict(r) for r in all_results]))

    return 0


if __name__ == "__main__":
    sys.exit(main())