//! # Zenith Task Model
//!
//! Tasks are the atomic units of execution derived from Intents.
//! While an Intent represents a user goal, a Task represents a concrete
//! unit of work assigned to a specific domain and hardware resource.

use serde::{Deserialize, Serialize};
use uuid::Uuid;
use crate::types::{ZTaskId, ZSessionId, ZIdentityId, Priority, EnergyCost, LatencyBudgetMs, ZTimestamp};
use crate::domain::Domain;

/// Hardware resource a task is assigned to
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum HardwareResource {
    /// General-purpose CPU core(s)
    Cpu { cores: u8 },
    /// GPU compute
    Gpu { vram_mb: u32 },
    /// Neural Processing Unit
    Npu { tops: u32 },
    /// Digital Signal Processor
    Dsp,
    /// FPGA fabric
    Fpga,
    /// Modem / radio
    Modem,
    /// Storage I/O
    Storage,
    /// Network I/O
    Network,
    /// Quantum Processing Unit
    Qpu,
}

/// Task execution priority class
#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
pub enum PriorityClass {
    /// Background (lowest, e.g., sync, indexing)
    Background = 0,
    /// Normal (default user tasks)
    Normal = 1,
    /// Elevated (user-visible, interactive)
    Elevated = 2,
    /// High (foreground, real-time response needed)
    High = 3,
    /// Critical (system, safety, real-time audio/video)
    Critical = 4,
}

impl PriorityClass {
    /// Convert a raw priority byte to a priority class
    pub fn from_priority(p: Priority) -> Self {
        match p {
            0..=50   => PriorityClass::Background,
            51..=100 => PriorityClass::Normal,
            101..=150=> PriorityClass::Elevated,
            151..=200=> PriorityClass::High,
            _        => PriorityClass::Critical,
        }
    }
}

/// Current execution state of a task
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum TaskState {
    /// Waiting in the scheduler queue
    Queued,
    /// Actively executing on hardware
    Running,
    /// Blocked waiting for I/O or another task
    Blocked { reason: String },
    /// Preempted by a higher-priority task
    Preempted,
    /// Suspended (device sleeping)
    Suspended,
    /// Checkpointed and ready for migration
    Checkpointed,
    /// Migrating to another domain
    Migrating { from: Domain, to: Domain },
    /// Completed successfully
    Completed { result_bytes: usize },
    /// Failed with error
    Failed { code: i32, message: String },
    /// Cancelled
    Cancelled,
}

impl TaskState {
    /// Whether the task is in a terminal state
    pub fn is_terminal(&self) -> bool {
        matches!(
            self,
            TaskState::Completed { .. } | TaskState::Failed { .. } | TaskState::Cancelled
        )
    }

    /// Whether the task is consuming CPU/GPU/NPU right now
    pub fn is_executing(&self) -> bool {
        matches!(self, TaskState::Running)
    }
}

/// A concrete unit of work assigned to a domain and hardware resource
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ZenithTask {
    /// Unique task ID
    pub id: ZTaskId,
    /// Parent intent ID
    pub intent_id: ZTaskId,
    /// Owning session
    pub session: ZSessionId,
    /// Owning identity
    pub identity: ZIdentityId,
    /// Human-readable description
    pub description: String,
    /// Assigned execution domain
    pub domain: Domain,
    /// Assigned hardware resource
    pub hardware: HardwareResource,
    /// Priority
    pub priority: Priority,
    /// Priority class (derived)
    pub priority_class: PriorityClass,
    /// Energy cost estimate
    pub energy_cost: EnergyCost,
    /// Latency budget
    pub latency_budget_ms: LatencyBudgetMs,
    /// Current state
    pub state: TaskState,
    /// Serialized task payload (domain-specific)
    pub payload: Vec<u8>,
    /// Serialized result (populated on completion)
    pub result: Option<Vec<u8>>,
    /// Checkpoint snapshot (populated before migration)
    pub checkpoint: Option<Vec<u8>>,
    /// Submission timestamp
    pub submitted_at: ZTimestamp,
    /// Start timestamp
    pub started_at: Option<ZTimestamp>,
    /// Completion timestamp
    pub completed_at: Option<ZTimestamp>,
    /// Number of migration events
    pub migration_count: u32,
    /// Number of preemption events
    pub preemption_count: u32,
    /// Tags
    pub tags: Vec<String>,
}

