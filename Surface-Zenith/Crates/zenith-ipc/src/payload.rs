//! # ZIB Payload Schemas
//!
//! Every topic has a strongly-typed payload schema.
//! Payloads are serialized as JSON for debuggability and bincode for performance.

use serde::{Deserialize, Serialize};
use uuid::Uuid;
use zenith_abi::domain::Domain;
use zenith_abi::types::{ZSessionId, ZTaskId, ZObjectId, ZTimestamp, Priority};
use zenith_abi::intent::IntentClass;
use zenith_abi::session::FormFactor;
use crate::topics::Topic;
use crate::error::ZibError;

// ---------------------------------------------------------------------------
// Payload validation trait
// ---------------------------------------------------------------------------

/// Trait for validating topic-specific payloads
pub trait PayloadSchema: Sized + serde::Serialize + for<'de> serde::Deserialize<'de> {
    /// The topic this schema belongs to
    fn topic() -> Topic;

    /// Validate the payload contents
    fn validate(&self) -> Result<(), ZibError> {
        Ok(()) // default: no extra validation
    }

    /// Serialize to bytes
    fn to_bytes(&self) -> Result<Vec<u8>, ZibError> {
        serde_json::to_vec(self).map_err(|e| ZibError::SerializationFailed {
            reason: e.to_string(),
        })
    }

    /// Deserialize from bytes
    fn from_bytes(bytes: &[u8]) -> Result<Self, ZibError> {
        serde_json::from_slice(bytes).map_err(|e| ZibError::DeserializationFailed {
            reason: e.to_string(),
        })
    }
}

// ---------------------------------------------------------------------------
// Session payloads
// ---------------------------------------------------------------------------

/// Payload for SessionOpened / SessionSync
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SessionOpenedPayload {
    pub session_id: ZSessionId,
    pub identity_id: Uuid,
    pub form_factor: FormFactor,
    pub active_domain: Domain,
    pub timestamp: ZTimestamp,
}

impl PayloadSchema for SessionOpenedPayload {
    fn topic() -> Topic { Topic::SessionOpened }
}

/// Payload for SessionMigrating
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SessionMigratingPayload {
    pub session_id: ZSessionId,
    pub from_device: String,
    pub to_device: String,
    pub snapshot_size_bytes: u64,
    pub timestamp: ZTimestamp,
}

impl PayloadSchema for SessionMigratingPayload {
    fn topic() -> Topic { Topic::SessionMigrating }
    fn validate(&self) -> Result<(), ZibError> {
        if self.from_device == self.to_device {
            return Err(ZibError::PayloadInvalid {
                reason: "source and target device must differ".into(),
            });
        }
        Ok(())
    }
}

// ---------------------------------------------------------------------------
// Intent payloads
// ---------------------------------------------------------------------------

/// Payload for IntentSubmit
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IntentSubmitPayload {
    pub intent_id: ZTaskId,
    pub session_id: ZSessionId,
    pub goal: String,
    pub class: IntentClass,
    pub priority: Priority,
    pub latency_budget_ms: u32,
    pub preferred_domain: Option<Domain>,
    pub timestamp: ZTimestamp,
}

impl PayloadSchema for IntentSubmitPayload {
    fn topic() -> Topic { Topic::IntentSubmit }
    fn validate(&self) -> Result<(), ZibError> {
        if self.goal.trim().is_empty() {
            return Err(ZibError::PayloadInvalid {
                reason: "intent goal cannot be empty".into(),
            });
        }
        if self.goal.len() > 4096 {
            return Err(ZibError::PayloadInvalid {
                reason: "intent goal exceeds 4096 characters".into(),
            });
        }
        Ok(())
    }
}

/// Payload for IntentComplete / IntentFailed
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IntentResultPayload {
    pub intent_id: ZTaskId,
    pub session_id: ZSessionId,
    pub success: bool,
    pub result_bytes: usize,
    pub error_message: Option<String>,
    pub execution_domain: Domain,
    pub duration_ms: u64,
    pub timestamp: ZTimestamp,
}

impl PayloadSchema for IntentResultPayload {
    fn topic() -> Topic { Topic::IntentComplete }
}

// ---------------------------------------------------------------------------
// Task payloads
// ---------------------------------------------------------------------------

/// Payload for TaskMigrating / TaskMigrated
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TaskMigrationPayload {
    pub task_id: ZTaskId,
    pub intent_id: ZTaskId,
    pub session_id: ZSessionId,
    pub from_domain: Domain,
    pub to_domain: Domain,
    pub snapshot_size_bytes: u64,
    pub migration_reason: MigrationReason,
    pub timestamp: ZTimestamp,
}

