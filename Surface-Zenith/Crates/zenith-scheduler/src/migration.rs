//! # Zenith Task Migration Engine
//!
//! Handles live migration of tasks between domains.
//! Supports both full-snapshot and incremental (dirty-page) migration.

use uuid::Uuid;
use std::collections::HashMap;
use zenith_abi::domain::Domain;
use zenith_abi::task::{ZenithTask, TaskState};
use zenith_abi::memory::MemoryPage;
use zenith_abi::types::{ZTaskId, ZSessionId, ZTimestamp};
use crate::error::SchedulerError;

// ---------------------------------------------------------------------------
// Migration mode
// ---------------------------------------------------------------------------

/// Migration strategy
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum MigrationMode {
    /// Full snapshot: serialize entire task state
    FullSnapshot,
    /// Incremental: only transfer dirty pages
    Incremental,
    /// Live: copy pages while task continues running (minimal downtime)
    Live,
}

// ---------------------------------------------------------------------------
// Migration reason
// ---------------------------------------------------------------------------

/// Why a migration was triggered
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum MigrationTrigger {
    /// Device form factor changed (fold/unfold)
    FormFactorChange,
    /// Source domain failed
    DomainFailure,
    /// Load balancing decision
    LoadBalance,
    /// User explicitly requested migration
    UserRequested,
    /// Power optimization
    PowerOptimization,
    /// Better hardware became available
    HardwareUpgrade,
    /// Security policy enforcement
    SecurityPolicy,
}

// ---------------------------------------------------------------------------
// Task snapshot
// ---------------------------------------------------------------------------

/// A complete snapshot of a task's execution state
#[derive(Debug, Clone)]
pub struct TaskSnapshot {
    /// Task ID
    pub task_id: ZTaskId,
    /// Session ID
    pub session_id: ZSessionId,
    /// Source domain
    pub source_domain: Domain,
    /// Snapshot version (for compatibility)
    pub version: u32,
    /// Simulated CPU register state
    pub cpu_state: Vec<u8>,
    /// Memory pages (full or dirty-only)
    pub memory_pages: Vec<MemoryPage>,
    /// Task-specific state (domain-serialized)
    pub task_state: Vec<u8>,
    /// Open file descriptors (handles)
    pub open_handles: Vec<u64>,
    /// Snapshot creation timestamp
    pub created_at: ZTimestamp,
    /// Whether this is a full or incremental snapshot
    pub is_incremental: bool,
    /// Checksum for integrity verification
    pub checksum: u32,
}

impl TaskSnapshot {
    /// Create a new snapshot
    pub fn new(
        task_id: ZTaskId,
        session_id: ZSessionId,
        source_domain: Domain,
        cpu_state: Vec<u8>,
        memory_pages: Vec<MemoryPage>,
        task_state: Vec<u8>,
        is_incremental: bool,
    ) -> Self {
        let checksum = Self::compute_checksum(&cpu_state, &task_state);
        Self {
            task_id,
            session_id,
            source_domain,
            version: 1,
            cpu_state,
            memory_pages,
            task_state,
            open_handles: Vec::new(),
            created_at: ZTimestamp(
                std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .unwrap_or_default()
                    .as_micros() as i64,
            ),
            is_incremental,
            checksum,
        }
    }

    /// Compute a simple checksum for integrity verification
    fn compute_checksum(cpu_state: &[u8], task_state: &[u8]) -> u32 {
        let mut sum = 0u32;
        for &b in cpu_state.iter().chain(task_state.iter()) {
            sum = sum.wrapping_add(b as u32);
        }
        sum
    }

    /// Verify snapshot integrity
    pub fn verify(&self) -> bool {
        let expected = Self::compute_checksum(&self.cpu_state, &self.task_state);
        self.checksum == expected
    }

    /// Total size in bytes
    pub fn size_bytes(&self) -> usize {
        self.cpu_state.len()
            + self.task_state.len()
            + self.memory_pages.iter().map(|p| p.bytes.len()).sum::<usize>()
    }

    /// Number of dirty pages
    pub fn dirty_page_count(&self) -> usize {
        self.memory_pages.iter().filter(|p| p.dirty).count()
    }

    /// Serialize to bytes (simplified — production would use bincode)
    pub fn serialize(&self) -> Vec<u8> {
        let mut buf = Vec::new();
        buf.extend_from_slice(&self.version.to_be_bytes());
        buf.extend_from_slice(&self.checksum.to_be_bytes());
        buf.extend_from_slice(&(self.cpu_state.len() as u32).to_be_bytes());
        buf.extend_from_slice(&self.cpu_state);
        buf.extend_from_slice(&(self.task_state.len() as u32).to_be_bytes());
        buf.extend_from_slice(&self.task_state);
        buf
    }

