//! # ZIB Error Types

use thiserror::Error;

/// All errors that can occur in the Zenith Interdomain Bus
#[derive(Debug, Error, Clone)]
pub enum ZibError {
    #[error("bus unavailable")]
    BusUnavailable,

    #[error("receiver disconnected")]
    ReceiverDisconnected,

    #[error("no subscribers for topic: {topic}")]
    NoSubscribers { topic: String },

    #[error("payload empty")]
    PayloadEmpty,

    #[error("payload too large: {size} bytes (max {max})")]
    PayloadTooLarge { size: usize, max: usize },

    #[error("payload invalid: {reason}")]
    PayloadInvalid { reason: String },

    #[error("message expired (age: {age_ms}ms, ttl: {ttl_ms}ms)")]
    MessageExpired { age_ms: i64, ttl_ms: u64 },

    #[error("topic missing from message")]
    MissingTopic,

    #[error("protocol version mismatch: expected {expected}, got {got}")]
    ProtocolVersionMismatch { expected: u8, got: u8 },

    #[error("serialization failed: {reason}")]
    SerializationFailed { reason: String },

    #[error("deserialization failed: {reason}")]
    DeserializationFailed { reason: String },

    #[error("capability required for topic: {topic}")]
    CapabilityRequired { topic: String },

    #[error("system-only topic: {topic}")]
    SystemOnlyTopic { topic: String },

    #[error("subscription limit reached for topic: {topic}")]
    SubscriptionLimitReached { topic: String },

    #[error("filter rejected message")]
    FilterRejected,

    #[error("codec error: {reason}")]
    CodecError { reason: String },

    #[error("channel send error")]
    ChannelSendError,

    #[error("channel receive error")]
    ChannelReceiveError,

    #[error("timeout after {ms}ms")]
    Timeout { ms: u64 },
}

impl ZibError {
    /// Whether this error is transient (retry may succeed)
    pub fn is_transient(&self) -> bool {
        matches!(
            self,
            ZibError::BusUnavailable
                | ZibError::Timeout { .. }
                | ZibError::ChannelSendError
                | ZibError::ChannelReceiveError
        )
    }
}