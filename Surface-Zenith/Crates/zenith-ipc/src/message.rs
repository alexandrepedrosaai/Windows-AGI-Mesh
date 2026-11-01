//! # ZIB Message Format
//!
//! Every message on the Zenith Interdomain Bus has a fixed wire format
//! with a typed topic, capability token, QoS metadata, and binary payload.

use serde::{Deserialize, Serialize};
use uuid::Uuid;
use std::time::{SystemTime, UNIX_EPOCH};
use zenith_abi::domain::Domain;
use zenith_abi::types::{ZSessionId, ZMessageId, ZTimestamp};
use crate::topics::Topic;
use crate::qos::QosPolicy;

// ---------------------------------------------------------------------------
// Message priority
// ---------------------------------------------------------------------------

/// Message delivery priority
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
pub enum MessagePriority {
    /// Background (metrics, heartbeats)
    Low    = 0,
    /// Normal application messages
    Normal = 1,
    /// User-visible, interactive
    High   = 2,
    /// System-critical (security, migration)
    Critical = 3,
}

impl MessagePriority {
    /// Derive priority from topic weight
    pub fn from_weight(w: u8) -> Self {
        match w {
            0..=50   => MessagePriority::Low,
            51..=150 => MessagePriority::Normal,
            151..=220=> MessagePriority::High,
            _        => MessagePriority::Critical,
        }
    }
}

// ---------------------------------------------------------------------------
// Message header
// ---------------------------------------------------------------------------

/// Fixed-size message header (serialized first on the wire)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MessageHeader {
    /// ZIB protocol version
    pub protocol_version: u8,
    /// Unique message ID
    pub message_id: ZMessageId,
    /// Session context
    pub session_id: ZSessionId,
    /// Correlation ID (for request/response pairs)
    pub correlation_id: Option<ZMessageId>,
    /// Source domain
    pub source: Domain,
    /// Target domain (None = broadcast to all subscribers)
    pub target: Option<Domain>,
    /// Topic
    pub topic: Topic,
    /// Message priority
    pub priority: MessagePriority,
    /// Time-to-live in milliseconds (0 = never expires)
    pub ttl_ms: u64,
    /// Creation timestamp (microseconds since UNIX epoch)
    pub created_at: ZTimestamp,
    /// Payload size in bytes
    pub payload_size: u32,
    /// Whether the payload is compressed
    pub compressed: bool,
    /// Whether the payload is encrypted
    pub encrypted: bool,
    /// Sequence number within the session
    pub sequence: u64,
}

impl MessageHeader {
    /// Create a new message header
    pub fn new(
        session_id: ZSessionId,
        source: Domain,
        target: Option<Domain>,
        topic: Topic,
        priority: MessagePriority,
        payload_size: u32,
    ) -> Self {
        let ttl_ms = topic.default_ttl_ms();
        Self {
            protocol_version: crate::ZIB_PROTOCOL_VERSION,
            message_id: Uuid::new_v4(),
            session_id,
            correlation_id: None,
            source,
            target,
            topic,
            priority,
            ttl_ms,
            created_at: ZTimestamp(
                SystemTime::now()
                    .duration_since(UNIX_EPOCH)
                    .unwrap_or_default()
                    .as_micros() as i64,
            ),
            payload_size,
            compressed: false,
            encrypted: false,
            sequence: 0,
        }
    }

    /// Check if this message has expired
    pub fn is_expired(&self) -> bool {
        if self.ttl_ms == 0 {
            return false; // never expires
        }
        let now_us = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_micros() as i64;
        let age_ms = (now_us - self.created_at.0) / 1_000;
        age_ms > self.ttl_ms as i64
    }

    /// Age of this message in milliseconds
    pub fn age_ms(&self) -> i64 {
        let now_us = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_micros() as i64;
        (now_us - self.created_at.0) / 1_000
    }
}

// ---------------------------------------------------------------------------
// ZMessage — the full IPC message
// ---------------------------------------------------------------------------

