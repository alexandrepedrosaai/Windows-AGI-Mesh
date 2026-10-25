//! # Hypervisor Metrics

use serde::{Deserialize, Serialize};

/// Hypervisor performance metrics
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct HypervisorMetrics {
    pub containers_created:    u64,
    pub containers_destroyed:  u64,
    pub tasks_assigned:        u64,
    pub tasks_completed:       u64,
    pub tasks_failed:          u64,
    pub migrations_started:    u64,
    pub migrations_completed:  u64,
    pub migrations_failed:     u64,
    pub health_checks:         u64,
    pub recoveries:            u64,
    pub total_uptime_ms:       u64,
}

impl HypervisorMetrics {
    pub fn new() -> Self { Self::default() }
    pub fn record_container_created(&mut self)   { self.containers_created += 1; }
    pub fn record_container_destroyed(&mut self) { self.containers_destroyed += 1; }
    pub fn record_task_assigned(&mut self)       { self.tasks_assigned += 1; }
    pub fn record_task_completed(&mut self)      { self.tasks_completed += 1; }
    pub fn record_task_failed(&mut self)         { self.tasks_failed += 1; }
    pub fn record_migration_started(&mut self)   { self.migrations_started += 1; }
    pub fn record_migration_completed(&mut self) { self.migrations_completed += 1; }
    pub fn record_migration_failed(&mut self)    { self.migrations_failed += 1; }
    pub fn record_health_check(&mut self)        { self.health_checks += 1; }
    pub fn record_recovery(&mut self)            { self.recoveries += 1; }

    pub fn migration_success_rate(&self) -> f64 {
        if self.migrations_started == 0 { return 1.0; }
        self.migrations_completed as f64 / self.migrations_started as f64
    }

    pub fn task_success_rate(&self) -> f64 {
        let total = self.tasks_completed + self.tasks_failed;
        if total == 0 { return 1.0; }
        self.tasks_completed as f64 / total as f64
    }

    pub fn active_containers(&self) -> u64 {
        self.containers_created.saturating_sub(self.containers_destroyed)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn metrics_rates() {
        let mut m = HypervisorMetrics::new();
        m.record_migration_started();
        m.record_migration_started();
        m.record_migration_completed();
        assert!((m.migration_success_rate() - 0.5).abs() < 0.01);
    }

    #[test]
    fn metrics_active_containers() {
        let mut m = HypervisorMetrics::new();
        m.record_container_created();
        m.record_container_created();
        m.record_container_destroyed();
        assert_eq!(m.active_containers(), 1);
    }
}