# =============================================================================
# Windows AGI Benchmark Lab — AGI Mesh Orchestrator
# Copyright (c) 2026 Microsoft Corporation. All Rights Reserved.
# =============================================================================

"""
AGI Mesh Multi-Agent Orchestrator.

Manages a fleet of specialized agents:
  - InferenceAgent: LLM inference via Ollama/vLLM
  - MemoryAgent: Vector store operations (Qdrant)
  - SearchAgent: Web search and retrieval
  - CodeAgent: Code generation and execution
  - BenchmarkAgent: Automated benchmark execution
  - MetricsAgent: System metrics collection

Provides:
  - FastAPI REST API
  - WebSocket streaming
  - Agent lifecycle management
  - Task routing and load balancing
  - Prometheus metrics
  - Redis-backed task queue
"""

from __future__ import annotations

import asyncio
import datetime
import json
import logging
import os
import platform
import sys
import time
import uuid
from dataclasses import asdict, dataclass, field
from enum import Enum
from typing import Any, AsyncGenerator

import psutil

log = logging.getLogger("agi.orchestrator")
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)-8s | %(name)s | %(message)s",
)

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
OLLAMA_URL = os.environ.get("OLLAMA_URL", "http://localhost:11434")
REDIS_URL = os.environ.get("REDIS_URL", "redis://localhost:6379")
QDRANT_URL = os.environ.get("QDRANT_URL", "http://localhost:6333")
AGENT_CONCURRENCY = int(os.environ.get("AGENT_CONCURRENCY", "4"))
LOG_LEVEL = os.environ.get("LOG_LEVEL", "INFO")
SERVE_PORT = int(os.environ.get("SERVE_PORT", "8500"))
VERSION = "1.0.0"
PROJECT = "Windows AGI Benchmark Lab"
VENDOR = "Microsoft Corporation"


# ---------------------------------------------------------------------------
# Enums
# ---------------------------------------------------------------------------
class AgentType(str, Enum):
    INFERENCE = "inference"
    MEMORY = "memory"
    SEARCH = "search"
    CODE = "code"
    BENCHMARK = "benchmark"
    METRICS = "metrics"
    COORDINATOR = "coordinator"


class TaskStatus(str, Enum):
    PENDING = "pending"
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"
    CANCELLED = "cancelled"
    TIMEOUT = "timeout"


class AgentStatus(str, Enum):
    IDLE = "idle"
    BUSY = "busy"
    ERROR = "error"
    OFFLINE = "offline"


# ---------------------------------------------------------------------------
# Data Models
# ---------------------------------------------------------------------------
@dataclass
class Task:
    """A task to be executed by an agent."""

    task_id: str
    task_type: str
    agent_type: AgentType
    payload: dict[str, Any]
    priority: int = 5
    timeout_sec: int = 300
    created_at: str = field(default_factory=lambda: datetime.datetime.utcnow().isoformat() + "Z")
    started_at: str = ""
    completed_at: str = ""
    status: TaskStatus = TaskStatus.PENDING
    result: dict[str, Any] = field(default_factory=dict)
    error_message: str = ""
    agent_id: str = ""
    retries: int = 0
    max_retries: int = 3

    @classmethod
    def create(
        cls,
        task_type: str,
        agent_type: AgentType,
        payload: dict[str, Any],
        priority: int = 5,
        timeout_sec: int = 300,
    ) -> "Task":
        return cls(
            task_id=str(uuid.uuid4()),
            task_type=task_type,
            agent_type=agent_type,
            payload=payload,
            priority=priority,
            timeout_sec=timeout_sec,
        )


@dataclass
class AgentInfo:
    """Agent registration and status information."""

    agent_id: str
    agent_type: AgentType
    name: str
    version: str
    status: AgentStatus
    capabilities: list[str]
    current_task_id: str = ""
    tasks_completed: int = 0
    tasks_failed: int = 0
    avg_task_duration_sec: float = 0.0
    registered_at: str = field(default_factory=lambda: datetime.datetime.utcnow().isoformat() + "Z")
    last_heartbeat: str = field(default_factory=lambda: datetime.datetime.utcnow().isoformat() + "Z")
    host: str = field(default_factory=platform.node)
    pid: int = field(default_factory=os.getpid)


