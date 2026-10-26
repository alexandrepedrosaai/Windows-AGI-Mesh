//! # Zenith Scheduler Engine
//!
//! The top-level orchestration engine that ties together the scheduler,
//! migration engine, predictive pre-loader, domain router, and IPC bus.

use std::sync::Arc;
use parking_lot::RwLock;
use uuid::Uuid;
use zenith_abi::intent::{Intent, IntentClass};
use zenith_abi::domain::Domain;
use zenith_abi::types::{ZIdentityId, ZSessionId};
use crate::scheduler::{ZenithScheduler, SchedulerConfig};
use crate::migration::{MigrationEngine, MigrationMode, MigrationTrigger};
use crate::predictor::PredictivePreloader;
use crate::router::{DomainRouter, LoadBalancePolicy, DomainLoad};
use crate::stats::SchedulerStats;
use crate::error::SchedulerError;

/// The Zenith Orchestration Engine
///
/// Combines all scheduler subsystems into a single unified interface.
#[derive(Clone)]
pub struct ZenithEngine {
    scheduler:  ZenithScheduler,
    migration:  Arc<RwLock<MigrationEngine>>,
    preloader:  Arc<RwLock<PredictivePreloader>>,
    router:     Arc<RwLock<DomainRouter>>,
}

impl ZenithEngine {
    /// Create a new engine with default configuration
    pub fn new() -> Self {
        Self {
            scheduler: ZenithScheduler::new(),
            migration: Arc::new(RwLock::new(MigrationEngine::new())),
            preloader: Arc::new(RwLock::new(PredictivePreloader::new())),
            router:    Arc::new(RwLock::new(DomainRouter::new(LoadBalancePolicy::Weighted))),
        }
    }

    /// Create an engine with custom scheduler configuration
    pub fn with_config(config: SchedulerConfig) -> Self {
        Self {
            scheduler: ZenithScheduler::with_config(config),
            migration: Arc::new(RwLock::new(MigrationEngine::new())),
            preloader: Arc::new(RwLock::new(PredictivePreloader::new())),
            router:    Arc::new(RwLock::new(DomainRouter::new(LoadBalancePolicy::Weighted))),
        }
    }

    /// Submit an intent and record it for behavior prediction
    pub fn submit_intent(
        &self,
        identity: ZIdentityId,
        intent: Intent,
    ) -> Result<uuid::Uuid, SchedulerError> {
        // Record for predictive pre-loading
        self.preloader.write().observe(identity, &intent.class);

        // Submit to scheduler
        self.scheduler.submit(intent)
    }

    /// Run one scheduling cycle
    pub fn tick(&self) -> Result<usize, SchedulerError> {
        self.scheduler.schedule_one()
    }

    /// Run until queue is empty
    pub fn drain(&self) -> Result<usize, SchedulerError> {
        self.scheduler.drain()
    }

    /// Get pre-load recommendations for an identity
    pub fn preload_recommendations(
        &self,
        identity: &ZIdentityId,
    ) -> Vec<crate::predictor::PreloadRecommendation> {
        self.preloader.read().recommendations(identity)
    }

    /// Update domain load information
    pub fn update_domain_load(&self, domain: Domain, load: DomainLoad) {
        self.router.write().update_load(&domain, load);
    }

    /// Mark a domain as unavailable (triggers migration of active tasks)
    pub fn domain_failed(&self, domain: &Domain) {
        self.router.write().set_unavailable(domain);
        tracing::warn!("Domain {:?} marked as unavailable", domain);
    }

    /// Mark a domain as available again
    pub fn domain_recovered(&self, domain: &Domain) {
        self.router.write().set_available(domain);
        tracing::info!("Domain {:?} recovered", domain);
    }

    /// Get scheduler statistics
    pub fn stats(&self) -> SchedulerStats {
        self.scheduler.stats()
    }

    /// Get migration success rate
    pub fn migration_success_rate(&self) -> f64 {
        self.migration.read().success_rate()
    }

