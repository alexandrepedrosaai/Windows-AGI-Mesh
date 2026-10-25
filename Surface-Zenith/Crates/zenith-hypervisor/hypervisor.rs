//! # Zenith Hypervisor — Main Orchestrator
//!
//! The top-level hypervisor that manages all domain containers,
//! coordinates migrations, enforces resource quotas, and maintains
//! the health of the entire Zenith OS domain ecosystem.

use std::sync::Arc;
use std::collections::HashMap;
use parking_lot::RwLock;
use uuid::Uuid;
use zenith_abi::domain::Domain;
use zenith_abi::types::{ZDomainId, ZTaskId, ZSessionId};
use crate::container::{DomainContainer, ContainerConfig, ContainerRegistry, ContainerState};
use crate::supervisor::DomainSupervisor;
use crate::migration::{LiveMigrationEngine, MigrationRequest, MigrationResult};
use crate::metrics::HypervisorMetrics;
use crate::quota::ResourceQuota;
use crate::error::ZhlError;
use crate::fault::FaultHandler;
use crate::recovery::RecoveryManager;
use crate::scheduler_bridge::SchedulerBridge;

// ---------------------------------------------------------------------------
// Hypervisor configuration
// ---------------------------------------------------------------------------

/// Configuration for the Zenith Hypervisor Layer
#[derive(Debug, Clone)]
pub struct HypervisorConfig {
    /// Whether to enable live migration
    pub live_migration_enabled: bool,
    /// Whether to enable automatic domain recovery
    pub auto_recovery_enabled: bool,
    /// Health check interval in milliseconds
    pub health_check_interval_ms: u64,
    /// Maximum concurrent migrations
    pub max_concurrent_migrations: usize,
    /// Whether to enable memory overcommit
    pub memory_overcommit: bool,
    /// Overcommit ratio (e.g., 1.5 = 50% overcommit)
    pub overcommit_ratio: f64,
    /// Whether to enable CPU pinning for real-time domains
    pub realtime_cpu_pinning: bool,
    /// Physical CPU cores reserved for real-time domains
    pub realtime_cores: Vec<u32>,
    /// Whether to enable NUMA-aware scheduling
    pub numa_aware: bool,
    /// Maximum memory balloon size (bytes)
    pub max_balloon_size: u64,
}

impl Default for HypervisorConfig {
    fn default() -> Self {
        Self {
            live_migration_enabled:     true,
            auto_recovery_enabled:      true,
            health_check_interval_ms:   500,
            max_concurrent_migrations:  2,
            memory_overcommit:          false,
            overcommit_ratio:           1.0,
            realtime_cpu_pinning:       true,
            realtime_cores:             vec![0, 1],
            numa_aware:                 false,
            max_balloon_size:           4 * 1024 * 1024 * 1024,
        }
    }
}

// ---------------------------------------------------------------------------
// Hypervisor event
// ---------------------------------------------------------------------------

/// Events emitted by the hypervisor for external consumers
#[derive(Debug, Clone)]
pub enum HypervisorEvent {
    /// A domain container was created
    ContainerCreated { id: ZDomainId, domain: Domain },
    /// A domain container started
    ContainerStarted { id: ZDomainId, domain: Domain },
    /// A domain container was paused
    ContainerPaused { id: ZDomainId, domain: Domain },
    /// A domain container was resumed
    ContainerResumed { id: ZDomainId, domain: Domain },
    /// A domain container crashed
    ContainerCrashed { id: ZDomainId, domain: Domain, reason: String },
    /// A domain container was recovered
    ContainerRecovered { id: ZDomainId, domain: Domain },
    /// A domain container was destroyed
    ContainerDestroyed { id: ZDomainId, domain: Domain },
    /// A task migration started
    MigrationStarted { task_id: ZTaskId, from: Domain, to: Domain },
    /// A task migration completed
    MigrationCompleted { task_id: ZTaskId, from: Domain, to: Domain, success: bool },
    /// A resource quota was exceeded
    QuotaExceeded { id: ZDomainId, domain: Domain, resource: String },
    /// A health check failed
    HealthCheckFailed { id: ZDomainId, domain: Domain, failures: u32 },
}

// ---------------------------------------------------------------------------
// Hypervisor inner state
// ---------------------------------------------------------------------------

struct HypervisorInner {
    config:           HypervisorConfig,
    registry:         ContainerRegistry,
    supervisor:       DomainSupervisor,
    migration_engine: LiveMigrationEngine,
    recovery_manager: RecoveryManager,
    fault_handler:    FaultHandler,
    scheduler_bridge: SchedulerBridge,
    metrics:          HypervisorMetrics,
    event_log:        Vec<HypervisorEvent>,
    active_migrations: HashMap<ZTaskId, ZDomainId>, // task → target container
}

