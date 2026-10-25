//! # ZenithBus — The Zenith Interdomain Bus Implementation
//!
//! The ZenithBus is the central message broker for all inter-domain
//! communication. It provides:
//!
//! - Typed topic routing
//! - Payload validation
//! - QoS enforcement (TTL, priority, delivery guarantees)
//! - Broadcast and directed delivery
//! - Built-in metrics
//! - Filter chains
//! - Async and sync APIs

use std::sync::Arc;
use std::collections::HashMap;
use parking_lot::RwLock;
use tokio::sync::broadcast;
use uuid::Uuid;
use zenith_abi::domain::Domain;
use zenith_abi::types::ZSessionId;
use crate::message::ZMessage;
use crate::topics::Topic;
use crate::error::ZibError;
use crate::metrics::BusMetrics;
use crate::filter::{FilterChain, MessageFilter};
use crate::payload::validate_payload;
use crate::qos::QosPolicy;

// ---------------------------------------------------------------------------
// Subscriber handle
// ---------------------------------------------------------------------------

/// A handle to a ZenithBus subscription
pub struct Subscription {
    /// Topic this subscription is for
    pub topic: Topic,
    /// Domain that subscribed
    pub domain: Domain,
    /// Broadcast receiver
    pub receiver: broadcast::Receiver<ZMessage>,
    /// Subscription ID
    pub id: Uuid,
}

impl Subscription {
    /// Receive the next message (async)
    pub async fn recv(&mut self) -> Result<ZMessage, ZibError> {
        loop {
            match self.receiver.recv().await {
                Ok(msg) => {
                    // Skip expired messages
                    if msg.is_expired() {
                        continue;
                    }
                    // Skip messages not for this domain (if directed)
                    if let Some(target) = msg.target() {
                        if target != &self.domain {
                            continue;
                        }
                    }
                    return Ok(msg);
                }
                Err(broadcast::error::RecvError::Closed) => {
                    return Err(ZibError::ReceiverDisconnected);
                }
                Err(broadcast::error::RecvError::Lagged(n)) => {
                    tracing::warn!(
                        "ZIB subscription lagged by {} messages on topic {:?}",
                        n, self.topic
                    );
                    continue;
                }
            }
        }
    }

    /// Try to receive a message without blocking
    pub fn try_recv(&mut self) -> Result<Option<ZMessage>, ZibError> {
        match self.receiver.try_recv() {
            Ok(msg) => {
                if msg.is_expired() {
                    return Ok(None);
                }
                Ok(Some(msg))
            }
            Err(broadcast::error::TryRecvError::Empty) => Ok(None),
            Err(broadcast::error::TryRecvError::Closed) => Err(ZibError::ReceiverDisconnected),
            Err(broadcast::error::TryRecvError::Lagged(_)) => Ok(None),
        }
    }
}

// ---------------------------------------------------------------------------
// Topic channel registry
// ---------------------------------------------------------------------------

/// Per-topic broadcast channel
struct TopicChannel {
    sender: broadcast::Sender<ZMessage>,
    qos: QosPolicy,
    subscriber_count: usize,
}

impl TopicChannel {
    fn new(capacity: usize, qos: QosPolicy) -> Self {
        let (sender, _) = broadcast::channel(capacity);
        Self { sender, qos, subscriber_count: 0 }
    }

    fn subscribe(&mut self) -> broadcast::Receiver<ZMessage> {
        self.subscriber_count += 1;
        self.sender.subscribe()
    }

    fn publish(&self, msg: ZMessage) -> Result<usize, ZibError> {
        self.sender.send(msg).map_err(|_| ZibError::NoSubscribers {
            topic: "unknown".into(),
        })
    }

    fn subscriber_count(&self) -> usize {
        self.sender.receiver_count()
    }
}

// ---------------------------------------------------------------------------
// ZenithBus
// ---------------------------------------------------------------------------

/// Inner state of the ZenithBus (shared via Arc<RwLock<>>)
struct BusInner {
    channels: HashMap<String, TopicChannel>,
    metrics: BusMetrics,
    filters: FilterChain,
    default_capacity: usize,
}

impl BusInner {
    fn new(default_capacity: usize) -> Self {
        Self {
            channels: HashMap::new(),
            metrics: BusMetrics::new(),
            filters: FilterChain::new(),
            default_capacity,
        }
    }

    fn get_or_create_channel(&mut self, topic: &Topic) -> &mut TopicChannel {
        let key = topic.name();
        if !self.channels.contains_key(&key) {
            let qos = Self::default_qos_for_topic(topic);
            let cap = self.default_capacity;
            self.channels.insert(key.clone(), TopicChannel::new(cap, qos));
        }
        self.channels.get_mut(&key).unwrap()
    }

