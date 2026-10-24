//! # AI Hardware Router
//!
//! Routes inference requests to the optimal hardware based on model size,
//! operation type, latency requirements, and current hardware availability.

use zenith_abi::inference::{InferenceRequest, InferenceHardware, InferenceOp, ModelKind};
use zenith_abi::domain::Domain;

/// Hardware availability state
#[derive(Debug, Clone)]
pub struct HardwareState {
    pub hardware:      InferenceHardware,
    pub available:     bool,
    pub utilization:   f64,
    pub queue_depth:   u32,
    pub avg_latency_ms: f64,
    pub power_mw:      u32,
}

impl HardwareState {
    pub fn new(hardware: InferenceHardware) -> Self {
        Self {
            hardware,
            available:     true,
            utilization:   0.0,
            queue_depth:   0,
            avg_latency_ms: 0.0,
            power_mw:      0,
        }
    }

    /// Routing score (higher = better choice)
    pub fn routing_score(&self, latency_budget_ms: u32) -> f64 {
        if !self.available { return 0.0; }
        let latency_ok = self.avg_latency_ms <= latency_budget_ms as f64;
        let load_factor = 1.0 - self.utilization;
        let queue_factor = 1.0 / (self.queue_depth as f64 + 1.0);
        let latency_bonus = if latency_ok { 1.0 } else { 0.5 };
        load_factor * queue_factor * latency_bonus
    }
}

/// Routing decision record
#[derive(Debug, Clone)]
pub struct RoutingDecision {
    pub request_id: uuid::Uuid,
    pub hardware:   InferenceHardware,
    pub reason:     String,
    pub score:      f64,
    pub timestamp:  std::time::Instant,
}

/// The AI Hardware Router
#[derive(Debug)]
pub struct HardwareRouter {
    /// Available hardware states
    hardware_states: Vec<HardwareState>,
    /// Routing history
    decisions:       Vec<RoutingDecision>,
    /// Total routing decisions
    total_decisions: u64,
    /// Routing policy
    policy:          RoutingPolicy,
}

/// Routing policy
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RoutingPolicy {
    /// Always use the best-fit hardware
    BestFit,
    /// Minimize power consumption
    PowerEfficient,
    /// Minimize latency
    LowestLatency,
    /// Round-robin across available hardware
    RoundRobin,
    /// Weighted combination
    Weighted,
}

impl HardwareRouter {
    /// Create a new hardware router
    pub fn new() -> Self {
        Self {
            hardware_states: vec![
                HardwareState::new(InferenceHardware::Npu),
                HardwareState::new(InferenceHardware::Gpu),
                HardwareState::new(InferenceHardware::Cpu),
                HardwareState::new(InferenceHardware::Qpu),
                HardwareState::new(InferenceHardware::Cloud),
                HardwareState::new(InferenceHardware::Hybrid),
            ],
            decisions:       Vec::new(),
            total_decisions: 0,
            policy:          RoutingPolicy::BestFit,
        }
    }

    /// Set routing policy
    pub fn set_policy(&mut self, policy: RoutingPolicy) {
        self.policy = policy;
    }

    /// Update hardware state
    pub fn update_state(&mut self, hardware: &InferenceHardware, utilization: f64, queue_depth: u32) {
        if let Some(state) = self.hardware_states.iter_mut().find(|s| &s.hardware == hardware) {
            state.utilization = utilization.clamp(0.0, 1.0);
            state.queue_depth = queue_depth;
        }
    }

    /// Mark hardware as unavailable
    pub fn set_unavailable(&mut self, hardware: &InferenceHardware) {
        if let Some(state) = self.hardware_states.iter_mut().find(|s| &s.hardware == hardware) {
            state.available = false;
        }
    }

    /// Mark hardware as available
    pub fn set_available(&mut self, hardware: &InferenceHardware) {
        if let Some(state) = self.hardware_states.iter_mut().find(|s| &s.hardware == hardware) {
            state.available = true;
        }
    }

    /// Route an inference request to the optimal hardware
    pub fn route(&mut self, request: &InferenceRequest) -> InferenceHardware {
        self.total_decisions += 1;

        // If caller specified hardware, respect it if available
        if let Some(ref preferred) = request.preferred_hardware {
            if self.is_available(preferred) {
                self.record_decision(request.id, preferred.clone(), "caller-specified", 1.0);
                return preferred.clone();
            }
        }

        // Route based on operation type
        let hardware = self.route_by_operation(&request.operation, request.latency_budget_ms);
        self.record_decision(request.id, hardware.clone(), "operation-based", 0.9);
        hardware
    }

