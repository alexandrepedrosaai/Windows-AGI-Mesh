//! # Zenith Inference Layer
//!
//! AI inference is not an application in the Zenith OS — it is a kernel-level
//! service. The Inference Router dispatches inference requests to the optimal
//! hardware (NPU, GPU, CPU, QPU, or Cloud) based on model size, latency
//! requirements, and available resources.

use serde::{Deserialize, Serialize};
use uuid::Uuid;
use crate::types::{ZInferenceId, ZSessionId, ZIdentityId, ZTimestamp, LatencyBudgetMs};
use crate::domain::Domain;

// ---------------------------------------------------------------------------
// Model descriptor
// ---------------------------------------------------------------------------

/// AI model type
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum ModelKind {
    /// Large Language Model (text generation, reasoning)
    Llm { parameter_count_b: u32 },
    /// Vision model (image classification, detection)
    Vision,
    /// Speech-to-text
    Stt,
    /// Text-to-speech
    Tts,
    /// Code generation
    CodeGen,
    /// Embedding model
    Embedding,
    /// Multimodal (text + vision + audio)
    Multimodal,
    /// Quantum ML model (runs on QPU)
    QuantumMl,
    /// Custom model
    Custom(String),
}

/// Quantization level for model inference
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum Quantization {
    /// Full precision (FP32)
    Fp32,
    /// Half precision (FP16)
    Fp16,
    /// Brain float (BF16)
    Bf16,
    /// 8-bit integer
    Int8,
    /// 4-bit integer
    Int4,
    /// 2-bit integer (extreme compression)
    Int2,
}

/// Descriptor of an AI model available for inference
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ModelDescriptor {
    /// Unique model ID
    pub id: Uuid,
    /// Model name (e.g., "Phi-4", "Copilot-Zenith-7B")
    pub name: String,
    /// Model kind
    pub kind: ModelKind,
    /// Quantization level
    pub quantization: Quantization,
    /// Model size in bytes (on disk)
    pub size_bytes: u64,
    /// Required VRAM in bytes
    pub vram_required: u64,
    /// Preferred hardware for this model
    pub preferred_hardware: InferenceHardware,
    /// Whether this model is loaded in memory
    pub loaded: bool,
    /// Model version
    pub version: String,
}

impl ModelDescriptor {
    /// Create a new model descriptor
    pub fn new(
        name: impl Into<String>,
        kind: ModelKind,
        quantization: Quantization,
        size_bytes: u64,
    ) -> Self {
        let preferred_hardware = Self::infer_hardware(&kind, size_bytes);
        Self {
            id: Uuid::new_v4(),
            name: name.into(),
            kind,
            quantization,
            size_bytes,
            vram_required: size_bytes / 2, // rough estimate
            preferred_hardware,
            loaded: false,
            version: "1.0.0".into(),
        }
    }

    /// Infer the best hardware for a model based on its kind and size
    fn infer_hardware(kind: &ModelKind, size_bytes: u64) -> InferenceHardware {
        match kind {
            ModelKind::QuantumMl => InferenceHardware::Qpu,
            ModelKind::Llm { parameter_count_b } if *parameter_count_b > 70 => {
                InferenceHardware::Cloud
            }
            ModelKind::Llm { .. } if size_bytes > 8 * 1024 * 1024 * 1024 => {
                InferenceHardware::Gpu
            }
            ModelKind::Llm { .. } => InferenceHardware::Npu,
            ModelKind::Vision    => InferenceHardware::Npu,
            ModelKind::Stt       => InferenceHardware::Npu,
            ModelKind::Tts       => InferenceHardware::Npu,
            ModelKind::CodeGen   => InferenceHardware::Gpu,
            ModelKind::Embedding => InferenceHardware::Npu,
            ModelKind::Multimodal=> InferenceHardware::Gpu,
            ModelKind::Custom(_) => InferenceHardware::Cpu,
        }
    }
}

// ---------------------------------------------------------------------------
// Inference hardware
// ---------------------------------------------------------------------------

/// Hardware target for inference execution
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum InferenceHardware {
    /// Neural Processing Unit (fastest for small models)
    Npu,
    /// GPU (best for large models)
    Gpu,
    /// CPU (fallback)
    Cpu,
    /// Quantum Processing Unit (quantum ML)
    Qpu,
    /// Cloud (for models too large for local hardware)
    Cloud,
    /// Hybrid (split between NPU + GPU)
    Hybrid,
}

// ---------------------------------------------------------------------------
// Inference request
// ---------------------------------------------------------------------------

