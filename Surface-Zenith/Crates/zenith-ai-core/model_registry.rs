//! # AI Model Registry
//!
//! Manages the lifecycle of AI models available to the Zenith AI Core.
//! Handles model loading, unloading, versioning, and capability discovery.

use std::collections::HashMap;
use uuid::Uuid;
use serde::{Deserialize, Serialize};
use zenith_abi::inference::{ModelDescriptor, ModelKind, Quantization, InferenceHardware};
use crate::error::AiCoreError;

// ---------------------------------------------------------------------------
// Model state
// ---------------------------------------------------------------------------

/// State of a model in the registry
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum ModelState {
    /// Model is registered but not loaded
    Registered,
    /// Model is being loaded into memory
    Loading,
    /// Model is loaded and ready for inference
    Ready,
    /// Model is being unloaded
    Unloading,
    /// Model failed to load
    Failed { reason: String },
    /// Model is deprecated (newer version available)
    Deprecated { successor_id: Uuid },
}

impl ModelState {
    pub fn is_ready(&self) -> bool {
        matches!(self, ModelState::Ready)
    }

    pub fn is_available(&self) -> bool {
        matches!(self, ModelState::Ready | ModelState::Registered)
    }
}

// ---------------------------------------------------------------------------
// Model capability
// ---------------------------------------------------------------------------

/// Capabilities of a model
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ModelCapabilities {
    /// Supports text generation
    pub text_generation:   bool,
    /// Supports text embedding
    pub embedding:         bool,
    /// Supports image understanding
    pub vision:            bool,
    /// Supports audio transcription
    pub audio:             bool,
    /// Supports code generation
    pub code:              bool,
    /// Supports function calling
    pub function_calling:  bool,
    /// Supports structured output (JSON mode)
    pub structured_output: bool,
    /// Supports streaming
    pub streaming:         bool,
    /// Maximum context window in tokens
    pub max_context_tokens: usize,
    /// Maximum output tokens
    pub max_output_tokens:  usize,
    /// Supported languages (ISO 639-1 codes)
    pub languages:         Vec<String>,
    /// Whether this model supports quantum-classical hybrid inference
    pub quantum_hybrid:    bool,
}

impl Default for ModelCapabilities {
    fn default() -> Self {
        Self {
            text_generation:   true,
            embedding:         false,
            vision:            false,
            audio:             false,
            code:              false,
            function_calling:  false,
            structured_output: false,
            streaming:         true,
            max_context_tokens: 4096,
            max_output_tokens:  2048,
            languages:         vec!["en".into()],
            quantum_hybrid:    false,
        }
    }
}

// ---------------------------------------------------------------------------
// Model record
// ---------------------------------------------------------------------------

/// A model record in the registry
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ModelRecord {
    /// Unique model ID
    pub id:           Uuid,
    /// Model descriptor (from ABI layer)
    pub descriptor:   ModelDescriptor,
    /// Model capabilities
    pub capabilities: ModelCapabilities,
    /// Current state
    pub state:        ModelState,
    /// Model tags for search
    pub tags:         Vec<String>,
    /// Model provider (e.g., "Microsoft", "OpenAI", "Meta")
    pub provider:     String,
    /// License type
    pub license:      String,
    /// Whether this model is the default for its kind
    pub is_default:   bool,
    /// Registration timestamp
    pub registered_at: std::time::Instant,
    /// Last used timestamp
    pub last_used:    Option<std::time::Instant>,
    /// Total inference requests served
    pub request_count: u64,
    /// Total tokens generated
    pub tokens_generated: u64,
    /// Average inference latency in milliseconds
    pub avg_latency_ms: f64,
}

impl ModelRecord {
    /// Create a new model record
    pub fn new(descriptor: ModelDescriptor, capabilities: ModelCapabilities) -> Self {
        let id = descriptor.id;
        Self {
            id,
            descriptor,
            capabilities,
            state:           ModelState::Registered,
            tags:            Vec::new(),
            provider:        "Unknown".into(),
            license:         "Unknown".into(),
            is_default:      false,
            registered_at:   std::time::Instant::now(),
            last_used:       None,
            request_count:   0,
            tokens_generated: 0,
            avg_latency_ms:  0.0,
        }
    }

    /// Record an inference request
    pub fn record_request(&mut self, tokens: u32, latency_ms: u32) {
        self.request_count   += 1;
        self.tokens_generated += tokens as u64;
        self.last_used        = Some(std::time::Instant::now());
        // Exponential moving average for latency
        let alpha = 0.1f64;
        self.avg_latency_ms = alpha * latency_ms as f64 + (1.0 - alpha) * self.avg_latency_ms;
    }

