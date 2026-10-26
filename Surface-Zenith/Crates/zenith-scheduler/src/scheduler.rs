//! # Zenith Intent Scheduler — Main Engine
//!
//! The ZIS main scheduler loop: accepts intents, classifies them,
//! builds execution plans, and dispatches tasks to domain runtimes.

use std::collections::HashMap;
use std::sync::Arc;
use parking_lot::RwLock;
use uuid::Uuid;
use zenith_abi::intent::{Intent, IntentClass, IntentState};
use zenith_abi::domain::Domain;
use zenith_abi::task::{ZenithTask, TaskState};
use zenith_abi::types::{ZTaskId, ZSessionId};
use crate::classifier::IntentClassifier;
use crate::planner::{ExecutionPlanner, ExecutionPlan};
use crate::priority_queue::IntentPriorityQueue;
use crate::heuristic::ScoreWeights;
use crate::stats::SchedulerStats;
use crate::error::SchedulerError;

// ---------------------------------------------------------------------------
// Scheduler configuration
// ---------------------------------------------------------------------------

/// Configuration for the Zenith Intent Scheduler
#[derive(Debug, Clone)]
pub struct SchedulerConfig {
    /// Maximum queue depth
    pub max_queue_depth: usize,
    /// Scheduling period in milliseconds
    pub scheduling_period_ms: u64,
    /// Anti-starvation aging period in milliseconds
    pub aging_period_ms: u64,
    /// Anti-starvation score increment per period
    pub aging_increment: i64,
    /// Available execution domains
    pub available_domains: Vec<Domain>,
    /// Score weights for the heuristic
    pub weights: ScoreWeights,
    /// Maximum concurrent tasks per domain
    pub max_tasks_per_domain: usize,
    /// Whether to enable predictive pre-loading
    pub predictive_loading: bool,
}

impl Default for SchedulerConfig {
    fn default() -> Self {
        Self {
            max_queue_depth: crate::MAX_QUEUE_DEPTH,
            scheduling_period_ms: crate::SCHEDULING_PERIOD_MS,
            aging_period_ms: 1_000,
            aging_increment: 10,
            available_domains: vec![
                Domain::Android,
                Domain::Windows,
                Domain::AI,
                Domain::Quantum,
                Domain::RealTime,
                Domain::Cloud,
            ],
            weights: ScoreWeights::default(),
            max_tasks_per_domain: 64,
            predictive_loading: true,
        }
    }
}

// ---------------------------------------------------------------------------
// Domain task tracker
// ---------------------------------------------------------------------------

/// Tracks active tasks per domain
#[derive(Debug, Default)]
struct DomainTracker {
    active_tasks: HashMap<Domain, Vec<ZTaskId>>,
    completed_tasks: HashMap<Domain, u64>,
    failed_tasks: HashMap<Domain, u64>,
}

impl DomainTracker {
    fn new() -> Self { Self::default() }

    fn add_task(&mut self, domain: Domain, task_id: ZTaskId) {
        self.active_tasks.entry(domain).or_default().push(task_id);
    }

    fn complete_task(&mut self, domain: &Domain, task_id: &ZTaskId) {
        if let Some(tasks) = self.active_tasks.get_mut(domain) {
            tasks.retain(|id| id != task_id);
        }
        *self.completed_tasks.entry(domain.clone()).or_insert(0) += 1;
    }

    fn fail_task(&mut self, domain: &Domain, task_id: &ZTaskId) {
        if let Some(tasks) = self.active_tasks.get_mut(domain) {
            tasks.retain(|id| id != task_id);
        }
        *self.failed_tasks.entry(domain.clone()).or_insert(0) += 1;
    }

    fn active_count(&self, domain: &Domain) -> usize {
        self.active_tasks.get(domain).map(|v| v.len()).unwrap_or(0)
    }

    fn total_active(&self) -> usize {
        self.active_tasks.values().map(|v| v.len()).sum()
    }
}