    /// Route based on operation type
    fn route_by_operation(&self, op: &InferenceOp, latency_budget_ms: u32) -> InferenceHardware {
        match op {
            InferenceOp::QuantumCircuit { .. } => {
                if self.is_available(&InferenceHardware::Qpu) {
                    InferenceHardware::Qpu
                } else {
                    InferenceHardware::Cpu
                }
            }
            InferenceOp::TextGeneration { prompt, .. } => {
                // Large prompts → GPU, small → NPU
                if prompt.len() > 10_000 {
                    if self.is_available(&InferenceHardware::Gpu) {
                        InferenceHardware::Gpu
                    } else {
                        InferenceHardware::Cloud
                    }
                } else if self.is_available(&InferenceHardware::Npu) {
                    InferenceHardware::Npu
                } else {
                    InferenceHardware::Cpu
                }
            }
            InferenceOp::Embedding { .. } => {
                if self.is_available(&InferenceHardware::Npu) {
                    InferenceHardware::Npu
                } else {
                    InferenceHardware::Cpu
                }
            }
            InferenceOp::ImageClassify { .. } => {
                if self.is_available(&InferenceHardware::Npu) {
                    InferenceHardware::Npu
                } else if self.is_available(&InferenceHardware::Gpu) {
                    InferenceHardware::Gpu
                } else {
                    InferenceHardware::Cpu
                }
            }
            InferenceOp::Transcribe { .. } => {
                if self.is_available(&InferenceHardware::Npu) {
                    InferenceHardware::Npu
                } else {
                    InferenceHardware::Cpu
                }
            }
            InferenceOp::Synthesize { .. } => {
                if self.is_available(&InferenceHardware::Npu) {
                    InferenceHardware::Npu
                } else {
                    InferenceHardware::Cpu
                }
            }
            InferenceOp::CodeComplete { .. } => {
                if self.is_available(&InferenceHardware::Gpu) {
                    InferenceHardware::Gpu
                } else if self.is_available(&InferenceHardware::Npu) {
                    InferenceHardware::Npu
                } else {
                    InferenceHardware::Cpu
                }
            }
            InferenceOp::ClassifyIntent { .. } => {
                if self.is_available(&InferenceHardware::Npu) {
                    InferenceHardware::Npu
                } else {
                    InferenceHardware::Cpu
                }
            }
        }
    }

    /// Whether a hardware target is available
    pub fn is_available(&self, hardware: &InferenceHardware) -> bool {
        self.hardware_states.iter()
            .find(|s| &s.hardware == hardware)
            .map(|s| s.available)
            .unwrap_or(false)
    }

    /// Get all available hardware targets
    pub fn available_hardware(&self) -> Vec<InferenceHardware> {
        self.hardware_states.iter()
            .filter(|s| s.available)
            .map(|s| s.hardware.clone())
            .collect()
    }

    /// Record a routing decision
    fn record_decision(&mut self, request_id: uuid::Uuid, hardware: InferenceHardware, reason: &str, score: f64) {
        self.decisions.push(RoutingDecision {
            request_id,
            hardware,
            reason: reason.to_string(),
            score,
            timestamp: std::time::Instant::now(),
        });
        if self.decisions.len() > 10_000 {
            self.decisions.drain(0..1000);
        }
    }

    /// Total routing decisions
    pub fn total_decisions(&self) -> u64 { self.total_decisions }

    /// Hardware utilization summary
    pub fn utilization_summary(&self) -> Vec<(InferenceHardware, f64)> {
        self.hardware_states.iter()
            .map(|s| (s.hardware.clone(), s.utilization))
            .collect()
    }
}

impl Default for HardwareRouter {
    fn default() -> Self { Self::new() }
}

#[cfg(test)]
mod tests {
    use super::*;
    use uuid::Uuid;
    use zenith_abi::inference::InferenceRequest;

    fn make_request(op: InferenceOp) -> InferenceRequest {
        InferenceRequest::new(Uuid::new_v4(), Uuid::new_v4(), Uuid::new_v4(), op)
    }

    #[test]
    fn router_quantum_to_qpu() {
        let mut router = HardwareRouter::new();
        let req = make_request(InferenceOp::QuantumCircuit {
            circuit_qasm: "H q[0];".into(),
            shots: 1024,
        });
        let hw = router.route(&req);
        assert_eq!(hw, InferenceHardware::Qpu);
    }

    #[test]
    fn router_embedding_to_npu() {
        let mut router = HardwareRouter::new();
        let req = make_request(InferenceOp::Embedding { text: "test".into() });
        let hw = router.route(&req);
        assert_eq!(hw, InferenceHardware::Npu);
    }

    #[test]
    fn router_unavailable_fallback() {
        let mut router = HardwareRouter::new();
        router.set_unavailable(&InferenceHardware::Npu);
        let req = make_request(InferenceOp::Embedding { text: "test".into() });
        let hw = router.route(&req);
        assert_ne!(hw, InferenceHardware::Npu);
    }

    #[test]
    fn router_caller_specified_hardware() {
        let mut router = HardwareRouter::new();
        let mut req = make_request(InferenceOp::ClassifyIntent { description: "test".into() });
        req.preferred_hardware = Some(InferenceHardware::Gpu);
        let hw = router.route(&req);
        assert_eq!(hw, InferenceHardware::Gpu);
    }

    #[test]
    fn router_available_hardware_list() {
        let mut router = HardwareRouter::new();
        router.set_unavailable(&InferenceHardware::Qpu);
        let available = router.available_hardware();
        assert!(!available.contains(&InferenceHardware::Qpu));
        assert!(available.contains(&InferenceHardware::Npu));
    }

    #[test]
    fn router_decision_tracking() {
        let mut router = HardwareRouter::new();
        for _ in 0..5 {
            let req = make_request(InferenceOp::Embedding { text: "doc".into() });
            router.route(&req);
        }
        assert_eq!(router.total_decisions(), 5);
    }
}