@dataclass
class OrchestratorStats:
    """Orchestrator runtime statistics."""

    uptime_sec: float
    total_tasks: int
    completed_tasks: int
    failed_tasks: int
    pending_tasks: int
    running_tasks: int
    registered_agents: int
    active_agents: int
    avg_task_duration_sec: float
    tasks_per_minute: float
    cpu_util_pct: float
    ram_used_gb: float
    timestamp: str


# ---------------------------------------------------------------------------
# Base Agent
# ---------------------------------------------------------------------------
class BaseAgent:
    """Base class for all AGI mesh agents."""

    def __init__(
        self,
        agent_type: AgentType,
        name: str,
        capabilities: list[str],
    ) -> None:
        self.agent_id = str(uuid.uuid4())[:8]
        self.agent_type = agent_type
        self.name = name
        self.capabilities = capabilities
        self.status = AgentStatus.IDLE
        self.tasks_completed = 0
        self.tasks_failed = 0
        self.total_duration_sec = 0.0
        self._running = False

        self.info = AgentInfo(
            agent_id=self.agent_id,
            agent_type=agent_type,
            name=name,
            version=VERSION,
            status=AgentStatus.IDLE,
            capabilities=capabilities,
        )

    async def execute(self, task: Task) -> dict[str, Any]:
        """Execute a task. Override in subclasses."""
        raise NotImplementedError

    async def run_task(self, task: Task) -> Task:
        """Run a task with lifecycle management."""
        self.status = AgentStatus.BUSY
        self.info.status = AgentStatus.BUSY
        self.info.current_task_id = task.task_id
        task.status = TaskStatus.RUNNING
        task.started_at = datetime.datetime.utcnow().isoformat() + "Z"
        task.agent_id = self.agent_id

        t_start = time.perf_counter()

        try:
            log.info("Agent %s executing task %s (%s)", self.agent_id, task.task_id, task.task_type)
            result = await asyncio.wait_for(
                self.execute(task),
                timeout=task.timeout_sec,
            )
            task.result = result
            task.status = TaskStatus.COMPLETED
            self.tasks_completed += 1
            log.info("Task %s completed by agent %s", task.task_id, self.agent_id)

        except asyncio.TimeoutError:
            task.status = TaskStatus.TIMEOUT
            task.error_message = f"Task timed out after {task.timeout_sec}s"
            self.tasks_failed += 1
            log.error("Task %s timed out", task.task_id)

        except Exception as exc:
            task.status = TaskStatus.FAILED
            task.error_message = str(exc)[:500]
            self.tasks_failed += 1
            log.error("Task %s failed: %s", task.task_id, exc)

        finally:
            elapsed = time.perf_counter() - t_start
            self.total_duration_sec += elapsed
            task.completed_at = datetime.datetime.utcnow().isoformat() + "Z"
            self.status = AgentStatus.IDLE
            self.info.status = AgentStatus.IDLE
            self.info.current_task_id = ""
            self.info.tasks_completed = self.tasks_completed
            self.info.tasks_failed = self.tasks_failed
            if self.tasks_completed > 0:
                self.info.avg_task_duration_sec = round(
                    self.total_duration_sec / self.tasks_completed, 3
                )

        return task

    def heartbeat(self) -> None:
        """Update agent heartbeat."""
        self.info.last_heartbeat = datetime.datetime.utcnow().isoformat() + "Z"


