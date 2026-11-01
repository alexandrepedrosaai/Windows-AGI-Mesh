//! # AI Inference Engine
//!
//! The core inference execution engine for the Zenith AI Core.
//! Manages inference requests, batching, hardware dispatch, and result streaming.

use std::collections::{HashMap, VecDeque};
use std::sync::Arc;
use parking_lot::RwLock;
use uuid::Uuid;
use serde::{Deserialize, Serialize};
use zenith_abi::inference::{
    InferenceRequest, InferenceResponse, InferenceResult, InferenceHardware, InferenceOp,
};
use zenith_abi::types::{ZInferenceId, ZSessionId};
use crate::error::AiCoreError;
use crate::model_registry::ModelRegistry;
use crate::hardware_router::HardwareRouter;
use crate::metrics::InferenceMetrics;

// ---------------------------------------------------------------------------
// Inference request state
// ---------------------------------------------------------------------------

/// State of an inference request
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum InferenceState {
    /// Request is queued
    Queued,
    /// Request is being preprocessed
    Preprocessing,
    /// Request is executing on hardware
    Executing { hardware: InferenceHardware },
    /// Request is being postprocessed
    Postprocessing,
    /// Request completed successfully
    Completed,
    /// Request failed
    Failed { reason: String },
    /// Request was cancelled
    Cancelled,
}

impl InferenceState {
    pub fn is_terminal(&self) -> bool {
        matches!(self, InferenceState::Completed | InferenceState::Failed { .. } | InferenceState::Cancelled)
    }

    pub fn is_active(&self) -> bool {
        matches!(self, InferenceState::Executing { .. } | InferenceState::Preprocessing | InferenceState::Postprocessing)
    }
}

// ---------------------------------------------------------------------------
// Inference job
// ---------------------------------------------------------------------------

/// An inference job tracked by the engine
#[derive(Debug, Clone)]
pub struct InferenceJob {
    /// Request ID
    pub id:           ZInferenceId,
    /// Original request
    pub request:      InferenceRequest,
    /// Current state
    pub state:        InferenceState,
    /// Assigned hardware
    pub hardware:     Option<InferenceHardware>,
    /// Submission time
    pub submitted_at: std::time::Instant,
    /// Start time (when execution began)
    pub started_at:   Option<std::time::Instant>,
    /// Completion time
    pub completed_at: Option<std::time::Instant>,
    /// Result (populated on completion)
    pub result:       Option<InferenceResult>,
    /// Number of retry attempts
    pub retry_count:  u32,
    /// Batch ID (if batched with other requests)
    pub batch_id:     Option<Uuid>,
}

impl InferenceJob {
    pub fn new(request: InferenceRequest) -> Self {
        Self {
            id:           request.id,
            request,
            state:        InferenceState::Queued,
            hardware:     None,
            submitted_at: std::time::Instant::now(),
            started_at:   None,
            completed_at: None,
            result:       None,
            retry_count:  0,
            batch_id:     None,
        }
    }

    pub fn start(&mut self, hardware: InferenceHardware) {
        self.state      = InferenceState::Executing { hardware: hardware.clone() };
        self.hardware   = Some(hardware);
        self.started_at = Some(std::time::Instant::now());
    }

    pub fn complete(&mut self, result: InferenceResult) {
        self.state        = InferenceState::Completed;
        self.result       = Some(result);
        self.completed_at = Some(std::time::Instant::now());
    }

    pub fn fail(&mut self, reason: impl Into<String>) {
        self.state        = InferenceState::Failed { reason: reason.into() };
        self.completed_at = Some(std::time::Instant::now());
    }

    pub fn cancel(&mut self) {
        self.state        = InferenceState::Cancelled;
        self.completed_at = Some(std::time::Instant::now());
    }

    pub fn queue_time_ms(&self) -> u64 {
        self.started_at
            .map(|s| s.duration_since(self.submitted_at).as_millis() as u64)
            .unwrap_or_else(|| self.submitted_at.elapsed().as_millis() as u64)
    }

    pub fn execution_time_ms(&self) -> Option<u64> {
        match (self.started_at, self.completed_at) {
            (Some(start), Some(end)) => Some(end.duration_since(start).as_millis() as u64),
            _ => None,
        }
    }