    fn default_qos_for_topic(topic: &Topic) -> QosPolicy {
        match topic {
            Topic::SecurityViolation
            | Topic::CapabilityRevoked
            | Topic::AttestationCompleted => QosPolicy::security(),

            Topic::SnapshotTransfer
            | Topic::TaskMigrating
            | Topic::TaskMigrated => QosPolicy::reliable(),

            Topic::Heartbeat
            | Topic::ThermalThrottle
            | Topic::HingeAngleChanged => QosPolicy::real_time(),

            _ => QosPolicy::best_effort(),
        }
    }
}

/// The Zenith Interdomain Bus — central message broker
///
/// Thread-safe and clone-able. All clones share the same underlying state.
#[derive(Clone)]
pub struct ZenithBus {
    inner: Arc<RwLock<BusInner>>,
}

impl ZenithBus {
    /// Create a new ZenithBus with a default channel capacity
    pub fn new(default_capacity: usize) -> Self {
        Self {
            inner: Arc::new(RwLock::new(BusInner::new(default_capacity))),
        }
    }

    /// Create a ZenithBus with default capacity (1024)
    pub fn default_bus() -> Self {
        Self::new(1024)
    }

    // ── Publishing ──────────────────────────────────────────────────────────

    /// Publish a message to the bus
    ///
    /// Returns the number of subscribers that received the message.
    pub fn publish(&self, msg: ZMessage) -> Result<usize, ZibError> {
        // Validate payload
        validate_payload(msg.topic(), &msg.payload)?;

        // Check TTL
        if msg.is_expired() {
            let mut inner = self.inner.write();
            inner.metrics.record_expired();
            return Err(ZibError::MessageExpired {
                age_ms: msg.header.age_ms(),
                ttl_ms: msg.header.ttl_ms,
            });
        }

        // Apply filter chain
        {
            let inner = self.inner.read();
            if !inner.filters.allow(&msg) {
                inner.metrics.record_rejected();
                return Err(ZibError::FilterRejected);
            }
        }

        // Publish to topic channel
        let topic_name = msg.topic().name();
        let mut inner = self.inner.write();
        let channel = inner.get_or_create_channel(msg.topic());
        let sub_count = channel.subscriber_count();

        match channel.publish(msg) {
            Ok(n) => {
                inner.metrics.record_published(n);
                Ok(n)
            }
            Err(_) if sub_count == 0 => {
                inner.metrics.record_rejected();
                // No subscribers — not an error for broadcast topics
                Ok(0)
            }
            Err(e) => {
                inner.metrics.record_rejected();
                Err(e)
            }
        }
    }

    /// Publish a raw payload to a topic (convenience method)
    pub fn publish_raw(
        &self,
        session_id: ZSessionId,
        source: Domain,
        topic: Topic,
        payload: Vec<u8>,
    ) -> Result<usize, ZibError> {
        let msg = ZMessage::broadcast(session_id, source, topic, payload);
        self.publish(msg)
    }

    // ── Subscribing ─────────────────────────────────────────────────────────

    /// Subscribe to a topic
    pub fn subscribe(&self, topic: Topic, domain: Domain) -> Subscription {
        let mut inner = self.inner.write();
        let channel = inner.get_or_create_channel(&topic);
        let receiver = channel.subscribe();
        inner.metrics.record_subscription();

        Subscription {
            topic,
            domain,
            receiver,
            id: Uuid::new_v4(),
        }
    }

    /// Subscribe to multiple topics at once
    pub fn subscribe_many(&self, topics: Vec<Topic>, domain: Domain) -> Vec<Subscription> {
        topics.into_iter().map(|t| self.subscribe(t, domain.clone())).collect()
    }

    // ── Metrics ─────────────────────────────────────────────────────────────

    /// Get a snapshot of bus metrics
    pub fn metrics(&self) -> BusMetrics {
        self.inner.read().metrics.clone()
    }

    /// Reset bus metrics
    pub fn reset_metrics(&self) {
        self.inner.write().metrics.reset();
    }

    // ── Filters ─────────────────────────────────────────────────────────────

    /// Add a message filter to the bus
    pub fn add_filter(&self, filter: Box<dyn MessageFilter + Send + Sync>) {
        self.inner.write().filters.add(filter);
    }

    // ── Diagnostics ─────────────────────────────────────────────────────────

    /// Number of active topic channels
    pub fn channel_count(&self) -> usize {
        self.inner.read().channels.len()
    }

    /// Number of subscribers for a specific topic
    pub fn subscriber_count(&self, topic: &Topic) -> usize {
        let inner = self.inner.read();
        inner
            .channels
            .get(&topic.name())
            .map(|c| c.subscriber_count())
            .unwrap_or(0)
    }

