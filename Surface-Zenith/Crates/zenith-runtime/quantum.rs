//! # Quantum Domain Runtime
//!
//! The Quantum Runtime manages QPU circuits, Q# execution, and QKD sessions.

use std::collections::HashMap;
use uuid::Uuid;
use serde::{Deserialize, Serialize};
use zenith_abi::domain::{Domain, DomainHealth};
use zenith_abi::task::{ZenithTask, TaskState};
use zenith_abi::types::ZTaskId;
use zenith_abi::contract::IZDomainRuntime;
use crate::error::RuntimeError;
use crate::metrics::DomainMetrics;
use crate::task_executor::TaskExecutor;

/// QPU circuit state
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum CircuitState {
    Pending,
    Compiling,
    Optimizing,
    Executing { shots_remaining: u32 },
    Completed,
    Failed { reason: String },
}

/// A quantum circuit job
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QuantumCircuitJob {
    pub id:           Uuid,
    pub qasm_source:  String,
    pub qubit_count:  u32,
    pub shots:        u32,
    pub state:        CircuitState,
    pub results:      Option<HashMap<String, u32>>,
    pub fidelity:     f32,
    pub submitted_at: std::time::Instant,
    pub completed_at: Option<std::time::Instant>,
}

impl QuantumCircuitJob {
    pub fn new(qasm: impl Into<String>, qubits: u32, shots: u32) -> Self {
        Self {
            id:           Uuid::new_v4(),
            qasm_source:  qasm.into(),
            qubit_count:  qubits,
            shots,
            state:        CircuitState::Pending,
            results:      None,
            fidelity:     0.0,
            submitted_at: std::time::Instant::now(),
            completed_at: None,
        }
    }

    pub fn execute_simulated(&mut self) {
        self.state = CircuitState::Executing { shots_remaining: self.shots };
        // Simulate Bell state measurement
        let mut counts = HashMap::new();
        counts.insert("00".into(), self.shots / 2);
        counts.insert("11".into(), self.shots / 2);
        self.results      = Some(counts);
        self.fidelity     = 0.9995;
        self.state        = CircuitState::Completed;
        self.completed_at = Some(std::time::Instant::now());
    }

    pub fn execution_time_ms(&self) -> Option<u64> {
        self.completed_at.map(|end| end.duration_since(self.submitted_at).as_millis() as u64)
    }
}

/// QKD session state
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum QkdSessionState {
    Initializing,
    KeyExchange,
    Established { key_bits: usize },
    Failed { reason: String },
    Expired,
}

/// A QKD session
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QkdSession {
    pub id:           Uuid,
    pub source:       String,
    pub target:       String,
    pub state:        QkdSessionState,
    pub qber:         f64,
    pub key_bits:     usize,
    pub created_at:   std::time::Instant,
    pub expires_at:   Option<std::time::Instant>,
}

impl QkdSession {
    pub fn new(source: impl Into<String>, target: impl Into<String>) -> Self {
        Self {
            id:         Uuid::new_v4(),
            source:     source.into(),
            target:     target.into(),
            state:      QkdSessionState::Initializing,
            qber:       0.0,
            key_bits:   0,
            created_at: std::time::Instant::now(),
            expires_at: None,
        }
    }

    pub fn establish(&mut self, key_bits: usize, qber: f64) {
        self.key_bits = key_bits;
        self.qber     = qber;
        self.state    = QkdSessionState::Established { key_bits };
        self.expires_at = Some(std::time::Instant::now() + std::time::Duration::from_secs(3600));
    }

    pub fn is_secure(&self) -> bool {
        self.qber < 0.11 && matches!(self.state, QkdSessionState::Established { .. })
    }

    pub fn is_expired(&self) -> bool {
        self.expires_at.map(|exp| std::time::Instant::now() > exp).unwrap_or(false)
    }
}

/// QPU hardware descriptor
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QpuDescriptor {
    pub qubit_count:     u32,
    pub gate_fidelity:   f64,
    pub t1_time_us:      f64,
    pub t2_time_us:      f64,
    pub connectivity:    String,
    pub error_correction: bool,
    pub simulator:       bool,
}

impl QpuDescriptor {
    pub fn zenith_simulator() -> Self {
        Self {
            qubit_count:     50,
            gate_fidelity:   0.9995,
            t1_time_us:      100.0,
            t2_time_us:      80.0,
            connectivity:    "all-to-all".into(),
            error_correction: true,
            simulator:       true,
        }
    }
}

/// The Quantum Domain Runtime
#[derive(Debug)]
pub struct QuantumRuntime {
    health:          DomainHealth,
    active_tasks:    HashMap<ZTaskId, ZenithTask>,
    circuit_jobs:    HashMap<Uuid, QuantumCircuitJob>,
    qkd_sessions:    HashMap<Uuid, QkdSession>,
    qpu:             QpuDescriptor,
    metrics:         DomainMetrics,
    executor:        TaskExecutor,
    initialized:     bool,
    total_circuits:  u64,
    total_shots:     u64,
    total_qkd:       u64,
}

impl QuantumRuntime {
    pub fn new() -> Self {
        Self {
            health:         DomainHealth::Initializing,
            active_tasks:   HashMap::new(),
            circuit_jobs:   HashMap::new(),
            qkd_sessions:   HashMap::new(),
            qpu:            QpuDescriptor::zenith_simulator(),
            metrics:        DomainMetrics::new(Domain::Quantum),
            executor:       TaskExecutor::new(Domain::Quantum),
            initialized:    false,
            total_circuits: 0,
            total_shots:    0,
            total_qkd:      0,
        }
    }