impl HypervisorInner {
    fn new(config: HypervisorConfig) -> Self {
        Self {
            supervisor:       DomainSupervisor::new(),
            migration_engine: LiveMigrationEngine::new(config.max_concurrent_migrations),
            recovery_manager: RecoveryManager::new(),
            fault_handler:    FaultHandler::new(),
            scheduler_bridge: SchedulerBridge::new(),
            metrics:          HypervisorMetrics::new(),
            event_log:        Vec::new(),
            active_migrations: HashMap::new(),
            registry:         ContainerRegistry::new(),
            config,
        }
    }

    fn emit_event(&mut self, event: HypervisorEvent) {
        tracing::info!("ZHL Event: {:?}", event);
        self.event_log.push(event);
        if self.event_log.len() > 10_000 {
            self.event_log.drain(0..1000);
        }
    }
}

// ---------------------------------------------------------------------------
// Zenith Hypervisor Layer
// ---------------------------------------------------------------------------

/// The Zenith Hypervisor Layer — manages all domain containers
///
/// Thread-safe via Arc<RwLock<>>. Clone to share across threads.
#[derive(Clone)]
pub struct ZenithHypervisor {
    inner: Arc<RwLock<HypervisorInner>>,
}

impl ZenithHypervisor {
    /// Create a new hypervisor with default configuration
    pub fn new() -> Self {
        Self::with_config(HypervisorConfig::default())
    }

    /// Create a hypervisor with custom configuration
    pub fn with_config(config: HypervisorConfig) -> Self {
        Self {
            inner: Arc::new(RwLock::new(HypervisorInner::new(config))),
        }
    }

    // ── Container management ─────────────────────────────────────────────────

    /// Create and start a domain container
    pub fn create_domain(&self, config: ContainerConfig) -> Result<ZDomainId, ZhlError> {
        let mut inner = self.inner.write();
        let domain = config.domain.clone();

        // Check if primary container already exists for this domain
        if config.is_primary && inner.registry.primary(&domain).is_some() {
            return Err(ZhlError::PrimaryContainerExists {
                domain: domain.name().to_string(),
            });
        }

        let mut container = DomainContainer::new(config);
        container.start()?;

        let id = container.id;
        inner.registry.register(container);
        inner.metrics.record_container_created();
        inner.emit_event(HypervisorEvent::ContainerCreated { id, domain: domain.clone() });
        inner.emit_event(HypervisorEvent::ContainerStarted { id, domain });

        tracing::info!("Domain container {} created and started", id);
        Ok(id)
    }

    /// Create all standard Zenith domains
    pub fn create_standard_domains(&self) -> Result<Vec<ZDomainId>, ZhlError> {
        let domains = vec![
            Domain::Android,
            Domain::Windows,
            Domain::AI,
            Domain::Quantum,
            Domain::RealTime,
            Domain::Cloud,
        ];

        let mut ids = Vec::new();
        for domain in domains {
            let config = ContainerConfig::default_for_domain(domain);
            let id = self.create_domain(config)?;
            ids.push(id);
        }
        Ok(ids)
    }

    /// Pause a domain container
    pub fn pause_domain(&self, id: &ZDomainId) -> Result<(), ZhlError> {
        let mut inner = self.inner.write();
        let container = inner.registry.get_mut(id)
            .ok_or_else(|| ZhlError::ContainerNotFound { id: id.to_string() })?;
        let domain = container.domain().clone();
        container.pause()?;
        inner.emit_event(HypervisorEvent::ContainerPaused { id: *id, domain });
        Ok(())
    }

    /// Resume a paused domain container
    pub fn resume_domain(&self, id: &ZDomainId) -> Result<(), ZhlError> {
        let mut inner = self.inner.write();
        let container = inner.registry.get_mut(id)
            .ok_or_else(|| ZhlError::ContainerNotFound { id: id.to_string() })?;
        let domain = container.domain().clone();
        container.resume()?;
        inner.emit_event(HypervisorEvent::ContainerResumed { id: *id, domain });
        Ok(())
    }

    /// Destroy a domain container
    pub fn destroy_domain(&self, id: &ZDomainId) -> Result<(), ZhlError> {
        let mut inner = self.inner.write();
        let container = inner.registry.get_mut(id)
            .ok_or_else(|| ZhlError::ContainerNotFound { id: id.to_string() })?;
        let domain = container.domain().clone();
        container.destroy()?;
        inner.emit_event(HypervisorEvent::ContainerDestroyed { id: *id, domain });
        inner.registry.remove(id);
        inner.metrics.record_container_destroyed();
        Ok(())
    }