# ---------------------------------------------------------------------------
# Inference Agent
# ---------------------------------------------------------------------------
class InferenceAgent(BaseAgent):
    """LLM inference agent using Ollama."""

    def __init__(self) -> None:
        super().__init__(
            agent_type=AgentType.INFERENCE,
            name="InferenceAgent",
            capabilities=[
                "text_generation",
                "chat_completion",
                "embedding",
                "streaming",
                "model_management",
            ],
        )
        self.ollama_url = OLLAMA_URL

    async def execute(self, task: Task) -> dict[str, Any]:
        """Execute inference task."""
        import aiohttp  # type: ignore[import]

        task_type = task.task_type
        payload = task.payload

        if task_type == "generate":
            return await self._generate(payload, aiohttp)
        elif task_type == "chat":
            return await self._chat(payload, aiohttp)
        elif task_type == "embed":
            return await self._embed(payload, aiohttp)
        elif task_type == "list_models":
            return await self._list_models(aiohttp)
        else:
            raise ValueError(f"Unknown inference task type: {task_type}")

    async def _generate(self, payload: dict[str, Any], aiohttp: Any) -> dict[str, Any]:
        """Generate text completion."""
        model = payload.get("model", "llama3")
        prompt = payload.get("prompt", "")
        stream = payload.get("stream", False)
        options = payload.get("options", {})

        t_start = time.perf_counter()

        async with aiohttp.ClientSession() as session:
            async with session.post(
                f"{self.ollama_url}/api/generate",
                json={"model": model, "prompt": prompt, "stream": stream, "options": options},
                timeout=aiohttp.ClientTimeout(total=300),
            ) as response:
                response.raise_for_status()
                data = await response.json()

        elapsed = time.perf_counter() - t_start
        output_tokens = data.get("eval_count", 0)
        eval_duration_ns = data.get("eval_duration", 0)
        tps = output_tokens / (eval_duration_ns / 1e9) if eval_duration_ns > 0 else 0.0

        return {
            "model": model,
            "response": data.get("response", ""),
            "prompt_tokens": data.get("prompt_eval_count", 0),
            "output_tokens": output_tokens,
            "tokens_per_sec": round(tps, 2),
            "total_latency_ms": round(elapsed * 1000, 2),
            "done": data.get("done", True),
        }

    async def _chat(self, payload: dict[str, Any], aiohttp: Any) -> dict[str, Any]:
        """Chat completion."""
        model = payload.get("model", "llama3")
        messages = payload.get("messages", [])

        async with aiohttp.ClientSession() as session:
            async with session.post(
                f"{self.ollama_url}/api/chat",
                json={"model": model, "messages": messages, "stream": False},
                timeout=aiohttp.ClientTimeout(total=300),
            ) as response:
                response.raise_for_status()
                data = await response.json()

        return {
            "model": model,
            "message": data.get("message", {}),
            "done": data.get("done", True),
        }

    async def _embed(self, payload: dict[str, Any], aiohttp: Any) -> dict[str, Any]:
        """Generate embeddings."""
        model = payload.get("model", "nomic-embed-text")
        prompt = payload.get("prompt", "")

        async with aiohttp.ClientSession() as session:
            async with session.post(
                f"{self.ollama_url}/api/embeddings",
                json={"model": model, "prompt": prompt},
                timeout=aiohttp.ClientTimeout(total=60),
            ) as response:
                response.raise_for_status()
                data = await response.json()

        embedding = data.get("embedding", [])
        return {
            "model": model,
            "embedding": embedding,
            "dimensions": len(embedding),
        }

    async def _list_models(self, aiohttp: Any) -> dict[str, Any]:
        """List available models."""
        async with aiohttp.ClientSession() as session:
            async with session.get(
                f"{self.ollama_url}/api/tags",
                timeout=aiohttp.ClientTimeout(total=10),
            ) as response:
                response.raise_for_status()
                data = await response.json()

        models = [m["name"] for m in data.get("models", [])]
        return {"models": models, "count": len(models)}


