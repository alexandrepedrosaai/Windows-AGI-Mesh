//! # Domain Container Model
//!
//! Each domain (Android, Windows, AI, Quantum, RealTime, Cloud) runs inside
//! a container managed by the Zenith Hypervisor Layer. Containers provide:
//!
//! - Isolated virtual address space
//! - Dedicated vCPU set
//! - Memory quota enforcement
//! - Capability-gated I/O
//! - Checkpoint/restore support

use serde::{Deserialize, Serialize};
use uuid::Uuid;
use std::collections::HashMap;
use zenith_abi::domain::{Domain, DomainHealth, DomainDescriptor};
use zenith_abi::types::{ZDomainId, ZTaskId, MemoryBytes, CpuQuotaNs, ZTimestamp};
use crate::vcpu::VCpu;
use crate::quota::ResourceQuota;
use crate::error::ZhlError;

// ---------------------------------------------------------------------------
// Container state machine
// ---------------------------------------------------------------------------

/// Lifecycle state of a domain container
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum ContainerState {
    /// Container is being created and initialized
    Creating,
    /// Container is fully operational
    Running,
    /// Container is paused (vCPUs halted, memory preserved)
    Paused,
    /// Container is being checkpointed
    Checkpointing,
    /// Container is being migrated to another physical location
    Migrating,
    /// Container is suspended (memory may be swapped)
    Suspended,
    /// Container is being destroyed
    Destroying,
    /// Container has been destroyed
    Destroyed,
    /// Container has crashed and is awaiting recovery
    Crashed { reason: String, crash_count: u32 },
    /// Container is being restarted after a crash
    Restarting,
}

impl ContainerState {
    /// Whether the container can accept new tasks
    pub fn can_accept_tasks(&self) -> bool {
        matches!(self, ContainerState::Running)
    }

    /// Whether the container is in a terminal state
    pub fn is_terminal(&self) -> bool {
        matches!(self, ContainerState::Destroyed)
    }

    /// Whether the container requires recovery action
    pub fn needs_recovery(&self) -> bool {
        matches!(self, ContainerState::Crashed { .. })
    }

    /// Convert to DomainHealth for the ABI layer
    pub fn to_domain_health(&self) -> DomainHealth {
        match self {
            ContainerState::Running       => DomainHealth::Healthy,
            ContainerState::Paused        => DomainHealth::Suspended,
            ContainerState::Suspended     => DomainHealth::Suspended,
            ContainerState::Crashed { reason, crash_count } => DomainHealth::Failed {
                reason: reason.clone(),
                crash_count: *crash_count,
            },
            ContainerState::Creating | ContainerState::Restarting => DomainHealth::Initializing,
            ContainerState::Migrating     => DomainHealth::Degraded { reason: "migrating".into() },
            ContainerState::Checkpointing => DomainHealth::Degraded { reason: "checkpointing".into() },
            ContainerState::Destroying | ContainerState::Destroyed => DomainHealth::ShuttingDown,
        }
    }
}

// ---------------------------------------------------------------------------
// Container configuration
// ---------------------------------------------------------------------------

/// Configuration for creating a domain container
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ContainerConfig {
    /// Domain type
    pub domain: Domain,
    /// Human-readable label
    pub label: String,
    /// Number of vCPUs to allocate
    pub vcpu_count: u8,
    /// Memory limit in bytes
    pub memory_limit: MemoryBytes,
    /// CPU quota in nanoseconds per scheduling period
    pub cpu_quota: CpuQuotaNs,
    /// Whether to enable memory ballooning (dynamic memory adjustment)
    pub memory_ballooning: bool,
    /// Whether to enable live migration support
    pub live_migration: bool,
    /// Whether to enable checkpoint/restore
    pub checkpointing: bool,
    /// Whether this container is the primary instance of its domain type
    pub is_primary: bool,
    /// Environment variables for the domain runtime
    pub env: HashMap<String, String>,
    /// Resource quota
    pub quota: ResourceQuota,
    /// Kernel command line arguments (for VM-based domains)
    pub kernel_args: Vec<String>,
    /// Root filesystem image path
    pub rootfs_path: Option<String>,
    /// Network configuration
    pub network: NetworkConfig,
}