/// Type of inference operation
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum InferenceOp {
    /// Text completion / generation
    TextGeneration {
        prompt: String,
        max_tokens: u32,
        temperature: f32,
    },
    /// Text embedding
    Embedding { text: String },
    /// Image classification
    ImageClassify { image_bytes: Vec<u8> },
    /// Speech to text
    Transcribe { audio_bytes: Vec<u8> },
    /// Text to speech
    Synthesize { text: String, voice: String },
    /// Code completion
    CodeComplete { prefix: String, suffix: String, language: String },
    /// Quantum circuit execution
    QuantumCircuit { circuit_qasm: String, shots: u32 },
    /// Intent classification (used by the Zenith scheduler)
    ClassifyIntent { description: String },
}

/// An inference request submitted to the Zenith AI Core
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InferenceRequest {
    /// Unique request ID
    pub id: ZInferenceId,
    /// Requesting session
    pub session: ZSessionId,
    /// Requesting identity
    pub identity: ZIdentityId,
    /// Target model
    pub model_id: Uuid,
    /// Operation to perform
    pub operation: InferenceOp,
    /// Latency budget
    pub latency_budget_ms: LatencyBudgetMs,
    /// Whether to stream results
    pub streaming: bool,
    /// Preferred hardware (None = let router decide)
    pub preferred_hardware: Option<InferenceHardware>,
    /// Submission timestamp
    pub submitted_at: ZTimestamp,
    /// Priority (0–255)
    pub priority: u8,
}

impl InferenceRequest {
    /// Create a new inference request
    pub fn new(
        session: ZSessionId,
        identity: ZIdentityId,
        model_id: Uuid,
        operation: InferenceOp,
    ) -> Self {
        Self {
            id: Uuid::new_v4(),
            session,
            identity,
            model_id,
            operation,
            latency_budget_ms: 500,
            streaming: false,
            preferred_hardware: None,
            submitted_at: ZTimestamp(
                std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .unwrap_or_default()
                    .as_micros() as i64,
            ),
            priority: 128,
        }
    }
}

// ---------------------------------------------------------------------------
// Inference result
// ---------------------------------------------------------------------------

/// Result of an inference operation
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum InferenceResult {
    /// Text generation result
    Text { content: String, tokens_generated: u32, finish_reason: String },
    /// Embedding vector
    Embedding { vector: Vec<f32> },
    /// Classification result
    Classification { label: String, confidence: f32 },
    /// Transcription result
    Transcription { text: String, language: String },
    /// Speech synthesis result
    Speech { audio_bytes: Vec<u8>, duration_ms: u32 },
    /// Code completion result
    Code { completion: String, language: String },
    /// Quantum circuit result
    QuantumResult { counts: std::collections::HashMap<String, u32>, shots: u32 },
    /// Intent classification result
    IntentClass { class: String, confidence: f32, suggested_domain: Domain },
    /// Error result
    Error { code: i32, message: String },
}

/// A completed inference response
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InferenceResponse {
    /// Request ID this responds to
    pub request_id: ZInferenceId,
    /// Hardware that executed this inference
    pub executed_on: InferenceHardware,
    /// Inference result
    pub result: InferenceResult,
    /// Execution time in milliseconds
    pub execution_ms: u32,
    /// Energy consumed in millijoules
    pub energy_mj: u32,
    /// Response timestamp
    pub responded_at: ZTimestamp,
}

// ---------------------------------------------------------------------------
// Inference router
// ---------------------------------------------------------------------------

/// Routes inference requests to the optimal hardware
#[derive(Debug, Default)]
pub struct InferenceRouter {
    models: std::collections::HashMap<Uuid, ModelDescriptor>,
    /// Request history for metrics
    request_count: u64,
    /// Total energy consumed
    total_energy_mj: u64,
}

impl InferenceRouter {
    /// Create a new inference router
    pub fn new() -> Self {
        Self::default()
    }

    /// Register a model
    pub fn register_model(&mut self, model: ModelDescriptor) -> Uuid {
        let id = model.id;
        self.models.insert(id, model);
        id
    }

    /// Get a model by ID
    pub fn get_model(&self, id: &Uuid) -> Option<&ModelDescriptor> {
        self.models.get(id)
    }