    /// Age since last use in seconds
    pub fn idle_seconds(&self) -> Option<u64> {
        self.last_used.map(|t| t.elapsed().as_secs())
    }

    /// Whether this model should be unloaded (idle too long)
    pub fn should_unload(&self, idle_threshold_s: u64) -> bool {
        self.idle_seconds().map(|s| s > idle_threshold_s).unwrap_or(false)
    }

    /// Add a tag
    pub fn tag(&mut self, tag: impl Into<String>) {
        self.tags.push(tag.into());
    }
}

// ---------------------------------------------------------------------------
// Model registry
// ---------------------------------------------------------------------------

/// The AI Model Registry
///
/// Manages all AI models available to the Zenith AI Core.
/// Supports model discovery, loading, unloading, and versioning.
#[derive(Debug, Default)]
pub struct ModelRegistry {
    /// All registered models
    models:          HashMap<Uuid, ModelRecord>,
    /// Name → model ID index
    name_index:      HashMap<String, Uuid>,
    /// Kind → default model ID
    default_by_kind: HashMap<String, Uuid>,
    /// Tag → model IDs
    tag_index:       HashMap<String, Vec<Uuid>>,
    /// Total models registered
    total_registered: u64,
    /// Total models loaded
    total_loaded:    u64,
    /// Total models unloaded
    total_unloaded:  u64,
}

impl ModelRegistry {
    /// Create a new model registry
    pub fn new() -> Self { Self::default() }

    /// Register a model
    pub fn register(&mut self, mut record: ModelRecord) -> Uuid {
        let id   = record.id;
        let name = record.descriptor.name.clone();

        // Index by name
        self.name_index.insert(name, id);

        // Index by tags
        for tag in &record.tags {
            self.tag_index.entry(tag.clone()).or_default().push(id);
        }

        // Set as default if flagged
        if record.is_default {
            let kind_key = format!("{:?}", record.descriptor.kind);
            self.default_by_kind.insert(kind_key, id);
        }

        self.models.insert(id, record);
        self.total_registered += 1;
        id
    }

    /// Get a model by ID
    pub fn get(&self, id: &Uuid) -> Option<&ModelRecord> {
        self.models.get(id)
    }

    /// Get a mutable model by ID
    pub fn get_mut(&mut self, id: &Uuid) -> Option<&mut ModelRecord> {
        self.models.get_mut(id)
    }

    /// Get a model by name
    pub fn get_by_name(&self, name: &str) -> Option<&ModelRecord> {
        self.name_index.get(name).and_then(|id| self.models.get(id))
    }

    /// Get the default model for a kind
    pub fn default_for_kind(&self, kind: &ModelKind) -> Option<&ModelRecord> {
        let key = format!("{kind:?}");
        self.default_by_kind.get(&key).and_then(|id| self.models.get(id))
    }

    /// Mark a model as loaded
    pub fn mark_loaded(&mut self, id: &Uuid) -> Result<(), AiCoreError> {
        let record = self.models.get_mut(id)
            .ok_or_else(|| AiCoreError::ModelNotFound { id: id.to_string() })?;
        record.state = ModelState::Ready;
        record.descriptor.loaded = true;
        self.total_loaded += 1;
        Ok(())
    }

    /// Mark a model as unloaded
    pub fn mark_unloaded(&mut self, id: &Uuid) -> Result<(), AiCoreError> {
        let record = self.models.get_mut(id)
            .ok_or_else(|| AiCoreError::ModelNotFound { id: id.to_string() })?;
        record.state = ModelState::Registered;
        record.descriptor.loaded = false;
        self.total_unloaded += 1;
        Ok(())
    }

    /// Mark a model as failed
    pub fn mark_failed(&mut self, id: &Uuid, reason: impl Into<String>) {
        if let Some(record) = self.models.get_mut(id) {
            record.state = ModelState::Failed { reason: reason.into() };
        }
    }

    /// Get all ready models
    pub fn ready_models(&self) -> Vec<&ModelRecord> {
        self.models.values().filter(|m| m.state.is_ready()).collect()
    }

    /// Get all models for a hardware target
    pub fn models_for_hardware(&self, hw: &InferenceHardware) -> Vec<&ModelRecord> {
        self.models.values()
            .filter(|m| &m.descriptor.preferred_hardware == hw)
            .collect()
    }

    /// Search models by tag
    pub fn search_by_tag(&self, tag: &str) -> Vec<&ModelRecord> {
        self.tag_index.get(tag)
            .map(|ids| ids.iter().filter_map(|id| self.models.get(id)).collect())
            .unwrap_or_default()
    }

