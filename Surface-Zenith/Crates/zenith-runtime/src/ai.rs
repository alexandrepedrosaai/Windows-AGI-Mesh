//! # AI Domain Runtime
//!
//! The AI Runtime manages NPU/GPU inference workloads, model loading,
//! and the Copilot kernel service.

use std::collections::HashMap;
use uuid::Uuid;
use serde::{Deserialize, Serialize};
use zenith_abi::domain::{Domain, DomainHealth};
use zenith_abi::task::{ZenithTask, TaskState};
use zenith_abi::types::{ZTaskId, ZInferenceId};
use zenith_abi::inference::{InferenceRequest, InferenceResponse, InferenceHardware};
use zenith_abi::contract::IZDomainRuntime;
use crate::error::RuntimeError;
use crate::metrics::DomainMetrics;
use crate::task_executor::TaskExecutor;

/// NPU engine state
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum NpuState {
    Idle,
    Loading { model: String },
    Inferring { request_id: Uuid },
    Error { reason: String },
}

/// GPU compute state
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum GpuState {
    Idle,
    Computing { task: String },
    Rendering,
    Error { reason: String },
}

/// Loaded model record
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LoadedModel {
    pub id:           Uuid,
    pub name:         String,
    pub size_bytes:   u64,
    pub hardware:     InferenceHardware,
    pub loaded_at:    std::time::Instant,
    pub request_count: u64,
    pub total_tokens: u64,
    pub avg_latency_ms: f64,
}

impl LoadedModel {
    pub fn new(id: Uuid, name: impl Into<String>, size_bytes: u64, hardware: InferenceHardware) -> Self {
        Self {
            id,
            name:          name.into(),
            size_bytes,
            hardware,
            loaded_at:     std::time::Instant::now(),
            request_count: 0,
            total_tokens:  0,
            avg_latency_ms: 0.0,
        }
    }

    pub fn record_inference(&mut self, tokens: u32, latency_ms: u32) {
        self.request_count += 1;
        self.total_tokens  += tokens as u64;
        let alpha = 0.1f64;
        self.avg_latency_ms = alpha * latency_ms as f64 + (1.0 - alpha) * self.avg_latency_ms;
    }

    pub fn idle_seconds(&self) -> u64 { self.loaded_at.elapsed().as_secs() }
}

/// Inference queue entry
#[derive(Debug, Clone)]
pub struct InferenceQueueEntry {
    pub request:     InferenceRequest,
    pub queued_at:   std::time::Instant,
    pub priority:    u8,
}

/// The AI Domain Runtime
#[derive(Debug)]
pub struct AiRuntime {
    health:          DomainHealth,
    active_tasks:    HashMap<ZTaskId, ZenithTask>,
    loaded_models:   HashMap<Uuid, LoadedModel>,
    inference_queue: std::collections::VecDeque<InferenceQueueEntry>,
    completed_inferences: Vec<InferenceResponse>,
    npu_state:       NpuState,
    gpu_state:       GpuState,
    npu_tops:        u32,
    gpu_vram_gb:     u32,
    metrics:         DomainMetrics,
    executor:        TaskExecutor,
    initialized:     bool,
    copilot_active:  bool,
    total_tokens:    u64,
    total_inferences: u64,
}

impl AiRuntime {
    pub fn new() -> Self {
        Self {
            health:               DomainHealth::Initializing,
            active_tasks:         HashMap::new(),
            loaded_models:        HashMap::new(),
            inference_queue:      std::collections::VecDeque::new(),
            completed_inferences: Vec::new(),
            npu_state:            NpuState::Idle,
            gpu_state:            GpuState::Idle,
            npu_tops:             300,
            gpu_vram_gb:          16,
            metrics:              DomainMetrics::new(Domain::AI),
            executor:             TaskExecutor::new(Domain::AI),
            initialized:          false,
            copilot_active:       false,
            total_tokens:         0,
            total_inferences:     0,
        }
    }

    /// Load a model into the AI runtime
    pub fn load_model(&mut self, id: Uuid, name: impl Into<String>, size_bytes: u64, hardware: InferenceHardware) -> Result<(), RuntimeError> {
        let name = name.into();
        self.npu_state = NpuState::Loading { model: name.clone() };
        let model = LoadedModel::new(id, name, size_bytes, hardware);
        self.loaded_models.insert(id, model);
        self.npu_state = NpuState::Idle;
        self.metrics.record_event("model_loaded");
        Ok(())
    }

    /// Unload a model
    pub fn unload_model(&mut self, id: &Uuid) -> bool {
        if self.loaded_models.remove(id).is_some() {
            self.metrics.record_event("model_unloaded");
            true
        } else {
            false
        }
    }

    /// Submit an inference request
    pub fn submit_inference(&mut self, request: InferenceRequest) -> ZInferenceId {
        let id = request.id;
        let priority = request.priority;
        self.inference_queue.push_back(InferenceQueueEntry {
            request,
            queued_at: std::time::Instant::now(),
            priority,
        });
        self.metrics.record_event("inference_submitted");
        id
    }