    // ── Task management ──────────────────────────────────────────────────────

    /// Assign a task to a domain container
    pub fn assign_task(&self, task_id: ZTaskId, domain: &Domain) -> Result<ZDomainId, ZhlError> {
        let mut inner = self.inner.write();
        let container = inner.registry.primary_mut(domain)
            .ok_or_else(|| ZhlError::DomainNotAvailable { domain: domain.name().to_string() })?;

        if !container.can_accept_task() {
            return Err(ZhlError::ContainerAtCapacity {
                id: container.id.to_string(),
            });
        }

        let container_id = container.id;
        container.add_task(task_id);
        inner.metrics.record_task_assigned();
        Ok(container_id)
    }

    /// Complete a task in a domain container
    pub fn complete_task(&self, task_id: &ZTaskId, domain: &Domain) -> Result<(), ZhlError> {
        let mut inner = self.inner.write();
        if let Some(container) = inner.registry.primary_mut(domain) {
            container.remove_task(task_id);
            container.stats.completed_tasks += 1;
            inner.metrics.record_task_completed();
        }
        Ok(())
    }

    /// Fail a task in a domain container
    pub fn fail_task(&self, task_id: &ZTaskId, domain: &Domain) -> Result<(), ZhlError> {
        let mut inner = self.inner.write();
        if let Some(container) = inner.registry.primary_mut(domain) {
            container.remove_task(task_id);
            container.stats.failed_tasks += 1;
            inner.metrics.record_task_failed();
        }
        Ok(())
    }

    // ── Migration ────────────────────────────────────────────────────────────

    /// Request a task migration between domains
    pub fn request_migration(
        &self,
        task_id: ZTaskId,
        from_domain: Domain,
        to_domain: Domain,
        trigger: impl Into<String>,
    ) -> Result<(), ZhlError> {
        let mut inner = self.inner.write();

        // Validate source domain is available
        if inner.registry.primary(&from_domain).is_none() {
            return Err(ZhlError::DomainNotAvailable {
                domain: from_domain.name().to_string(),
            });
        }

        // Validate target domain is available and can accept tasks
        let target_ok = inner.registry.primary(&to_domain)
            .map(|c| c.can_accept_task())
            .unwrap_or(false);

        if !target_ok {
            return Err(ZhlError::DomainNotAvailable {
                domain: to_domain.name().to_string(),
            });
        }

        let request = MigrationRequest {
            id:         Uuid::new_v4(),
            task_id,
            from_domain: from_domain.clone(),
            to_domain:   to_domain.clone(),
            trigger:     trigger.into(),
            requested_at: std::time::Instant::now(),
        };

        inner.migration_engine.enqueue(request)?;
        inner.emit_event(HypervisorEvent::MigrationStarted {
            task_id,
            from: from_domain,
            to:   to_domain,
        });
        inner.metrics.record_migration_started();
        Ok(())
    }

    /// Process pending migrations (call periodically)
    pub fn process_migrations(&self) -> Vec<MigrationResult> {
        let mut inner = self.inner.write();
        let results = inner.migration_engine.process_pending();

        for result in &results {
            inner.emit_event(HypervisorEvent::MigrationCompleted {
                task_id: result.task_id,
                from:    result.from_domain.clone(),
                to:      result.to_domain.clone(),
                success: result.success,
            });
            if result.success {
                inner.metrics.record_migration_completed();
            } else {
                inner.metrics.record_migration_failed();
            }
        }

        results
    }

    // ── Health monitoring ────────────────────────────────────────────────────

    /// Run a health check on all containers
    pub fn health_check_all(&self) -> HashMap<ZDomainId, bool> {
        let mut inner = self.inner.write();
        let mut results = HashMap::new();

        let container_ids: Vec<ZDomainId> = inner.registry
            .running()
            .iter()
            .map(|c| c.id)
            .collect();

        for id in container_ids {
            let healthy = inner.supervisor.check_health(&id);
            results.insert(id, healthy);

            if let Some(container) = inner.registry.get_mut(&id) {
                if healthy {
                    container.record_health_success();
                } else {
                    let domain = container.domain().clone();
                    let failures = container.health_failures + 1;
                    container.record_health_failure("health check timeout");
                    inner.emit_event(HypervisorEvent::HealthCheckFailed {
                        id,
                        domain,
                        failures,
                    });
                }
            }
        }

        inner.metrics.record_health_check();
        results
    }