/// A complete ZIB message with header and payload
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ZMessage {
    /// Message header
    pub header: MessageHeader,
    /// Binary payload (topic-specific schema)
    pub payload: Vec<u8>,
    /// Optional capability token bytes (serialized)
    pub capability: Option<Vec<u8>>,
    /// Optional routing tags for filter chains
    pub tags: Vec<String>,
}

impl ZMessage {
    /// Create a new ZMessage
    pub fn new(
        session_id: ZSessionId,
        source: Domain,
        target: Option<Domain>,
        topic: Topic,
        payload: Vec<u8>,
    ) -> Self {
        let priority = MessagePriority::from_weight(topic.priority_weight());
        let header = MessageHeader::new(
            session_id,
            source,
            target,
            topic,
            priority,
            payload.len() as u32,
        );
        Self {
            header,
            payload,
            capability: None,
            tags: Vec::new(),
        }
    }

    /// Create a broadcast message (no specific target domain)
    pub fn broadcast(
        session_id: ZSessionId,
        source: Domain,
        topic: Topic,
        payload: Vec<u8>,
    ) -> Self {
        Self::new(session_id, source, None, topic, payload)
    }

    /// Create a directed message to a specific domain
    pub fn directed(
        session_id: ZSessionId,
        source: Domain,
        target: Domain,
        topic: Topic,
        payload: Vec<u8>,
    ) -> Self {
        Self::new(session_id, source, Some(target), topic, payload)
    }

    /// Set correlation ID (for request/response pairing)
    pub fn with_correlation(mut self, id: ZMessageId) -> Self {
        self.header.correlation_id = Some(id);
        self
    }

    /// Set sequence number
    pub fn with_sequence(mut self, seq: u64) -> Self {
        self.header.sequence = seq;
        self
    }

    /// Add a routing tag
    pub fn tag(mut self, tag: impl Into<String>) -> Self {
        self.tags.push(tag.into());
        self
    }

    /// Mark payload as compressed
    pub fn compressed(mut self) -> Self {
        self.header.compressed = true;
        self
    }

    /// Mark payload as encrypted
    pub fn encrypted(mut self) -> Self {
        self.header.encrypted = true;
        self
    }

    /// Whether this message has expired
    pub fn is_expired(&self) -> bool {
        self.header.is_expired()
    }

    /// Message ID
    pub fn id(&self) -> ZMessageId {
        self.header.message_id
    }

    /// Topic
    pub fn topic(&self) -> &Topic {
        &self.header.topic
    }

    /// Source domain
    pub fn source(&self) -> &Domain {
        &self.header.source
    }

    /// Target domain (None = broadcast)
    pub fn target(&self) -> Option<&Domain> {
        self.header.target.as_ref()
    }

    /// Payload size in bytes
    pub fn payload_size(&self) -> usize {
        self.payload.len()
    }

    /// Validate basic message constraints
    pub fn validate(&self) -> Result<(), crate::error::ZibError> {
        if self.payload.is_empty() {
            return Err(crate::error::ZibError::PayloadEmpty);
        }
        if self.payload.len() > crate::MAX_PAYLOAD_BYTES {
            return Err(crate::error::ZibError::PayloadTooLarge {
                size: self.payload.len(),
                max: crate::MAX_PAYLOAD_BYTES,
            });
        }
        if self.header.protocol_version != crate::ZIB_PROTOCOL_VERSION {
            return Err(crate::error::ZibError::ProtocolVersionMismatch {
                expected: crate::ZIB_PROTOCOL_VERSION,
                got: self.header.protocol_version,
            });
        }
        Ok(())
    }
}

// ---------------------------------------------------------------------------
// Message builder
// ---------------------------------------------------------------------------

/// Fluent builder for ZMessage
pub struct MessageBuilder {
    session_id: ZSessionId,
    source: Domain,
    target: Option<Domain>,
    topic: Option<Topic>,
    payload: Vec<u8>,
    tags: Vec<String>,
    correlation_id: Option<ZMessageId>,
    sequence: u64,
}