    /// Deserialize from bytes
    pub fn deserialize(data: &[u8]) -> Result<Self, SchedulerError> {
        if data.len() < 12 {
            return Err(SchedulerError::MigrationFailed {
                reason: "snapshot data too short".into(),
            });
        }
        let version  = u32::from_be_bytes(data[0..4].try_into().unwrap());
        let checksum = u32::from_be_bytes(data[4..8].try_into().unwrap());
        let cpu_len  = u32::from_be_bytes(data[8..12].try_into().unwrap()) as usize;

        if data.len() < 12 + cpu_len + 4 {
            return Err(SchedulerError::MigrationFailed {
                reason: "snapshot data truncated".into(),
            });
        }

        let cpu_state = data[12..12 + cpu_len].to_vec();
        let task_len  = u32::from_be_bytes(
            data[12 + cpu_len..16 + cpu_len].try_into().unwrap()
        ) as usize;
        let task_state = if data.len() >= 16 + cpu_len + task_len {
            data[16 + cpu_len..16 + cpu_len + task_len].to_vec()
        } else {
            Vec::new()
        };

        Ok(Self {
            task_id: Uuid::new_v4(),
            session_id: Uuid::new_v4(),
            source_domain: Domain::Windows,
            version,
            cpu_state,
            memory_pages: Vec::new(),
            task_state,
            open_handles: Vec::new(),
            created_at: ZTimestamp(0),
            is_incremental: false,
            checksum,
        })
    }
}

// ---------------------------------------------------------------------------
// Migration plan
// ---------------------------------------------------------------------------

/// A planned migration from one domain to another
#[derive(Debug, Clone)]
pub struct MigrationPlan {
    /// Unique migration ID
    pub id: Uuid,
    /// Task being migrated
    pub task_id: ZTaskId,
    /// Source domain
    pub from: Domain,
    /// Target domain
    pub to: Domain,
    /// Migration mode
    pub mode: MigrationMode,
    /// Trigger reason
    pub trigger: MigrationTrigger,
    /// Estimated downtime in milliseconds
    pub estimated_downtime_ms: u32,
    /// Estimated data transfer size in bytes
    pub estimated_transfer_bytes: u64,
}

impl MigrationPlan {
    /// Create a new migration plan
    pub fn new(
        task_id: ZTaskId,
        from: Domain,
        to: Domain,
        mode: MigrationMode,
        trigger: MigrationTrigger,
    ) -> Self {
        let estimated_downtime_ms = match mode {
            MigrationMode::FullSnapshot  => 100,
            MigrationMode::Incremental   => 20,
            MigrationMode::Live          => 5,
        };
        Self {
            id: Uuid::new_v4(),
            task_id,
            from,
            to,
            mode,
            trigger,
            estimated_downtime_ms,
            estimated_transfer_bytes: 0,
        }
    }
}

// ---------------------------------------------------------------------------
// Migration result
// ---------------------------------------------------------------------------

/// Result of a completed migration
#[derive(Debug, Clone)]
pub struct MigrationResult {
    pub plan_id: Uuid,
    pub task_id: ZTaskId,
    pub from: Domain,
    pub to: Domain,
    pub success: bool,
    pub actual_downtime_ms: u32,
    pub bytes_transferred: u64,
    pub pages_transferred: u32,
    pub error: Option<String>,
}

// ---------------------------------------------------------------------------
// Migration engine
// ---------------------------------------------------------------------------

/// The Zenith Task Migration Engine
///
/// Orchestrates live migration of tasks between domains.
#[derive(Debug, Default)]
pub struct MigrationEngine {
    /// Active migrations (plan_id → plan)
    active: HashMap<Uuid, MigrationPlan>,
    /// Completed migrations
    history: Vec<MigrationResult>,
    /// Total migrations attempted
    total_attempted: u64,
    /// Total migrations succeeded
    total_succeeded: u64,
}

impl MigrationEngine {
    /// Create a new migration engine
    pub fn new() -> Self { Self::default() }

    /// Plan a migration
    pub fn plan(
        &mut self,
        task_id: ZTaskId,
        from: Domain,
        to: Domain,
        mode: MigrationMode,
        trigger: MigrationTrigger,
    ) -> Result<MigrationPlan, SchedulerError> {
        if from == to {
            return Err(SchedulerError::MigrationFailed {
                reason: "source and target domains must differ".into(),
            });
        }
        let plan = MigrationPlan::new(task_id, from, to, mode, trigger);
        self.active.insert(plan.id, plan.clone());
        Ok(plan)
    }