# ---------------------------------------------------------------------------
# Memory Agent (Vector Store)
# ---------------------------------------------------------------------------
class MemoryAgent(BaseAgent):
    """Vector memory agent using Qdrant."""

    def __init__(self) -> None:
        super().__init__(
            agent_type=AgentType.MEMORY,
            name="MemoryAgent",
            capabilities=[
                "vector_store",
                "semantic_search",
                "document_storage",
                "collection_management",
            ],
        )
        self.qdrant_url = QDRANT_URL

    async def execute(self, task: Task) -> dict[str, Any]:
        """Execute memory task."""
        task_type = task.task_type
        payload = task.payload

        if task_type == "store":
            return await self._store(payload)
        elif task_type == "search":
            return await self._search(payload)
        elif task_type == "delete":
            return await self._delete(payload)
        elif task_type == "list_collections":
            return await self._list_collections()
        else:
            raise ValueError(f"Unknown memory task type: {task_type}")

    async def _store(self, payload: dict[str, Any]) -> dict[str, Any]:
        """Store a document with its embedding."""
        try:
            from qdrant_client import AsyncQdrantClient  # type: ignore[import]
            from qdrant_client.models import PointStruct, VectorParams, Distance  # type: ignore[import]

            collection = payload.get("collection", "agi-memory")
            document_id = payload.get("id", str(uuid.uuid4()))
            embedding = payload.get("embedding", [])
            metadata = payload.get("metadata", {})

            client = AsyncQdrantClient(url=self.qdrant_url)

            # Create collection if needed
            try:
                await client.create_collection(
                    collection_name=collection,
                    vectors_config=VectorParams(size=len(embedding), distance=Distance.COSINE),
                )
            except Exception:
                pass  # Collection may already exist

            # Store point
            await client.upsert(
                collection_name=collection,
                points=[PointStruct(
                    id=document_id,
                    vector=embedding,
                    payload=metadata,
                )],
            )

            return {"stored": True, "id": document_id, "collection": collection}

        except ImportError:
            return {"stored": False, "error": "qdrant-client not installed"}

    async def _search(self, payload: dict[str, Any]) -> dict[str, Any]:
        """Semantic search in vector store."""
        try:
            from qdrant_client import AsyncQdrantClient  # type: ignore[import]

            collection = payload.get("collection", "agi-memory")
            query_vector = payload.get("query_vector", [])
            limit = payload.get("limit", 10)
            score_threshold = payload.get("score_threshold", 0.7)

            client = AsyncQdrantClient(url=self.qdrant_url)
            results = await client.search(
                collection_name=collection,
                query_vector=query_vector,
                limit=limit,
                score_threshold=score_threshold,
            )

            return {
                "results": [
                    {
                        "id": str(r.id),
                        "score": r.score,
                        "payload": r.payload,
                    }
                    for r in results
                ],
                "count": len(results),
            }

        except ImportError:
            return {"results": [], "error": "qdrant-client not installed"}

    async def _delete(self, payload: dict[str, Any]) -> dict[str, Any]:
        """Delete documents from vector store."""
        try:
            from qdrant_client import AsyncQdrantClient  # type: ignore[import]
            from qdrant_client.models import PointIdsList  # type: ignore[import]

            collection = payload.get("collection", "agi-memory")
            ids = payload.get("ids", [])

            client = AsyncQdrantClient(url=self.qdrant_url)
            await client.delete(
                collection_name=collection,
                points_selector=PointIdsList(points=ids),
            )

            return {"deleted": True, "count": len(ids)}

        except ImportError:
            return {"deleted": False, "error": "qdrant-client not installed"}

    async def _list_collections(self) -> dict[str, Any]:
        """List all collections."""
        try:
            from qdrant_client import AsyncQdrantClient  # type: ignore[import]

            client = AsyncQdrantClient(url=self.qdrant_url)
            collections = await client.get_collections()
            return {
                "collections": [c.name for c in collections.collections],
                "count": len(collections.collections),
            }

        except ImportError:
            return {"collections": [], "error": "qdrant-client not installed"}


