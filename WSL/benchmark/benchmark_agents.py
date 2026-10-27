# =============================================================================
# Windows AGI Benchmark Lab — Agent Throughput Benchmark
# Copyright (c) 2026 Microsoft Corporation. All Rights Reserved.
# =============================================================================
"""AGI Mesh agent throughput and latency benchmark."""

from __future__ import annotations
import argparse, asyncio, datetime, json, logging, os, pathlib, platform, sys, time
from dataclasses import asdict, dataclass
from typing import Any
import psutil

log = logging.getLogger("agi.bench.agents")
logging.basicConfig(level=logging.INFO, format="%(asctime)s | %(levelname)-8s | %(name)s | %(message)s")

AGENT_URL = os.environ.get("AGENT_URL", "http://localhost:8500")
OLLAMA_URL = os.environ.get("OLLAMA_URL", "http://localhost:11434")
QDRANT_URL = os.environ.get("QDRANT_URL", "http://localhost:6333")
REDIS_URL  = os.environ.get("REDIS_URL",  "redis://localhost:6379")

@dataclass
class AgentResult:
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

def _make_result(benchmark: str, latency_ms: float, throughput: float,
                 status: str="success", error_msg: str="", notes: str="") -> AgentResult:
    mem = psutil.virtual_memory()
    return AgentResult(
        timestamp=datetime.datetime.utcnow().isoformat()+"Z", suite="agents",
        benchmark=benchmark, model="agi_mesh", prompt_type="agent_task",
        prompt_tokens=0, output_tokens=0, ttft_ms=0.0,
        total_latency_ms=latency_ms, tokens_per_sec=throughput,
        vram_used_gb=0.0, ram_used_gb=round(mem.used/(1024**3),2),
        gpu_util_pct=0.0, cpu_util_pct=psutil.cpu_percent(interval=0.1),
        power_watts=0.0, temp_celsius=0.0, context_length=0, batch_size=1,
        quantization="", backend="agi_mesh", device="cpu",
        gpu_vendor="none", gpu_model="none", host_os=_detect_host_os(),
        status=status, error_message=error_msg, notes=notes)

def check_service(url: str, path: str="/health") -> bool:
    try:
        import requests
        r = requests.get(f"{url}{path}", timeout=5)
        return r.status_code == 200
    except: return False

def bench_agent_api_latency(url: str, n_requests: int=50) -> list[AgentResult]:
    results = []
    try:
        import requests
    except ImportError:
        return results
    if not check_service(url):
        log.warning("Agent API not available at %s", url)
        results.append(_make_result("agent_api_unavailable", 0.0, 0.0, "skipped",
                                    error_msg="Agent API not running"))
        return results
    for i in range(n_requests):
        t0 = time.perf_counter()
        try:
            r = requests.get(f"{url}/health", timeout=10)
            r.raise_for_status()
            elapsed_ms = round((time.perf_counter()-t0)*1000, 2)
            results.append(_make_result(f"agent_health_req{i}", elapsed_ms, round(1000/elapsed_ms,1),
                                        notes=f"req={i+1}/{n_requests}"))
        except Exception as exc:
            elapsed_ms = round((time.perf_counter()-t0)*1000, 2)
            results.append(_make_result(f"agent_health_req{i}", elapsed_ms, 0.0, "error",
                                        error_msg=str(exc)[:200]))
    return results

def bench_inference_agent(url: str, n_requests: int=20) -> list[AgentResult]:
    results = []
    try:
        import requests
    except ImportError:
        return results
    if not check_service(url):
        return results
    task_payload = {
        "task_type": "generate",
        "agent_type": "inference",
        "payload": {"model": "llama3", "prompt": "What is 2+2?", "stream": False},
        "timeout_sec": 60
    }
    for i in range(n_requests):
        t0 = time.perf_counter()
        try:
            r = requests.post(f"{url}/tasks", json=task_payload, timeout=120)
            r.raise_for_status()
            task_id = r.json().get("task_id","")
            # Poll for result
            for _ in range(30):
                time.sleep(1)
                poll = requests.get(f"{url}/tasks/{task_id}", timeout=10)
                if poll.status_code == 200:
                    data = poll.json()
                    if data.get("status") in ("completed","failed","error"):
                        break
            elapsed_ms = round((time.perf_counter()-t0)*1000, 2)
            results.append(_make_result(f"agent_inference_req{i}", elapsed_ms,
                                        round(1000/elapsed_ms,2) if elapsed_ms>0 else 0.0,
                                        notes=f"task_id={task_id}"))
        except Exception as exc:
            elapsed_ms = round((time.perf_counter()-t0)*1000, 2)
            results.append(_make_result(f"agent_inference_req{i}", elapsed_ms, 0.0, "error",
                                        error_msg=str(exc)[:200]))
    return results