    pub fn total_time_ms(&self) -> Option<u64> {
        self.completed_at.map(|end| end.duration_since(self.submitted_at).as_millis() as u64)
    }
}

// ---------------------------------------------------------------------------
// Inference batch
// ---------------------------------------------------------------------------

/// A batch of inference requests for efficient hardware utilization
#[derive(Debug)]
pub struct InferenceBatch {
    pub id:       Uuid,
    pub jobs:     Vec<ZInferenceId>,
    pub hardware: InferenceHardware,
    pub model_id: Uuid,
    pub created_at: std::time::Instant,
}

impl InferenceBatch {
    pub fn new(hardware: InferenceHardware, model_id: Uuid) -> Self {
        Self {
            id:         Uuid::new_v4(),
            jobs:       Vec::new(),
            hardware,
            model_id,
            created_at: std::time::Instant::now(),
        }
    }

    pub fn add_job(&mut self, job_id: ZInferenceId) {
        self.jobs.push(job_id);
    }

    pub fn is_full(&self) -> bool {
        self.jobs.len() >= crate::MAX_BATCH_SIZE
    }

    pub fn size(&self) -> usize { self.jobs.len() }
}

// ---------------------------------------------------------------------------
// Inference engine configuration
// ---------------------------------------------------------------------------

/// Configuration for the inference engine
#[derive(Debug, Clone)]
pub struct InferenceEngineConfig {
    /// Maximum queue depth
    pub max_queue_depth:    usize,
    /// Maximum concurrent jobs
    pub max_concurrent:     usize,
    /// Enable request batching
    pub batching_enabled:   bool,
    /// Batch timeout in milliseconds
    pub batch_timeout_ms:   u64,
    /// Maximum retry attempts
    pub max_retries:        u32,
    /// Retry delay in milliseconds
    pub retry_delay_ms:     u64,
    /// Enable result caching
    pub caching_enabled:    bool,
    /// Cache TTL in seconds
    pub cache_ttl_s:        u64,
}

impl Default for InferenceEngineConfig {
    fn default() -> Self {
        Self {
            max_queue_depth:  10_000,
            max_concurrent:   16,
            batching_enabled: true,
            batch_timeout_ms: 10,
            max_retries:      3,
            retry_delay_ms:   100,
            caching_enabled:  true,
            cache_ttl_s:      300,
        }
    }
}

// ---------------------------------------------------------------------------
// Result cache
// ---------------------------------------------------------------------------

/// Cached inference result
#[derive(Debug, Clone)]
struct CachedResult {
    result:     InferenceResult,
    cached_at:  std::time::Instant,
    ttl_s:      u64,
    hit_count:  u64,
}

impl CachedResult {
    fn is_expired(&self) -> bool {
        self.cached_at.elapsed().as_secs() > self.ttl_s
    }
}

/// Simple inference result cache (keyed by request hash)
#[derive(Debug, Default)]
struct ResultCache {
    entries:    HashMap<u64, CachedResult>,
    hits:       u64,
    misses:     u64,
    evictions:  u64,
}

impl ResultCache {
    fn new() -> Self { Self::default() }

    fn get(&mut self, key: u64) -> Option<InferenceResult> {
        if let Some(entry) = self.entries.get_mut(&key) {
            if entry.is_expired() {
                self.entries.remove(&key);
                self.evictions += 1;
                self.misses += 1;
                return None;
            }
            entry.hit_count += 1;
            self.hits += 1;
            return Some(entry.result.clone());
        }
        self.misses += 1;
        None
    }

    fn insert(&mut self, key: u64, result: InferenceResult, ttl_s: u64) {
        self.entries.insert(key, CachedResult {
            result,
            cached_at: std::time::Instant::now(),
            ttl_s,
            hit_count: 0,
        });
    }

    fn hit_rate(&self) -> f64 {
        let total = self.hits + self.misses;
        if total == 0 { return 0.0; }
        self.hits as f64 / total as f64
    }