impl ZenithTask {
    /// Create a new task
    pub fn new(
        intent_id: ZTaskId,
        session: ZSessionId,
        identity: ZIdentityId,
        description: impl Into<String>,
        domain: Domain,
        hardware: HardwareResource,
        priority: Priority,
    ) -> Self {
        let priority_class = PriorityClass::from_priority(priority);
        let now = ZTimestamp(
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default()
                .as_micros() as i64,
        );
        Self {
            id: Uuid::new_v4(),
            intent_id,
            session,
            identity,
            description: description.into(),
            domain,
            hardware,
            priority,
            priority_class,
            energy_cost: 50,
            latency_budget_ms: 100,
            state: TaskState::Queued,
            payload: Vec::new(),
            result: None,
            checkpoint: None,
            submitted_at: now,
            started_at: None,
            completed_at: None,
            migration_count: 0,
            preemption_count: 0,
            tags: Vec::new(),
        }
    }

    /// Start executing this task
    pub fn start(&mut self) {
        self.state = TaskState::Running;
        self.started_at = Some(ZTimestamp(
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default()
                .as_micros() as i64,
        ));
    }

    /// Complete this task with a result payload
    pub fn complete(&mut self, result: Vec<u8>) {
        let len = result.len();
        self.result = Some(result);
        self.state = TaskState::Completed { result_bytes: len };
        self.completed_at = Some(ZTimestamp(
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default()
                .as_micros() as i64,
        ));
    }

    /// Fail this task
    pub fn fail(&mut self, code: i32, message: impl Into<String>) {
        self.state = TaskState::Failed { code, message: message.into() };
        self.completed_at = Some(ZTimestamp(
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default()
                .as_micros() as i64,
        ));
    }

    /// Checkpoint this task for migration
    pub fn checkpoint(&mut self, snapshot: Vec<u8>) {
        self.checkpoint = Some(snapshot);
        self.state = TaskState::Checkpointed;
    }

    /// Migrate this task to a new domain
    pub fn migrate(&mut self, target: Domain) {
        let from = self.domain.clone();
        self.state = TaskState::Migrating { from, to: target.clone() };
        self.domain = target;
        self.migration_count += 1;
    }

    /// Preempt this task
    pub fn preempt(&mut self) {
        self.state = TaskState::Preempted;
        self.preemption_count += 1;
    }

    /// Resume after preemption
    pub fn resume(&mut self) {
        self.state = TaskState::Running;
    }

    /// Execution duration in microseconds (if completed)
    pub fn execution_duration_us(&self) -> Option<i64> {
        match (self.started_at, self.completed_at) {
            (Some(start), Some(end)) => Some(end.0 - start.0),
            _ => None,
        }
    }

    /// Add a tag
    pub fn tag(&mut self, t: impl Into<String>) {
        self.tags.push(t.into());
    }
}

/// Task queue — priority-ordered collection of pending tasks
#[derive(Debug, Default)]
pub struct TaskQueue {
    tasks: Vec<ZenithTask>,
}

impl TaskQueue {
    /// Create a new empty queue
    pub fn new() -> Self {
        Self::default()
    }

    /// Enqueue a task (maintains priority order)
    pub fn enqueue(&mut self, task: ZenithTask) {
        self.tasks.push(task);
        // Sort descending by priority
        self.tasks.sort_by(|a, b| b.priority.cmp(&a.priority));
    }

    /// Dequeue the highest-priority task
    pub fn dequeue(&mut self) -> Option<ZenithTask> {
        if self.tasks.is_empty() {
            None
        } else {
            Some(self.tasks.remove(0))
        }
    }

    /// Peek at the highest-priority task without removing it
    pub fn peek(&self) -> Option<&ZenithTask> {
        self.tasks.first()
    }

    /// Number of tasks in the queue
    pub fn len(&self) -> usize {
        self.tasks.len()
    }

    /// Whether the queue is empty
    pub fn is_empty(&self) -> bool {
        self.tasks.is_empty()
    }