    /// Find the best model for a given capability
    pub fn best_for_capability(&self, capability: &str) -> Option<&ModelRecord> {
        self.models.values()
            .filter(|m| m.state.is_ready())
            .filter(|m| match capability {
                "text_generation"   => m.capabilities.text_generation,
                "embedding"         => m.capabilities.embedding,
                "vision"            => m.capabilities.vision,
                "audio"             => m.capabilities.audio,
                "code"              => m.capabilities.code,
                "function_calling"  => m.capabilities.function_calling,
                "quantum_hybrid"    => m.capabilities.quantum_hybrid,
                _                   => false,
            })
            .min_by(|a, b| {
                a.avg_latency_ms.partial_cmp(&b.avg_latency_ms)
                    .unwrap_or(std::cmp::Ordering::Equal)
            })
    }

    /// Get models that should be unloaded (idle too long)
    pub fn idle_models(&self, idle_threshold_s: u64) -> Vec<Uuid> {
        self.models.values()
            .filter(|m| m.state.is_ready() && m.should_unload(idle_threshold_s))
            .map(|m| m.id)
            .collect()
    }

    /// Total model count
    pub fn count(&self) -> usize { self.models.len() }

    /// Ready model count
    pub fn ready_count(&self) -> usize { self.ready_models().len() }

    /// Total registered
    pub fn total_registered(&self) -> u64 { self.total_registered }

    /// Total loaded
    pub fn total_loaded(&self) -> u64 { self.total_loaded }

