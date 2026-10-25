//! # Domain Supervisor
//!
//! Monitors domain container health using an Erlang-inspired supervision tree.
//! Implements L1–L4 recovery levels.

use std::collections::HashMap;
use uuid::Uuid;
use zenith_abi::types::ZDomainId;
use crate::container::DomainContainer;

/// Recovery level
#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord)]
pub enum RecoveryLevel {
    /// L1: Restart failed thread (1ms)
    Thread,
    /// L2: Restart failed process (10ms)
    Process,
    /// L3: Restart domain runtime (100ms)
    Domain,
    /// L4: Migrate domain to another physical node
    Migrate,
}

/// Supervision strategy
#[derive(Debug, Clone)]
pub enum SupervisionStrategy {
    /// Restart only the failed child
    OneForOne,
    /// Restart all children when one fails
    OneForAll,
    /// Restart failed child and all children started after it
    RestForOne,
}

/// A supervision tree node
#[derive(Debug)]
pub struct SupervisionNode {
    pub id:               ZDomainId,
    pub strategy:         SupervisionStrategy,
    pub max_restarts:     u32,
    pub restart_window_s: u64,
    pub restart_count:    u32,
    pub last_restart:     Option<std::time::Instant>,
    pub children:         Vec<ZDomainId>,
}

impl SupervisionNode {
    pub fn new(id: ZDomainId, strategy: SupervisionStrategy) -> Self {
        Self {
            id,
            strategy,
            max_restarts: 5,
            restart_window_s: 60,
            restart_count: 0,
            last_restart: None,
            children: Vec::new(),
        }
    }

    /// Whether this node can be restarted (within rate limit)
    pub fn can_restart(&self) -> bool {
        if self.restart_count >= self.max_restarts {
            if let Some(last) = self.last_restart {
                if last.elapsed().as_secs() < self.restart_window_s {
                    return false;
                }
                // Window expired — reset counter
            }
        }
        true
    }

    /// Record a restart
    pub fn record_restart(&mut self) {
        self.restart_count += 1;
        self.last_restart = Some(std::time::Instant::now());
    }
}

/// The Domain Supervisor — health monitoring and recovery orchestration
#[derive(Debug, Default)]
pub struct DomainSupervisor {
    nodes:          HashMap<ZDomainId, SupervisionNode>,
    health_history: HashMap<ZDomainId, Vec<bool>>,
    check_count:    u64,
}

impl DomainSupervisor {
    /// Create a new supervisor
    pub fn new() -> Self {
        Self::default()
    }

    /// Register a container with the supervisor
    pub fn register(&mut self, id: ZDomainId, strategy: SupervisionStrategy) {
        self.nodes.insert(id, SupervisionNode::new(id, strategy));
        self.health_history.insert(id, Vec::new());
    }

    /// Perform a health check on a container
    ///
    /// In production: sends a heartbeat request and waits for response.
    /// Here: simulates health based on history.
    pub fn check_health(&mut self, id: &ZDomainId) -> bool {
        self.check_count += 1;

        // Simulate: 99% healthy
        let healthy = (self.check_count % 100) != 0;

        if let Some(history) = self.health_history.get_mut(id) {
            history.push(healthy);
            if history.len() > 100 {
                history.remove(0);
            }
        }

        healthy
    }

    /// Get health score for a container (0.0–1.0)
    pub fn health_score(&self, id: &ZDomainId) -> f64 {
        if let Some(history) = self.health_history.get(id) {
            if history.is_empty() { return 1.0; }
            let healthy = history.iter().filter(|&&h| h).count();
            healthy as f64 / history.len() as f64
        } else {
            0.0
        }
    }

    /// Determine the appropriate recovery level for a container
    pub fn recovery_level(&self, id: &ZDomainId) -> RecoveryLevel {
        let score = self.health_score(id);
        let node = self.nodes.get(id);
        let restarts = node.map(|n| n.restart_count).unwrap_or(0);

        if restarts == 0 {
            RecoveryLevel::Thread
        } else if restarts < 2 {
            RecoveryLevel::Process
        } else if restarts < 4 {
            RecoveryLevel::Domain
        } else {
            RecoveryLevel::Migrate
        }
    }

    /// Whether a container can be restarted
    pub fn can_restart(&self, id: &ZDomainId) -> bool {
        self.nodes.get(id).map(|n| n.can_restart()).unwrap_or(false)
    }

    /// Record a restart for a container
    pub fn record_restart(&mut self, id: &ZDomainId) {
        if let Some(node) = self.nodes.get_mut(id) {
            node.record_restart();
        }
    }

    /// Total health checks performed
    pub fn check_count(&self) -> u64 {
        self.check_count
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn supervisor_health_check() {
        let mut supervisor = DomainSupervisor::new();
        let id = Uuid::new_v4();
        supervisor.register(id, SupervisionStrategy::OneForOne);
        let healthy = supervisor.check_health(&id);
        // First check (count=1) should be healthy
        assert!(healthy);
    }

    #[test]
    fn supervisor_health_score() {
        let mut supervisor = DomainSupervisor::new();
        let id = Uuid::new_v4();
        supervisor.register(id, SupervisionStrategy::OneForOne);
        // Run 10 checks
        for _ in 0..10 {
            supervisor.check_health(&id);
        }
        let score = supervisor.health_score(&id);
        assert!(score >= 0.0 && score <= 1.0);
    }

    #[test]
    fn recovery_level_escalation() {
        let mut supervisor = DomainSupervisor::new();
        let id = Uuid::new_v4();
        supervisor.register(id, SupervisionStrategy::OneForOne);
        assert_eq!(supervisor.recovery_level(&id), RecoveryLevel::Thread);
        supervisor.record_restart(&id);
        assert_eq!(supervisor.recovery_level(&id), RecoveryLevel::Process);
        supervisor.record_restart(&id);
        supervisor.record_restart(&id);
        assert_eq!(supervisor.recovery_level(&id), RecoveryLevel::Domain);
    }

    #[test]
    fn restart_rate_limiting() {
        let mut node = SupervisionNode::new(Uuid::new_v4(), SupervisionStrategy::OneForOne);
        node.max_restarts = 2;
        node.restart_window_s = 3600;
        assert!(node.can_restart());
        node.record_restart();
        node.record_restart();
        assert!(!node.can_restart()); // Rate limited
    }
}