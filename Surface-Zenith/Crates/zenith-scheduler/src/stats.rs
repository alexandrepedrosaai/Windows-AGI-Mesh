//! # Zenith Scheduler Statistics

use serde::{Deserialize, Serialize};

/// Scheduler statistics snapshot
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct SchedulerStats {
    pub total_submitted:  u64,
    pub total_scheduled:  u64,
    pub total_completed:  u64,
    pub total_failed:     u64,
    pub total_cancelled:  u64,
    pub total_dropped:    u64,
    pub total_tasks_dispatched: u64,
    pub total_migrations: u64,
}

impl SchedulerStats {
    pub fn new() -> Self { Self::default() }

    pub fn record_submitted(&mut self)              { self.total_submitted += 1; }
    pub fn record_scheduled(&mut self, tasks: usize){ self.total_scheduled += 1; self.total_tasks_dispatched += tasks as u64; }
    pub fn record_completed(&mut self)              { self.total_completed += 1; }
    pub fn record_failed(&mut self)                 { self.total_failed += 1; }
    pub fn record_cancelled(&mut self)              { self.total_cancelled += 1; }
    pub fn record_dropped(&mut self)                { self.total_dropped += 1; }
    pub fn record_migration(&mut self)              { self.total_migrations += 1; }

    pub fn completion_rate(&self) -> f64 {
        if self.total_scheduled == 0 { return 0.0; }
        self.total_completed as f64 / self.total_scheduled as f64
    }

    pub fn failure_rate(&self) -> f64 {
        let total = self.total_completed + self.total_failed;
        if total == 0 { return 0.0; }
        self.total_failed as f64 / total as f64
    }

    pub fn drop_rate(&self) -> f64 {
        let total = self.total_submitted + self.total_dropped;
        if total == 0 { return 0.0; }
        self.total_dropped as f64 / total as f64
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn stats_rates() {
        let mut s = SchedulerStats::new();
        s.record_submitted();
        s.record_submitted();
        s.record_scheduled(3);
        s.record_scheduled(2);
        s.record_completed();
        s.record_failed();
        assert_eq!(s.total_submitted, 2);
        assert_eq!(s.total_tasks_dispatched, 5);
        assert!(s.failure_rate() > 0.0);
    }
}