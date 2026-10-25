//! # Scheduler Bridge
//!
//! Bridges the Zenith Hypervisor Layer with the Intent Scheduler.
//! Translates scheduler decisions into hypervisor actions.

use std::collections::HashMap;
use uuid::Uuid;
use zenith_abi::domain::Domain;
use zenith_abi::types::{ZTaskId, ZDomainId};

/// A scheduler decision received by the hypervisor
#[derive(Debug, Clone)]
pub struct SchedulerDecision {
    pub task_id:    ZTaskId,
    pub domain:     Domain,
    pub priority:   u8,
    pub energy_cost: u32,
    pub latency_ms: u32,
}

/// Bridge between the scheduler and hypervisor
#[derive(Debug, Default)]
pub struct SchedulerBridge {
    pending_decisions: Vec<SchedulerDecision>,
    processed_count:   u64,
    rejected_count:    u64,
}

impl SchedulerBridge {
    pub fn new() -> Self { Self::default() }

    /// Submit a scheduler decision to the hypervisor
    pub fn submit_decision(&mut self, decision: SchedulerDecision) {
        self.pending_decisions.push(decision);
    }

    /// Process all pending decisions
    pub fn process_pending(&mut self) -> Vec<SchedulerDecision> {
        let decisions = std::mem::take(&mut self.pending_decisions);
        self.processed_count += decisions.len() as u64;
        decisions
    }

    /// Reject a decision (domain unavailable)
    pub fn reject_decision(&mut self, task_id: ZTaskId, reason: impl Into<String>) {
        self.rejected_count += 1;
        tracing::warn!("Scheduler decision rejected for task {}: {}", task_id, reason.into());
    }

    /// Total decisions processed
    pub fn processed_count(&self) -> u64 { self.processed_count }

    /// Total decisions rejected
    pub fn rejected_count(&self) -> u64 { self.rejected_count }

    /// Acceptance rate
    pub fn acceptance_rate(&self) -> f64 {
        let total = self.processed_count + self.rejected_count;
        if total == 0 { return 1.0; }
        self.processed_count as f64 / total as f64
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn scheduler_bridge_process() {
        let mut bridge = SchedulerBridge::new();
        bridge.submit_decision(SchedulerDecision {
            task_id:     Uuid::new_v4(),
            domain:      Domain::Windows,
            priority:    128,
            energy_cost: 50,
            latency_ms:  100,
        });
        let decisions = bridge.process_pending();
        assert_eq!(decisions.len(), 1);
        assert_eq!(bridge.processed_count(), 1);
    }

    #[test]
    fn scheduler_bridge_acceptance_rate() {
        let mut bridge = SchedulerBridge::new();
        bridge.submit_decision(SchedulerDecision {
            task_id: Uuid::new_v4(), domain: Domain::AI,
            priority: 100, energy_cost: 30, latency_ms: 50,
        });
        bridge.process_pending();
        bridge.reject_decision(Uuid::new_v4(), "domain unavailable");
        assert!((bridge.acceptance_rate() - 0.5).abs() < 0.01);
    }
}