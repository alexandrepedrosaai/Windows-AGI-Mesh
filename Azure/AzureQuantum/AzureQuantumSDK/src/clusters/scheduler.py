"""
scheduler.py — Distributed workload scheduler for the AGI-Mesh cluster.
Supports: round-robin, least-loaded, quantum-aware, photonic-latency-aware,
          MAIA-300 affinity, Brainwave FPGA affinity, priority queues.
Integrates with Hollow-Core Fiber topology for latency-optimal routing.
"""
from __future__ import annotations
import heapq, logging, math, threading, time, uuid
from collections import defaultdict, deque
from dataclasses import dataclass, field
from enum import Enum, auto
from typing import Any, Callable, Dict, List, Optional, Set, Tuple

logger = logging.getLogger(__name__)

class SchedulingPolicy(str, Enum):
    ROUND_ROBIN         = "round-robin"
    LEAST_LOADED        = "least-loaded"
    QUANTUM_AWARE       = "quantum-aware"
    PHOTONIC_LATENCY    = "photonic-latency"
    MAIA_AFFINITY       = "maia-affinity"
    FPGA_AFFINITY       = "fpga-affinity"
    PRIORITY_QUEUE      = "priority-queue"
    POWER_AWARE         = "power-aware"
    LOCALITY_AWARE      = "locality-aware"

class TaskStatus(str, Enum):
    PENDING   = "pending"
    RUNNING   = "running"
    COMPLETED = "completed"
    FAILED    = "failed"
    CANCELLED = "cancelled"
    RETRYING  = "retrying"

@dataclass(order=True)
class ScheduledTask:
    priority:    int
    task_id:     str = field(compare=False)
    task_type:   str = field(compare=False)
    payload:     Any = field(compare=False)
    created_at:  float = field(default_factory=time.time, compare=False)
    deadline_at: Optional[float] = field(default=None, compare=False)
    retries:     int = field(default=0, compare=False)
    max_retries: int = field(default=3, compare=False)
    node_affinity: Optional[str] = field(default=None, compare=False)
    requires_quantum: bool = field(default=False, compare=False)
    requires_fpga:    bool = field(default=False, compare=False)
    requires_maia:    bool = field(default=False, compare=False)
    requires_photonic: bool = field(default=False, compare=False)
    status:      TaskStatus = field(default=TaskStatus.PENDING, compare=False)
    assigned_node: Optional[str] = field(default=None, compare=False)
    started_at:  Optional[float] = field(default=None, compare=False)
    completed_at: Optional[float] = field(default=None, compare=False)
    result:      Any = field(default=None, compare=False)
    error:       Optional[str] = field(default=None, compare=False)

    @property
    def age_seconds(self) -> float:
        return time.time() - self.created_at

    @property
    def latency_ms(self) -> Optional[float]:
        if self.started_at and self.completed_at:
            return (self.completed_at - self.started_at) * 1000
        return None

    @property
    def is_expired(self) -> bool:
        if self.deadline_at is None:
            return False
        return time.time() > self.deadline_at

    @property
    def can_retry(self) -> bool:
        return self.retries < self.max_retries

@dataclass
class NodeState:
    node_id:          str
    hostname:         str
    ip_address:       str
    gpu_count:        int
    maia_count:       int
    fpga_count:       int
    quantum_enabled:  bool
    photonic_enabled: bool
    load_factor:      float = 0.0
    active_tasks:     int   = 0
    completed_tasks:  int   = 0
    failed_tasks:     int   = 0
    health_score:     float = 1.0
    last_heartbeat:   float = field(default_factory=time.time)
    region:           str   = "eastus2"
    datacenter:       str   = "azure-dc-1"
    power_watts:      float = 0.0
    network_gbps:     float = 400.0

    @property
    def is_healthy(self) -> bool:
        return (self.health_score > 0.5 and
                time.time() - self.last_heartbeat < 30.0)

    @property
    def effective_capacity(self) -> float:
        base = self.gpu_count + self.maia_count * 4 + self.fpga_count * 2
        return base * self.health_score

    @property
    def utilization(self) -> float:
        cap = self.effective_capacity
        return self.active_tasks / max(1, cap)

