//! # Memory Subsystem Metrics

use serde::{Deserialize, Serialize};

/// Memory subsystem metrics
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct MemoryMetrics {
    pub total_allocations:    u64,
    pub total_frees:          u64,
    pub total_bytes_allocated: u64,
    pub total_bytes_freed:    u64,
    pub umos_created:         u64,
    pub umos_destroyed:       u64,
    pub cow_mappings_created: u64,
    pub cow_faults_handled:   u64,
    pub writes:               u64,
    pub bytes_written:        u64,
    pub reads:                u64,
    pub bytes_read:           u64,
    pub pressure_events:      u64,
    pub oom_events:           u64,
    pub swap_ins:             u64,
    pub swap_outs:            u64,
}

impl MemoryMetrics {
    pub fn new() -> Self { Self::default() }

    pub fn record_allocation(&mut self, bytes: u64) {
        self.total_allocations += 1;
        self.total_bytes_allocated += bytes;
    }

    pub fn record_free(&mut self, bytes: u64) {
        self.total_frees += 1;
        self.total_bytes_freed += bytes;
    }

    pub fn record_umo_created(&mut self)   { self.umos_created += 1; }
    pub fn record_umo_destroyed(&mut self) { self.umos_destroyed += 1; }
    pub fn record_cow_created(&mut self)   { self.cow_mappings_created += 1; }
    pub fn record_cow_fault(&mut self)     { self.cow_faults_handled += 1; }

    pub fn record_write(&mut self, bytes: u64) {
        self.writes += 1;
        self.bytes_written += bytes;
    }

    pub fn record_read(&mut self, bytes: u64) {
        self.reads += 1;
        self.bytes_read += bytes;
    }

    pub fn record_pressure(&mut self) { self.pressure_events += 1; }
    pub fn record_oom(&mut self)      { self.oom_events += 1; }
    pub fn record_swap_in(&mut self)  { self.swap_ins += 1; }
    pub fn record_swap_out(&mut self) { self.swap_outs += 1; }

    pub fn active_umos(&self) -> u64 {
        self.umos_created.saturating_sub(self.umos_destroyed)
    }

    pub fn net_bytes_allocated(&self) -> i64 {
        self.total_bytes_allocated as i64 - self.total_bytes_freed as i64
    }

    pub fn allocation_rate(&self) -> f64 {
        let total = self.total_allocations + self.total_frees;
        if total == 0 { return 0.0; }
        self.total_allocations as f64 / total as f64
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn metrics_tracking() {
        let mut m = MemoryMetrics::new();
        m.record_allocation(4096);
        m.record_allocation(4096);
        m.record_free(4096);
        assert_eq!(m.total_allocations, 2);
        assert_eq!(m.total_frees, 1);
        assert_eq!(m.net_bytes_allocated(), 4096);
    }

    #[test]
    fn metrics_umo_tracking() {
        let mut m = MemoryMetrics::new();
        m.record_umo_created();
        m.record_umo_created();
        m.record_umo_destroyed();
        assert_eq!(m.active_umos(), 1);
    }
}