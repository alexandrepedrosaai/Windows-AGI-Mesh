//! # Zenith Error Types

use thiserror::Error;

/// Master error type for all Zenith ABI operations
#[derive(Debug, Error, Clone)]
pub enum ZenithError {
    // Session errors
    #[error("session not found: {id}")]
    SessionNotFound { id: String },
    #[error("session already exists: {id}")]
    SessionAlreadyExists { id: String },
    #[error("session terminated")]
    SessionTerminated,

    // Intent errors
    #[error("intent not found: {id}")]
    IntentNotFound { id: String },
    #[error("intent already completed")]
    IntentAlreadyCompleted,
    #[error("intent scheduling failed: {reason}")]
    IntentSchedulingFailed { reason: String },

    // Task errors
    #[error("task not found: {id}")]
    TaskNotFound { id: String },
    #[error("task migration failed: {reason}")]
    TaskMigrationFailed { reason: String },
    #[error("task checkpoint failed: {reason}")]
    TaskCheckpointFailed { reason: String },
    #[error("task execution failed: code={code}, message={message}")]
    TaskExecutionFailed { code: i32, message: String },

    // Memory errors
    #[error("object not found: {id}")]
    ObjectNotFound { id: String },
    #[error("memory capacity exceeded")]
    MemoryCapacityExceeded,
    #[error("write lock conflict: held by {holder}")]
    WriteLockConflict { holder: String },
    #[error("page boundary exceeded")]
    PageBoundaryExceeded,
    #[error("object not accessible: state={state}")]
    ObjectNotAccessible { state: String },

    // Capability errors
    #[error("capability token invalid")]
    CapabilityInvalid,
    #[error("capability token expired")]
    CapabilityExpired,
    #[error("capability token revoked")]
    CapabilityRevoked,
    #[error("permission denied: resource={resource}, access={access}")]
    PermissionDenied { resource: String, access: String },

    // Domain errors
    #[error("domain not available: {domain}")]
    DomainNotAvailable { domain: String },
    #[error("domain health check failed: {reason}")]
    DomainHealthFailed { reason: String },
    #[error("cross-domain operation denied: {from} → {to}")]
    CrossDomainDenied { from: String, to: String },

    // Device errors
    #[error("device not found: {id}")]
    DeviceNotFound { id: String },
    #[error("device already in use by {owner}")]
    DeviceInUse { owner: String },
    #[error("device unavailable: {reason}")]
    DeviceUnavailable { reason: String },

    // IPC errors
    #[error("IPC bus unavailable")]
    BusUnavailable,
    #[error("IPC receiver disconnected")]
    ReceiverDisconnected,
    #[error("IPC message expired")]
    MessageExpired,
    #[error("IPC payload invalid: {reason}")]
    PayloadInvalid { reason: String },
    #[error("IPC payload empty")]
    PayloadEmpty,

    // Inference errors
    #[error("model not found: {id}")]
    ModelNotFound { id: String },
    #[error("model not loaded")]
    ModelNotLoaded,
    #[error("inference failed: {reason}")]
    InferenceFailed { reason: String },
    #[error("inference hardware unavailable: {hardware}")]
    InferenceHardwareUnavailable { hardware: String },

    // Security errors
    #[error("security violation: {detail}")]
    SecurityViolation { detail: String },
    #[error("container sealed")]
    ContainerSealed,
    #[error("attestation failed")]
    AttestationFailed,
    #[error("quantum key distribution failed")]
    QkdFailed,

    // Serialization errors
    #[error("serialization failed: {reason}")]
    SerializationFailed { reason: String },
    #[error("deserialization failed: {reason}")]
    DeserializationFailed { reason: String },

    // Version errors
    #[error("ABI version mismatch: expected={expected}, got={got}")]
    AbiVersionMismatch { expected: String, got: String },

    // Generic
    #[error("internal error: {message}")]
    Internal { message: String },
    #[error("not implemented: {feature}")]
    NotImplemented { feature: String },
    #[error("timeout after {ms}ms")]
    Timeout { ms: u64 },
    #[error("resource exhausted: {resource}")]
    ResourceExhausted { resource: String },
}

impl ZenithError {
    /// Whether this error is recoverable (retry may succeed)
    pub fn is_recoverable(&self) -> bool {
        matches!(
            self,
            ZenithError::Timeout { .. }
                | ZenithError::ResourceExhausted { .. }
                | ZenithError::BusUnavailable
                | ZenithError::DomainNotAvailable { .. }
                | ZenithError::InferenceHardwareUnavailable { .. }
        )
    }

    /// Whether this error is a security violation
    pub fn is_security_error(&self) -> bool {
        matches!(
            self,
            ZenithError::CapabilityInvalid
                | ZenithError::CapabilityExpired
                | ZenithError::CapabilityRevoked
                | ZenithError::PermissionDenied { .. }
                | ZenithError::CrossDomainDenied { .. }
                | ZenithError::SecurityViolation { .. }
                | ZenithError::AttestationFailed
                | ZenithError::QkdFailed
        )
    }

    /// Error code for kernel-level error reporting
    pub fn error_code(&self) -> i32 {
        match self {
            ZenithError::SessionNotFound { .. }     => -1,
            ZenithError::IntentNotFound { .. }      => -2,
            ZenithError::TaskNotFound { .. }        => -3,
            ZenithError::ObjectNotFound { .. }      => -4,
            ZenithError::CapabilityInvalid          => -10,
            ZenithError::CapabilityExpired          => -11,
            ZenithError::CapabilityRevoked          => -12,
            ZenithError::PermissionDenied { .. }    => -13,
            ZenithError::CrossDomainDenied { .. }   => -14,
            ZenithError::SecurityViolation { .. }   => -15,
            ZenithError::MemoryCapacityExceeded     => -20,
            ZenithError::WriteLockConflict { .. }   => -21,
            ZenithError::DomainNotAvailable { .. }  => -30,
            ZenithError::BusUnavailable             => -40,
            ZenithError::Timeout { .. }             => -50,
            ZenithError::Internal { .. }            => -99,
            _                                       => -1,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn error_codes() {
        assert_eq!(ZenithError::CapabilityInvalid.error_code(), -10);
        assert_eq!(ZenithError::BusUnavailable.error_code(), -40);
        assert!(ZenithError::Timeout { ms: 100 }.is_recoverable());
        assert!(ZenithError::SecurityViolation { detail: "test".into() }.is_security_error());
    }

    #[test]
    fn error_display() {
        let e = ZenithError::PermissionDenied {
            resource: "Camera".into(),
            access: "Write".into(),
        };
        assert!(e.to_string().contains("Camera"));
    }
}