//! # ZIB Topic Registry
//!
//! All IPC topics are strongly typed. No raw strings are used for routing.
//! Each topic has an associated payload schema and QoS policy.

use serde::{Deserialize, Serialize};

/// All valid topics on the Zenith Interdomain Bus
///
/// Topics are the primary routing key for all ZIB messages.
/// Adding a new topic requires updating this enum AND the payload schema.
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum Topic {
    // ── Session lifecycle ──────────────────────────────────────────────────
    /// Session opened or resumed
    SessionOpened,
    /// Session suspended
    SessionSuspended,
    /// Session resumed from suspension
    SessionResumed,
    /// Session terminated
    SessionTerminated,
    /// Session migrating to another device
    SessionMigrating,
    /// Session state synchronized across domains
    SessionSync,

    // ── Intent lifecycle ───────────────────────────────────────────────────
    /// New intent submitted to the scheduler
    IntentSubmit,
    /// Intent has been classified and planned
    IntentPlanned,
    /// Intent assigned to a domain
    IntentAssigned,
    /// Intent completed successfully
    IntentComplete,
    /// Intent failed
    IntentFailed,
    /// Intent cancelled
    IntentCancelled,

    // ── Task lifecycle ─────────────────────────────────────────────────────
    /// Task started executing
    TaskStarted,
    /// Task completed
    TaskCompleted,
    /// Task failed
    TaskFailed,
    /// Task preempted
    TaskPreempted,
    /// Task checkpointed
    TaskCheckpointed,
    /// Task migrating between domains
    TaskMigrating,
    /// Task migration completed
    TaskMigrated,

    // ── Memory fabric ──────────────────────────────────────────────────────
    /// Universal Memory Object created
    MemoryObjectCreated,
    /// UMO pages updated (dirty pages available)
    MemoryUpdate,
    /// UMO write lock acquired
    MemoryLockAcquired,
    /// UMO write lock released
    MemoryLockReleased,
    /// UMO deleted
    MemoryObjectDeleted,
    /// Snapshot ready for transfer
    SnapshotReady,
    /// Snapshot transfer in progress
    SnapshotTransfer,
    /// Snapshot restored
    SnapshotRestored,

    // ── Domain lifecycle ───────────────────────────────────────────────────
    /// Domain runtime started
    DomainStarted,
    /// Domain runtime stopped
    DomainStopped,
    /// Domain health status update
    DomainHealth,
    /// Domain migration request
    DomainMigrate,
    /// Domain form factor changed (fold/unfold)
    DomainFormFactorChanged,

    // ── Device events ──────────────────────────────────────────────────────
    /// Device acquired by a domain
    DeviceAcquired,
    /// Device released
    DeviceReleased,
    /// Device state changed
    DeviceStateChanged,
    /// Hinge angle changed (fold/unfold event)
    HingeAngleChanged,

    // ── AI / Inference ─────────────────────────────────────────────────────
    /// Inference request submitted
    InferenceRequest,
    /// Inference result ready
    InferenceResult,
    /// Model loaded into memory
    ModelLoaded,
    /// Model unloaded from memory
    ModelUnloaded,
    /// Copilot intent classified
    CopilotIntentClassified,

    // ── Security ───────────────────────────────────────────────────────────
    /// Capability token issued
    CapabilityIssued,
    /// Capability token revoked
    CapabilityRevoked,
    /// Security violation detected
    SecurityViolation,
    /// Attestation completed
    AttestationCompleted,
    /// QKD session established
    QkdSessionEstablished,

    // ── Quantum ────────────────────────────────────────────────────────────
    /// Quantum circuit submitted
    QuantumCircuitSubmit,
    /// Quantum circuit result ready
    QuantumCircuitResult,
    /// QPU state update
    QpuStateUpdate,

    // ── System ─────────────────────────────────────────────────────────────
    /// System heartbeat (1 Hz)
    Heartbeat,
    /// Power state changed
    PowerStateChanged,
    /// Thermal throttling event
    ThermalThrottle,
    /// Runtime started
    RuntimeStart,
    /// Runtime stopped
    RuntimeStop,
    /// Metrics snapshot
    MetricsSnapshot,

    // ── Custom / Extension ─────────────────────────────────────────────────
    /// Custom topic for domain-specific extensions
    Custom(String),
}

