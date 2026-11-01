//! # Live Migration Engine
//!
//! Implements live migration of tasks between domain containers.
//! Supports three migration modes:
//!   1. FullSnapshot — serialize entire task state, transfer, restore
//!   2. Incremental  — transfer only dirty pages
//!   3. Live         — pre-copy pages while task continues running

use std::collections::{HashMap, VecDeque};
use uuid::Uuid;
use zenith_abi::domain::Domain;
use zenith_abi::types::ZTaskId;
use crate::error::ZhlError;

/// Migration mode
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum MigrationMode {
    FullSnapshot,
    Incremental,
    Live,
}

/// A pending migration request
#[derive(Debug, Clone)]
pub struct MigrationRequest {
    pub id:           Uuid,
    pub task_id:      ZTaskId,
    pub from_domain:  Domain,
    pub to_domain:    Domain,
    pub trigger:      String,
    pub requested_at: std::time::Instant,
}

/// Result of a completed migration
#[derive(Debug, Clone)]
pub struct MigrationResult {
    pub request_id:       Uuid,
    pub task_id:          ZTaskId,
    pub from_domain:      Domain,
    pub to_domain:        Domain,
    pub success:          bool,
    pub downtime_ms:      u32,
    pub bytes_transferred: u64,
    pub pages_transferred: u32,
    pub mode_used:        MigrationMode,
    pub error:            Option<String>,
    pub completed_at:     std::time::Instant,
}

/// Pre-copy iteration state for live migration
#[derive(Debug)]
struct PreCopyState {
    iteration:        u32,
    pages_copied:     u64,
    dirty_pages:      u64,
    convergence_rate: f64,
}

impl PreCopyState {
    fn new() -> Self {
        Self {
            iteration:        0,
            pages_copied:     0,
            dirty_pages:      0,
            convergence_rate: 0.0,
        }
    }

    /// Whether pre-copy has converged (dirty pages < threshold)
    fn has_converged(&self, total_pages: u64) -> bool {
        if total_pages == 0 { return true; }
        let dirty_ratio = self.dirty_pages as f64 / total_pages as f64;
        dirty_ratio < crate::LIVE_MIGRATION_DIRTY_THRESHOLD
    }

    /// Simulate one pre-copy iteration
    fn iterate(&mut self, total_pages: u64) {
        self.iteration += 1;
        // Simulate convergence: dirty pages decrease each iteration
        let dirty_ratio = (0.5f64).powi(self.iteration as i32);
        self.dirty_pages = (total_pages as f64 * dirty_ratio) as u64;
        self.pages_copied += total_pages - self.dirty_pages;
        self.convergence_rate = 1.0 - dirty_ratio;
    }
}

/// The Live Migration Engine
#[derive(Debug)]
pub struct LiveMigrationEngine {
    /// Pending migration requests
    queue:              VecDeque<MigrationRequest>,
    /// Active migrations (request_id → pre-copy state)
    active:             HashMap<Uuid, PreCopyState>,
    /// Completed migration results
    history:            Vec<MigrationResult>,
    /// Maximum concurrent migrations
    max_concurrent:     usize,
    /// Total migrations attempted
    total_attempted:    u64,
    /// Total migrations succeeded
    total_succeeded:    u64,
    /// Total bytes transferred across all migrations
    total_bytes:        u64,
}

impl LiveMigrationEngine {
    /// Create a new migration engine
    pub fn new(max_concurrent: usize) -> Self {
        Self {
            queue:           VecDeque::new(),
            active:          HashMap::new(),
            history:         Vec::new(),
            max_concurrent,
            total_attempted: 0,
            total_succeeded: 0,
            total_bytes:     0,
        }
    }

    /// Enqueue a migration request
    pub fn enqueue(&mut self, request: MigrationRequest) -> Result<(), ZhlError> {
        if self.queue.len() + self.active.len() >= self.max_concurrent * 4 {
            return Err(ZhlError::MigrationQueueFull);
        }
        self.queue.push_back(request);
        Ok(())
    }

    /// Process all pending migrations
    pub fn process_pending(&mut self) -> Vec<MigrationResult> {
        let mut results = Vec::new();

        while self.active.len() < self.max_concurrent {
            if let Some(request) = self.queue.pop_front() {
                let id = request.id;
                self.active.insert(id, PreCopyState::new());
                // Execute migration immediately (simplified)
                if let Some(result) = self.execute_migration(request) {
                    self.active.remove(&id);
                    results.push(result);
                }
            } else {
                break;
            }
        }

        results
    }