    /// Build a standard Zenith model registry
    pub fn build_zenith_default() -> Self {
        let mut registry = Self::new();

        // Phi-4 Mini — primary on-device LLM (NPU)
        let phi4_desc = ModelDescriptor::new(
            "Phi-4-Mini",
            ModelKind::Llm { parameter_count_b: 4 },
            Quantization::Int4,
            2 * 1024 * 1024 * 1024,
        );
        let mut phi4_caps = ModelCapabilities::default();
        phi4_caps.function_calling  = true;
        phi4_caps.structured_output = true;
        phi4_caps.code              = true;
        phi4_caps.max_context_tokens = 16384;
        phi4_caps.languages = vec!["en".into(), "pt".into(), "es".into(), "fr".into(), "de".into()];

        let mut phi4 = ModelRecord::new(phi4_desc, phi4_caps);
        phi4.provider   = "Microsoft".into();
        phi4.license    = "MIT".into();
        phi4.is_default = true;
        phi4.tag("llm");
        phi4.tag("on-device");
        phi4.tag("copilot");
        registry.register(phi4);

        // Copilot-Zenith-7B — enhanced Copilot model (GPU)
        let copilot_desc = ModelDescriptor::new(
            "Copilot-Zenith-7B",
            ModelKind::Llm { parameter_count_b: 7 },
            Quantization::Int4,
            4 * 1024 * 1024 * 1024,
        );
        let mut copilot_caps = ModelCapabilities::default();
        copilot_caps.function_calling  = true;
        copilot_caps.structured_output = true;
        copilot_caps.code              = true;
        copilot_caps.vision            = true;
        copilot_caps.max_context_tokens = 32768;

        let mut copilot = ModelRecord::new(copilot_desc, copilot_caps);
        copilot.provider = "Microsoft".into();
        copilot.license  = "Proprietary".into();
        copilot.tag("llm");
        copilot.tag("copilot");
        copilot.tag("multimodal");
        registry.register(copilot);

        // Whisper-Large-v3 — speech-to-text (NPU)
        let whisper_desc = ModelDescriptor::new(
            "Whisper-Large-v3",
            ModelKind::Stt,
            Quantization::Int8,
            1_500_000_000,
        );
        let mut whisper_caps = ModelCapabilities::default();
        whisper_caps.text_generation = false;
        whisper_caps.audio           = true;
        whisper_caps.max_context_tokens = 448;
        whisper_caps.languages = vec!["en".into(), "pt".into(), "es".into(), "fr".into(),
                                      "de".into(), "zh".into(), "ja".into(), "ko".into()];

        let mut whisper = ModelRecord::new(whisper_desc, whisper_caps);
        whisper.provider   = "OpenAI".into();
        whisper.license    = "MIT".into();
        whisper.is_default = true;
        whisper.tag("stt");
        whisper.tag("audio");
        registry.register(whisper);

        // E5-Large — text embedding (NPU)
        let e5_desc = ModelDescriptor::new(
            "E5-Large-v2",
            ModelKind::Embedding,
            Quantization::Int8,
            500_000_000,
        );
        let mut e5_caps = ModelCapabilities::default();
        e5_caps.text_generation = false;
        e5_caps.embedding        = true;
        e5_caps.max_context_tokens = 512;

        let mut e5 = ModelRecord::new(e5_desc, e5_caps);
        e5.provider   = "Microsoft".into();
        e5.license    = "MIT".into();
        e5.is_default = true;
        e5.tag("embedding");
        e5.tag("rag");
        registry.register(e5);

        // Florence-2 — vision model (NPU)
        let florence_desc = ModelDescriptor::new(
            "Florence-2-Large",
            ModelKind::Vision,
            Quantization::Int8,
            800_000_000,
        );
        let mut florence_caps = ModelCapabilities::default();
        florence_caps.text_generation = false;
        florence_caps.vision          = true;
        florence_caps.max_context_tokens = 1024;

        let mut florence = ModelRecord::new(florence_desc, florence_caps);
        florence.provider   = "Microsoft".into();
        florence.license    = "MIT".into();
        florence.is_default = true;
        florence.tag("vision");
        florence.tag("multimodal");
        registry.register(florence);

        // CodeBERT — code understanding (NPU)
        let codebert_desc = ModelDescriptor::new(
            "CodeBERT-Base",
            ModelKind::CodeGen,
            Quantization::Int8,
            500_000_000,
        );
        let mut codebert_caps = ModelCapabilities::default();
        codebert_caps.code = true;
        codebert_caps.max_context_tokens = 512;

        let mut codebert = ModelRecord::new(codebert_desc, codebert_caps);
        codebert.provider   = "Microsoft".into();
        codebert.license    = "MIT".into();
        codebert.is_default = true;
        codebert.tag("code");
        codebert.tag("development");
        registry.register(codebert);

        registry
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    fn make_record(name: &str, kind: ModelKind) -> ModelRecord {
        let desc = ModelDescriptor::new(name, kind, Quantization::Int4, 1_000_000_000);
        ModelRecord::new(desc, ModelCapabilities::default())
    }

    #[test]
    fn registry_register_get() {
        let mut registry = ModelRegistry::new();
        let record = make_record("TestModel", ModelKind::Llm { parameter_count_b: 7 });
        let id = registry.register(record);
        assert!(registry.get(&id).is_some());
        assert_eq!(registry.count(), 1);
    }

    #[test]
    fn registry_get_by_name() {
        let mut registry = ModelRegistry::new();
        let record = make_record("MyModel", ModelKind::Embedding);
        registry.register(record);
        assert!(registry.get_by_name("MyModel").is_some());
        assert!(registry.get_by_name("NonExistent").is_none());
    }

    #[test]
    fn registry_mark_loaded_unloaded() {
        let mut registry = ModelRegistry::new();
        let record = make_record("LoadTest", ModelKind::Stt);
        let id = registry.register(record);
        registry.mark_loaded(&id).unwrap();
        assert!(registry.get(&id).unwrap().state.is_ready());
        registry.mark_unloaded(&id).unwrap();
        assert!(!registry.get(&id).unwrap().state.is_ready());
    }

    #[test]
    fn registry_tag_search() {
        let mut registry = ModelRegistry::new();
        let mut r1 = make_record("Model1", ModelKind::Llm { parameter_count_b: 4 });
        r1.tag("copilot");
        r1.tag("on-device");
        let mut r2 = make_record("Model2", ModelKind::Embedding);
        r2.tag("rag");
        registry.register(r1);
        registry.register(r2);
        assert_eq!(registry.search_by_tag("copilot").len(), 1);
        assert_eq!(registry.search_by_tag("rag").len(), 1);
        assert_eq!(registry.search_by_tag("nonexistent").len(), 0);
    }

    #[test]
    fn registry_request_tracking() {
        let mut registry = ModelRegistry::new();
        let record = make_record("TrackModel", ModelKind::Llm { parameter_count_b: 7 });
        let id = registry.register(record);
        registry.mark_loaded(&id).unwrap();
        registry.get_mut(&id).unwrap().record_request(512, 150);
        let model = registry.get(&id).unwrap();
        assert_eq!(model.request_count, 1);
        assert_eq!(model.tokens_generated, 512);
    }

    #[test]
    fn registry_zenith_default() {
        let registry = ModelRegistry::build_zenith_default();
        assert!(registry.count() >= 5);
        assert!(registry.get_by_name("Phi-4-Mini").is_some());
        assert!(registry.get_by_name("Whisper-Large-v3").is_some());
        assert!(registry.get_by_name("E5-Large-v2").is_some());
    }

    #[test]
    fn registry_best_for_capability() {
        let mut registry = ModelRegistry::build_zenith_default();
        // Load all models
        let ids: Vec<Uuid> = registry.models.keys().copied().collect();
        for id in ids {
            registry.mark_loaded(&id).unwrap();
        }
        assert!(registry.best_for_capability("embedding").is_some());
        assert!(registry.best_for_capability("audio").is_some());
        assert!(registry.best_for_capability("code").is_some());
    }
}