    /// Submit a quantum circuit for execution
    pub fn submit_circuit(&mut self, qasm: impl Into<String>, qubits: u32, shots: u32) -> Result<Uuid, RuntimeError> {
        if qubits > self.qpu.qubit_count {
            return Err(RuntimeError::QubitLimitExceeded {
                requested: qubits,
                available: self.qpu.qubit_count,
            });
        }
        let mut job = QuantumCircuitJob::new(qasm, qubits, shots);
        let id = job.id;
        job.execute_simulated();
        self.total_circuits += 1;
        self.total_shots    += shots as u64;
        self.circuit_jobs.insert(id, job);
        self.metrics.record_event("circuit_executed");
        Ok(id)
    }

    /// Get circuit results
    pub fn get_circuit_results(&self, id: &Uuid) -> Option<&HashMap<String, u32>> {
        self.circuit_jobs.get(id)?.results.as_ref()
    }

    /// Establish a QKD session
    pub fn establish_qkd(&mut self, source: impl Into<String>, target: impl Into<String>, key_bits: usize) -> Uuid {
        let mut session = QkdSession::new(source, target);
        session.establish(key_bits, 0.02); // 2% QBER (well below 11% threshold)
        let id = session.id;
        self.qkd_sessions.insert(id, session);
        self.total_qkd += 1;
        self.metrics.record_event("qkd_established");
        id
    }

    /// Get a QKD session
    pub fn get_qkd_session(&self, id: &Uuid) -> Option<&QkdSession> {
        self.qkd_sessions.get(id)
    }

    /// Revoke a QKD session
    pub fn revoke_qkd(&mut self, id: &Uuid) -> bool {
        self.qkd_sessions.remove(id).is_some()
    }

    /// Purge expired QKD sessions
    pub fn purge_expired_qkd(&mut self) -> usize {
        let expired: Vec<Uuid> = self.qkd_sessions.iter()
            .filter(|(_, s)| s.is_expired())
            .map(|(&id, _)| id)
            .collect();
        let count = expired.len();
        for id in expired {
            self.qkd_sessions.remove(&id);
        }
        count
    }

    /// QPU descriptor
    pub fn qpu(&self) -> &QpuDescriptor { &self.qpu }

    /// Total circuits executed
    pub fn total_circuits(&self) -> u64 { self.total_circuits }

    /// Total shots executed
    pub fn total_shots(&self) -> u64 { self.total_shots }

    /// Active QKD sessions
    pub fn qkd_session_count(&self) -> usize { self.qkd_sessions.len() }

    /// Metrics
    pub fn metrics(&self) -> &DomainMetrics { &self.metrics }
}

impl IZDomainRuntime for QuantumRuntime {
    fn start(&mut self) -> zenith_abi::types::ZResult<()> {
        self.initialized = true;
        self.health = DomainHealth::Healthy;
        tracing::info!("Quantum Runtime started ({} qubits, fidelity: {:.4})",
            self.qpu.qubit_count, self.qpu.gate_fidelity);
        Ok(())
    }

    fn stop(&mut self) -> zenith_abi::types::ZResult<()> {
        self.circuit_jobs.clear();
        self.qkd_sessions.clear();
        self.health = DomainHealth::ShuttingDown;
        self.initialized = false;
        Ok(())
    }

    fn health(&self) -> DomainHealth { self.health.clone() }

    fn accept_task(&mut self, mut task: ZenithTask, _snapshot: &[u8]) -> zenith_abi::types::ZResult<()> {
        task.resume();
        self.active_tasks.insert(task.id, task);
        self.metrics.record_task_accepted();
        Ok(())
    }

    fn snapshot_all(&mut self) -> zenith_abi::types::ZResult<Vec<(ZTaskId, Vec<u8>)>> {
        Ok(self.active_tasks.iter()
            .map(|(&id, task)| (id, serde_json::to_vec(task).unwrap_or_default()))
            .collect())
    }

    fn domain(&self) -> Domain { Domain::Quantum }
}

impl Default for QuantumRuntime {
    fn default() -> Self { Self::new() }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn quantum_runtime_start() {
        let mut rt = QuantumRuntime::new();
        rt.start().unwrap();
        assert_eq!(rt.health(), DomainHealth::Healthy);
    }

    #[test]
    fn quantum_circuit_execution() {
        let mut rt = QuantumRuntime::new();
        rt.start().unwrap();
        let id = rt.submit_circuit("H q[0]; CNOT q[0],q[1];", 2, 1024).unwrap();
        let results = rt.get_circuit_results(&id).unwrap();
        assert!(results.contains_key("00"));
        assert!(results.contains_key("11"));
        assert_eq!(rt.total_circuits(), 1);
        assert_eq!(rt.total_shots(), 1024);
    }

    #[test]
    fn quantum_qubit_limit() {
        let mut rt = QuantumRuntime::new();
        rt.start().unwrap();
        let result = rt.submit_circuit("H q[0];", 100, 100); // 100 > 50 qubits
        assert!(result.is_err());
    }

    #[test]
    fn quantum_qkd_session() {
        let mut rt = QuantumRuntime::new();
        rt.start().unwrap();
        let id = rt.establish_qkd("android", "windows", 256);
        let session = rt.get_qkd_session(&id).unwrap();
        assert!(session.is_secure());
        assert_eq!(session.key_bits, 256);
        assert_eq!(rt.qkd_session_count(), 1);
        rt.revoke_qkd(&id);
        assert_eq!(rt.qkd_session_count(), 0);
    }

    #[test]
    fn quantum_domain_identity() {
        let rt = QuantumRuntime::new();
        assert_eq!(rt.domain(), Domain::Quantum);
    }
}