//! # AI Core Metrics

use serde::{Deserialize, Serialize};

/// Inference metrics
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct InferenceMetrics {
    pub total_submitted:    u64,
    pub total_completed:    u64,
    pub total_failed:       u64,
    pub total_cancelled:    u64,
    pub total_tokens:       u64,
    pub total_latency_ms:   u64,
    pub cache_hits:         u64,
    pub cache_misses:       u64,
    pub npu_requests:       u64,
    pub gpu_requests:       u64,
    pub cpu_requests:       u64,
    pub qpu_requests:       u64,
    pub cloud_requests:     u64,
}

impl InferenceMetrics {
    pub fn new() -> Self { Self::default() }

    pub fn record_submitted(&mut self)              { self.total_submitted += 1; }
    pub fn record_completed(&mut self, latency_ms: u32) {
        self.total_completed += 1;
        self.total_latency_ms += latency_ms as u64;
    }
    pub fn record_failed(&mut self)                 { self.total_failed += 1; }
    pub fn record_cancelled(&mut self)              { self.total_cancelled += 1; }
    pub fn record_tokens(&mut self, count: u32)     { self.total_tokens += count as u64; }
    pub fn record_cache_hit(&mut self)              { self.cache_hits += 1; }
    pub fn record_cache_miss(&mut self)             { self.cache_misses += 1; }

    pub fn success_rate(&self) -> f64 {
        let total = self.total_completed + self.total_failed;
        if total == 0 { return 1.0; }
        self.total_completed as f64 / total as f64
    }

    pub fn avg_latency_ms(&self) -> f64 {
        if self.total_completed == 0 { return 0.0; }
        self.total_latency_ms as f64 / self.total_completed as f64
    }

    pub fn cache_hit_rate(&self) -> f64 {
        let total = self.cache_hits + self.cache_misses;
        if total == 0 { return 0.0; }
        self.cache_hits as f64 / total as f64
    }

    pub fn throughput_tps(&self, elapsed_s: f64) -> f64 {
        if elapsed_s == 0.0 { return 0.0; }
        self.total_tokens as f64 / elapsed_s
    }
}

/// AI Core overall metrics
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct AiCoreMetrics {
    pub inference:       InferenceMetrics,
    pub copilot_requests: u64,
    pub rag_queries:     u64,
    pub embeddings:      u64,
    pub classifications: u64,
    pub safety_blocks:   u64,
    pub stream_sessions: u64,
}

impl AiCoreMetrics {
    pub fn new() -> Self { Self::default() }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn inference_metrics_rates() {
        let mut m = InferenceMetrics::new();
        m.record_submitted();
        m.record_submitted();
        m.record_completed(100);
        m.record_failed();
        assert!((m.success_rate() - 0.5).abs() < 0.01);
        assert_eq!(m.avg_latency_ms(), 100.0);
    }

    #[test]
    fn inference_metrics_cache() {
        let mut m = InferenceMetrics::new();
        m.record_cache_hit();
        m.record_cache_hit();
        m.record_cache_miss();
        assert!((m.cache_hit_rate() - 2.0/3.0).abs() < 0.01);
    }
}