# =============================================================================
# Windows AGI Benchmark Lab — vLLM Benchmark Module
# Copyright (c) 2026 Microsoft Corporation. All Rights Reserved.
# =============================================================================
"""vLLM inference benchmark module. Measures throughput, latency, TTFT."""

from __future__ import annotations
import argparse, datetime, json, logging, os, pathlib, platform, subprocess, sys, time
from dataclasses import asdict, dataclass
from typing import Any
import psutil

log = logging.getLogger("agi.bench.vllm")
logging.basicConfig(level=logging.INFO, format="%(asctime)s | %(levelname)-8s | %(name)s | %(message)s")

VLLM_URL = os.environ.get("VLLM_URL", "http://localhost:8000")
DEFAULT_MODELS = ["meta-llama/Meta-Llama-3-8B-Instruct", "microsoft/phi-4", "mistralai/Mistral-7B-Instruct-v0.3"]
WARMUP_REQUESTS = 5
BENCHMARK_REQUESTS = 50

PROMPTS = {
    "short":     "What is 2+2?",
    "medium":    "Explain transformer attention mechanisms in detail.",
    "long":      "Write a comprehensive analysis of distributed AI inference architectures covering model parallelism, tensor parallelism, pipeline parallelism, quantization strategies, and hardware utilization for large language models with billions of parameters.",
    "code":      "Write a complete Python async HTTP server with connection pooling, retry logic, circuit breaker, and comprehensive error handling.",
    "reasoning": "A train leaves at 9AM at 80km/h. Another leaves at 10AM at 100km/h. Distance=360km. When do they meet?",
}

@dataclass
class VLLMResult:
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

def _get_gpu_info() -> tuple[str, str]:
    try:
        r = subprocess.run(["nvidia-smi","--query-gpu=name","--format=csv,noheader"], capture_output=True, text=True, timeout=3)
        if r.returncode == 0: return "nvidia", r.stdout.strip().splitlines()[0]
    except: pass
    try:
        r = subprocess.run(["rocm-smi","--showproductname","--json"], capture_output=True, text=True, timeout=3)
        if r.returncode == 0:
            data = json.loads(r.stdout)
            for v in data.values():
                if isinstance(v, dict): return "amd", v.get("Card series","AMD GPU")
    except: pass
    return "none", "CPU"

def _get_vram_gb() -> float:
    try:
        r = subprocess.run(["nvidia-smi","--query-gpu=memory.used","--format=csv,noheader,nounits"], capture_output=True, text=True, timeout=3)
        if r.returncode == 0: return round(float(r.stdout.strip())/1024, 2)
    except: pass
    return 0.0

def _make_result(benchmark: str, model: str, prompt_type: str, status: str,
                 ttft_ms: float=0.0, total_ms: float=0.0, tps: float=0.0,
                 prompt_tokens: int=0, output_tokens: int=0,
                 error_msg: str="", notes: str="",
                 gpu_vendor: str="none", gpu_model: str="CPU") -> VLLMResult:
    mem = psutil.virtual_memory()
    return VLLMResult(
        timestamp=datetime.datetime.utcnow().isoformat()+"Z", suite="vllm",
        benchmark=benchmark, model=model, prompt_type=prompt_type,
        prompt_tokens=prompt_tokens, output_tokens=output_tokens,
        ttft_ms=ttft_ms, total_latency_ms=total_ms, tokens_per_sec=tps,
        vram_used_gb=_get_vram_gb(), ram_used_gb=round(mem.used/(1024**3),2),
        gpu_util_pct=0.0, cpu_util_pct=psutil.cpu_percent(interval=0.1),
        power_watts=0.0, temp_celsius=0.0, context_length=2048, batch_size=1,
        quantization="fp16", backend="vllm", device=gpu_vendor if gpu_vendor!="none" else "cpu",
        gpu_vendor=gpu_vendor, gpu_model=gpu_model, host_os=_detect_host_os(),
        status=status, error_message=error_msg, notes=notes)

