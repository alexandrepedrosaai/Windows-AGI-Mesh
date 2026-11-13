"""
worker_01.py — AGI-Mesh cluster worker 01.
Role: LLM prefill (MAIA-300).
Handles task dispatch, execution, heartbeat, and result reporting.
"""
from __future__ import annotations
import logging, math, random, threading, time, uuid
from typing import Any, Callable, Dict, List, Optional
from .scheduler import AGIMeshScheduler, NodeState, ScheduledTask, TaskStatus

logger = logging.getLogger(__name__)

WORKER_ID = 1
WORKER_VERSION = "2.0.0"
WORKER_ROLE = "LLM prefill (MAIA-300)"

class Worker01:
    """
    AGI-Mesh cluster worker 01.
    Role: LLM prefill (MAIA-300).
    Connects to the AGIMeshScheduler and processes assigned tasks.
    """

    def __init__(self, scheduler: AGIMeshScheduler,
                 node_id: Optional[str] = None,
                 heartbeat_interval: float = 5.0,
                 max_concurrent_tasks: int = 8) -> None:
        self.worker_id   = node_id or f"worker-01-{uuid.uuid4().hex[:8]}"
        self.scheduler   = scheduler
        self.heartbeat_interval = heartbeat_interval
        self.max_concurrent = max_concurrent_tasks
        self._active_tasks: Dict[str, threading.Thread] = {}
        self._lock       = threading.RLock()
        self._running    = False
        self._heartbeat_thread: Optional[threading.Thread] = None
        self._poll_thread: Optional[threading.Thread] = None
        self._stats      = {"processed": 0, "failed": 0, "retried": 0}
        self._rng        = random.Random(WORKER_ID)
        self._node_state = NodeState(
            node_id=self.worker_id,
            hostname=f"worker-01.agi-mesh.local",
            ip_address=f"10.1.0.1",
            gpu_count=8 if 1 <= 6 else 0,
            maia_count=96 if 1 <= 3 else 0,
            fpga_count=8 if 4 <= 1 <= 6 else 0,
            quantum_enabled=false,
            photonic_enabled=false,
            region="eastus2", datacenter="azure-dc-1")
        scheduler.register_node(self._node_state)
        logger.info("Worker %s initialized | role=%s", self.worker_id, WORKER_ROLE)

    def start(self) -> None:
        self._running = True
        self._heartbeat_thread = threading.Thread(
            target=self._heartbeat_loop, daemon=True, name=f"worker-01-heartbeat")
        self._poll_thread = threading.Thread(
            target=self._poll_loop, daemon=True, name=f"worker-01-poll")
        self._heartbeat_thread.start()
        self._poll_thread.start()
        logger.info("Worker %s started", self.worker_id)

    def stop(self) -> None:
        self._running = False
        logger.info("Worker %s stopping | processed=%d failed=%d",
                    self.worker_id, self._stats["processed"], self._stats["failed"])

    def _heartbeat_loop(self) -> None:
        while self._running:
            try:
                load = len(self._active_tasks) / max(1, self.max_concurrent)
                self.scheduler.update_node_heartbeat(
                    self.worker_id, load_factor=load,
                    health_score=1.0 - load * 0.1,
                    power_watts=self._estimate_power())
            except Exception as exc:
                logger.error("Heartbeat error: %s", exc)
            time.sleep(self.heartbeat_interval)

    def _poll_loop(self) -> None:
        while self._running:
            try:
                with self._lock:
                    if len(self._active_tasks) >= self.max_concurrent:
                        time.sleep(0.01)
                        continue
                result = self.scheduler.schedule_next()
                if result is None:
                    time.sleep(0.005)
                    continue
                task, node = result
                if node.node_id != self.worker_id:
                    time.sleep(0.001)
                    continue
                t = threading.Thread(target=self._execute_task, args=(task,),
                                     daemon=True, name=f"task-{task.task_id[:8]}")
                with self._lock:
                    self._active_tasks[task.task_id] = t
                t.start()
            except Exception as exc:
                logger.error("Poll loop error: %s", exc)
                time.sleep(0.1)

    def _execute_task(self, task: ScheduledTask) -> None:
        try:
            result = self._dispatch(task)
            self.scheduler.complete_task(task.task_id, result=result)
            with self._lock:
                self._stats["processed"] += 1
        except Exception as exc:
            logger.error("Task %s failed: %s", task.task_id, exc)
            self.scheduler.complete_task(task.task_id, error=str(exc))
            with self._lock:
                self._stats["failed"] += 1
        finally:
            with self._lock:
                self._active_tasks.pop(task.task_id, None)

    def _dispatch(self, task: ScheduledTask) -> Any:
        handlers = {
            "experiment":   self._handle_experiment,
            "inference":    self._handle_inference,
            "training":     self._handle_training,
            "benchmark":    self._handle_benchmark,
            "factorize":    self._handle_factorize,
            "photonic":     self._handle_photonic,
            "qec":          self._handle_qec,
        }
        handler = handlers.get(task.task_type, self._handle_generic)
        return handler(task)

    def _handle_experiment(self, task: ScheduledTask) -> dict:
        payload = task.payload or {}
        qubits  = payload.get("qubit_count", 4)
        shots   = payload.get("shot_count", 100)
        theta_z = payload.get("theta_z", 0.5)
        theta_y = payload.get("theta_y", 0.3)
        # Simulate experiment
        samples = [0.5 + 0.3*math.sin(theta_z*i/max(1,shots)) + self._rng.gauss(0,0.05)
                   for i in range(shots)]
        mean = sum(samples)/len(samples)
        var  = sum((s-mean)**2 for s in samples)/len(samples)
        return {"mean": mean, "deviation": math.sqrt(max(0,var)),
                "above_threshold": mean > 0.5, "shot_count": shots,
                "qubit_count": qubits, "worker_id": self.worker_id}

    def _handle_inference(self, task: ScheduledTask) -> dict:
        payload = task.payload or {}
        n_tokens = payload.get("max_new_tokens", 64)
        tokens = [self._rng.randint(100, 50000) for _ in range(n_tokens)]
        return {"output_tokens": tokens, "token_count": n_tokens,
                "worker_id": self.worker_id, "latency_ms": self._rng.uniform(100, 500)}

    def _handle_training(self, task: ScheduledTask) -> dict:
        payload = task.payload or {}
        step    = payload.get("step", 0)
        loss    = 4.0*math.exp(-step/10000.0) + 0.5 + self._rng.gauss(0, 0.05)
        return {"step": step, "loss": max(0.1, loss), "worker_id": self.worker_id,
                "gradient_norm": self._rng.uniform(0.5, 2.0),
                "tokens_per_second": self._rng.uniform(50000, 200000)}

    def _handle_benchmark(self, task: ScheduledTask) -> dict:
        payload = task.payload or {}
        mean = self._rng.uniform(0.3, 0.7)
        return {"mean": mean, "deviation": self._rng.uniform(0.01, 0.1),
                "passed": True, "worker_id": self.worker_id}

    def _handle_factorize(self, task: ScheduledTask) -> dict:
        payload = task.payload or {}
        n = payload.get("number", 15)
        for i in range(2, int(math.isqrt(n))+1):
            if n % i == 0:
                return {"n": n, "factor1": i, "factor2": n//i, "is_prime": False}
        return {"n": n, "factor1": 1, "factor2": n, "is_prime": True}

    def _handle_photonic(self, task: ScheduledTask) -> dict:
        payload = task.payload or {}
        data_kb = payload.get("data_kb", 1.0)
        latency = self._rng.uniform(100, 500)
        return {"data_kb": data_kb, "latency_us": latency,
                "photonic_ops": int(data_kb*1000), "worker_id": self.worker_id}

    def _handle_qec(self, task: ScheduledTask) -> dict:
        payload = task.payload or {}
        syndrome = payload.get("syndrome", [0]*8)
        corrected = [0]*len(syndrome)
        return {"syndrome": syndrome, "corrected": corrected,
                "is_correctable": True, "worker_id": self.worker_id}

    def _handle_generic(self, task: ScheduledTask) -> dict:
        time.sleep(self._rng.uniform(0.001, 0.01))
        return {"task_type": task.task_type, "worker_id": self.worker_id, "ok": True}

    def _estimate_power(self) -> float:
        base = 200.0 * (8 if 1 <= 6 else 1)  # GPU power
        load = len(self._active_tasks) / max(1, self.max_concurrent)
        return base * (0.3 + 0.7 * load)

    @property
    def active_task_count(self) -> int:
        with self._lock:
            return len(self._active_tasks)

    def stats(self) -> dict:
        with self._lock:
            return {
                "worker_id": self.worker_id,
                "role": WORKER_ROLE,
                "active_tasks": len(self._active_tasks),
                **self._stats,
            }

    def __repr__(self) -> str:
        return f"Worker01(id={self.worker_id!r}, active={self.active_task_count})"