impl ContainerConfig {
    /// Create a default configuration for a domain
    pub fn default_for_domain(domain: Domain) -> Self {
        let (vcpu_count, memory_limit) = match &domain {
            Domain::Android  => (4,  4  * 1024 * 1024 * 1024),
            Domain::Windows  => (8,  8  * 1024 * 1024 * 1024),
            Domain::AI       => (4,  16 * 1024 * 1024 * 1024),
            Domain::Quantum  => (2,  2  * 1024 * 1024 * 1024),
            Domain::RealTime => (2,  1  * 1024 * 1024 * 1024),
            Domain::Cloud    => (2,  2  * 1024 * 1024 * 1024),
            Domain::Custom(_)=> (2,  2  * 1024 * 1024 * 1024),
        };
        Self {
            label: domain.name().to_string(),
            domain: domain.clone(),
            vcpu_count,
            memory_limit,
            cpu_quota: 1_000_000_000,
            memory_ballooning: true,
            live_migration: true,
            checkpointing: true,
            is_primary: true,
            env: HashMap::new(),
            quota: ResourceQuota::for_domain(&domain),
            kernel_args: Vec::new(),
            rootfs_path: None,
            network: NetworkConfig::default(),
        }
    }
}

/// Network configuration for a container
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct NetworkConfig {
    /// Whether networking is enabled
    pub enabled: bool,
    /// Virtual network interface name
    pub vif_name: Option<String>,
    /// MAC address
    pub mac_address: Option<String>,
    /// IP address (CIDR notation)
    pub ip_address: Option<String>,
    /// Gateway
    pub gateway: Option<String>,
    /// DNS servers
    pub dns_servers: Vec<String>,
    /// Whether to share the host network namespace
    pub host_network: bool,
}

// ---------------------------------------------------------------------------
// Container runtime statistics
// ---------------------------------------------------------------------------

/// Runtime statistics for a container
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct ContainerStats {
    /// CPU time consumed in nanoseconds
    pub cpu_time_ns: u64,
    /// Current CPU usage percentage (0.0–100.0)
    pub cpu_usage_pct: f64,
    /// Current memory usage in bytes
    pub memory_used: MemoryBytes,
    /// Peak memory usage in bytes
    pub memory_peak: MemoryBytes,
    /// Number of page faults
    pub page_faults: u64,
    /// Number of TLB misses
    pub tlb_misses: u64,
    /// Number of context switches
    pub context_switches: u64,
    /// Number of tasks currently running
    pub active_tasks: u32,
    /// Total tasks completed
    pub completed_tasks: u64,
    /// Total tasks failed
    pub failed_tasks: u64,
    /// Number of migrations in
    pub migrations_in: u32,
    /// Number of migrations out
    pub migrations_out: u32,
    /// Number of checkpoints created
    pub checkpoints: u32,
    /// Uptime in milliseconds
    pub uptime_ms: u64,
    /// Last statistics update timestamp
    pub last_updated: ZTimestamp,
}

impl ContainerStats {
    /// Update CPU usage percentage from raw CPU time
    pub fn update_cpu_usage(&mut self, elapsed_ns: u64) {
        if elapsed_ns > 0 {
            self.cpu_usage_pct = (self.cpu_time_ns as f64 / elapsed_ns as f64) * 100.0;
            self.cpu_usage_pct = self.cpu_usage_pct.min(100.0);
        }
    }

    /// Memory usage percentage
    pub fn memory_usage_pct(&self, limit: MemoryBytes) -> f64 {
        if limit == 0 { return 0.0; }
        (self.memory_used as f64 / limit as f64) * 100.0
    }
}

// ---------------------------------------------------------------------------
// Domain container
// ---------------------------------------------------------------------------

