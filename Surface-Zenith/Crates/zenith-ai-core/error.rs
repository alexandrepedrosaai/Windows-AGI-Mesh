//! # AI Core Errors

use thiserror::Error;

/// All errors from the Zenith AI Core
#[derive(Debug, Error, Clone)]
pub enum AiCoreError {
    #[error("model not found: {id}")]
    ModelNotFound { id: String },

    #[error("model not loaded: {name}")]
    ModelNotLoaded { name: String },

    #[error("inference failed: {reason}")]
    InferenceFailed { reason: String },

    #[error("queue full: depth={depth}, max={max}")]
    QueueFull { depth: usize, max: usize },

    #[error("session not found: {id}")]
    SessionNotFound { id: String },

    #[error("context window exceeded: {tokens} > {max}")]
    ContextWindowExceeded { tokens: usize, max: usize },

    #[error("hardware unavailable: {hardware}")]
    HardwareUnavailable { hardware: String },

    #[error("safety filter blocked: {reason}")]
    SafetyBlocked { reason: String },

    #[error("tokenization failed: {reason}")]
    TokenizationFailed { reason: String },

    #[error("embedding failed: {reason}")]
    EmbeddingFailed { reason: String },

    #[error("RAG retrieval failed: {reason}")]
    RagFailed { reason: String },

    #[error("streaming error: {reason}")]
    StreamingError { reason: String },

    #[error("quantization failed: {reason}")]
    QuantizationFailed { reason: String },

    #[error("pipeline stage failed: {stage}: {reason}")]
    PipelineFailed { stage: String, reason: String },

    #[error("timeout after {ms}ms")]
    Timeout { ms: u64 },

    #[error("internal AI core error: {message}")]
    Internal { message: String },
}

impl AiCoreError {
    pub fn is_recoverable(&self) -> bool {
        matches!(
            self,
            AiCoreError::QueueFull { .. }
                | AiCoreError::HardwareUnavailable { .. }
                | AiCoreError::Timeout { .. }
        )
    }
}