    fn purge_expired(&mut self) {
        let expired: Vec<u64> = self.entries.iter()
            .filter(|(_, e)| e.is_expired())
            .map(|(&k, _)| k)
            .collect();
        for key in expired {
            self.entries.remove(&key);
            self.evictions += 1;
        }
    }
}

// ---------------------------------------------------------------------------
// Inference engine inner state
// ---------------------------------------------------------------------------

struct EngineInner {
    config:       InferenceEngineConfig,
    queue:        VecDeque<ZInferenceId>,
    jobs:         HashMap<ZInferenceId, InferenceJob>,
    active_jobs:  HashMap<ZInferenceId, InferenceJob>,
    completed:    Vec<InferenceJob>,
    batches:      HashMap<Uuid, InferenceBatch>,
    cache:        ResultCache,
    metrics:      InferenceMetrics,
    router:       HardwareRouter,
}

impl EngineInner {
    fn new(config: InferenceEngineConfig, router: HardwareRouter) -> Self {
        Self {
            config,
            queue:       VecDeque::new(),
            jobs:        HashMap::new(),
            active_jobs: HashMap::new(),
            completed:   Vec::new(),
            batches:     HashMap::new(),
            cache:       ResultCache::new(),
            metrics:     InferenceMetrics::new(),
            router,
        }
    }

    /// Compute a cache key for a request
    fn cache_key(request: &InferenceRequest) -> u64 {
        use std::hash::{Hash, Hasher};
        use std::collections::hash_map::DefaultHasher;
        let mut hasher = DefaultHasher::new();
        request.model_id.hash(&mut hasher);
        // Hash the operation type
        match &request.operation {
            InferenceOp::TextGeneration { prompt, .. } => prompt.hash(&mut hasher),
            InferenceOp::Embedding { text }            => text.hash(&mut hasher),
            InferenceOp::ClassifyIntent { description }=> description.hash(&mut hasher),
            _                                          => {},
        }
        hasher.finish()
    }
}

// ---------------------------------------------------------------------------
// Inference engine
// ---------------------------------------------------------------------------

/// The Zenith AI Inference Engine
///
/// Manages the full lifecycle of inference requests from submission
/// to result delivery, including batching, caching, and hardware routing.
#[derive(Clone)]
pub struct InferenceEngine {
    inner: Arc<RwLock<EngineInner>>,
}

impl InferenceEngine {
    /// Create a new inference engine
    pub fn new(config: InferenceEngineConfig, router: HardwareRouter) -> Self {
        Self {
            inner: Arc::new(RwLock::new(EngineInner::new(config, router))),
        }
    }

    /// Create with default configuration
    pub fn default_engine() -> Self {
        Self::new(InferenceEngineConfig::default(), HardwareRouter::new())
    }

    // ── Request submission ───────────────────────────────────────────────────

    /// Submit an inference request
    pub fn submit(&self, request: InferenceRequest) -> Result<ZInferenceId, AiCoreError> {
        let mut inner = self.inner.write();

        // Check queue capacity
        if inner.queue.len() >= inner.config.max_queue_depth {
            return Err(AiCoreError::QueueFull {
                depth: inner.queue.len(),
                max:   inner.config.max_queue_depth,
            });
        }

        // Check cache (for deterministic requests)
        if inner.config.caching_enabled {
            let key = EngineInner::cache_key(&request);
            if let Some(cached) = inner.cache.get(key) {
                inner.metrics.record_cache_hit();
                // Return a synthetic completed job
                let id = request.id;
                let mut job = InferenceJob::new(request);
                job.complete(cached);
                inner.completed.push(job);
                return Ok(id);
            }
        }

        let id = request.id;
        let job = InferenceJob::new(request);
        inner.queue.push_back(id);
        inner.jobs.insert(id, job);
        inner.metrics.record_submitted();

        Ok(id)
    }

    /// Submit multiple requests at once
    pub fn submit_batch(&self, requests: Vec<InferenceRequest>) -> Vec<Result<ZInferenceId, AiCoreError>> {
        requests.into_iter().map(|r| self.submit(r)).collect()
    }

    // ── Processing ───────────────────────────────────────────────────────────