    /// Execute a single migration
    fn execute_migration(&mut self, request: MigrationRequest) -> Option<MigrationResult> {
        self.total_attempted += 1;

        // Determine migration mode based on task size (simulated)
        let total_pages = 1024u64; // Simulated: 4MB task
        let mode = MigrationMode::Incremental;

        let state = self.active.get_mut(&request.id)?;

        // Simulate pre-copy iterations for live migration
        let max_iterations = match mode {
            MigrationMode::Live => 5,
            _                   => 1,
        };

        for _ in 0..max_iterations {
            state.iterate(total_pages);
            if state.has_converged(total_pages) {
                break;
            }
        }

        let bytes_transferred = state.pages_copied * crate::PAGE_SIZE as u64;
        let pages_transferred = state.pages_copied as u32;
        let downtime_ms = match mode {
            MigrationMode::FullSnapshot  => 100,
            MigrationMode::Incremental   => 20,
            MigrationMode::Live          => 5,
        };

        self.total_succeeded += 1;
        self.total_bytes += bytes_transferred;

        let result = MigrationResult {
            request_id:       request.id,
            task_id:          request.task_id,
            from_domain:      request.from_domain,
            to_domain:        request.to_domain,
            success:          true,
            downtime_ms,
            bytes_transferred,
            pages_transferred,
            mode_used:        mode,
            error:            None,
            completed_at:     std::time::Instant::now(),
        };

        self.history.push(result.clone());
        if self.history.len() > 1000 {
            self.history.drain(0..100);
        }

        Some(result)
    }

    /// Migration success rate
    pub fn success_rate(&self) -> f64 {
        if self.total_attempted == 0 { return 1.0; }
        self.total_succeeded as f64 / self.total_attempted as f64
    }

    /// Average bytes transferred per migration
    pub fn avg_bytes_per_migration(&self) -> f64 {
        if self.total_succeeded == 0 { return 0.0; }
        self.total_bytes as f64 / self.total_succeeded as f64
    }

    /// Migration history
    pub fn history(&self) -> &[MigrationResult] {
        &self.history
    }

    /// Queue depth
    pub fn queue_depth(&self) -> usize {
        self.queue.len()
    }

    /// Active migration count
    pub fn active_count(&self) -> usize {
        self.active.len()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn make_request(from: Domain, to: Domain) -> MigrationRequest {
        MigrationRequest {
            id:          Uuid::new_v4(),
            task_id:     Uuid::new_v4(),
            from_domain: from,
            to_domain:   to,
            trigger:     "test".into(),
            requested_at: std::time::Instant::now(),
        }
    }

    #[test]
    fn migration_engine_basic() {
        let mut engine = LiveMigrationEngine::new(2);
        let req = make_request(Domain::Android, Domain::Windows);
        engine.enqueue(req).unwrap();
        assert_eq!(engine.queue_depth(), 1);
        let results = engine.process_pending();
        assert_eq!(results.len(), 1);
        assert!(results[0].success);
        assert_eq!(engine.queue_depth(), 0);
    }

    #[test]
    fn migration_engine_success_rate() {
        let mut engine = LiveMigrationEngine::new(4);
        for _ in 0..5 {
            let req = make_request(Domain::Android, Domain::AI);
            engine.enqueue(req).unwrap();
        }
        engine.process_pending();
        assert_eq!(engine.success_rate(), 1.0);
    }

    #[test]
    fn migration_queue_full() {
        let mut engine = LiveMigrationEngine::new(1);
        for _ in 0..4 {
            let req = make_request(Domain::Windows, Domain::AI);
            engine.enqueue(req).unwrap();
        }
        let req = make_request(Domain::Windows, Domain::AI);
        assert!(engine.enqueue(req).is_err());
    }

    #[test]
    fn pre_copy_convergence() {
        let mut state = PreCopyState::new();
        let total_pages = 1000u64;
        for _ in 0..10 {
            state.iterate(total_pages);
            if state.has_converged(total_pages) {
                break;
            }
        }
        assert!(state.has_converged(total_pages));
    }
}