    /// Execute a migration (simulated)
    pub fn execute(
        &mut self,
        plan_id: &Uuid,
        task: &mut ZenithTask,
        snapshot: TaskSnapshot,
    ) -> Result<MigrationResult, SchedulerError> {
        let plan = self.active.remove(plan_id)
            .ok_or_else(|| SchedulerError::MigrationFailed {
                reason: format!("plan {plan_id} not found"),
            })?;

        self.total_attempted += 1;

        // Verify snapshot integrity
        if !snapshot.verify() {
            let result = MigrationResult {
                plan_id: *plan_id,
                task_id: plan.task_id,
                from: plan.from.clone(),
                to: plan.to.clone(),
                success: false,
                actual_downtime_ms: 0,
                bytes_transferred: 0,
                pages_transferred: 0,
                error: Some("snapshot integrity check failed".into()),
            };
            self.history.push(result.clone());
            return Err(SchedulerError::MigrationFailed {
                reason: "snapshot integrity check failed".into(),
            });
        }

        let bytes_transferred = snapshot.size_bytes() as u64;
        let pages_transferred = snapshot.memory_pages.len() as u32;

        // Perform the migration
        task.migrate(plan.to.clone());

        let result = MigrationResult {
            plan_id: *plan_id,
            task_id: plan.task_id,
            from: plan.from,
            to: plan.to,
            success: true,
            actual_downtime_ms: plan.estimated_downtime_ms,
            bytes_transferred,
            pages_transferred,
            error: None,
        };

        self.total_succeeded += 1;
        self.history.push(result.clone());

        tracing::info!(
            "Migration {} completed: {} pages, {} bytes transferred",
            plan_id, pages_transferred, bytes_transferred
        );

        Ok(result)
    }

    /// Success rate (0.0–1.0)
    pub fn success_rate(&self) -> f64 {
        if self.total_attempted == 0 { return 1.0; }
        self.total_succeeded as f64 / self.total_attempted as f64
    }

    /// Migration history
    pub fn history(&self) -> &[MigrationResult] {
        &self.history
    }

    /// Total migrations attempted
    pub fn total_attempted(&self) -> u64 { self.total_attempted }

    /// Total migrations succeeded
    pub fn total_succeeded(&self) -> u64 { self.total_succeeded }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;
    use zenith_abi::task::HardwareResource;

    fn make_task() -> ZenithTask {
        ZenithTask::new(
            Uuid::new_v4(), Uuid::new_v4(), Uuid::new_v4(),
            "test task", Domain::Android,
            HardwareResource::Cpu { cores: 2 }, 128,
        )
    }

    fn make_snapshot(task: &ZenithTask) -> TaskSnapshot {
        TaskSnapshot::new(
            task.id,
            task.session,
            task.domain.clone(),
            vec![0x41u8; 64],  // simulated CPU registers
            vec![],
            vec![0x42u8; 128], // simulated task state
            false,
        )
    }

    #[test]
    fn snapshot_integrity() {
        let task = make_task();
        let snap = make_snapshot(&task);
        assert!(snap.verify());
    }

    #[test]
    fn snapshot_tamper_detected() {
        let task = make_task();
        let mut snap = make_snapshot(&task);
        snap.cpu_state[0] ^= 0xFF; // tamper
        assert!(!snap.verify());
    }

    #[test]
    fn snapshot_serialize_deserialize() {
        let task = make_task();
        let snap = make_snapshot(&task);
        let bytes = snap.serialize();
        let restored = TaskSnapshot::deserialize(&bytes).unwrap();
        assert_eq!(restored.version, snap.version);
        assert_eq!(restored.cpu_state, snap.cpu_state);
    }

    #[test]
    fn migration_android_to_windows() {
        let mut engine = MigrationEngine::new();
        let mut task = make_task();
        let task_id = task.id;

        let plan = engine.plan(
            task_id,
            Domain::Android,
            Domain::Windows,
            MigrationMode::FullSnapshot,
            MigrationTrigger::FormFactorChange,
        ).unwrap();

        let snap = make_snapshot(&task);
        let result = engine.execute(&plan.id, &mut task, snap).unwrap();

        assert!(result.success);
        assert_eq!(task.domain, Domain::Windows);
        assert_eq!(task.migration_count, 1);
        assert_eq!(engine.success_rate(), 1.0);
    }

    #[test]
    fn migration_same_domain_rejected() {
        let mut engine = MigrationEngine::new();
        let result = engine.plan(
            Uuid::new_v4(),
            Domain::Windows,
            Domain::Windows,
            MigrationMode::FullSnapshot,
            MigrationTrigger::LoadBalance,
        );
        assert!(result.is_err());
    }

    #[test]
    fn migration_tampered_snapshot_fails() {
        let mut engine = MigrationEngine::new();
        let mut task = make_task();
        let task_id = task.id;

        let plan = engine.plan(
            task_id,
            Domain::Android,
            Domain::Windows,
            MigrationMode::FullSnapshot,
            MigrationTrigger::DomainFailure,
        ).unwrap();

        let mut snap = make_snapshot(&task);
        snap.cpu_state[0] ^= 0xFF; // tamper

        let result = engine.execute(&plan.id, &mut task, snap);
        assert!(result.is_err());
        assert_eq!(engine.success_rate(), 0.0);
    }

    #[test]
    fn migration_history_recorded() {
        let mut engine = MigrationEngine::new();
        let mut task = make_task();
        let task_id = task.id;

        let plan = engine.plan(
            task_id,
            Domain::Android,
            Domain::AI,
            MigrationMode::Incremental,
            MigrationTrigger::LoadBalance,
        ).unwrap();

        let snap = make_snapshot(&task);
        engine.execute(&plan.id, &mut task, snap).unwrap();

        assert_eq!(engine.history().len(), 1);
        assert_eq!(engine.total_attempted(), 1);
        assert_eq!(engine.total_succeeded(), 1);
    }
}