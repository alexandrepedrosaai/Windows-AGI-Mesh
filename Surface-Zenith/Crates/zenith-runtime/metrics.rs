//! # Domain Runtime Metrics

use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use zenith_abi::domain::Domain;

/// Per-domain runtime metrics
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DomainMetrics {
    pub domain:          String,
    pub tasks_accepted:  u64,
    pub tasks_completed: u64,
    pub tasks_failed:    u64,
    pub events:          HashMap<String, u64>,
    pub uptime_ms:       u64,
    pub started_at:      std::time::Instant,
}

impl DomainMetrics {
    pub fn new(domain: Domain) -> Self {
        Self {
            domain:          domain.name().to_string(),
            tasks_accepted:  0,
            tasks_completed: 0,
            tasks_failed:    0,
            events:          HashMap::new(),
            uptime_ms:       0,
            started_at:      std::time::Instant::now(),
        }
    }

    pub fn record_task_accepted(&mut self)  { self.tasks_accepted += 1; }
    pub fn record_task_completed(&mut self) { self.tasks_completed += 1; }
    pub fn record_task_failed(&mut self)    { self.tasks_failed += 1; }

    pub fn record_event(&mut self, event: &str) {
        *self.events.entry(event.to_string()).or_insert(0) += 1;
    }

    pub fn uptime_ms(&self) -> u64 {
        self.started_at.elapsed().as_millis() as u64
    }

    pub fn task_success_rate(&self) -> f64 {
        let total = self.tasks_completed + self.tasks_failed;
        if total == 0 { return 1.0; }
        self.tasks_completed as f64 / total as f64
    }

    pub fn event_count(&self, event: &str) -> u64 {
        *self.events.get(event).unwrap_or(&0)
    }
}

/// Runtime metrics registry
#[derive(Debug, Default)]
pub struct RuntimeMetricsRegistry {
    metrics: HashMap<String, DomainMetrics>,
}

impl RuntimeMetricsRegistry {
    pub fn new() -> Self { Self::default() }

    pub fn register(&mut self, metrics: DomainMetrics) {
        self.metrics.insert(metrics.domain.clone(), metrics);
    }

    pub fn get(&self, domain: &str) -> Option<&DomainMetrics> {
        self.metrics.get(domain)
    }

    pub fn all(&self) -> Vec<&DomainMetrics> {
        self.metrics.values().collect()
    }

    pub fn total_tasks_accepted(&self) -> u64 {
        self.metrics.values().map(|m| m.tasks_accepted).sum()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn domain_metrics_tracking() {
        let mut m = DomainMetrics::new(Domain::Windows);
        m.record_task_accepted();
        m.record_task_accepted();
        m.record_task_completed();
        m.record_task_failed();
        assert_eq!(m.tasks_accepted, 2);
        assert!((m.task_success_rate() - 0.5).abs() < 0.01);
    }

    #[test]
    fn domain_metrics_events() {
        let mut m = DomainMetrics::new(Domain::Android);
        m.record_event("app_launched");
        m.record_event("app_launched");
        m.record_event("app_stopped");
        assert_eq!(m.event_count("app_launched"), 2);
        assert_eq!(m.event_count("app_stopped"), 1);
        assert_eq!(m.event_count("nonexistent"), 0);
    }

    #[test]
    fn metrics_registry() {
        let mut registry = RuntimeMetricsRegistry::new();
        let mut m1 = DomainMetrics::new(Domain::Windows);
        m1.record_task_accepted();
        let mut m2 = DomainMetrics::new(Domain::Android);
        m2.record_task_accepted();
        m2.record_task_accepted();
        registry.register(m1);
        registry.register(m2);
        assert_eq!(registry.total_tasks_accepted(), 3);
    }
}