    /// Drain all tasks for a specific domain
    pub fn drain_domain(&mut self, domain: &Domain) -> Vec<ZenithTask> {
        let mut drained = Vec::new();
        let mut remaining = Vec::new();
        for task in self.tasks.drain(..) {
            if &task.domain == domain {
                drained.push(task);
            } else {
                remaining.push(task);
            }
        }
        self.tasks = remaining;
        drained
    }
}

/// Task registry — tracks all tasks across all sessions
#[derive(Debug, Default)]
pub struct TaskRegistry {
    tasks: std::collections::HashMap<ZTaskId, ZenithTask>,
}

impl TaskRegistry {
    /// Create a new registry
    pub fn new() -> Self {
        Self::default()
    }

    /// Register a task
    pub fn register(&mut self, task: ZenithTask) {
        self.tasks.insert(task.id, task);
    }

    /// Get a task by ID
    pub fn get(&self, id: &ZTaskId) -> Option<&ZenithTask> {
        self.tasks.get(id)
    }

    /// Get a mutable task by ID
    pub fn get_mut(&mut self, id: &ZTaskId) -> Option<&mut ZenithTask> {
        self.tasks.get_mut(id)
    }

    /// Get all tasks for a session
    pub fn session_tasks(&self, session: &ZSessionId) -> Vec<&ZenithTask> {
        self.tasks.values().filter(|t| &t.session == session).collect()
    }

    /// Get all running tasks
    pub fn running_tasks(&self) -> Vec<&ZenithTask> {
        self.tasks.values().filter(|t| t.state.is_executing()).collect()
    }

    /// Get all tasks for a domain
    pub fn domain_tasks(&self, domain: &Domain) -> Vec<&ZenithTask> {
        self.tasks.values().filter(|t| &t.domain == domain).collect()
    }

    /// Total task count
    pub fn count(&self) -> usize {
        self.tasks.len()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn make_task(priority: Priority, domain: Domain) -> ZenithTask {
        ZenithTask::new(
            Uuid::new_v4(), Uuid::new_v4(), Uuid::new_v4(),
            "test task", domain, HardwareResource::Cpu { cores: 2 }, priority,
        )
    }

    #[test]
    fn task_queue_priority_order() {
        let mut queue = TaskQueue::new();
        queue.enqueue(make_task(50, Domain::Android));
        queue.enqueue(make_task(200, Domain::Windows));
        queue.enqueue(make_task(100, Domain::AI));

        let first = queue.dequeue().unwrap();
        assert_eq!(first.priority, 200);
        let second = queue.dequeue().unwrap();
        assert_eq!(second.priority, 100);
    }

    #[test]
    fn task_lifecycle() {
        let mut task = make_task(128, Domain::Windows);
        assert_eq!(task.state, TaskState::Queued);
        task.start();
        assert!(task.state.is_executing());
        task.complete(b"result".to_vec());
        assert!(task.state.is_terminal());
    }

    #[test]
    fn task_migration() {
        let mut task = make_task(100, Domain::Android);
        task.start();
        task.checkpoint(b"snapshot".to_vec());
        task.migrate(Domain::Windows);
        assert_eq!(task.domain, Domain::Windows);
        assert_eq!(task.migration_count, 1);
    }

    #[test]
    fn priority_class_mapping() {
        assert_eq!(PriorityClass::from_priority(0),   PriorityClass::Background);
        assert_eq!(PriorityClass::from_priority(75),  PriorityClass::Normal);
        assert_eq!(PriorityClass::from_priority(125), PriorityClass::Elevated);
        assert_eq!(PriorityClass::from_priority(175), PriorityClass::High);
        assert_eq!(PriorityClass::from_priority(255), PriorityClass::Critical);
    }

    #[test]
    fn task_registry_domain_filter() {
        let mut registry = TaskRegistry::new();
        for _ in 0..3 {
            registry.register(make_task(100, Domain::Windows));
        }
        for _ in 0..2 {
            registry.register(make_task(100, Domain::Android));
        }
        assert_eq!(registry.domain_tasks(&Domain::Windows).len(), 3);
        assert_eq!(registry.domain_tasks(&Domain::Android).len(), 2);
    }
}