impl PayloadSchema for TaskMigrationPayload {
    fn topic() -> Topic { Topic::TaskMigrating }
    fn validate(&self) -> Result<(), ZibError> {
        if self.from_domain == self.to_domain {
            return Err(ZibError::PayloadInvalid {
                reason: "migration source and target domains must differ".into(),
            });
        }
        Ok(())
    }
}

/// Reason for task migration
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum MigrationReason {
    /// Form factor changed (fold/unfold)
    FormFactorChange,
    /// Source domain failed
    DomainFailure,
    /// Load balancing
    LoadBalance,
    /// User-initiated
    UserRequested,
    /// Power optimization
    PowerOptimization,
    /// Better hardware available
    HardwareUpgrade,
}

// ---------------------------------------------------------------------------
// Memory payloads
// ---------------------------------------------------------------------------

/// Payload for MemoryUpdate (dirty pages notification)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MemoryUpdatePayload {
    pub object_id: ZObjectId,
    pub session_id: ZSessionId,
    pub dirty_page_count: u32,
    pub total_page_count: u32,
    pub object_version: u64,
    pub writer_domain: Domain,
    pub timestamp: ZTimestamp,
}

impl PayloadSchema for MemoryUpdatePayload {
    fn topic() -> Topic { Topic::MemoryUpdate }
}

/// Payload for SnapshotTransfer
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SnapshotTransferPayload {
    pub task_id: ZTaskId,
    pub session_id: ZSessionId,
    pub from_domain: Domain,
    pub to_domain: Domain,
    /// Snapshot data (chunked for large snapshots)
    pub chunk_index: u32,
    pub total_chunks: u32,
    pub chunk_data: Vec<u8>,
    pub checksum: u32,
    pub timestamp: ZTimestamp,
}

impl PayloadSchema for SnapshotTransferPayload {
    fn topic() -> Topic { Topic::SnapshotTransfer }
    fn validate(&self) -> Result<(), ZibError> {
        if self.chunk_index >= self.total_chunks {
            return Err(ZibError::PayloadInvalid {
                reason: format!(
                    "chunk_index {} >= total_chunks {}",
                    self.chunk_index, self.total_chunks
                ),
            });
        }
        if self.chunk_data.is_empty() {
            return Err(ZibError::PayloadInvalid {
                reason: "snapshot chunk data cannot be empty".into(),
            });
        }
        Ok(())
    }
}

// ---------------------------------------------------------------------------
// Domain payloads
// ---------------------------------------------------------------------------

/// Payload for DomainHealth
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DomainHealthPayload {
    pub domain: Domain,
    pub health: zenith_abi::domain::DomainHealth,
    pub cpu_usage_pct: f32,
    pub memory_usage_pct: f32,
    pub active_task_count: u32,
    pub timestamp: ZTimestamp,
}

impl PayloadSchema for DomainHealthPayload {
    fn topic() -> Topic { Topic::DomainHealth }
    fn validate(&self) -> Result<(), ZibError> {
        if self.cpu_usage_pct < 0.0 || self.cpu_usage_pct > 100.0 {
            return Err(ZibError::PayloadInvalid {
                reason: format!("invalid cpu_usage_pct: {}", self.cpu_usage_pct),
            });
        }
        Ok(())
    }
}

/// Payload for DomainFormFactorChanged
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FormFactorChangedPayload {
    pub session_id: ZSessionId,
    pub old_form_factor: FormFactor,
    pub new_form_factor: FormFactor,
    pub hinge_angle_degrees: f32,
    pub recommended_domain: Domain,
    pub timestamp: ZTimestamp,
}

impl PayloadSchema for FormFactorChangedPayload {
    fn topic() -> Topic { Topic::DomainFormFactorChanged }
}

// ---------------------------------------------------------------------------
// Inference payloads
// ---------------------------------------------------------------------------

/// Payload for InferenceRequest
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InferenceRequestPayload {
    pub request_id: Uuid,
    pub session_id: ZSessionId,
    pub model_name: String,
    pub operation: String,
    pub input_bytes: Vec<u8>,
    pub max_tokens: Option<u32>,
    pub temperature: Option<f32>,
    pub streaming: bool,
    pub priority: Priority,
    pub timestamp: ZTimestamp,
}

impl PayloadSchema for InferenceRequestPayload {
    fn topic() -> Topic { Topic::InferenceRequest }
    fn validate(&self) -> Result<(), ZibError> {
        if self.model_name.trim().is_empty() {
            return Err(ZibError::PayloadInvalid {
                reason: "model_name cannot be empty".into(),
            });
        }
        if let Some(temp) = self.temperature {
            if !(0.0..=2.0).contains(&temp) {
                return Err(ZibError::PayloadInvalid {
                    reason: format!("temperature {temp} out of range [0.0, 2.0]"),
                });
            }
        }
        Ok(())
    }
}

