//! # Zenith ABI Contract Traits
//!
//! Formal interface contracts that all Zenith subsystems must implement.
//! These traits define the Universal ABI that applications compile against.

use crate::types::{ZResult, ZSessionId, ZTaskId, ZObjectId, ZDeviceId};
use crate::domain::Domain;
use crate::intent::Intent;
use crate::session::Session;
use crate::task::ZenithTask;
use crate::memory::UniversalMemoryObject;
use crate::inference::{InferenceRequest, InferenceResponse};

/// Core session management contract
pub trait IZSession {
    /// Open or resume a session
    fn open_session(&mut self, session: Session) -> ZResult<ZSessionId>;
    /// Suspend a session
    fn suspend_session(&mut self, id: &ZSessionId) -> ZResult<()>;
    /// Resume a suspended session
    fn resume_session(&mut self, id: &ZSessionId) -> ZResult<()>;
    /// Terminate a session
    fn terminate_session(&mut self, id: &ZSessionId) -> ZResult<()>;
    /// Get session state
    fn session_state(&self, id: &ZSessionId) -> ZResult<crate::session::SessionState>;
}

/// Intent submission and tracking contract
pub trait IZIntent {
    /// Submit an intent for scheduling
    fn submit_intent(&mut self, intent: Intent) -> ZResult<ZTaskId>;
    /// Cancel a pending intent
    fn cancel_intent(&mut self, id: &ZTaskId) -> ZResult<()>;
    /// Get intent state
    fn intent_state(&self, id: &ZTaskId) -> ZResult<crate::intent::IntentState>;
    /// Wait for intent completion (async in real impl)
    fn await_intent(&self, id: &ZTaskId) -> ZResult<Vec<u8>>;
}

/// Task execution contract
pub trait IZTask {
    /// Execute a task
    fn execute(&mut self, task: &mut ZenithTask) -> ZResult<Vec<u8>>;
    /// Checkpoint a running task
    fn checkpoint(&mut self, task: &mut ZenithTask) -> ZResult<Vec<u8>>;
    /// Restore a task from checkpoint
    fn restore(&mut self, task: &mut ZenithTask, snapshot: &[u8]) -> ZResult<()>;
    /// Migrate a task to another domain
    fn migrate(&mut self, task: &mut ZenithTask, target: Domain) -> ZResult<()>;
}

/// Memory object contract
pub trait IZMemory {
    /// Allocate a new Universal Memory Object
    fn allocate(&mut self, name: &str, kind: crate::memory::UmoKind, session: ZSessionId) -> ZResult<ZObjectId>;
    /// Map an object into the current domain's address space
    fn map(&mut self, id: &ZObjectId, domain: Domain) -> ZResult<*mut u8>;
    /// Unmap an object
    fn unmap(&mut self, id: &ZObjectId, domain: &Domain) -> ZResult<()>;
    /// Write to an object
    fn write(&mut self, id: &ZObjectId, offset: usize, data: &[u8], writer: Domain) -> ZResult<()>;
    /// Read from an object
    fn read(&self, id: &ZObjectId, offset: usize, len: usize) -> ZResult<Vec<u8>>;
    /// Free an object
    fn free(&mut self, id: &ZObjectId) -> ZResult<()>;
}

/// Device access contract
pub trait IZDevice {
    /// Acquire a device
    fn acquire(&mut self, class: &crate::device::DeviceClass, domain: Domain) -> ZResult<ZDeviceId>;
    /// Release a device
    fn release(&mut self, id: &ZDeviceId, domain: &Domain) -> ZResult<()>;
    /// Query device state
    fn device_state(&self, id: &ZDeviceId) -> ZResult<crate::device::DeviceState>;
    /// Send a command to a device
    fn send_command(&mut self, id: &ZDeviceId, command: &[u8]) -> ZResult<Vec<u8>>;
}

/// AI inference contract
pub trait IZInference {
    /// Submit an inference request
    fn infer(&mut self, request: InferenceRequest) -> ZResult<InferenceResponse>;
    /// Stream inference results (simplified: returns iterator of chunks)
    fn infer_stream(&mut self, request: InferenceRequest) -> ZResult<Vec<Vec<u8>>>;
    /// Load a model into memory
    fn load_model(&mut self, model_id: uuid::Uuid) -> ZResult<()>;
    /// Unload a model from memory
    fn unload_model(&mut self, model_id: uuid::Uuid) -> ZResult<()>;
}

/// Domain runtime contract — implemented by Android, Windows, AI, Quantum domains
pub trait IZDomainRuntime {
    /// Start the domain runtime
    fn start(&mut self) -> ZResult<()>;
    /// Stop the domain runtime
    fn stop(&mut self) -> ZResult<()>;
    /// Get domain health
    fn health(&self) -> crate::domain::DomainHealth;
    /// Accept a migrated task
    fn accept_task(&mut self, task: ZenithTask, snapshot: &[u8]) -> ZResult<()>;
    /// Snapshot all running tasks
    fn snapshot_all(&mut self) -> ZResult<Vec<(ZTaskId, Vec<u8>)>>;
    /// Domain identifier
    fn domain(&self) -> Domain;
}

/// Snapshotable contract — for any entity that supports checkpointing
pub trait IZSnapshotable {
    /// Create a snapshot of current state
    fn snapshot(&self) -> ZResult<Vec<u8>>;
    /// Restore from a snapshot
    fn restore_from(&mut self, snapshot: &[u8]) -> ZResult<()>;
    /// Snapshot version for compatibility checking
    fn snapshot_version(&self) -> u32;
}

/// Capability-gated contract — for any operation requiring authorization
pub trait IZCapabilityGated {
    /// Validate that a capability token authorizes this operation
    fn validate_capability(
        &self,
        token: &crate::capability::CapabilityToken,
        resource: &crate::domain::ResourceClass,
        access: &crate::domain::AccessLevel,
    ) -> ZResult<()>;
}

/// Metrics contract — for any subsystem that exposes telemetry
pub trait IZMetrics {
    /// Get current metrics as a key-value map
    fn metrics(&self) -> std::collections::HashMap<String, f64>;
    /// Reset metrics counters
    fn reset_metrics(&mut self);
}

/// Version contract — for ABI compatibility checking
pub trait IZVersioned {
    /// ABI version this component implements
    fn abi_version(&self) -> &str;
    /// Whether this component is compatible with a given ABI version
    fn is_compatible(&self, version: &str) -> bool {
        self.abi_version() == version
    }
}

/// Full Zenith ABI — composite of all sub-contracts
///
/// A complete Zenith OS implementation must satisfy all of these traits.
pub trait ZenithAbi:
    IZSession
    + IZIntent
    + IZMemory
    + IZDevice
    + IZInference
    + IZMetrics
    + IZVersioned
{
}