    /// Current queue depth
    pub fn queue_depth(&self) -> usize {
        self.scheduler.queue_depth()
    }

    /// Total active tasks
    pub fn total_active_tasks(&self) -> usize {
        self.scheduler.total_active_tasks()
    }

    /// Engine health summary
    pub fn health_summary(&self) -> EngineSummary {
        let stats = self.stats();
        EngineSummary {
            queue_depth: self.queue_depth(),
            active_plans: self.scheduler.active_plan_count(),
            total_active_tasks: self.total_active_tasks(),
            total_submitted: stats.total_submitted,
            total_completed: stats.total_completed,
            total_failed: stats.total_failed,
            completion_rate: stats.completion_rate(),
            migration_success_rate: self.migration_success_rate(),
            available_domains: self.router.read().available_domains(),
        }
    }
}

impl Default for ZenithEngine {
    fn default() -> Self { Self::new() }
}

/// Engine health summary
#[derive(Debug, Clone)]
pub struct EngineSummary {
    pub queue_depth:            usize,
    pub active_plans:           usize,
    pub total_active_tasks:     usize,
    pub total_submitted:        u64,
    pub total_completed:        u64,
    pub total_failed:           u64,
    pub completion_rate:        f64,
    pub migration_success_rate: f64,
    pub available_domains:      Vec<Domain>,
}

impl std::fmt::Display for EngineSummary {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(
            f,
            "ZenithEngine[queue={}, plans={}, tasks={}, submitted={}, completed={}, \
             failed={}, completion={:.1}%, migration={:.1}%, domains={:?}]",
            self.queue_depth,
            self.active_plans,
            self.total_active_tasks,
            self.total_submitted,
            self.total_completed,
            self.total_failed,
            self.completion_rate * 100.0,
            self.migration_success_rate * 100.0,
            self.available_domains,
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use zenith_abi::intent::{Intent, IntentClass};

    fn make_intent(class: IntentClass) -> Intent {
        Intent::new(
            Uuid::new_v4(), Uuid::new_v4(),
            "test goal", class, 128,
        )
    }

    #[test]
    fn engine_submit_and_drain() {
        let engine = ZenithEngine::new();
        let identity = Uuid::new_v4();

        for _ in 0..5 {
            engine.submit_intent(identity, make_intent(IntentClass::Productivity)).unwrap();
        }

        assert_eq!(engine.queue_depth(), 5);
        let dispatched = engine.drain().unwrap();
        assert!(dispatched > 0);
        assert_eq!(engine.queue_depth(), 0);
    }

    #[test]
    fn engine_domain_failure_recovery() {
        let engine = ZenithEngine::new();
        engine.domain_failed(&Domain::Windows);
        let available = engine.router.read().available_domains();
        assert!(!available.contains(&Domain::Windows));

        engine.domain_recovered(&Domain::Windows);
        let available = engine.router.read().available_domains();
        assert!(available.contains(&Domain::Windows));
    }

    #[test]
    fn engine_health_summary() {
        let engine = ZenithEngine::new();
        let identity = Uuid::new_v4();
        engine.submit_intent(identity, make_intent(IntentClass::Inference)).unwrap();
        engine.tick().unwrap();

        let summary = engine.health_summary();
        assert!(summary.total_submitted >= 1);
        assert!(!summary.available_domains.is_empty());
        assert!(!summary.to_string().is_empty());
    }

    #[test]
    fn engine_preload_recommendations() {
        let engine = ZenithEngine::new();
        let identity = Uuid::new_v4();

        // Build up a pattern
        for _ in 0..5 {
            engine.submit_intent(identity, make_intent(IntentClass::Productivity)).unwrap();
        }

        // Recommendations may be empty if current hour doesn't match
        // Just verify it doesn't panic
        let recs = engine.preload_recommendations(&identity);
        assert!(recs.len() <= 3);
    }
}