/// Payload for InferenceResult
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InferenceResultPayload {
    pub request_id: Uuid,
    pub session_id: ZSessionId,
    pub success: bool,
    pub output_bytes: Vec<u8>,
    pub tokens_generated: Option<u32>,
    pub execution_ms: u32,
    pub hardware_used: String,
    pub energy_mj: u32,
    pub timestamp: ZTimestamp,
}

impl PayloadSchema for InferenceResultPayload {
    fn topic() -> Topic { Topic::InferenceResult }
}

// ---------------------------------------------------------------------------
// Security payloads
// ---------------------------------------------------------------------------

/// Payload for SecurityViolation
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SecurityViolationPayload {
    pub session_id: ZSessionId,
    pub violating_domain: Domain,
    pub target_domain: Option<Domain>,
    pub violation_type: ViolationType,
    pub detail: String,
    pub severity: ViolationSeverity,
    pub timestamp: ZTimestamp,
}

impl PayloadSchema for SecurityViolationPayload {
    fn topic() -> Topic { Topic::SecurityViolation }
}

/// Type of security violation
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum ViolationType {
    UnauthorizedCrossDomainAccess,
    InvalidCapabilityToken,
    ExpiredCapabilityToken,
    RevokedCapabilityToken,
    MemoryBoundaryViolation,
    PrivilegeEscalation,
    TamperingDetected,
    ReplayAttack,
}

/// Severity of a security violation
#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
pub enum ViolationSeverity {
    Low,
    Medium,
    High,
    Critical,
}

// ---------------------------------------------------------------------------
// Quantum payloads
// ---------------------------------------------------------------------------

/// Payload for QuantumCircuitSubmit
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QuantumCircuitPayload {
    pub circuit_id: Uuid,
    pub session_id: ZSessionId,
    pub qasm_source: String,
    pub qubit_count: u32,
    pub shots: u32,
    pub error_correction: bool,
    pub timestamp: ZTimestamp,
}

impl PayloadSchema for QuantumCircuitPayload {
    fn topic() -> Topic { Topic::QuantumCircuitSubmit }
    fn validate(&self) -> Result<(), ZibError> {
        if self.qasm_source.trim().is_empty() {
            return Err(ZibError::PayloadInvalid {
                reason: "QASM source cannot be empty".into(),
            });
        }
        if self.qubit_count == 0 || self.qubit_count > 1024 {
            return Err(ZibError::PayloadInvalid {
                reason: format!("qubit_count {} out of range [1, 1024]", self.qubit_count),
            });
        }
        if self.shots == 0 || self.shots > 1_000_000 {
            return Err(ZibError::PayloadInvalid {
                reason: format!("shots {} out of range [1, 1000000]", self.shots),
            });
        }
        Ok(())
    }
}

/// Payload for QuantumCircuitResult
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QuantumCircuitResultPayload {
    pub circuit_id: Uuid,
    pub session_id: ZSessionId,
    pub counts: std::collections::HashMap<String, u32>,
    pub shots_executed: u32,
    pub execution_ms: u32,
    pub fidelity: f32,
    pub timestamp: ZTimestamp,
}

impl PayloadSchema for QuantumCircuitResultPayload {
    fn topic() -> Topic { Topic::QuantumCircuitResult }
}

// ---------------------------------------------------------------------------
// System payloads
// ---------------------------------------------------------------------------

/// Payload for Heartbeat
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HeartbeatPayload {
    pub source_domain: Domain,
    pub uptime_ms: u64,
    pub active_sessions: u32,
    pub active_tasks: u32,
    pub memory_usage_pct: f32,
    pub cpu_usage_pct: f32,
    pub timestamp: ZTimestamp,
}

impl PayloadSchema for HeartbeatPayload {
    fn topic() -> Topic { Topic::Heartbeat }
}

/// Payload for MetricsSnapshot
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MetricsSnapshotPayload {
    pub source_domain: Domain,
    pub metrics: std::collections::HashMap<String, f64>,
    pub timestamp: ZTimestamp,
}

impl PayloadSchema for MetricsSnapshotPayload {
    fn topic() -> Topic { Topic::MetricsSnapshot }
}

// ---------------------------------------------------------------------------
// Generic payload validator
// ---------------------------------------------------------------------------