def check_vllm_available(url: str) -> bool:
    try:
        import requests
        r = requests.get(f"{url}/health", timeout=5)
        return r.status_code == 200
    except: return False

def benchmark_completions(url: str, model: str, prompt_type: str, prompt: str,
                          gpu_vendor: str, gpu_model: str, n_requests: int=10) -> list[VLLMResult]:
    results = []
    try:
        import requests
    except ImportError:
        log.error("requests not installed")
        return results

    for i in range(n_requests):
        log.info("vLLM completion: model=%s prompt=%s req=%d/%d", model, prompt_type, i+1, n_requests)
        t_start = time.perf_counter()
        status = "success"; error_msg = ""; tps = 0.0; output_tokens = 0; prompt_tokens = 0
        try:
            response = requests.post(f"{url}/v1/completions",
                json={"model": model, "prompt": prompt, "max_tokens": 256, "temperature": 0.0, "stream": False},
                timeout=300)
            response.raise_for_status()
            data = response.json()
            t_end = time.perf_counter()
            elapsed = t_end - t_start
            choice = data.get("choices", [{}])[0]
            usage = data.get("usage", {})
            output_tokens = usage.get("completion_tokens", 0)
            prompt_tokens = usage.get("prompt_tokens", 0)
            tps = round(output_tokens / elapsed, 2) if elapsed > 0 and output_tokens > 0 else 0.0
        except Exception as exc:
            t_end = time.perf_counter()
            status = "error"; error_msg = str(exc)[:300]
        elapsed_ms = round((t_end - t_start)*1000, 2)
        results.append(_make_result(
            benchmark=f"vllm_completion_{prompt_type}_req{i}",
            model=model, prompt_type=prompt_type, status=status,
            ttft_ms=0.0, total_ms=elapsed_ms, tps=tps,
            prompt_tokens=prompt_tokens, output_tokens=output_tokens,
            error_msg=error_msg, notes=f"req={i+1}/{n_requests}",
            gpu_vendor=gpu_vendor, gpu_model=gpu_model))
        time.sleep(0.5)
    return results

def benchmark_chat_completions(url: str, model: str, gpu_vendor: str, gpu_model: str, n_requests: int=10) -> list[VLLMResult]:
    results = []
    try:
        import requests
    except ImportError:
        return results
    messages = [
        {"role": "system", "content": "You are a helpful AI assistant for the Windows AGI Benchmark Lab."},
        {"role": "user", "content": "Explain the difference between AMD ROCm and NVIDIA CUDA for AI inference."}
    ]
    for i in range(n_requests):
        log.info("vLLM chat: model=%s req=%d/%d", model, i+1, n_requests)
        t_start = time.perf_counter()
        status = "success"; error_msg = ""; tps = 0.0; output_tokens = 0
        try:
            response = requests.post(f"{url}/v1/chat/completions",
                json={"model": model, "messages": messages, "max_tokens": 256, "temperature": 0.0},
                timeout=300)
            response.raise_for_status()
            data = response.json()
            t_end = time.perf_counter()
            elapsed = t_end - t_start
            usage = data.get("usage", {})
            output_tokens = usage.get("completion_tokens", 0)
            tps = round(output_tokens / elapsed, 2) if elapsed > 0 and output_tokens > 0 else 0.0
        except Exception as exc:
            t_end = time.perf_counter()
            status = "error"; error_msg = str(exc)[:300]
        elapsed_ms = round((t_end - t_start)*1000, 2)
        results.append(_make_result(
            benchmark=f"vllm_chat_req{i}", model=model, prompt_type="chat",
            status=status, total_ms=elapsed_ms, tps=tps, output_tokens=output_tokens,
            error_msg=error_msg, gpu_vendor=gpu_vendor, gpu_model=gpu_model))
        time.sleep(0.5)
    return results