impl MessageBuilder {
    /// Start building a message
    pub fn new(session_id: ZSessionId, source: Domain) -> Self {
        Self {
            session_id,
            source,
            target: None,
            topic: None,
            payload: Vec::new(),
            tags: Vec::new(),
            correlation_id: None,
            sequence: 0,
        }
    }

    /// Set the target domain
    pub fn to(mut self, domain: Domain) -> Self {
        self.target = Some(domain);
        self
    }

    /// Set the topic
    pub fn topic(mut self, topic: Topic) -> Self {
        self.topic = Some(topic);
        self
    }

    /// Set the payload
    pub fn payload(mut self, payload: Vec<u8>) -> Self {
        self.payload = payload;
        self
    }

    /// Set JSON payload from a serializable value
    pub fn json_payload<T: serde::Serialize>(mut self, value: &T) -> Self {
        self.payload = serde_json::to_vec(value).unwrap_or_default();
        self
    }

    /// Add a tag
    pub fn tag(mut self, tag: impl Into<String>) -> Self {
        self.tags.push(tag.into());
        self
    }

    /// Set correlation ID
    pub fn correlate(mut self, id: ZMessageId) -> Self {
        self.correlation_id = Some(id);
        self
    }

    /// Set sequence number
    pub fn sequence(mut self, seq: u64) -> Self {
        self.sequence = seq;
        self
    }

    /// Build the message
    pub fn build(self) -> Result<ZMessage, crate::error::ZibError> {
        let topic = self.topic.ok_or(crate::error::ZibError::MissingTopic)?;
        let mut msg = ZMessage::new(
            self.session_id,
            self.source,
            self.target,
            topic,
            self.payload,
        );
        msg.tags = self.tags;
        if let Some(cid) = self.correlation_id {
            msg.header.correlation_id = Some(cid);
        }
        msg.header.sequence = self.sequence;
        msg.validate()?;
        Ok(msg)
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    fn make_msg() -> ZMessage {
        ZMessage::new(
            Uuid::new_v4(),
            Domain::Android,
            Some(Domain::Windows),
            Topic::IntentSubmit,
            b"test-payload".to_vec(),
        )
    }

    #[test]
    fn message_creation() {
        let msg = make_msg();
        assert_eq!(msg.source(), &Domain::Android);
        assert_eq!(msg.target(), Some(&Domain::Windows));
        assert_eq!(msg.topic(), &Topic::IntentSubmit);
        assert!(!msg.is_expired());
    }

    #[test]
    fn message_validation_empty_payload() {
        let msg = ZMessage::new(
            Uuid::new_v4(), Domain::AI, None,
            Topic::Heartbeat, vec![],
        );
        assert!(matches!(msg.validate(), Err(crate::error::ZibError::PayloadEmpty)));
    }

    #[test]
    fn message_builder() {
        let session = Uuid::new_v4();
        let msg = MessageBuilder::new(session, Domain::Windows)
            .to(Domain::AI)
            .topic(Topic::InferenceRequest)
            .payload(b"inference-data".to_vec())
            .tag("high-priority")
            .sequence(42)
            .build()
            .unwrap();

        assert_eq!(msg.header.sequence, 42);
        assert_eq!(msg.tags, vec!["high-priority"]);
        assert_eq!(msg.target(), Some(&Domain::AI));
    }

    #[test]
    fn broadcast_message() {
        let msg = ZMessage::broadcast(
            Uuid::new_v4(), Domain::AI,
            Topic::DomainHealth, b"healthy".to_vec(),
        );
        assert!(msg.target().is_none());
    }

    #[test]
    fn message_priority_from_topic() {
        let security_msg = ZMessage::new(
            Uuid::new_v4(), Domain::Windows, None,
            Topic::SecurityViolation, b"violation".to_vec(),
        );
        assert_eq!(security_msg.header.priority, MessagePriority::Critical);

        let heartbeat_msg = ZMessage::new(
            Uuid::new_v4(), Domain::Windows, None,
            Topic::Heartbeat, b"beat".to_vec(),
        );
        assert_eq!(heartbeat_msg.header.priority, MessagePriority::Low);
    }
}