# ---------------------------------------------------------------------------
# Metrics Agent
# ---------------------------------------------------------------------------
class MetricsAgent(BaseAgent):
    """System and GPU metrics collection agent."""

    def __init__(self) -> None:
        super().__init__(
            agent_type=AgentType.METRICS,
            name="MetricsAgent",
            capabilities=[
                "cpu_metrics",
                "memory_metrics",
                "gpu_metrics_amd",
                "gpu_metrics_nvidia",
                "disk_metrics",
                "network_metrics",
            ],
        )

    async def execute(self, task: Task) -> dict[str, Any]:
        """Execute metrics collection task."""
        task_type = task.task_type

        if task_type == "system_snapshot":
            return await self._system_snapshot()
        elif task_type == "gpu_metrics":
            return await self._gpu_metrics()
        elif task_type == "cpu_metrics":
            return await self._cpu_metrics()
        else:
            raise ValueError(f"Unknown metrics task type: {task_type}")

    async def _system_snapshot(self) -> dict[str, Any]:
        """Collect full system snapshot."""
        mem = psutil.virtual_memory()
        cpu_freq = psutil.cpu_freq()

        return {
            "timestamp": datetime.datetime.utcnow().isoformat() + "Z",
            "cpu_util_pct": psutil.cpu_percent(interval=0.5),
            "cpu_freq_mhz": round(cpu_freq.current, 1) if cpu_freq else 0.0,
            "ram_used_gb": round(mem.used / (1024**3), 2),
            "ram_total_gb": round(mem.total / (1024**3), 2),
            "ram_util_pct": round(mem.percent, 2),
            "load_avg": list(os.getloadavg()) if hasattr(os, "getloadavg") else [0, 0, 0],
            "hostname": platform.node(),
            "os": platform.system(),
            "arch": platform.machine(),
        }

    async def _gpu_metrics(self) -> dict[str, Any]:
        """Collect GPU metrics."""
        import subprocess

        metrics: dict[str, Any] = {"vendor": "none", "metrics": {}}

        # Try NVIDIA
        try:
            result = subprocess.run(
                ["nvidia-smi", "--query-gpu=name,utilization.gpu,memory.used,memory.total,power.draw,temperature.gpu",
                 "--format=csv,noheader,nounits"],
                capture_output=True, text=True, timeout=5,
            )
            if result.returncode == 0:
                parts = result.stdout.strip().split(",")
                if len(parts) >= 6:
                    metrics["vendor"] = "nvidia"
                    metrics["metrics"] = {
                        "name": parts[0].strip(),
                        "gpu_util_pct": float(parts[1].strip()),
                        "vram_used_gb": round(float(parts[2].strip()) / 1024, 2),
                        "vram_total_gb": round(float(parts[3].strip()) / 1024, 2),
                        "power_watts": float(parts[4].strip()),
                        "temp_celsius": float(parts[5].strip()),
                    }
                    return metrics
        except (FileNotFoundError, subprocess.TimeoutExpired, ValueError):
            pass

        # Try AMD
        try:
            result = subprocess.run(
                ["rocm-smi", "--showuse", "--showtemp", "--showpower", "--showmemuse", "--json"],
                capture_output=True, text=True, timeout=5,
            )
            if result.returncode == 0:
                data = json.loads(result.stdout)
                for card_data in data.values():
                    if isinstance(card_data, dict):
                        metrics["vendor"] = "amd"
                        metrics["metrics"] = {
                            "gpu_util_pct": float(str(card_data.get("GPU use (%)", 0)).replace("%", "")),
                            "temp_celsius": float(str(card_data.get("Temperature (Sensor edge) (C)", 0)).replace("C", "")),
                            "power_watts": float(str(card_data.get("Average Graphics Package Power (W)", 0)).replace("W", "")),
                        }
                        break
        except (FileNotFoundError, subprocess.TimeoutExpired, json.JSONDecodeError, ValueError):
            pass

        return metrics

    async def _cpu_metrics(self) -> dict[str, Any]:
        """Collect detailed CPU metrics."""
        return {
            "timestamp": datetime.datetime.utcnow().isoformat() + "Z",
            "util_total_pct": psutil.cpu_percent(interval=0.5),
            "util_per_core": psutil.cpu_percent(interval=0.5, percpu=True),
            "cores_physical": psutil.cpu_count(logical=False),
            "cores_logical": psutil.cpu_count(logical=True),
            "freq_mhz": round(psutil.cpu_freq().current, 1) if psutil.cpu_freq() else 0.0,
            "load_avg": list(os.getloadavg()) if hasattr(os, "getloadavg") else [0, 0, 0],
        }


