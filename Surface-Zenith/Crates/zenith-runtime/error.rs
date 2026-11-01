//! # Runtime Errors

use thiserror::Error;

/// All errors from the Zenith domain runtimes
#[derive(Debug, Error, Clone)]
pub enum RuntimeError {
    #[error("app not found: {package}")]
    AppNotFound { package: String },

    #[error("process not found: PID {pid}")]
    ProcessNotFound { pid: u32 },

    #[error("qubit limit exceeded: requested {requested}, available {available}")]
    QubitLimitExceeded { requested: u32, available: u32 },

    #[error("audio stream not found: {id}")]
    AudioStreamNotFound { id: String },

    #[error("cloud service unavailable: {service}")]
    CloudServiceUnavailable { service: String },

    #[error("sync failed: {reason}")]
    SyncFailed { reason: String },

    #[error("task execution failed: {reason}")]
    TaskFailed { reason: String },

    #[error("domain not initialized")]
    NotInitialized,

    #[error("capability denied: {operation}")]
    CapabilityDenied { operation: String },

    #[error("resource limit exceeded: {resource}")]
    ResourceLimitExceeded { resource: String },

    #[error("IPC error: {reason}")]
    IpcError { reason: String },

    #[error("timeout after {ms}ms")]
    Timeout { ms: u64 },

    #[error("internal runtime error: {message}")]
    Internal { message: String },
}

impl RuntimeError {
    pub fn is_recoverable(&self) -> bool {
        matches!(
            self,
            RuntimeError::Timeout { .. }
                | RuntimeError::CloudServiceUnavailable { .. }
                | RuntimeError::ResourceLimitExceeded { .. }
        )
    }
}