/// A domain container managed by the Zenith Hypervisor Layer
#[derive(Debug)]
pub struct DomainContainer {
    /// Unique container ID
    pub id: ZDomainId,
    /// Container configuration
    pub config: ContainerConfig,
    /// Current lifecycle state
    pub state: ContainerState,
    /// Virtual CPUs
    pub vcpus: Vec<VCpu>,
    /// Runtime statistics
    pub stats: ContainerStats,
    /// Active task IDs
    pub active_tasks: Vec<ZTaskId>,
    /// Container creation timestamp
    pub created_at: ZTimestamp,
    /// Last state transition timestamp
    pub last_transition: ZTimestamp,
    /// Number of consecutive health check failures
    pub health_failures: u32,
    /// Total crash count
    pub crash_count: u32,
    /// Whether this container is currently being health-checked
    pub health_check_in_progress: bool,
    /// Container-specific metadata
    pub metadata: HashMap<String, String>,
}

impl DomainContainer {
    /// Create a new domain container
    pub fn new(config: ContainerConfig) -> Self {
        let now = ZTimestamp(
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default()
                .as_micros() as i64,
        );

        let vcpus = (0..config.vcpu_count)
            .map(|i| VCpu::new(i as u32, config.domain.clone()))
            .collect();

        Self {
            id: Uuid::new_v4(),
            config,
            state: ContainerState::Creating,
            vcpus,
            stats: ContainerStats::default(),
            active_tasks: Vec::new(),
            created_at: now,
            last_transition: now,
            health_failures: 0,
            crash_count: 0,
            health_check_in_progress: false,
            metadata: HashMap::new(),
        }
    }

    /// Transition to a new state
    pub fn transition(&mut self, new_state: ContainerState) {
        tracing::info!(
            "Container {} ({:?}) transitioning: {:?} → {:?}",
            self.id, self.config.domain, self.state, new_state
        );
        self.state = new_state;
        self.last_transition = ZTimestamp(
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default()
                .as_micros() as i64,
        );
    }

    /// Start the container
    pub fn start(&mut self) -> Result<(), ZhlError> {
        match self.state {
            ContainerState::Creating | ContainerState::Restarting => {
                // Initialize vCPUs
                for vcpu in &mut self.vcpus {
                    vcpu.initialize()?;
                }
                self.transition(ContainerState::Running);
                self.stats.uptime_ms = 0;
                Ok(())
            }
            ContainerState::Paused | ContainerState::Suspended => {
                // Resume from paused state
                for vcpu in &mut self.vcpus {
                    vcpu.resume()?;
                }
                self.transition(ContainerState::Running);
                Ok(())
            }
            _ => Err(ZhlError::InvalidStateTransition {
                from: format!("{:?}", self.state),
                to:   "Running".into(),
            }),
        }
    }

    /// Pause the container (halt vCPUs, preserve memory)
    pub fn pause(&mut self) -> Result<(), ZhlError> {
        if self.state != ContainerState::Running {
            return Err(ZhlError::InvalidStateTransition {
                from: format!("{:?}", self.state),
                to:   "Paused".into(),
            });
        }
        for vcpu in &mut self.vcpus {
            vcpu.pause()?;
        }
        self.transition(ContainerState::Paused);
        Ok(())
    }

    /// Resume a paused container
    pub fn resume(&mut self) -> Result<(), ZhlError> {
        if !matches!(self.state, ContainerState::Paused | ContainerState::Suspended) {
            return Err(ZhlError::InvalidStateTransition {
                from: format!("{:?}", self.state),
                to:   "Running".into(),
            });
        }
        for vcpu in &mut self.vcpus {
            vcpu.resume()?;
        }
        self.transition(ContainerState::Running);
        Ok(())
    }

    /// Destroy the container
    pub fn destroy(&mut self) -> Result<(), ZhlError> {
        for vcpu in &mut self.vcpus {
            vcpu.halt();
        }
        self.active_tasks.clear();
        self.transition(ContainerState::Destroyed);
        Ok(())
    }

