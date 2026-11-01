//! # ZIB Quality of Service
//!
//! QoS policies control message delivery guarantees, TTL, retry behavior,
//! and ordering semantics for each topic.

use serde::{Deserialize, Serialize};

/// Delivery guarantee level
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum DeliveryGuarantee {
    /// Fire and forget — no acknowledgment required
    AtMostOnce,
    /// Deliver at least once — may duplicate on retry
    AtLeastOnce,
    /// Exactly once — deduplication enforced
    ExactlyOnce,
}

/// Message ordering guarantee
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum OrderingGuarantee {
    /// No ordering guarantee
    Unordered,
    /// Messages from the same source arrive in order
    PerSource,
    /// All messages arrive in global order (expensive)
    GlobalOrder,
}

/// QoS policy for a topic or message
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QosPolicy {
    /// Delivery guarantee
    pub delivery: DeliveryGuarantee,
    /// Ordering guarantee
    pub ordering: OrderingGuarantee,
    /// Time-to-live in milliseconds (0 = never expires)
    pub ttl_ms: u64,
    /// Maximum retry attempts (for AtLeastOnce / ExactlyOnce)
    pub max_retries: u32,
    /// Retry backoff in milliseconds
    pub retry_backoff_ms: u64,
    /// Whether to persist messages across restarts
    pub persistent: bool,
    /// Maximum queue depth before dropping old messages
    pub max_queue_depth: usize,
}

impl QosPolicy {
    /// Best-effort policy (fire and forget, no ordering)
    pub fn best_effort() -> Self {
        Self {
            delivery: DeliveryGuarantee::AtMostOnce,
            ordering: OrderingGuarantee::Unordered,
            ttl_ms: 5_000,
            max_retries: 0,
            retry_backoff_ms: 0,
            persistent: false,
            max_queue_depth: 1024,
        }
    }

    /// Reliable policy (at-least-once, per-source ordering)
    pub fn reliable() -> Self {
        Self {
            delivery: DeliveryGuarantee::AtLeastOnce,
            ordering: OrderingGuarantee::PerSource,
            ttl_ms: 30_000,
            max_retries: 3,
            retry_backoff_ms: 100,
            persistent: false,
            max_queue_depth: 4096,
        }
    }

    /// Exactly-once policy (for critical operations)
    pub fn exactly_once() -> Self {
        Self {
            delivery: DeliveryGuarantee::ExactlyOnce,
            ordering: OrderingGuarantee::GlobalOrder,
            ttl_ms: 0, // never expires
            max_retries: 10,
            retry_backoff_ms: 500,
            persistent: true,
            max_queue_depth: 256,
        }
    }

    /// Real-time policy (low TTL, no retries)
    pub fn real_time() -> Self {
        Self {
            delivery: DeliveryGuarantee::AtMostOnce,
            ordering: OrderingGuarantee::PerSource,
            ttl_ms: 100,
            max_retries: 0,
            retry_backoff_ms: 0,
            persistent: false,
            max_queue_depth: 64,
        }
    }

    /// Security policy (exactly-once, persistent, never expires)
    pub fn security() -> Self {
        Self {
            delivery: DeliveryGuarantee::ExactlyOnce,
            ordering: OrderingGuarantee::GlobalOrder,
            ttl_ms: 0,
            max_retries: 5,
            retry_backoff_ms: 200,
            persistent: true,
            max_queue_depth: 512,
        }
    }
}

impl Default for QosPolicy {
    fn default() -> Self {
        Self::best_effort()
    }
}

/// Retry state for a message
#[derive(Debug, Clone)]
pub struct RetryState {
    pub attempt: u32,
    pub max_retries: u32,
    pub next_retry_ms: u64,
    pub backoff_ms: u64,
}

impl RetryState {
    /// Create a new retry state from a QoS policy
    pub fn new(policy: &QosPolicy) -> Self {
        Self {
            attempt: 0,
            max_retries: policy.max_retries,
            next_retry_ms: policy.retry_backoff_ms,
            backoff_ms: policy.retry_backoff_ms,
        }
    }

    /// Whether another retry is allowed
    pub fn can_retry(&self) -> bool {
        self.attempt < self.max_retries
    }

    /// Advance to the next retry (exponential backoff)
    pub fn advance(&mut self) {
        self.attempt += 1;
        self.next_retry_ms = self.backoff_ms * (1 << self.attempt.min(10));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn retry_state_backoff() {
        let policy = QosPolicy::reliable();
        let mut state = RetryState::new(&policy);
        assert!(state.can_retry());
        state.advance();
        assert_eq!(state.attempt, 1);
        assert!(state.next_retry_ms > policy.retry_backoff_ms);
    }

    #[test]
    fn retry_exhaustion() {
        let policy = QosPolicy {
            max_retries: 2,
            ..QosPolicy::reliable()
        };
        let mut state = RetryState::new(&policy);
        state.advance();
        state.advance();
        assert!(!state.can_retry());
    }

    #[test]
    fn qos_policies_distinct() {
        let be = QosPolicy::best_effort();
        let rt = QosPolicy::real_time();
        assert!(rt.ttl_ms < be.ttl_ms);
        assert_eq!(be.delivery, DeliveryGuarantee::AtMostOnce);
    }
}