def bench_vector_search(qdrant_url: str, n_queries: int=100) -> list[AgentResult]:
    results = []
    try:
        from qdrant_client import QdrantClient
        import numpy as np
    except ImportError:
        log.info("qdrant-client not installed — skipping vector search benchmark")
        return results
    if not check_service(qdrant_url, "/healthz"):
        log.warning("Qdrant not available at %s", qdrant_url)
        return results
    try:
        client = QdrantClient(url=qdrant_url)
        collection_name = "agi_bench_test"
        dim = 768
        rng = np.random.default_rng(42)
        # Create test collection
        from qdrant_client.models import VectorParams, Distance, PointStruct
        try:
            client.create_collection(collection_name, vectors_config=VectorParams(size=dim, distance=Distance.COSINE))
        except: pass
        # Insert test vectors
        points = [PointStruct(id=i, vector=rng.standard_normal(dim).tolist(), payload={"idx": i}) for i in range(1000)]
        client.upsert(collection_name, points=points)
        # Benchmark search
        for i in range(n_queries):
            query_vec = rng.standard_normal(dim).tolist()
            t0 = time.perf_counter()
            search_results = client.search(collection_name, query_vector=query_vec, limit=10)
            elapsed_ms = round((time.perf_counter()-t0)*1000, 2)
            results.append(_make_result(f"vector_search_q{i}", elapsed_ms,
                                        round(1000/elapsed_ms,1) if elapsed_ms>0 else 0.0,
                                        notes=f"dim={dim} results={len(search_results)}"))
        # Cleanup
        try: client.delete_collection(collection_name)
        except: pass
    except Exception as exc:
        log.error("Vector search benchmark failed: %s", exc)
        results.append(_make_result("vector_search_failed", 0.0, 0.0, "error", error_msg=str(exc)[:300]))
    return results

def bench_redis_throughput(redis_url: str, n_ops: int=10000) -> list[AgentResult]:
    results = []
    try:
        import redis as redis_lib
    except ImportError:
        log.info("redis not installed — skipping Redis benchmark")
        return results
    try:
        client = redis_lib.from_url(redis_url, decode_responses=True)
        client.ping()
    except Exception as exc:
        log.warning("Redis not available: %s", exc)
        return results
    # SET benchmark
    t0 = time.perf_counter()
    for i in range(n_ops):
        client.set(f"bench:key:{i}", f"value_{i}", ex=60)
    elapsed = time.perf_counter() - t0
    set_ops_per_sec = round(n_ops / elapsed, 0)
    results.append(_make_result("redis_set", round(elapsed*1000,2), set_ops_per_sec,
                                notes=f"ops_per_sec={set_ops_per_sec} n_ops={n_ops}"))
    # GET benchmark
    t0 = time.perf_counter()
    for i in range(n_ops):
        _ = client.get(f"bench:key:{i}")
    elapsed = time.perf_counter() - t0
    get_ops_per_sec = round(n_ops / elapsed, 0)
    results.append(_make_result("redis_get", round(elapsed*1000,2), get_ops_per_sec,
                                notes=f"ops_per_sec={get_ops_per_sec} n_ops={n_ops}"))
    # Cleanup
    for i in range(n_ops):
        client.delete(f"bench:key:{i}")
    return results

def main() -> int:
    parser = argparse.ArgumentParser(description="Agent Benchmark — Microsoft AGI Lab")
    parser.add_argument("--agent-url", default=AGENT_URL)
    parser.add_argument("--qdrant-url", default=QDRANT_URL)
    parser.add_argument("--redis-url", default=REDIS_URL)
    parser.add_argument("--requests", type=int, default=20)
    parser.add_argument("--output", default="benchmark/reports/agents_results.json")
    parser.add_argument("--verbose", "-v", action="store_true")
    args = parser.parse_args()
    if args.verbose: logging.getLogger().setLevel(logging.DEBUG)

    all_results = []
    all_results.extend(bench_agent_api_latency(args.agent_url, args.requests))
    all_results.extend(bench_inference_agent(args.agent_url, min(args.requests, 10)))
    all_results.extend(bench_vector_search(args.qdrant_url, args.requests))
    all_results.extend(bench_redis_throughput(args.redis_url, min(args.requests*100, 5000)))

    out_path = pathlib.Path(args.output)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with open(out_path, "w") as f:
        json.dump({"suite":"agents","results":[asdict(r) for r in all_results]}, f, indent=2)
    log.info("Results saved: %s (%d records)", out_path, len(all_results))
    print(json.dumps([asdict(r) for r in all_results]))
    return 0

if __name__ == "__main__":
    sys.exit(main())