    /// Process one pending request (call periodically)
    pub fn process_one(&self) -> Option<ZInferenceId> {
        let mut inner = self.inner.write();

        // Check concurrent limit
        if inner.active_jobs.len() >= inner.config.max_concurrent {
            return None;
        }

        let id = inner.queue.pop_front()?;
        let mut job = inner.jobs.remove(&id)?;

        // Route to hardware
        let hardware = inner.router.route(&job.request);
        job.start(hardware.clone());

        // Execute (simulated)
        let result = Self::execute_simulated(&job.request, &hardware);
        let execution_ms = job.started_at.map(|s| s.elapsed().as_millis() as u32).unwrap_or(42);

        // Cache result if applicable
        if inner.config.caching_enabled {
            let key = EngineInner::cache_key(&job.request);
            inner.cache.insert(key, result.clone(), inner.config.cache_ttl_s);
        }

        job.complete(result);
        inner.metrics.record_completed(execution_ms);

        let completed_id = job.id;
        inner.completed.push(job);

        Some(completed_id)
    }

    /// Process all pending requests
    pub fn drain(&self) -> usize {
        let mut count = 0;
        while self.process_one().is_some() {
            count += 1;
        }
        count
    }

    /// Simulated inference execution
    fn execute_simulated(request: &InferenceRequest, hardware: &InferenceHardware) -> InferenceResult {
        match &request.operation {
            InferenceOp::TextGeneration { prompt, max_tokens, .. } => {
                InferenceResult::Text {
                    content: format!(
                        "[Zenith AI on {:?}] Response to: {}",
                        hardware,
                        &prompt[..prompt.len().min(80)]
                    ),
                    tokens_generated: (*max_tokens).min(256),
                    finish_reason: "stop".into(),
                }
            }
            InferenceOp::Embedding { text } => {
                InferenceResult::Embedding {
                    vector: vec![0.1f32; crate::DEFAULT_EMBEDDING_DIM],
                }
            }
            InferenceOp::ImageClassify { .. } => {
                InferenceResult::Classification {
                    label:      "document".into(),
                    confidence: 0.95,
                }
            }
            InferenceOp::Transcribe { .. } => {
                InferenceResult::Transcription {
                    text:     "Transcribed audio content".into(),
                    language: "en".into(),
                }
            }
            InferenceOp::Synthesize { text, voice } => {
                InferenceResult::Speech {
                    audio_bytes:  vec![0u8; 1024],
                    duration_ms:  (text.len() as u32 * 50).min(10_000),
                }
            }
            InferenceOp::CodeComplete { prefix, language, .. } => {
                InferenceResult::Code {
                    completion: format!("// AI completion for {language}\n// {prefix}"),
                    language:   language.clone(),
                }
            }
            InferenceOp::QuantumCircuit { shots, .. } => {
                let mut counts = std::collections::HashMap::new();
                counts.insert("00".into(), shots / 2);
                counts.insert("11".into(), shots / 2);
                InferenceResult::QuantumResult { counts, shots: *shots }
            }
            InferenceOp::ClassifyIntent { description } => {
                InferenceResult::IntentClass {
                    class:            "Productivity".into(),
                    confidence:       0.92,
                    suggested_domain: zenith_abi::domain::Domain::Windows,
                }
            }
        }
    }

    // ── Result retrieval ─────────────────────────────────────────────────────

    /// Get the result of a completed request
    pub fn get_result(&self, id: &ZInferenceId) -> Option<InferenceResult> {
        let inner = self.inner.read();
        inner.completed.iter()
            .find(|j| &j.id == id)
            .and_then(|j| j.result.clone())
    }

    /// Cancel a pending request
    pub fn cancel(&self, id: &ZInferenceId) -> bool {
        let mut inner = self.inner.write();
        inner.queue.retain(|&qid| &qid != id);
        if let Some(mut job) = inner.jobs.remove(id) {
            job.cancel();
            inner.completed.push(job);
            inner.metrics.record_cancelled();
            true
        } else {
            false
        }
    }

    // ── Diagnostics ──────────────────────────────────────────────────────────

    /// Queue depth
    pub fn queue_depth(&self) -> usize {
        self.inner.read().queue.len()
    }