    /// Process one inference request
    pub fn process_inference(&mut self) -> Option<InferenceResponse> {
        let entry = self.inference_queue.pop_front()?;
        self.total_inferences += 1;

        // Simulate inference
        let tokens = 128u32;
        let latency_ms = 42u32;
        self.total_tokens += tokens as u64;

        // Update model stats
        if let Some(model) = self.loaded_models.get_mut(&entry.request.model_id) {
            model.record_inference(tokens, latency_ms);
        }

        let response = InferenceResponse {
            request_id:  entry.request.id,
            executed_on: InferenceHardware::Npu,
            result:      zenith_abi::inference::InferenceResult::Text {
                content:          "[AI] Inference result".into(),
                tokens_generated: tokens,
                finish_reason:    "stop".into(),
            },
            execution_ms: latency_ms,
            energy_mj:    50,
            responded_at: zenith_abi::types::ZTimestamp(
                std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .unwrap_or_default()
                    .as_micros() as i64,
            ),
        };

        self.completed_inferences.push(response.clone());
        self.metrics.record_event("inference_completed");
        Some(response)
    }

    /// Drain all pending inferences
    pub fn drain_inferences(&mut self) -> Vec<InferenceResponse> {
        let mut results = Vec::new();
        while let Some(r) = self.process_inference() {
            results.push(r);
        }
        results
    }

    /// Activate Copilot kernel service
    pub fn activate_copilot(&mut self) {
        self.copilot_active = true;
        self.metrics.record_event("copilot_activated");
        tracing::info!("Zenith Copilot kernel service activated");
    }

    /// Deactivate Copilot
    pub fn deactivate_copilot(&mut self) {
        self.copilot_active = false;
    }

    /// Loaded model count
    pub fn loaded_model_count(&self) -> usize { self.loaded_models.len() }

    /// Inference queue depth
    pub fn queue_depth(&self) -> usize { self.inference_queue.len() }

    /// Total inferences processed
    pub fn total_inferences(&self) -> u64 { self.total_inferences }

    /// Total tokens generated
    pub fn total_tokens(&self) -> u64 { self.total_tokens }

    /// Whether Copilot is active
    pub fn copilot_active(&self) -> bool { self.copilot_active }

    /// NPU state
    pub fn npu_state(&self) -> &NpuState { &self.npu_state }

    /// GPU state
    pub fn gpu_state(&self) -> &GpuState { &self.gpu_state }

    /// Metrics
    pub fn metrics(&self) -> &DomainMetrics { &self.metrics }
}

impl IZDomainRuntime for AiRuntime {
    fn start(&mut self) -> zenith_abi::types::ZResult<()> {
        self.initialized = true;
        self.health = DomainHealth::Healthy;
        self.activate_copilot();
        tracing::info!("AI Runtime started (NPU: {} TOPS, GPU: {} GB VRAM)", self.npu_tops, self.gpu_vram_gb);
        Ok(())
    }

    fn stop(&mut self) -> zenith_abi::types::ZResult<()> {
        self.deactivate_copilot();
        self.loaded_models.clear();
        self.inference_queue.clear();
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

    fn domain(&self) -> Domain { Domain::AI }
}

impl Default for AiRuntime {
    fn default() -> Self { Self::new() }
}

#[cfg(test)]
mod tests {
    use super::*;
    use zenith_abi::inference::{InferenceOp, InferenceRequest};

    #[test]
    fn ai_runtime_start_stop() {
        let mut rt = AiRuntime::new();
        rt.start().unwrap();
        assert_eq!(rt.health(), DomainHealth::Healthy);
        assert!(rt.copilot_active());
        rt.stop().unwrap();
        assert!(!rt.copilot_active());
    }

    #[test]
    fn ai_runtime_model_lifecycle() {
        let mut rt = AiRuntime::new();
        rt.start().unwrap();
        let model_id = Uuid::new_v4();
        rt.load_model(model_id, "Phi-4-Mini", 2_000_000_000, InferenceHardware::Npu).unwrap();
        assert_eq!(rt.loaded_model_count(), 1);
        rt.unload_model(&model_id);
        assert_eq!(rt.loaded_model_count(), 0);
    }

    #[test]
    fn ai_runtime_inference() {
        let mut rt = AiRuntime::new();
        rt.start().unwrap();
        let model_id = Uuid::new_v4();
        rt.load_model(model_id, "TestModel", 1_000_000_000, InferenceHardware::Npu).unwrap();

        let request = InferenceRequest::new(
            Uuid::new_v4(), Uuid::new_v4(), model_id,
            InferenceOp::TextGeneration {
                prompt: "Hello".into(), max_tokens: 128, temperature: 0.7,
            },
        );
        rt.submit_inference(request);
        assert_eq!(rt.queue_depth(), 1);

        let response = rt.process_inference().unwrap();
        assert_eq!(rt.queue_depth(), 0);
        assert_eq!(rt.total_inferences(), 1);
    }

    #[test]
    fn ai_runtime_drain() {
        let mut rt = AiRuntime::new();
        rt.start().unwrap();
        let model_id = Uuid::new_v4();
        rt.load_model(model_id, "M", 1_000_000, InferenceHardware::Cpu).unwrap();

        for _ in 0..5 {
            let req = InferenceRequest::new(
                Uuid::new_v4(), Uuid::new_v4(), model_id,
                InferenceOp::Embedding { text: "test".into() },
            );
            rt.submit_inference(req);
        }
        let results = rt.drain_inferences();
        assert_eq!(results.len(), 5);
        assert_eq!(rt.total_inferences(), 5);
    }

    #[test]
    fn ai_domain_identity() {
        let rt = AiRuntime::new();
        assert_eq!(rt.domain(), Domain::AI);
    }
}