    /// Record a health check failure
    pub fn record_health_failure(&mut self, reason: impl Into<String>) {
        self.health_failures += 1;
        if self.health_failures >= crate::MAX_HEALTH_FAILURES {
            self.crash_count += 1;
            self.transition(ContainerState::Crashed {
                reason: reason.into(),
                crash_count: self.crash_count,
            });
        }
    }

    /// Reset health failure counter after successful check
    pub fn record_health_success(&mut self) {
        self.health_failures = 0;
    }

    /// Add a task to this container
    pub fn add_task(&mut self, task_id: ZTaskId) {
        if !self.active_tasks.contains(&task_id) {
            self.active_tasks.push(task_id);
            self.stats.active_tasks += 1;
        }
    }

    /// Remove a task from this container
    pub fn remove_task(&mut self, task_id: &ZTaskId) -> bool {
        let before = self.active_tasks.len();
        self.active_tasks.retain(|id| id != task_id);
        let removed = self.active_tasks.len() < before;
        if removed {
            self.stats.active_tasks = self.stats.active_tasks.saturating_sub(1);
        }
        removed
    }

    /// Whether this container can accept a new task
    pub fn can_accept_task(&self) -> bool {
        self.state.can_accept_tasks()
            && self.stats.memory_used < self.config.memory_limit
&& self.stats.active_tasks < self.config.quota.max_tasks
    }

    /// Domain type of this container
    pub fn domain(&self) -> &Domain {
        &self.config.domain
    }

    /// Convert to ABI DomainDescriptor
    pub fn to_descriptor(&self) -> DomainDescriptor {
        let mut desc = DomainDescriptor::new(
            self.config.domain.clone(),
            self.config.label.clone(),
        );
        desc.id = self.id;
        desc.memory_limit = self.config.memory_limit;
        desc.cpu_quota = self.config.cpu_quota;
        desc.health = self.state.to_domain_health();
        desc.is_primary = self.config.is_primary;
        desc
    }

    /// Uptime in milliseconds
    pub fn uptime_ms(&self) -> u64 {
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_micros() as i64;
        ((now - self.created_at.0) / 1000).max(0) as u64
    }
}

// ---------------------------------------------------------------------------
// Container registry
// ---------------------------------------------------------------------------

/// Registry of all domain containers managed by the ZHL
#[derive(Debug, Default)]
pub struct ContainerRegistry {
    containers: HashMap<ZDomainId, DomainContainer>,
    /// Domain type → primary container ID
    primary_map: HashMap<String, ZDomainId>,
}

impl ContainerRegistry {
    /// Create a new empty registry
    pub fn new() -> Self {
        Self::default()
    }

    /// Register a new container
    pub fn register(&mut self, container: DomainContainer) -> ZDomainId {
        let id = container.id;
        let domain_key = container.config.domain.name().to_string();

        if container.config.is_primary {
            self.primary_map.insert(domain_key, id);
        }

        self.containers.insert(id, container);
        id
    }

    /// Get a container by ID
    pub fn get(&self, id: &ZDomainId) -> Option<&DomainContainer> {
        self.containers.get(id)
    }

    /// Get a mutable container by ID
    pub fn get_mut(&mut self, id: &ZDomainId) -> Option<&mut DomainContainer> {
        self.containers.get_mut(id)
    }

    /// Get the primary container for a domain type
    pub fn primary(&self, domain: &Domain) -> Option<&DomainContainer> {
        self.primary_map
            .get(domain.name())
            .and_then(|id| self.containers.get(id))
    }

    /// Get the primary mutable container for a domain type
    pub fn primary_mut(&mut self, domain: &Domain) -> Option<&mut DomainContainer> {
        let id = self.primary_map.get(domain.name()).copied()?;
        self.containers.get_mut(&id)
    }

    /// Get all containers for a domain type
    pub fn by_domain(&self, domain: &Domain) -> Vec<&DomainContainer> {
        self.containers
            .values()
            .filter(|c| &c.config.domain == domain)
            .collect()
    }