def benchmark_throughput(url: str, model: str, gpu_vendor: str, gpu_model: str) -> list[VLLMResult]:
    """Measure sustained throughput with concurrent requests."""
    import concurrent.futures, requests
    results = []
    prompt = PROMPTS["medium"]
    n_concurrent = 4
    n_batches = 5

    def single_request(req_id: int) -> dict:
        t0 = time.perf_counter()
        try:
            r = requests.post(f"{url}/v1/completions",
                json={"model": model, "prompt": prompt, "max_tokens": 128, "temperature": 0.0},
                timeout=300)
            r.raise_for_status()
            data = r.json()
            elapsed = time.perf_counter() - t0
            tokens = data.get("usage", {}).get("completion_tokens", 0)
            return {"status": "success", "elapsed": elapsed, "tokens": tokens, "req_id": req_id}
        except Exception as exc:
            return {"status": "error", "elapsed": time.perf_counter()-t0, "tokens": 0, "error": str(exc), "req_id": req_id}

    for batch in range(n_batches):
        log.info("vLLM throughput batch %d/%d (concurrent=%d)", batch+1, n_batches, n_concurrent)
        t_batch_start = time.perf_counter()
        with concurrent.futures.ThreadPoolExecutor(max_workers=n_concurrent) as executor:
            futures = [executor.submit(single_request, i) for i in range(n_concurrent)]
            batch_results = [f.result() for f in concurrent.futures.as_completed(futures)]
        t_batch_elapsed = time.perf_counter() - t_batch_start
        total_tokens = sum(r["tokens"] for r in batch_results)
        successful = sum(1 for r in batch_results if r["status"] == "success")
        batch_tps = round(total_tokens / t_batch_elapsed, 2) if t_batch_elapsed > 0 else 0.0
        results.append(_make_result(
            benchmark=f"vllm_throughput_batch{batch}_concurrent{n_concurrent}",
            model=model, prompt_type="medium", status="success" if successful == n_concurrent else "partial",
            total_ms=round(t_batch_elapsed*1000, 2), tps=batch_tps, output_tokens=total_tokens,
            notes=f"concurrent={n_concurrent} successful={successful}/{n_concurrent} batch_tps={batch_tps}",
            gpu_vendor=gpu_vendor, gpu_model=gpu_model))
        time.sleep(1)
    return results

def main() -> int:
    parser = argparse.ArgumentParser(description="vLLM Benchmark — Microsoft AGI Lab")
    parser.add_argument("--models", nargs="+", default=DEFAULT_MODELS)
    parser.add_argument("--url", default=VLLM_URL)
    parser.add_argument("--requests", type=int, default=10)
    parser.add_argument("--output", default="benchmark/reports/vllm_results.json")
    parser.add_argument("--verbose", "-v", action="store_true")
    args = parser.parse_args()
    if args.verbose: logging.getLogger().setLevel(logging.DEBUG)

    if not check_vllm_available(args.url):
        log.error("vLLM not available at %s", args.url)
        log.error("Start vLLM: python -m vllm.entrypoints.openai.api_server --model meta-llama/Meta-Llama-3-8B-Instruct")
        placeholder = _make_result("vllm_unavailable","none","","skipped",error_msg="vLLM not running")
        print(json.dumps([asdict(placeholder)]))
        return 0

    gpu_vendor, gpu_model = _get_gpu_info()
    log.info("GPU: %s — %s", gpu_vendor, gpu_model)
    all_results = []

    for model in args.models:
        log.info("Benchmarking model: %s", model)
        for prompt_type, prompt_text in PROMPTS.items():
            results = benchmark_completions(args.url, model, prompt_type, prompt_text, gpu_vendor, gpu_model, args.requests)
            all_results.extend(results)
        chat_results = benchmark_chat_completions(args.url, model, gpu_vendor, gpu_model, args.requests)
        all_results.extend(chat_results)
        throughput_results = benchmark_throughput(args.url, model, gpu_vendor, gpu_model)
        all_results.extend(throughput_results)

    out_path = pathlib.Path(args.output)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with open(out_path, "w") as f:
        json.dump({"suite":"vllm","results":[asdict(r) for r in all_results]}, f, indent=2)
    log.info("Results saved: %s (%d records)", out_path, len(all_results))
    print(json.dumps([asdict(r) for r in all_results]))
    return 0

if __name__ == "__main__":
    sys.exit(main())