// ---------------------------------------------------------------------------
// Scheduler state
// ---------------------------------------------------------------------------

/// Internal state of the Zenith Intent Scheduler
struct SchedulerState {
    /// Intent priority queue
    queue: IntentPriorityQueue,
    /// Active execution plans (intent_id → plan)
    active_plans: HashMap<ZTaskId, ExecutionPlan>,
    /// Completed intent IDs (for deduplication)
    completed_intents: std::collections::HashSet<ZTaskId>,
    /// Domain task tracker
    domain_tracker: DomainTracker,
    /// Scheduler statistics
    stats: SchedulerStats,
    /// Configuration
    config: SchedulerConfig,
    /// Execution planner
    planner: ExecutionPlanner,
}

impl SchedulerState {
    fn new(config: SchedulerConfig) -> Self {
        let planner = ExecutionPlanner::new(config.available_domains.clone());
        let queue = IntentPriorityQueue::new(config.max_queue_depth)
            .with_aging(config.aging_period_ms, config.aging_increment);
        Self {
            queue,
            active_plans: HashMap::new(),
            completed_intents: std::collections::HashSet::new(),
            domain_tracker: DomainTracker::new(),
            stats: SchedulerStats::new(),
            planner,
            config,
        }
    }
}

// ---------------------------------------------------------------------------
// Zenith Intent Scheduler
// ---------------------------------------------------------------------------

/// The Zenith Intent Scheduler (ZIS)
///
/// Thread-safe via Arc<RwLock<>>. Clone to share across threads.
#[derive(Clone)]
pub struct ZenithScheduler {
    state: Arc<RwLock<SchedulerState>>,
}

impl ZenithScheduler {
    /// Create a new scheduler with default configuration
    pub fn new() -> Self {
        Self::with_config(SchedulerConfig::default())
    }

    /// Create a scheduler with custom configuration
    pub fn with_config(config: SchedulerConfig) -> Self {
        Self {
            state: Arc::new(RwLock::new(SchedulerState::new(config))),
        }
    }

    // ── Intent submission ───────────────────────────────────────────────────

    /// Submit an intent for scheduling
    ///
    /// The intent is classified, scored, and enqueued.
    /// Returns the intent ID.
    pub fn submit(&self, mut intent: Intent) -> Result<ZTaskId, SchedulerError> {
        let id = intent.id;

        // Classify if not already classified
        if intent.class == IntentClass::Unknown {
            IntentClassifier::classify_and_apply(&mut intent);
        }

        // Compute scheduling score
        intent.compute_score();

        // Transition to Classifying state
        intent.transition(IntentState::Classifying);

        let mut state = self.state.write();

        // Check for duplicate
        if state.completed_intents.contains(&id) {
            return Err(SchedulerError::IntentAlreadyCompleted { id: id.to_string() });
        }

        // Enqueue
        let domains = state.config.available_domains.clone();
        if !state.queue.enqueue(intent, &domains) {
            state.stats.record_dropped();
            return Err(SchedulerError::QueueFull {
                depth: state.queue.len(),
                max: state.config.max_queue_depth,
            });
        }

        state.stats.record_submitted();
        tracing::debug!("Intent {} submitted to ZIS queue", id);
        Ok(id)
    }

    /// Submit multiple intents at once
    pub fn submit_batch(&self, intents: Vec<Intent>) -> Vec<Result<ZTaskId, SchedulerError>> {
        intents.into_iter().map(|i| self.submit(i)).collect()
    }

    // ── Scheduling ──────────────────────────────────────────────────────────