    /// Route an inference request to the optimal hardware
    pub fn route(&self, request: &InferenceRequest) -> InferenceHardware {
        // If caller specified hardware, respect it
        if let Some(ref hw) = request.preferred_hardware {
            return hw.clone();
        }

        // Look up model preference
        if let Some(model) = self.models.get(&request.model_id) {
            return model.preferred_hardware.clone();
        }

        // Default routing based on operation type
        match &request.operation {
            InferenceOp::QuantumCircuit { .. }  => InferenceHardware::Qpu,
            InferenceOp::TextGeneration { .. }  => InferenceHardware::Npu,
            InferenceOp::Embedding { .. }       => InferenceHardware::Npu,
            InferenceOp::ImageClassify { .. }   => InferenceHardware::Npu,
            InferenceOp::Transcribe { .. }      => InferenceHardware::Npu,
            InferenceOp::Synthesize { .. }      => InferenceHardware::Npu,
            InferenceOp::CodeComplete { .. }    => InferenceHardware::Gpu,
            InferenceOp::ClassifyIntent { .. }  => InferenceHardware::Npu,
        }
    }

    /// Simulate executing an inference request (returns a mock response)
    pub fn execute_mock(&mut self, request: &InferenceRequest) -> InferenceResponse {
        let hardware = self.route(request);
        self.request_count += 1;
        let energy = 50u32;
        self.total_energy_mj += energy as u64;

        let result = match &request.operation {
            InferenceOp::TextGeneration { prompt, .. } => InferenceResult::Text {
                content: format!("[Zenith AI] Response to: {}", &prompt[..prompt.len().min(50)]),
                tokens_generated: 128,
                finish_reason: "stop".into(),
            },
            InferenceOp::ClassifyIntent { description } => InferenceResult::IntentClass {
                class: "Productivity".into(),
                confidence: 0.92,
                suggested_domain: Domain::Windows,
            },
            InferenceOp::Embedding { .. } => InferenceResult::Embedding {
                vector: vec![0.1f32; 768],
            },
            InferenceOp::QuantumCircuit { shots, .. } => InferenceResult::QuantumResult {
                counts: {
                    let mut m = std::collections::HashMap::new();
                    m.insert("00".into(), shots / 2);
                    m.insert("11".into(), shots / 2);
                    m
                },
                shots: *shots,
            },
            _ => InferenceResult::Text {
                content: "[Zenith AI] Operation completed".into(),
                tokens_generated: 0,
                finish_reason: "stop".into(),
            },
        };

        InferenceResponse {
            request_id: request.id,
            executed_on: hardware,
            result,
            execution_ms: 42,
            energy_mj: energy,
            responded_at: ZTimestamp(
                std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .unwrap_or_default()
                    .as_micros() as i64,
            ),
        }
    }

    /// Total requests processed
    pub fn request_count(&self) -> u64 {
        self.request_count
    }

    /// Total energy consumed in millijoules
    pub fn total_energy_mj(&self) -> u64 {
        self.total_energy_mj
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn model_hardware_inference() {
        let small_llm = ModelDescriptor::new(
            "Phi-4-mini", ModelKind::Llm { parameter_count_b: 4 },
            Quantization::Int4, 2 * 1024 * 1024 * 1024,
        );
        assert_eq!(small_llm.preferred_hardware, InferenceHardware::Npu);

        let large_llm = ModelDescriptor::new(
            "GPT-4-class", ModelKind::Llm { parameter_count_b: 175 },
            Quantization::Fp16, 350 * 1024 * 1024 * 1024,
        );
        assert_eq!(large_llm.preferred_hardware, InferenceHardware::Cloud);

        let quantum = ModelDescriptor::new(
            "QML-v1", ModelKind::QuantumMl,
            Quantization::Fp32, 1024,
        );
        assert_eq!(quantum.preferred_hardware, InferenceHardware::Qpu);
    }

    #[test]
    fn inference_router_mock_execution() {
        let mut router = InferenceRouter::new();
        let model = ModelDescriptor::new(
            "Copilot-Zenith", ModelKind::Llm { parameter_count_b: 7 },
            Quantization::Int4, 4 * 1024 * 1024 * 1024,
        );
        let model_id = router.register_model(model);

        let session  = Uuid::new_v4();
        let identity = Uuid::new_v4();
        let request  = InferenceRequest::new(
            session, identity, model_id,
            InferenceOp::TextGeneration {
                prompt: "Analyze this contract".into(),
                max_tokens: 512,
                temperature: 0.7,
            },
        );

        let response = router.execute_mock(&request);
        assert_eq!(router.request_count(), 1);
        assert!(matches!(response.result, InferenceResult::Text { .. }));
    }

    #[test]
    fn quantum_circuit_routing() {
        let router = InferenceRouter::new();
        let session  = Uuid::new_v4();
        let identity = Uuid::new_v4();
        let request  = InferenceRequest::new(
            session, identity, Uuid::new_v4(),
            InferenceOp::QuantumCircuit {
                circuit_qasm: "H q[0]; CNOT q[0],q[1];".into(),
                shots: 1024,
            },
        );
        assert_eq!(router.route(&request), InferenceHardware::Qpu);
    }
}