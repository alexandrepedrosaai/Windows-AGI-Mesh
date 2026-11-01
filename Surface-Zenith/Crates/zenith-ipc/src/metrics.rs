//! # ZIB Bus Metrics

use serde::{Deserialize, Serialize};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;

/// Atomic metrics counters for the ZenithBus
#[derive(Debug, Default)]
pub struct AtomicMetrics {
    pub published:    AtomicU64,
    pub delivered:    AtomicU64,
    pub rejected:     AtomicU64,
    pub expired:      AtomicU64,
    pub subscriptions: AtomicU64,
    pub bytes_sent:   AtomicU64,
}

/// Snapshot of bus metrics (cloneable, serializable)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BusMetrics {
    pub published:     u64,
    pub delivered:     u64,
    pub rejected:      u64,
    pub expired:       u64,
    pub subscriptions: u64,
    pub bytes_sent:    u64,
}

impl BusMetrics {
    /// Create zeroed metrics
    pub fn new() -> Self {
        Self { published: 0, delivered: 0, rejected: 0, expired: 0, subscriptions: 0, bytes_sent: 0 }
    }

    /// Record a successful publish
    pub fn record_published(&mut self, delivered: usize) {
        self.published += 1;
        self.delivered += delivered as u64;
    }

    /// Record a rejected message
    pub fn record_rejected(&mut self) {
        self.rejected += 1;
    }

    /// Record an expired message
    pub fn record_expired(&mut self) {
        self.expired += 1;
    }

    /// Record a new subscription
    pub fn record_subscription(&mut self) {
        self.subscriptions += 1;
    }

    /// Record bytes sent
    pub fn record_bytes(&mut self, bytes: u64) {
        self.bytes_sent += bytes;
    }

    /// Reset all counters
    pub fn reset(&mut self) {
        *self = Self::new();
    }

    /// Delivery success rate (0.0–1.0)
    pub fn delivery_rate(&self) -> f64 {
        if self.published == 0 { return 1.0; }
        self.delivered as f64 / (self.published as f64 * self.subscriptions.max(1) as f64)
    }

    /// Rejection rate (0.0–1.0)
    pub fn rejection_rate(&self) -> f64 {
        let total = self.published + self.rejected;
        if total == 0 { return 0.0; }
        self.rejected as f64 / total as f64
    }
}

impl Default for BusMetrics {
    fn default() -> Self { Self::new() }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn metrics_tracking() {
        let mut m = BusMetrics::new();
        m.record_published(3);
        m.record_published(2);
        m.record_rejected();
        assert_eq!(m.published, 2);
        assert_eq!(m.delivered, 5);
        assert_eq!(m.rejected, 1);
    }

    #[test]
    fn metrics_reset() {
        let mut m = BusMetrics::new();
        m.record_published(10);
        m.reset();
        assert_eq!(m.published, 0);
    }
}