    /// Run one scheduling cycle
    ///
    /// Dequeues the highest-priority intent, builds an execution plan,
    /// and dispatches tasks to domain runtimes.
    ///
    /// Returns the number of tasks dispatched.
    pub fn schedule_one(&self) -> Result<usize, SchedulerError> {
        let mut state = self.state.write();

        // Apply aging to prevent starvation
        state.queue.apply_aging_pass();

        // Dequeue highest-priority intent
        let scheduled = match state.queue.dequeue() {
            Some(s) => s,
            None => return Ok(0),
        };

        let mut intent = scheduled.intent;
        let intent_id = intent.id;

        // Build execution plan
        intent.transition(IntentState::Planning);
        let plan = state.planner.plan(&intent)
            .map_err(|e| SchedulerError::PlanningFailed {
                intent_id: intent_id.to_string(),
                reason: e.to_string(),
            })?;

        let task_count = plan.tasks.len();

        // Check domain availability
        let unavailable = state.planner.check_domain_availability(&plan);
        if !unavailable.is_empty() {
            tracing::warn!(
                "Intent {} requires unavailable domains: {:?}",
                intent_id, unavailable
            );
        }

        // Assign tasks to domain tracker
        for task in &plan.tasks {
            state.domain_tracker.add_task(task.domain.clone(), task.id);
        }

        // Transition intent to Queued state
        let primary_domain = plan.domains_involved.first()
            .cloned()
            .unwrap_or(Domain::Windows);
        intent.transition(IntentState::Queued { domain: primary_domain });

        // Store the plan
        state.active_plans.insert(intent_id, plan);
        state.stats.record_scheduled(task_count);

        tracing::debug!(
            "Intent {} scheduled: {} tasks dispatched",
            intent_id, task_count
        );

        Ok(task_count)
    }

    /// Run the scheduler until the queue is empty
    pub fn drain(&self) -> Result<usize, SchedulerError> {
        let mut total = 0;
        loop {
            let dispatched = self.schedule_one()?;
            if dispatched == 0 {
                break;
            }
            total += dispatched;
        }
        Ok(total)
    }

    // ── Task completion ─────────────────────────────────────────────────────

    /// Report a task as completed
    pub fn complete_task(
        &self,
        intent_id: &ZTaskId,
        task_id: &ZTaskId,
        domain: &Domain,
        result: Vec<u8>,
    ) -> Result<(), SchedulerError> {
        let mut state = self.state.write();
        state.domain_tracker.complete_task(domain, task_id);

        if let Some(plan) = state.active_plans.get_mut(intent_id) {
            plan.dag.complete_node(task_id);

            if plan.dag.is_complete() {
                state.completed_intents.insert(*intent_id);
                state.active_plans.remove(intent_id);
                state.stats.record_completed();
                tracing::info!("Intent {} fully completed", intent_id);
            }
        }

        Ok(())
    }

    /// Report a task as failed
    pub fn fail_task(
        &self,
        intent_id: &ZTaskId,
        task_id: &ZTaskId,
        domain: &Domain,
        reason: impl Into<String>,
    ) -> Result<(), SchedulerError> {
        let reason = reason.into();
        let mut state = self.state.write();
        state.domain_tracker.fail_task(domain, task_id);

        if let Some(plan) = state.active_plans.get_mut(intent_id) {
            plan.dag.fail_node(task_id, &reason);
            state.stats.record_failed();
        }

        Ok(())
    }

    // ── Cancellation ────────────────────────────────────────────────────────

    /// Cancel a pending intent
    pub fn cancel(&self, intent_id: &ZTaskId) -> Result<(), SchedulerError> {
        let mut state = self.state.write();

        // Try to remove from queue
        if state.queue.remove(intent_id).is_some() {
            state.stats.record_cancelled();
            return Ok(());
        }

        // Try to cancel active plan
        if state.active_plans.remove(intent_id).is_some() {
            state.stats.record_cancelled();
            return Ok(());
        }

        Err(SchedulerError::IntentNotFound { id: intent_id.to_string() })
    }

    // ── Diagnostics ─────────────────────────────────────────────────────────

    /// Current queue depth
    pub fn queue_depth(&self) -> usize {
        self.state.read().queue.len()
    }

    /// Number of active execution plans
    pub fn active_plan_count(&self) -> usize {
        self.state.read().active_plans.len()
    }