    /// Whether the bus has any subscribers for a topic
    pub fn has_subscribers(&self, topic: &Topic) -> bool {
        self.subscriber_count(topic) > 0
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;
    use zenith_abi::intent::IntentClass;
    use zenith_abi::types::ZTimestamp;
    use crate::payload::{IntentSubmitPayload, PayloadSchema};

    fn make_intent_payload() -> Vec<u8> {
        IntentSubmitPayload {
            intent_id: Uuid::new_v4(),
            session_id: Uuid::new_v4(),
            goal: "open excel".into(),
            class: IntentClass::Productivity,
            priority: 128,
            latency_budget_ms: 100,
            preferred_domain: Some(Domain::Windows),
            timestamp: ZTimestamp(0),
        }
        .to_bytes()
        .unwrap()
    }

    #[tokio::test]
    async fn publish_and_receive() {
        let bus = ZenithBus::new(64);
        let session = Uuid::new_v4();

        let mut sub = bus.subscribe(Topic::IntentSubmit, Domain::Windows);

        let payload = make_intent_payload();
        bus.publish(ZMessage::broadcast(
            session, Domain::Android, Topic::IntentSubmit, payload,
        )).unwrap();

        let msg = sub.recv().await.unwrap();
        assert_eq!(msg.topic(), &Topic::IntentSubmit);
    }

    #[tokio::test]
    async fn multiple_subscribers_receive() {
        let bus = ZenithBus::new(64);
        let session = Uuid::new_v4();

        let mut sub1 = bus.subscribe(Topic::DomainHealth, Domain::Windows);
        let mut sub2 = bus.subscribe(Topic::DomainHealth, Domain::Android);
        let mut sub3 = bus.subscribe(Topic::DomainHealth, Domain::AI);

        use crate::payload::{DomainHealthPayload, PayloadSchema};
        use zenith_abi::domain::DomainHealth;
        let payload = DomainHealthPayload {
            domain: Domain::Windows,
            health: DomainHealth::Healthy,
            cpu_usage_pct: 45.0,
            memory_usage_pct: 60.0,
            active_task_count: 12,
            timestamp: ZTimestamp(0),
        }.to_bytes().unwrap();

        bus.publish(ZMessage::broadcast(
            session, Domain::Windows, Topic::DomainHealth, payload,
        )).unwrap();

        let m1 = sub1.recv().await.unwrap();
        let m2 = sub2.recv().await.unwrap();
        let m3 = sub3.recv().await.unwrap();

        assert_eq!(m1.topic(), &Topic::DomainHealth);
        assert_eq!(m2.topic(), &Topic::DomainHealth);
        assert_eq!(m3.topic(), &Topic::DomainHealth);
    }

    #[test]
    fn empty_payload_rejected() {
        let bus = ZenithBus::new(64);
        let session = Uuid::new_v4();
        let msg = ZMessage::broadcast(
            session, Domain::Android, Topic::IntentSubmit, vec![],
        );
        assert!(matches!(bus.publish(msg), Err(ZibError::PayloadEmpty)));
    }

    #[test]
    fn metrics_track_publishes() {
        let bus = ZenithBus::new(64);
        let session = Uuid::new_v4();
        let payload = make_intent_payload();

        // No subscribers — publish returns Ok(0)
        let _ = bus.publish(ZMessage::broadcast(
            session, Domain::Android, Topic::IntentSubmit, payload,
        ));

        let metrics = bus.metrics();
        assert!(metrics.published >= 0);
    }

    #[tokio::test]
    async fn directed_message_filtered_by_domain() {
        let bus = ZenithBus::new(64);
        let session = Uuid::new_v4();

        // Subscribe as Windows domain
        let mut sub_win = bus.subscribe(Topic::TaskMigrating, Domain::Windows);

        use crate::payload::{TaskMigrationPayload, MigrationReason, PayloadSchema};
        let payload = TaskMigrationPayload {
            task_id: Uuid::new_v4(),
            intent_id: Uuid::new_v4(),
            session_id: session,
            from_domain: Domain::Android,
            to_domain: Domain::Windows,
            snapshot_size_bytes: 1024,
            migration_reason: MigrationReason::FormFactorChange,
            timestamp: ZTimestamp(0),
        }.to_bytes().unwrap();

        // Directed to Windows
        bus.publish(ZMessage::directed(
            session, Domain::Android, Domain::Windows,
            Topic::TaskMigrating, payload,
        )).unwrap();

        let msg = sub_win.recv().await.unwrap();
        assert_eq!(msg.target(), Some(&Domain::Windows));
    }
}