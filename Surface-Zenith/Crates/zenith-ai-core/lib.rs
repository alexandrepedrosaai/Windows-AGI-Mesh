//! # Zenith AI Core
//!
//! The AI Core is a kernel-level service in the Surface Zenith OS.
//! Unlike traditional AI assistants that run as applications, the Zenith
//! AI Core is integrated into the orchestration layer itself.
//!
//! ## Responsibilities
//!
//! - **Intent Classification**: Classify natural-language goals into IntentClass
//! - **Inference Routing**: Route inference requests to optimal hardware (NPU/GPU/QPU/Cloud)
//! - **Model Management**: Load/unload models based on usage patterns
//! - **Copilot Integration**: Provide the Copilot API to all domains
//! - **Context Management**: Maintain conversation context across sessions
//! - **Multimodal Processing**: Handle text, image, audio, and code inputs
//! - **Quantum-Classical Hybrid**: Route quantum ML workloads to QPU
//!
//! ## Architecture
//!
//! ```text
//! User Intent
//!      ↓
//! AI Core (kernel service)
//!      ↓
//! ┌────────────────────────────────────┐
//! │ Intent Classifier │ Context Manager │
//! │ Model Registry    │ Copilot Engine  │
//! │ Inference Router  │ Multimodal Hub  │
//! └────────────────────────────────────┘
//!      ↓
//! Hardware Router
//!      ↓
//! ┌──────┬──────┬──────┬───────┐
//! │ NPU  │ GPU  │ CPU  │  QPU  │
//! └──────┴──────┴──────┴───────┘
//! ```

#![deny(missing_docs)]
#![warn(clippy::all)]

pub mod classifier;
pub mod context;
pub mod copilot;
pub mod embedding;
pub mod error;
pub mod hardware_router;
pub mod inference_engine;
pub mod metrics;
pub mod model_registry;
pub mod multimodal;
pub mod pipeline;
pub mod prompt;
pub mod quantization;
pub mod rag;
pub mod safety;
pub mod session_context;
pub mod streaming;
pub mod tokenizer;

pub use classifier::*;
pub use context::*;
pub use copilot::*;
pub use embedding::*;
pub use error::*;
pub use hardware_router::*;
pub use inference_engine::*;
pub use metrics::*;
pub use model_registry::*;
pub use multimodal::*;
pub use pipeline::*;
pub use prompt::*;
pub use quantization::*;
pub use rag::*;
pub use safety::*;
pub use session_context::*;
pub use streaming::*;
pub use tokenizer::*;

/// AI Core version
pub const AI_CORE_VERSION: &str = "0.1.0";

/// Maximum context window size (tokens)
pub const MAX_CONTEXT_TOKENS: usize = 128_000;

/// Maximum batch size for inference
pub const MAX_BATCH_SIZE: usize = 32;

/// Default temperature for text generation
pub const DEFAULT_TEMPERATURE: f32 = 0.7;

/// Default top-p for nucleus sampling
pub const DEFAULT_TOP_P: f32 = 0.9;

/// Maximum model size for NPU (bytes)
pub const NPU_MAX_MODEL_SIZE: u64 = 8 * 1024 * 1024 * 1024; // 8 GB

/// Maximum model size for GPU (bytes)
pub const GPU_MAX_MODEL_SIZE: u64 = 24 * 1024 * 1024 * 1024; // 24 GB

/// Embedding dimension for the default embedding model
pub const DEFAULT_EMBEDDING_DIM: usize = 1536;

/// Maximum RAG document chunks
pub const MAX_RAG_CHUNKS: usize = 10;