# ---------------------------------------------------------------------------
# Orchestrator
# ---------------------------------------------------------------------------
class AGIMeshOrchestrator:
    """Main AGI Mesh orchestrator."""

    def __init__(self) -> None:
        self.agents: dict[str, BaseAgent] = {}
        self.task_queue: asyncio.Queue[Task] = asyncio.Queue()
        self.completed_tasks: dict[str, Task] = {}
        self.running_tasks: dict[str, Task] = {}
        self._running = False
        self._start_time = time.time()
        self._total_tasks = 0
        self._completed_count = 0
        self._failed_count = 0

        # Register default agents
        self._register_default_agents()

    def _register_default_agents(self) -> None:
        """Register default agent fleet."""
        agents: list[BaseAgent] = [
            InferenceAgent(),
            MemoryAgent(),
            MetricsAgent(),
        ]
        for agent in agents:
            self.agents[agent.agent_id] = agent
            log.info("Registered agent: %s (%s)", agent.name, agent.agent_id)

    def get_stats(self) -> OrchestratorStats:
        """Get orchestrator statistics."""
        uptime = time.time() - self._start_time
        mem = psutil.virtual_memory()
        active_agents = sum(1 for a in self.agents.values() if a.status == AgentStatus.BUSY)

        return OrchestratorStats(
            uptime_sec=round(uptime, 2),
            total_tasks=self._total_tasks,
            completed_tasks=self._completed_count,
            failed_tasks=self._failed_count,
            pending_tasks=self.task_queue.qsize(),
            running_tasks=len(self.running_tasks),
            registered_agents=len(self.agents),
            active_agents=active_agents,
            avg_task_duration_sec=0.0,
            tasks_per_minute=round(self._completed_count / max(uptime / 60, 1), 2),
            cpu_util_pct=psutil.cpu_percent(interval=None),
            ram_used_gb=round(mem.used / (1024**3), 2),
            timestamp=datetime.datetime.utcnow().isoformat() + "Z",
        )

    async def submit_task(self, task: Task) -> str:
        """Submit a task to the queue."""
        await self.task_queue.put(task)
        self._total_tasks += 1
        log.info("Task submitted: %s (%s)", task.task_id, task.task_type)
        return task.task_id

    async def get_task_result(self, task_id: str) -> Task | None:
        """Get the result of a completed task."""
        return self.completed_tasks.get(task_id)

    def _find_available_agent(self, agent_type: AgentType) -> BaseAgent | None:
        """Find an available agent of the given type."""
        for agent in self.agents.values():
            if agent.agent_type == agent_type and agent.status == AgentStatus.IDLE:
                return agent
        return None

    async def _worker(self) -> None:
        """Worker coroutine that processes tasks from the queue."""
        while self._running:
            try:
                task = await asyncio.wait_for(self.task_queue.get(), timeout=1.0)
            except asyncio.TimeoutError:
                continue

            # Find available agent
            agent = self._find_available_agent(task.agent_type)
            if not agent:
                # Re-queue if no agent available
                await self.task_queue.put(task)
                await asyncio.sleep(0.1)
                continue

            # Execute task
            self.running_tasks[task.task_id] = task
            try:
                completed_task = await agent.run_task(task)
                self.completed_tasks[task.task_id] = completed_task

                if completed_task.status == TaskStatus.COMPLETED:
                    self._completed_count += 1
                else:
                    self._failed_count += 1

            finally:
                self.running_tasks.pop(task.task_id, None)
                self.task_queue.task_done()

    async def start(self, num_workers: int = 4) -> None:
        """Start the orchestrator."""
        self._running = True
        log.info("Starting AGI Mesh Orchestrator with %d workers", num_workers)

        workers = [asyncio.create_task(self._worker()) for _ in range(num_workers)]

        try:
            await asyncio.gather(*workers)
        except asyncio.CancelledError:
            log.info("Orchestrator stopped")

    def stop(self) -> None:
        """Stop the orchestrator."""
        self._running = False
        log.info("Orchestrator stopping...")


