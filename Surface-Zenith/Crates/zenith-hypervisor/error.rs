//! # ZHL Error Types

use thiserror::Error;

/// All errors from the Zenith Hypervisor Layer
#[derive(Debug, Error, Clone)]
pub enum ZhlError {
    #[error("container not found: {id}")]
    ContainerNotFound { id: String },

    #[error("primary container already exists for domain: {domain}")]
    PrimaryContainerExists { domain: String },

    #[error("domain not available: {domain}")]
    DomainNotAvailable { domain: String },

    #[error("container at capacity: {id}")]
    ContainerAtCapacity { id: String },

    #[error("invalid state transition: {from} → {to}")]
    InvalidStateTransition { from: String, to: String },

    #[error("vCPU {index} already initialized")]
    VCpuAlreadyInitialized { index: u32 },

    #[error("vCPU {index} not running")]
    VCpuNotRunning { index: u32 },

    #[error("invalid vCPU {index} state: {state}")]
    InvalidVCpuState { index: u32, state: String },

    #[error("snapshot index mismatch: expected {expected}, got {got}")]
    SnapshotIndexMismatch { expected: u32, got: u32 },

    #[error("migration queue full")]
    MigrationQueueFull,

    #[error("migration failed: {reason}")]
    MigrationFailed { reason: String },

    #[error("recovery failed: {reason}")]
    RecoveryFailed { reason: String },

    #[error("quota exceeded: {resource} for container {id}")]
    QuotaExceeded { id: String, resource: String },

    #[error("memory allocation failed: requested {bytes} bytes")]
    MemoryAllocationFailed { bytes: u64 },

    #[error("isolation violation: domain {from} attempted to access {to}")]
    IsolationViolation { from: String, to: String },

    #[error("snapshot failed: {reason}")]
    SnapshotFailed { reason: String },

    #[error("hardware resource unavailable: {resource}")]
    HardwareUnavailable { resource: String },

    #[error("internal hypervisor error: {message}")]
    Internal { message: String },
}

impl ZhlError {
    /// Whether this error is recoverable
    pub fn is_recoverable(&self) -> bool {
        matches!(
            self,
            ZhlError::ContainerAtCapacity { .. }
                | ZhlError::MigrationQueueFull
                | ZhlError::HardwareUnavailable { .. }
        )
    }
}