    /// Active job count
    pub fn active_count(&self) -> usize {
        self.inner.read().active_jobs.len()
    }

    /// Completed job count
    pub fn completed_count(&self) -> usize {
        self.inner.read().completed.len()
    }

    /// Cache hit rate
    pub fn cache_hit_rate(&self) -> f64 {
        self.inner.read().cache.hit_rate()
    }

    /// Inference metrics
    pub fn metrics(&self) -> InferenceMetrics {
        self.inner.read().metrics.clone()
    }

    /// Purge expired cache entries
    pub fn purge_cache(&self) {
        self.inner.write().cache.purge_expired();
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;
    use zenith_abi::inference::InferenceOp;

    fn make_request(op: InferenceOp) -> InferenceRequest {
        InferenceRequest::new(
            Uuid::new_v4(), Uuid::new_v4(), Uuid::new_v4(), op,
        )
    }

    #[test]
    fn engine_submit_and_process() {
        let engine = InferenceEngine::default_engine();
        let req = make_request(InferenceOp::TextGeneration {
            prompt:      "Hello, Zenith!".into(),
            max_tokens:  128,
            temperature: 0.7,
        });
        let id = engine.submit(req).unwrap();
        assert_eq!(engine.queue_depth(), 1);
        engine.process_one();
        assert_eq!(engine.queue_depth(), 0);
        assert!(engine.get_result(&id).is_some());
    }

    #[test]
    fn engine_drain() {
        let engine = InferenceEngine::default_engine();
        for i in 0..5 {
            let req = make_request(InferenceOp::Embedding {
                text: format!("document {i}"),
            });
            engine.submit(req).unwrap();
        }
        let processed = engine.drain();
        assert_eq!(processed, 5);
        assert_eq!(engine.queue_depth(), 0);
    }

    #[test]
    fn engine_cancel() {
        let engine = InferenceEngine::default_engine();
        let req = make_request(InferenceOp::ClassifyIntent {
            description: "open excel".into(),
        });
        let id = engine.submit(req).unwrap();
        assert!(engine.cancel(&id));
        assert_eq!(engine.queue_depth(), 0);
    }

    #[test]
    fn engine_text_generation_result() {
        let engine = InferenceEngine::default_engine();
        let req = make_request(InferenceOp::TextGeneration {
            prompt:      "Analyze this contract".into(),
            max_tokens:  256,
            temperature: 0.5,
        });
        let id = engine.submit(req).unwrap();
        engine.process_one();
        let result = engine.get_result(&id).unwrap();
        assert!(matches!(result, InferenceResult::Text { .. }));
    }

    #[test]
    fn engine_embedding_result() {
        let engine = InferenceEngine::default_engine();
        let req = make_request(InferenceOp::Embedding {
            text: "Surface Zenith OS".into(),
        });
        let id = engine.submit(req).unwrap();
        engine.process_one();
        let result = engine.get_result(&id).unwrap();
        if let InferenceResult::Embedding { vector } = result {
            assert_eq!(vector.len(), crate::DEFAULT_EMBEDDING_DIM);
        } else {
            panic!("Expected embedding result");
        }
    }

    #[test]
    fn engine_queue_full() {
        let config = InferenceEngineConfig {
            max_queue_depth: 2,
            ..Default::default()
        };
        let engine = InferenceEngine::new(config, HardwareRouter::new());
        engine.submit(make_request(InferenceOp::Embedding { text: "a".into() })).unwrap();
        engine.submit(make_request(InferenceOp::Embedding { text: "b".into() })).unwrap();
        let result = engine.submit(make_request(InferenceOp::Embedding { text: "c".into() }));
        assert!(matches!(result, Err(AiCoreError::QueueFull { .. })));
    }

    #[test]
    fn engine_metrics_tracking() {
        let engine = InferenceEngine::default_engine();
        for _ in 0..3 {
            let req = make_request(InferenceOp::ClassifyIntent {
                description: "test".into(),
            });
            engine.submit(req).unwrap();
        }
        engine.drain();
        let metrics = engine.metrics();
        assert_eq!(metrics.total_submitted, 3);
        assert_eq!(metrics.total_completed, 3);
    }
}