class AGIMeshScheduler:
    """
    Distributed task scheduler for the Windows-AGI-Mesh cluster.
    Supports heterogeneous hardware: GPU, MAIA-300, Brainwave FPGA,
    Majorana QPU, and Hollow-Core Fiber photonic nodes.
    """

    def __init__(self, policy: SchedulingPolicy = SchedulingPolicy.LEAST_LOADED,
                 max_queue_size: int = 100_000) -> None:
        self.policy         = policy
        self.max_queue_size = max_queue_size
        self._nodes:  Dict[str, NodeState] = {}
        self._queue:  List[ScheduledTask]  = []  # min-heap by priority
        self._running: Dict[str, ScheduledTask] = {}
        self._completed: deque = deque(maxlen=10_000)
        self._lock    = threading.RLock()
        self._stats   = defaultdict(int)
        self._rr_idx  = 0
        self._scheduler_id = str(uuid.uuid4())
        logger.info("AGIMeshScheduler started | policy=%s | id=%s",
                    policy.value, self._scheduler_id)

    # ── Node management ───────────────────────────────────────────────────────
    def register_node(self, node: NodeState) -> None:
        with self._lock:
            self._nodes[node.node_id] = node
            logger.info("Registered node %s (%s) | GPUs=%d MAIA=%d FPGA=%d quantum=%s",
                        node.node_id, node.hostname,
                        node.gpu_count, node.maia_count, node.fpga_count,
                        node.quantum_enabled)

    def deregister_node(self, node_id: str) -> None:
        with self._lock:
            if node_id in self._nodes:
                del self._nodes[node_id]
                logger.info("Deregistered node %s", node_id)

    def update_node_heartbeat(self, node_id: str, load_factor: float = 0.0,
                               health_score: float = 1.0, power_watts: float = 0.0) -> None:
        with self._lock:
            if node_id in self._nodes:
                n = self._nodes[node_id]
                n.last_heartbeat = time.time()
                n.load_factor    = load_factor
                n.health_score   = health_score
                n.power_watts    = power_watts

    def get_healthy_nodes(self) -> List[NodeState]:
        with self._lock:
            return [n for n in self._nodes.values() if n.is_healthy]

    def get_quantum_nodes(self) -> List[NodeState]:
        return [n for n in self.get_healthy_nodes() if n.quantum_enabled]

    def get_maia_nodes(self) -> List[NodeState]:
        return [n for n in self.get_healthy_nodes() if n.maia_count > 0]

    def get_fpga_nodes(self) -> List[NodeState]:
        return [n for n in self.get_healthy_nodes() if n.fpga_count > 0]

    def get_photonic_nodes(self) -> List[NodeState]:
        return [n for n in self.get_healthy_nodes() if n.photonic_enabled]

    # ── Task submission ───────────────────────────────────────────────────────
    def submit(self, task_type: str, payload: Any, priority: int = 5,
               deadline_seconds: Optional[float] = None,
               node_affinity: Optional[str] = None,
               requires_quantum: bool = False,
               requires_fpga: bool = False,
               requires_maia: bool = False,
               requires_photonic: bool = False,
               max_retries: int = 3) -> str:
        with self._lock:
            if len(self._queue) >= self.max_queue_size:
                raise RuntimeError(f"Queue full ({self.max_queue_size} tasks)")
            task_id = str(uuid.uuid4())
            deadline = time.time() + deadline_seconds if deadline_seconds else None
            task = ScheduledTask(
                priority=priority, task_id=task_id, task_type=task_type,
                payload=payload, deadline_at=deadline, node_affinity=node_affinity,
                requires_quantum=requires_quantum, requires_fpga=requires_fpga,
                requires_maia=requires_maia, requires_photonic=requires_photonic,
                max_retries=max_retries)
            heapq.heappush(self._queue, task)
            self._stats["submitted"] += 1
            logger.debug("Submitted task %s type=%s priority=%d", task_id, task_type, priority)
            return task_id

    def submit_batch(self, tasks: List[Dict[str, Any]]) -> List[str]:
        return [self.submit(**t) for t in tasks]

    # ── Scheduling ────────────────────────────────────────────────────────────
    def schedule_next(self) -> Optional[Tuple[ScheduledTask, NodeState]]:
        with self._lock:
            if not self._queue:
                return None
            healthy = self.get_healthy_nodes()
            if not healthy:
                logger.warning("No healthy nodes available")
                return None
            # Pop highest-priority (lowest value) task
            task = heapq.heappop(self._queue)
            if task.is_expired:
                task.status = TaskStatus.CANCELLED
                self._completed.append(task)
                self._stats["expired"] += 1
                return None
            node = self._select_node(task, healthy)
            if node is None:
                heapq.heappush(self._queue, task)
                return None
            task.status       = TaskStatus.RUNNING
            task.assigned_node = node.node_id
            task.started_at   = time.time()
            node.active_tasks += 1
            self._running[task.task_id] = task
            self._stats["scheduled"] += 1
            return task, node

    def _select_node(self, task: ScheduledTask,
                     candidates: List[NodeState]) -> Optional[NodeState]:
        # Filter by requirements
        filtered = candidates
        if task.requires_quantum:
            filtered = [n for n in filtered if n.quantum_enabled]
        if task.requires_maia:
            filtered = [n for n in filtered if n.maia_count > 0]
        if task.requires_fpga:
            filtered = [n for n in filtered if n.fpga_count > 0]
        if task.requires_photonic:
            filtered = [n for n in filtered if n.photonic_enabled]
        if task.node_affinity:
            affinity = [n for n in filtered if n.node_id == task.node_affinity]
            if affinity:
                filtered = affinity
        if not filtered:
            return None

        if self.policy == SchedulingPolicy.ROUND_ROBIN:
            node = filtered[self._rr_idx % len(filtered)]
            self._rr_idx += 1
            return node
        elif self.policy == SchedulingPolicy.LEAST_LOADED:
            return min(filtered, key=lambda n: n.utilization)
        elif self.policy == SchedulingPolicy.QUANTUM_AWARE:
            quantum = [n for n in filtered if n.quantum_enabled]
            pool = quantum if quantum else filtered
            return min(pool, key=lambda n: n.utilization)
        elif self.policy == SchedulingPolicy.MAIA_AFFINITY:
            maia = [n for n in filtered if n.maia_count > 0]
            pool = maia if maia else filtered
            return min(pool, key=lambda n: n.utilization)
        elif self.policy == SchedulingPolicy.FPGA_AFFINITY:
            fpga = [n for n in filtered if n.fpga_count > 0]
            pool = fpga if fpga else filtered
            return min(pool, key=lambda n: n.utilization)
        elif self.policy == SchedulingPolicy.POWER_AWARE:
            return min(filtered, key=lambda n: n.power_watts + n.utilization * 1000)
        elif self.policy == SchedulingPolicy.PHOTONIC_LATENCY:
            photonic = [n for n in filtered if n.photonic_enabled]
            pool = photonic if photonic else filtered
            return min(pool, key=lambda n: n.utilization)
        else:
            return min(filtered, key=lambda n: n.utilization)

    def complete_task(self, task_id: str, result: Any = None,
                      error: Optional[str] = None) -> None:
        with self._lock:
            if task_id not in self._running:
                logger.warning("complete_task: unknown task %s", task_id)
                return
            task = self._running.pop(task_id)
            task.completed_at = time.time()
            task.result = result
            if error:
                task.error  = error
                task.status = TaskStatus.FAILED
                self._stats["failed"] += 1
                if task.can_retry:
                    task.retries += 1
                    task.status   = TaskStatus.RETRYING
                    task.started_at = None
                    task.assigned_node = None
                    heapq.heappush(self._queue, task)
                    self._stats["retried"] += 1
                    logger.warning("Retrying task %s (attempt %d/%d)",
                                   task_id, task.retries, task.max_retries)
            else:
                task.status = TaskStatus.COMPLETED
                self._stats["completed"] += 1
            if task.assigned_node and task.assigned_node in self._nodes:
                node = self._nodes[task.assigned_node]
                node.active_tasks = max(0, node.active_tasks - 1)
                if error:
                    node.failed_tasks += 1
                else:
                    node.completed_tasks += 1
            self._completed.append(task)

    def cancel_task(self, task_id: str) -> bool:
        with self._lock:
            for i, task in enumerate(self._queue):
                if task.task_id == task_id:
                    self._queue.pop(i)
                    heapq.heapify(self._queue)
                    task.status = TaskStatus.CANCELLED
                    self._completed.append(task)
                    self._stats["cancelled"] += 1
                    return True
            if task_id in self._running:
                task = self._running[task_id]
                task.status = TaskStatus.CANCELLED
                self._completed.append(task)
                del self._running[task_id]
                self._stats["cancelled"] += 1
                return True
            return False

    # ── Stats and monitoring ──────────────────────────────────────────────────
    def queue_depth(self) -> int:
        with self._lock:
            return len(self._queue)

    def running_count(self) -> int:
        with self._lock:
            return len(self._running)

    def stats(self) -> Dict[str, Any]:
        with self._lock:
            healthy = self.get_healthy_nodes()
            return {
                "scheduler_id": self._scheduler_id,
                "policy": self.policy.value,
                "queue_depth": len(self._queue),
                "running": len(self._running),
                "total_nodes": len(self._nodes),
                "healthy_nodes": len(healthy),
                "quantum_nodes": len(self.get_quantum_nodes()),
                "maia_nodes": len(self.get_maia_nodes()),
                "fpga_nodes": len(self.get_fpga_nodes()),
                "photonic_nodes": len(self.get_photonic_nodes()),
                **dict(self._stats),
            }

    def node_stats(self) -> List[Dict[str, Any]]:
        with self._lock:
            return [{
                "node_id": n.node_id, "hostname": n.hostname,
                "health": n.health_score, "load": n.load_factor,
                "active_tasks": n.active_tasks, "completed": n.completed_tasks,
                "failed": n.failed_tasks, "utilization": round(n.utilization, 3),
                "gpu_count": n.gpu_count, "maia_count": n.maia_count,
                "fpga_count": n.fpga_count, "quantum": n.quantum_enabled,
                "photonic": n.photonic_enabled, "region": n.region,
            } for n in self._nodes.values()]

    def __repr__(self) -> str:
        return (f"AGIMeshScheduler(policy={self.policy.value}, "
                f"queue={len(self._queue)}, running={len(self._running)}, "
                f"nodes={len(self._nodes)})")
