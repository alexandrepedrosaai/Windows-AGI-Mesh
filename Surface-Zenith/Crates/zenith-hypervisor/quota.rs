//! # Resource Quota Enforcement

use serde::{Deserialize, Serialize};
use zenith_abi::types::MemoryBytes;

/// Resource quota for a domain container
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ResourceQuota {
    /// Maximum CPU usage percentage (0–100)
    pub max_cpu_pct:        f64,
    /// Maximum memory in bytes
    pub max_memory:         MemoryBytes,
    /// Maximum network bandwidth in bytes/second
    pub max_network_bps:    u64,
    /// Maximum disk I/O in bytes/second
    pub max_disk_iops:      u64,
    /// Maximum number of open file descriptors
    pub max_fds:            u32,
    /// Maximum number of threads
    pub max_threads:        u32,
    /// Maximum number of active tasks
    pub max_tasks:          u32,
    /// CPU burst allowance (percentage above max_cpu_pct for short periods)
    pub cpu_burst_pct:      f64,
    /// Burst duration in milliseconds
    pub burst_duration_ms:  u64,
}

impl Default for ResourceQuota {
    fn default() -> Self {
        Self {
            max_cpu_pct:       80.0,
            max_memory:        8 * 1024 * 1024 * 1024,
            max_network_bps:   1_000_000_000,
            max_disk_iops:     100_000,
            max_fds:           65536,
            max_threads:       4096,
            max_tasks:         1000,
            cpu_burst_pct:     100.0,
            burst_duration_ms: 1000,
        }
    }
}

impl ResourceQuota {
    /// Create a quota for a specific domain type
    pub fn for_domain(domain: &zenith_abi::domain::Domain) -> Self {
        match domain {
            zenith_abi::domain::Domain::Android => Self {
                max_cpu_pct:   60.0,
                max_memory:    4 * 1024 * 1024 * 1024,
                max_tasks:     500,
                ..Default::default()
            },
            zenith_abi::domain::Domain::Windows => Self {
                max_cpu_pct:   80.0,
                max_memory:    8 * 1024 * 1024 * 1024,
                max_tasks:     1000,
                ..Default::default()
            },
            zenith_abi::domain::Domain::AI => Self {
                max_cpu_pct:   90.0,
                max_memory:    16 * 1024 * 1024 * 1024,
                max_tasks:     200,
                ..Default::default()
            },
            zenith_abi::domain::Domain::RealTime => Self {
                max_cpu_pct:   30.0,
                max_memory:    1 * 1024 * 1024 * 1024,
                max_tasks:     100,
                cpu_burst_pct: 50.0,
                ..Default::default()
            },
            _ => Self::default(),
        }
    }

    /// Check if CPU usage is within quota
    pub fn cpu_ok(&self, usage_pct: f64) -> bool {
        usage_pct <= self.max_cpu_pct + self.cpu_burst_pct
    }

    /// Check if memory usage is within quota
    pub fn memory_ok(&self, used: MemoryBytes) -> bool {
        used <= self.max_memory
    }

    /// Check if task count is within quota
    pub fn tasks_ok(&self, count: u32) -> bool {
        count <= self.max_tasks
    }
}

/// Quota violation record
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QuotaViolation {
    pub resource:   String,
    pub limit:      f64,
    pub actual:     f64,
    pub timestamp:  zenith_abi::types::ZTimestamp,
}

/// Quota enforcer — tracks and enforces resource limits
#[derive(Debug, Default)]
pub struct QuotaEnforcer {
    violations: Vec<QuotaViolation>,
}

impl QuotaEnforcer {
    pub fn new() -> Self { Self::default() }

    /// Check all quotas and record violations
    pub fn check(
        &mut self,
        quota: &ResourceQuota,
        cpu_pct: f64,
        memory: MemoryBytes,
        task_count: u32,
    ) -> Vec<QuotaViolation> {
        let mut violations = Vec::new();
        let now = zenith_abi::types::ZTimestamp(
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default()
                .as_micros() as i64,
        );

        if !quota.cpu_ok(cpu_pct) {
            violations.push(QuotaViolation {
                resource:  "cpu".into(),
                limit:     quota.max_cpu_pct,
                actual:    cpu_pct,
                timestamp: now,
            });
        }
        if !quota.memory_ok(memory) {
            violations.push(QuotaViolation {
                resource:  "memory".into(),
                limit:     quota.max_memory as f64,
                actual:    memory as f64,
                timestamp: now,
            });
        }
        if !quota.tasks_ok(task_count) {
            violations.push(QuotaViolation {
                resource:  "tasks".into(),
                limit:     quota.max_tasks as f64,
                actual:    task_count as f64,
                timestamp: now,
            });
        }

        self.violations.extend(violations.clone());
        violations
    }

    /// Total violation count
    pub fn violation_count(&self) -> usize {
        self.violations.len()
    }

    /// Recent violations
    pub fn recent(&self, count: usize) -> &[QuotaViolation] {
        let len = self.violations.len();
        &self.violations[len.saturating_sub(count)..]
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn quota_cpu_check() {
        let quota = ResourceQuota::default();
        assert!(quota.cpu_ok(79.0));
        assert!(quota.cpu_ok(80.0));
        assert!(!quota.cpu_ok(181.0)); // exceeds max + burst
    }

    #[test]
    fn quota_memory_check() {
        let quota = ResourceQuota::default();
        assert!(quota.memory_ok(4 * 1024 * 1024 * 1024));
        assert!(!quota.memory_ok(9 * 1024 * 1024 * 1024));
    }

    #[test]
    fn quota_enforcer_violations() {
        let mut enforcer = QuotaEnforcer::new();
        let quota = ResourceQuota::default();
        let violations = enforcer.check(&quota, 200.0, 0, 0);
        assert_eq!(violations.len(), 1);
        assert_eq!(violations[0].resource, "cpu");
    }

    #[test]
    fn quota_for_realtime_domain() {
        let quota = ResourceQuota::for_domain(&zenith_abi::domain::Domain::RealTime);
        assert!(quota.max_cpu_pct < 50.0);
        assert!(quota.max_memory < 2 * 1024 * 1024 * 1024);
    }
}