/// Validate a raw payload bytes against a topic's expected schema
pub fn validate_payload(topic: &Topic, bytes: &[u8]) -> Result<(), ZibError> {
    if bytes.is_empty() {
        return Err(ZibError::PayloadEmpty);
    }
    match topic {
        Topic::IntentSubmit => {
            IntentSubmitPayload::from_bytes(bytes)?.validate()
        }
        Topic::TaskMigrating | Topic::TaskMigrated => {
            TaskMigrationPayload::from_bytes(bytes)?.validate()
        }
        Topic::SnapshotTransfer => {
            SnapshotTransferPayload::from_bytes(bytes)?.validate()
        }
        Topic::DomainHealth => {
            DomainHealthPayload::from_bytes(bytes)?.validate()
        }
        Topic::InferenceRequest => {
            InferenceRequestPayload::from_bytes(bytes)?.validate()
        }
        Topic::SecurityViolation => {
            SecurityViolationPayload::from_bytes(bytes)?;
            Ok(())
        }
        Topic::QuantumCircuitSubmit => {
            QuantumCircuitPayload::from_bytes(bytes)?.validate()
        }
        Topic::SessionMigrating => {
            SessionMigratingPayload::from_bytes(bytes)?.validate()
        }
        // Topics with no strict schema validation
        _ => Ok(()),
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;
    use zenith_abi::intent::IntentClass;

    #[test]
    fn intent_submit_payload_valid() {
        let p = IntentSubmitPayload {
            intent_id: Uuid::new_v4(),
            session_id: Uuid::new_v4(),
            goal: "analyze contract".into(),
            class: IntentClass::Productivity,
            priority: 128,
            latency_budget_ms: 100,
            preferred_domain: Some(Domain::Windows),
            timestamp: ZTimestamp(0),
        };
        assert!(p.validate().is_ok());
        let bytes = p.to_bytes().unwrap();
        let restored = IntentSubmitPayload::from_bytes(&bytes).unwrap();
        assert_eq!(restored.goal, "analyze contract");
    }

    #[test]
    fn intent_submit_empty_goal_rejected() {
        let p = IntentSubmitPayload {
            intent_id: Uuid::new_v4(),
            session_id: Uuid::new_v4(),
            goal: "   ".into(),
            class: IntentClass::Unknown,
            priority: 0,
            latency_budget_ms: 0,
            preferred_domain: None,
            timestamp: ZTimestamp(0),
        };
        assert!(p.validate().is_err());
    }

    #[test]
    fn snapshot_transfer_chunk_validation() {
        let p = SnapshotTransferPayload {
            task_id: Uuid::new_v4(),
            session_id: Uuid::new_v4(),
            from_domain: Domain::Android,
            to_domain: Domain::Windows,
            chunk_index: 5,
            total_chunks: 3, // invalid: index >= total
            chunk_data: b"data".to_vec(),
            checksum: 0,
            timestamp: ZTimestamp(0),
        };
        assert!(p.validate().is_err());
    }

    #[test]
    fn quantum_circuit_validation() {
        let p = QuantumCircuitPayload {
            circuit_id: Uuid::new_v4(),
            session_id: Uuid::new_v4(),
            qasm_source: "H q[0]; CNOT q[0],q[1];".into(),
            qubit_count: 2,
            shots: 1024,
            error_correction: true,
            timestamp: ZTimestamp(0),
        };
        assert!(p.validate().is_ok());

        let bad = QuantumCircuitPayload {
            qubit_count: 0,
            ..p
        };
        assert!(bad.validate().is_err());
    }

    #[test]
    fn inference_temperature_validation() {
        let mut p = InferenceRequestPayload {
            request_id: Uuid::new_v4(),
            session_id: Uuid::new_v4(),
            model_name: "Phi-4".into(),
            operation: "text_generation".into(),
            input_bytes: b"hello".to_vec(),
            max_tokens: Some(512),
            temperature: Some(3.5), // invalid
            streaming: false,
            priority: 128,
            timestamp: ZTimestamp(0),
        };
        assert!(p.validate().is_err());
        p.temperature = Some(0.7);
        assert!(p.validate().is_ok());
    }

    #[test]
    fn generic_validator_dispatches() {
        let p = IntentSubmitPayload {
            intent_id: Uuid::new_v4(),
            session_id: Uuid::new_v4(),
            goal: "open excel".into(),
            class: IntentClass::Productivity,
            priority: 100,
            latency_budget_ms: 50,
            preferred_domain: None,
            timestamp: ZTimestamp(0),
        };
        let bytes = p.to_bytes().unwrap();
        assert!(validate_payload(&Topic::IntentSubmit, &bytes).is_ok());
        assert!(validate_payload(&Topic::IntentSubmit, &[]).is_err());
    }
}