impl Topic {
    /// Human-readable topic name (used for logging and debugging)
    pub fn name(&self) -> String {
        match self {
            Topic::SessionOpened           => "session.opened".into(),
            Topic::SessionSuspended        => "session.suspended".into(),
            Topic::SessionResumed          => "session.resumed".into(),
            Topic::SessionTerminated       => "session.terminated".into(),
            Topic::SessionMigrating        => "session.migrating".into(),
            Topic::SessionSync             => "session.sync".into(),
            Topic::IntentSubmit            => "intent.submit".into(),
            Topic::IntentPlanned           => "intent.planned".into(),
            Topic::IntentAssigned          => "intent.assigned".into(),
            Topic::IntentComplete          => "intent.complete".into(),
            Topic::IntentFailed            => "intent.failed".into(),
            Topic::IntentCancelled         => "intent.cancelled".into(),
            Topic::TaskStarted             => "task.started".into(),
            Topic::TaskCompleted           => "task.completed".into(),
            Topic::TaskFailed              => "task.failed".into(),
            Topic::TaskPreempted           => "task.preempted".into(),
            Topic::TaskCheckpointed        => "task.checkpointed".into(),
            Topic::TaskMigrating           => "task.migrating".into(),
            Topic::TaskMigrated            => "task.migrated".into(),
            Topic::MemoryObjectCreated     => "memory.object.created".into(),
            Topic::MemoryUpdate            => "memory.update".into(),
            Topic::MemoryLockAcquired      => "memory.lock.acquired".into(),
            Topic::MemoryLockReleased      => "memory.lock.released".into(),
            Topic::MemoryObjectDeleted     => "memory.object.deleted".into(),
            Topic::SnapshotReady           => "snapshot.ready".into(),
            Topic::SnapshotTransfer        => "snapshot.transfer".into(),
            Topic::SnapshotRestored        => "snapshot.restored".into(),
            Topic::DomainStarted           => "domain.started".into(),
            Topic::DomainStopped           => "domain.stopped".into(),
            Topic::DomainHealth            => "domain.health".into(),
            Topic::DomainMigrate           => "domain.migrate".into(),
            Topic::DomainFormFactorChanged => "domain.formfactor.changed".into(),
            Topic::DeviceAcquired          => "device.acquired".into(),
            Topic::DeviceReleased          => "device.released".into(),
            Topic::DeviceStateChanged      => "device.state.changed".into(),
            Topic::HingeAngleChanged       => "device.hinge.changed".into(),
            Topic::InferenceRequest        => "inference.request".into(),
            Topic::InferenceResult         => "inference.result".into(),
            Topic::ModelLoaded             => "model.loaded".into(),
            Topic::ModelUnloaded           => "model.unloaded".into(),
            Topic::CopilotIntentClassified => "copilot.intent.classified".into(),
            Topic::CapabilityIssued        => "security.capability.issued".into(),
            Topic::CapabilityRevoked       => "security.capability.revoked".into(),
            Topic::SecurityViolation       => "security.violation".into(),
            Topic::AttestationCompleted    => "security.attestation.completed".into(),
            Topic::QkdSessionEstablished   => "security.qkd.established".into(),
            Topic::QuantumCircuitSubmit    => "quantum.circuit.submit".into(),
            Topic::QuantumCircuitResult    => "quantum.circuit.result".into(),
            Topic::QpuStateUpdate          => "quantum.qpu.state".into(),
            Topic::Heartbeat               => "system.heartbeat".into(),
            Topic::PowerStateChanged       => "system.power.changed".into(),
            Topic::ThermalThrottle         => "system.thermal.throttle".into(),
            Topic::RuntimeStart            => "runtime.start".into(),
            Topic::RuntimeStop             => "runtime.stop".into(),
            Topic::MetricsSnapshot         => "system.metrics.snapshot".into(),
            Topic::Custom(s)               => format!("custom.{s}"),
        }
    }

    /// Default TTL for messages on this topic (milliseconds)
    pub fn default_ttl_ms(&self) -> u64 {
        match self {
            Topic::Heartbeat               => 1_000,
            Topic::SnapshotTransfer        => 30_000,
            Topic::InferenceRequest        => 10_000,
            Topic::QuantumCircuitSubmit    => 60_000,
            Topic::SecurityViolation       => 0, // never expires
            Topic::ThermalThrottle         => 500,
            _                              => crate::DEFAULT_TTL_MS,
        }
    }

    /// Whether this topic requires a capability token to publish
    pub fn requires_capability(&self) -> bool {
        matches!(
            self,
            Topic::SnapshotTransfer
                | Topic::DomainMigrate
                | Topic::CapabilityIssued
                | Topic::CapabilityRevoked
                | Topic::SecurityViolation
                | Topic::QuantumCircuitSubmit
                | Topic::QkdSessionEstablished
                | Topic::AttestationCompleted
        )
    }

    /// Whether this topic is a system-only topic (cannot be published by apps)
    pub fn is_system_only(&self) -> bool {
        matches!(
            self,
            Topic::Heartbeat
                | Topic::RuntimeStart
                | Topic::RuntimeStop
                | Topic::ThermalThrottle
                | Topic::PowerStateChanged
                | Topic::MetricsSnapshot
        )
    }

    /// Priority weight for this topic (higher = processed first)
    pub fn priority_weight(&self) -> u8 {
        match self {
            Topic::SecurityViolation       => 255,
            Topic::ThermalThrottle         => 240,
            Topic::DomainHealth            => 220,
            Topic::TaskMigrating           => 200,
            Topic::SnapshotTransfer        => 190,
            Topic::IntentSubmit            => 150,
            Topic::InferenceRequest        => 140,
            Topic::Heartbeat               => 50,
            Topic::MetricsSnapshot         => 30,
            _                              => 100,
        }
    }
}

impl std::fmt::Display for Topic {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.name())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn topic_names_unique() {
        let topics = vec![
            Topic::SessionSync,
            Topic::IntentSubmit,
            Topic::TaskMigrating,
            Topic::MemoryUpdate,
            Topic::DomainHealth,
            Topic::Heartbeat,
        ];
        let names: std::collections::HashSet<String> =
            topics.iter().map(|t| t.name()).collect();
        assert_eq!(names.len(), topics.len());
    }

    #[test]
    fn system_topics_flagged() {
        assert!(Topic::Heartbeat.is_system_only());
        assert!(!Topic::IntentSubmit.is_system_only());
    }

    #[test]
    fn security_topics_require_capability() {
        assert!(Topic::CapabilityRevoked.requires_capability());
        assert!(!Topic::SessionSync.requires_capability());
    }

    #[test]
    fn custom_topic_name() {
        let t = Topic::Custom("my.extension".into());
        assert_eq!(t.name(), "custom.my.extension");
    }
}