    /// Get all running containers
    pub fn running(&self) -> Vec<&DomainContainer> {
        self.containers
            .values()
            .filter(|c| c.state == ContainerState::Running)
            .collect()
    }

    /// Get all crashed containers
    pub fn crashed(&self) -> Vec<&DomainContainer> {
        self.containers
            .values()
            .filter(|c| c.state.needs_recovery())
            .collect()
    }

    /// Remove a destroyed container
    pub fn remove(&mut self, id: &ZDomainId) -> Option<DomainContainer> {
        if let Some(container) = self.containers.remove(id) {
            let domain_key = container.config.domain.name().to_string();
            if self.primary_map.get(&domain_key) == Some(id) {
                self.primary_map.remove(&domain_key);
            }
            Some(container)
        } else {
            None
        }
    }

    /// Total container count
    pub fn count(&self) -> usize {
        self.containers.len()
    }

    /// Count of running containers
    pub fn running_count(&self) -> usize {
        self.running().len()
    }

    /// Total active tasks across all containers
    pub fn total_active_tasks(&self) -> usize {
        self.containers.values().map(|c| c.active_tasks.len()).sum()
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    fn make_container(domain: Domain) -> DomainContainer {
        DomainContainer::new(ContainerConfig::default_for_domain(domain))
    }

    #[test]
    fn container_lifecycle() {
        let mut c = make_container(Domain::Android);
        assert_eq!(c.state, ContainerState::Creating);
        c.start().unwrap();
        assert_eq!(c.state, ContainerState::Running);
        c.pause().unwrap();
        assert_eq!(c.state, ContainerState::Paused);
        c.resume().unwrap();
        assert_eq!(c.state, ContainerState::Running);
        c.destroy().unwrap();
        assert_eq!(c.state, ContainerState::Destroyed);
    }

    #[test]
    fn container_health_failures() {
        let mut c = make_container(Domain::Windows);
        c.start().unwrap();
        c.record_health_failure("timeout");
        c.record_health_failure("timeout");
        assert_eq!(c.state, ContainerState::Running); // not yet crashed
        c.record_health_failure("timeout");
        assert!(c.state.needs_recovery());
    }

    #[test]
    fn container_task_management() {
        let mut c = make_container(Domain::AI);
        c.start().unwrap();
        let task_id = Uuid::new_v4();
        c.add_task(task_id);
        assert_eq!(c.active_tasks.len(), 1);
        assert!(c.remove_task(&task_id));
        assert_eq!(c.active_tasks.len(), 0);
    }

    #[test]
    fn registry_primary_lookup() {
        let mut registry = ContainerRegistry::new();
        let c = make_container(Domain::Windows);
        registry.register(c);
        assert!(registry.primary(&Domain::Windows).is_some());
        assert!(registry.primary(&Domain::Android).is_none());
    }

    #[test]
    fn registry_by_domain() {
        let mut registry = ContainerRegistry::new();
        let mut c1 = make_container(Domain::Android);
        c1.config.is_primary = true;
        let mut c2 = make_container(Domain::Android);
        c2.config.is_primary = false;
        registry.register(c1);
        registry.register(c2);
        assert_eq!(registry.by_domain(&Domain::Android).len(), 2);
    }

    #[test]
    fn container_stats_memory_pct() {
        let mut stats = ContainerStats::default();
        stats.memory_used = 4 * 1024 * 1024 * 1024; // 4 GB
        let limit = 8 * 1024 * 1024 * 1024u64;       // 8 GB
        assert!((stats.memory_usage_pct(limit) - 50.0).abs() < 0.01);
    }

    #[test]
    fn container_to_descriptor() {
        let mut c = make_container(Domain::AI);
        c.start().unwrap();
        let desc = c.to_descriptor();
        assert_eq!(desc.domain, Domain::AI);
        assert!(matches!(desc.health, DomainHealth::Healthy));
    }
}