    /// Total active tasks across all domains
    pub fn total_active_tasks(&self) -> usize {
        self.state.read().domain_tracker.total_active()
    }

    /// Active tasks for a specific domain
    pub fn domain_active_tasks(&self, domain: &Domain) -> usize {
        self.state.read().domain_tracker.active_count(domain)
    }

    /// Scheduler statistics snapshot
    pub fn stats(&self) -> SchedulerStats {
        self.state.read().stats.clone()
    }

    /// Queue utilization ratio (0.0–1.0)
    pub fn queue_utilization(&self) -> f64 {
        self.state.read().queue.utilization()
    }
}

impl Default for ZenithScheduler {
    fn default() -> Self { Self::new() }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;
    use zenith_abi::intent::{Intent, IntentClass};

    fn make_intent(class: IntentClass, priority: u8) -> Intent {
        Intent::new(
            Uuid::new_v4(), Uuid::new_v4(),
            "test goal", class, priority,
        )
    }

    #[test]
    fn submit_and_schedule() {
        let scheduler = ZenithScheduler::new();
        let intent = make_intent(IntentClass::Productivity, 128);
        scheduler.submit(intent).unwrap();
        assert_eq!(scheduler.queue_depth(), 1);

        let dispatched = scheduler.schedule_one().unwrap();
        assert!(dispatched > 0);
        assert_eq!(scheduler.queue_depth(), 0);
    }

    #[test]
    fn submit_batch() {
        let scheduler = ZenithScheduler::new();
        let intents: Vec<Intent> = (0..5)
            .map(|i| make_intent(IntentClass::Productivity, i * 50))
            .collect();
        let results = scheduler.submit_batch(intents);
        assert!(results.iter().all(|r| r.is_ok()));
        assert_eq!(scheduler.queue_depth(), 5);
    }

    #[test]
    fn drain_queue() {
        let scheduler = ZenithScheduler::new();
        for _ in 0..10 {
            scheduler.submit(make_intent(IntentClass::Messaging, 100)).unwrap();
        }
        let total = scheduler.drain().unwrap();
        assert!(total > 0);
        assert_eq!(scheduler.queue_depth(), 0);
    }

    #[test]
    fn cancel_pending_intent() {
        let scheduler = ZenithScheduler::new();
        let intent = make_intent(IntentClass::Media, 50);
        let id = intent.id;
        scheduler.submit(intent).unwrap();
        assert_eq!(scheduler.queue_depth(), 1);
        scheduler.cancel(&id).unwrap();
        assert_eq!(scheduler.queue_depth(), 0);
    }

    #[test]
    fn stats_track_submissions() {
        let scheduler = ZenithScheduler::new();
        for _ in 0..3 {
            scheduler.submit(make_intent(IntentClass::Productivity, 100)).unwrap();
        }
        let stats = scheduler.stats();
        assert_eq!(stats.total_submitted, 3);
    }

    #[test]
    fn high_priority_scheduled_first() {
        let scheduler = ZenithScheduler::new();
        let low  = make_intent(IntentClass::Media, 10);
        let high = make_intent(IntentClass::Productivity, 200);
        let low_id  = low.id;
        let high_id = high.id;

        scheduler.submit(low).unwrap();
        scheduler.submit(high).unwrap();

        // Schedule one — should pick the high-priority intent
        scheduler.schedule_one().unwrap();

        // High-priority intent should now be in active plans
        assert_eq!(scheduler.active_plan_count(), 1);
    }

    #[test]
    fn queue_full_returns_error() {
        let config = SchedulerConfig {
            max_queue_depth: 2,
            ..SchedulerConfig::default()
        };
        let scheduler = ZenithScheduler::with_config(config);
        scheduler.submit(make_intent(IntentClass::Productivity, 100)).unwrap();
        scheduler.submit(make_intent(IntentClass::Productivity, 100)).unwrap();
        let result = scheduler.submit(make_intent(IntentClass::Productivity, 100));
        assert!(matches!(result, Err(SchedulerError::QueueFull { .. })));
    }
}