# ---------------------------------------------------------------------------
# FastAPI Server
# ---------------------------------------------------------------------------
def create_app() -> Any:
    """Create FastAPI application."""
    try:
        from fastapi import FastAPI, HTTPException  # type: ignore[import]
        from fastapi.middleware.cors import CORSMiddleware  # type: ignore[import]
        from pydantic import BaseModel  # type: ignore[import]
    except ImportError:
        log.error("FastAPI not installed. Run: pip install fastapi uvicorn")
        return None

    app = FastAPI(
        title="Windows AGI Benchmark Lab — AGI Mesh API",
        description=f"{PROJECT} — {VENDOR}",
        version=VERSION,
        docs_url="/docs",
        redoc_url="/redoc",
    )

    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    orchestrator = AGIMeshOrchestrator()

    class TaskRequest(BaseModel):
        task_type: str
        agent_type: str
        payload: dict[str, Any]
        priority: int = 5
        timeout_sec: int = 300

    @app.on_event("startup")
    async def startup() -> None:
        asyncio.create_task(orchestrator.start(num_workers=AGENT_CONCURRENCY))
        log.info("AGI Mesh API started on port %d", SERVE_PORT)

    @app.get("/health")
    async def health() -> dict[str, Any]:
        return {
            "status": "healthy",
            "project": PROJECT,
            "vendor": VENDOR,
            "version": VERSION,
            "timestamp": datetime.datetime.utcnow().isoformat() + "Z",
        }

    @app.get("/stats")
    async def stats() -> dict[str, Any]:
        return asdict(orchestrator.get_stats())

    @app.get("/agents")
    async def list_agents() -> dict[str, Any]:
        return {
            "agents": [asdict(a.info) for a in orchestrator.agents.values()],
            "count": len(orchestrator.agents),
        }

    @app.post("/tasks")
    async def submit_task(request: TaskRequest) -> dict[str, Any]:
        try:
            agent_type = AgentType(request.agent_type)
        except ValueError:
            raise HTTPException(status_code=400, detail=f"Invalid agent_type: {request.agent_type}")

        task = Task.create(
            task_type=request.task_type,
            agent_type=agent_type,
            payload=request.payload,
            priority=request.priority,
            timeout_sec=request.timeout_sec,
        )

        task_id = await orchestrator.submit_task(task)
        return {"task_id": task_id, "status": "submitted"}

    @app.get("/tasks/{task_id}")
    async def get_task(task_id: str) -> dict[str, Any]:
        task = await orchestrator.get_task_result(task_id)
        if not task:
            # Check running tasks
            running = orchestrator.running_tasks.get(task_id)
            if running:
                return asdict(running)
            raise HTTPException(status_code=404, detail=f"Task {task_id} not found")
        return asdict(task)

    @app.get("/metrics")
    async def prometheus_metrics() -> Any:
        from fastapi.responses import PlainTextResponse  # type: ignore[import]
        stats = orchestrator.get_stats()
        lines = [
            f"agi_orchestrator_uptime_sec {stats.uptime_sec}",
            f"agi_orchestrator_total_tasks {stats.total_tasks}",
            f"agi_orchestrator_completed_tasks {stats.completed_tasks}",
            f"agi_orchestrator_failed_tasks {stats.failed_tasks}",
            f"agi_orchestrator_pending_tasks {stats.pending_tasks}",
            f"agi_orchestrator_running_tasks {stats.running_tasks}",
            f"agi_orchestrator_registered_agents {stats.registered_agents}",
            f"agi_orchestrator_active_agents {stats.active_agents}",
            f"agi_orchestrator_cpu_util_pct {stats.cpu_util_pct}",
            f"agi_orchestrator_ram_used_gb {stats.ram_used_gb}",
        ]
        return PlainTextResponse("\n".join(lines) + "\n")

    return app


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main() -> int:
    """AGI Mesh Orchestrator entry point."""
    import argparse

    parser = argparse.ArgumentParser(description="AGI Mesh Orchestrator — Microsoft AGI Lab")
    parser.add_argument("--serve", action="store_true", help="Start API server")
    parser.add_argument("--port", type=int, default=SERVE_PORT)
    parser.add_argument("--workers", type=int, default=AGENT_CONCURRENCY)
    parser.add_argument("--verbose", "-v", action="store_true")
    args = parser.parse_args()

    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)

    if args.serve:
        try:
            import uvicorn  # type: ignore[import]
            app = create_app()
            if app:
                log.info("Starting AGI Mesh API on port %d", args.port)
                uvicorn.run(app, host="0.0.0.0", port=args.port, log_level="info")
            else:
                log.error("Failed to create FastAPI app")
                return 1
        except ImportError:
            log.error("uvicorn not installed. Run: pip install uvicorn")
            return 1
    else:
        # Run standalone orchestrator
        orchestrator = AGIMeshOrchestrator()
        log.info("Starting AGI Mesh Orchestrator (standalone mode)")
        log.info("Agents: %d registered", len(orchestrator.agents))
        stats = orchestrator.get_stats()
        log.info("Stats: %s", asdict(stats))

    return 0


if __name__ == "__main__":
    sys.exit(main())