    /// Recover crashed containers
    pub fn recover_crashed(&self) -> Vec<ZDomainId> {
        let mut inner = self.inner.write();
        let crashed_ids: Vec<ZDomainId> = inner.registry
            .crashed()
            .iter()
            .map(|c| c.id)
            .collect();

        let mut recovered = Vec::new();

        for id in crashed_ids {
            if let Some(container) = inner.registry.get_mut(&id) {
                let domain = container.domain().clone();
                match inner.recovery_manager.recover(container) {
                    Ok(()) => {
                        recovered.push(id);
                        inner.emit_event(HypervisorEvent::ContainerRecovered { id, domain });
                        inner.metrics.record_recovery();
                    }
                    Err(e) => {
                        tracing::error!("Failed to recover container {}: {}", id, e);
                    }
                }
            }
        }

        recovered
    }

    // ── Diagnostics ──────────────────────────────────────────────────────────

    /// Get hypervisor metrics snapshot
    pub fn metrics(&self) -> HypervisorMetrics {
        self.inner.read().metrics.clone()
    }

    /// Get recent hypervisor events
    pub fn recent_events(&self, count: usize) -> Vec<HypervisorEvent> {
        let inner = self.inner.read();
        let len = inner.event_log.len();
        inner.event_log[len.saturating_sub(count)..].to_vec()
    }

    /// Get all container descriptors
    pub fn domain_descriptors(&self) -> Vec<zenith_abi::domain::DomainDescriptor> {
        self.inner.read()
            .registry
            .running()
            .iter()
            .map(|c| c.to_descriptor())
            .collect()
    }

    /// Total active tasks across all domains
    pub fn total_active_tasks(&self) -> usize {
        self.inner.read().registry.total_active_tasks()
    }

    /// Number of running containers
    pub fn running_container_count(&self) -> usize {
        self.inner.read().registry.running_count()
    }

    /// Whether a specific domain is available
    pub fn is_domain_available(&self, domain: &Domain) -> bool {
        self.inner.read()
            .registry
            .primary(domain)
            .map(|c| c.state.can_accept_tasks())
            .unwrap_or(false)
    }

    /// Get available domains
    pub fn available_domains(&self) -> Vec<Domain> {
        let inner = self.inner.read();
        inner.registry.running()
            .iter()
            .map(|c| c.config.domain.clone())
            .collect()
    }
}

impl Default for ZenithHypervisor {
    fn default() -> Self { Self::new() }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hypervisor_create_domain() {
        let hv = ZenithHypervisor::new();
        let config = ContainerConfig::default_for_domain(Domain::Android);
        let id = hv.create_domain(config).unwrap();
        assert!(hv.is_domain_available(&Domain::Android));
        assert_eq!(hv.running_container_count(), 1);
        hv.destroy_domain(&id).unwrap();
        assert_eq!(hv.running_container_count(), 0);
    }

    #[test]
    fn hypervisor_duplicate_primary_rejected() {
        let hv = ZenithHypervisor::new();
        let c1 = ContainerConfig::default_for_domain(Domain::Windows);
        let c2 = ContainerConfig::default_for_domain(Domain::Windows);
        hv.create_domain(c1).unwrap();
        assert!(hv.create_domain(c2).is_err());
    }

    #[test]
    fn hypervisor_task_assignment() {
        let hv = ZenithHypervisor::new();
        let config = ContainerConfig::default_for_domain(Domain::AI);
        hv.create_domain(config).unwrap();

        let task_id = Uuid::new_v4();
        let container_id = hv.assign_task(task_id, &Domain::AI).unwrap();
        assert_eq!(hv.total_active_tasks(), 1);

        hv.complete_task(&task_id, &Domain::AI).unwrap();
        assert_eq!(hv.total_active_tasks(), 0);
    }

    #[test]
    fn hypervisor_standard_domains() {
        let hv = ZenithHypervisor::new();
        let ids = hv.create_standard_domains().unwrap();
        assert_eq!(ids.len(), 6);
        assert_eq!(hv.running_container_count(), 6);
        assert!(hv.is_domain_available(&Domain::Android));
        assert!(hv.is_domain_available(&Domain::Windows));
        assert!(hv.is_domain_available(&Domain::AI));
        assert!(hv.is_domain_available(&Domain::Quantum));
    }

    #[test]
    fn hypervisor_health_check() {
        let hv = ZenithHypervisor::new();
        let config = ContainerConfig::default_for_domain(Domain::Windows);
        hv.create_domain(config).unwrap();
        let results = hv.health_check_all();
        assert_eq!(results.len(), 1);
    }

    #[test]
    fn hypervisor_available_domains() {
        let hv = ZenithHypervisor::new();
        hv.create_domain(ContainerConfig::default_for_domain(Domain::Android)).unwrap();
        hv.create_domain(ContainerConfig::default_for_domain(Domain::Windows)).unwrap();
        let available = hv.available_domains();
        assert_eq!(available.len(), 2);
    }
}