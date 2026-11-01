//! # Embedding Engine
//!
//! Generates vector embeddings for text, images, and code.
//! Used by the RAG system and semantic search.

use std::collections::HashMap;
use uuid::Uuid;
use serde::{Deserialize, Serialize};
use crate::error::AiCoreError;

/// An embedding vector
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Embedding {
    pub id:        Uuid,
    pub vector:    Vec<f32>,
    pub dimension: usize,
    pub model:     String,
    pub input_len: usize,
    pub created_at: std::time::Instant,
}

impl Embedding {
    pub fn new(vector: Vec<f32>, model: impl Into<String>, input_len: usize) -> Self {
        let dimension = vector.len();
        Self {
            id: Uuid::new_v4(),
            vector,
            dimension,
            model: model.into(),
            input_len,
            created_at: std::time::Instant::now(),
        }
    }

    /// Cosine similarity with another embedding
    pub fn cosine_similarity(&self, other: &Embedding) -> f32 {
        if self.dimension != other.dimension { return 0.0; }
        let dot: f32 = self.vector.iter().zip(&other.vector).map(|(a, b)| a * b).sum();
        let norm_a: f32 = self.vector.iter().map(|x| x * x).sum::<f32>().sqrt();
        let norm_b: f32 = other.vector.iter().map(|x| x * x).sum::<f32>().sqrt();
        if norm_a == 0.0 || norm_b == 0.0 { return 0.0; }
        dot / (norm_a * norm_b)
    }

    /// Euclidean distance to another embedding
    pub fn euclidean_distance(&self, other: &Embedding) -> f32 {
        if self.dimension != other.dimension { return f32::MAX; }
        self.vector.iter().zip(&other.vector)
            .map(|(a, b)| (a - b).powi(2))
            .sum::<f32>()
            .sqrt()
    }

    /// L2 normalize this embedding
    pub fn normalize(&mut self) {
        let norm: f32 = self.vector.iter().map(|x| x * x).sum::<f32>().sqrt();
        if norm > 0.0 {
            for x in &mut self.vector {
                *x /= norm;
            }
        }
    }
}

/// Embedding engine
#[derive(Debug, Default)]
pub struct EmbeddingEngine {
    model_name:    String,
    dimension:     usize,
    total_requests: u64,
    total_tokens:  u64,
    cache:         HashMap<u64, Embedding>,
    cache_hits:    u64,
    cache_misses:  u64,
}

impl EmbeddingEngine {
    pub fn new(model_name: impl Into<String>, dimension: usize) -> Self {
        Self {
            model_name: model_name.into(),
            dimension,
            ..Default::default()
        }
    }

    pub fn default_engine() -> Self {
        Self::new("E5-Large-v2", crate::DEFAULT_EMBEDDING_DIM)
    }

    /// Generate an embedding for text
    pub fn embed_text(&mut self, text: &str) -> Result<Embedding, AiCoreError> {
        self.total_requests += 1;
        self.total_tokens += (text.len() / 4) as u64;

        // Check cache
        let cache_key = self.hash_text(text);
        if let Some(cached) = self.cache.get(&cache_key) {
            self.cache_hits += 1;
            return Ok(cached.clone());
        }
        self.cache_misses += 1;

        // Generate simulated embedding
        let vector = self.generate_simulated_embedding(text);
        let mut embedding = Embedding::new(vector, &self.model_name, text.len());
        embedding.normalize();

        self.cache.insert(cache_key, embedding.clone());
        Ok(embedding)
    }

    /// Generate embeddings for multiple texts (batch)
    pub fn embed_batch(&mut self, texts: &[&str]) -> Result<Vec<Embedding>, AiCoreError> {
        texts.iter().map(|t| self.embed_text(t)).collect()
    }

    /// Find the most similar embedding from a list
    pub fn most_similar<'a>(&self, query: &Embedding, candidates: &'a [Embedding]) -> Option<(&'a Embedding, f32)> {
        candidates.iter()
            .map(|e| (e, query.cosine_similarity(e)))
            .max_by(|(_, a), (_, b)| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal))
    }

    /// Find top-k most similar embeddings
    pub fn top_k_similar<'a>(&self, query: &Embedding, candidates: &'a [Embedding], k: usize) -> Vec<(&'a Embedding, f32)> {
        let mut scored: Vec<(&Embedding, f32)> = candidates.iter()
            .map(|e| (e, query.cosine_similarity(e)))
            .collect();
        scored.sort_by(|(_, a), (_, b)| b.partial_cmp(a).unwrap_or(std::cmp::Ordering::Equal));
        scored.into_iter().take(k).collect()
    }

    /// Generate a deterministic simulated embedding from text
    fn generate_simulated_embedding(&self, text: &str) -> Vec<f32> {
        let mut vector = vec![0.0f32; self.dimension];
        for (i, byte) in text.bytes().enumerate() {
            let idx = (i * 7 + byte as usize) % self.dimension;
            vector[idx] += (byte as f32 - 128.0) / 128.0;
        }
        vector
    }

    fn hash_text(&self, text: &str) -> u64 {
        use std::hash::{Hash, Hasher};
        use std::collections::hash_map::DefaultHasher;
        let mut hasher = DefaultHasher::new();
        text.hash(&mut hasher);
        hasher.finish()
    }

    pub fn total_requests(&self) -> u64 { self.total_requests }
    pub fn cache_hit_rate(&self) -> f64 {
        let total = self.cache_hits + self.cache_misses;
        if total == 0 { return 0.0; }
        self.cache_hits as f64 / total as f64
    }
    pub fn dimension(&self) -> usize { self.dimension }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn embedding_cosine_similarity() {
        let e1 = Embedding::new(vec![1.0, 0.0, 0.0], "test", 3);
        let e2 = Embedding::new(vec![1.0, 0.0, 0.0], "test", 3);
        let e3 = Embedding::new(vec![0.0, 1.0, 0.0], "test", 3);
        assert!((e1.cosine_similarity(&e2) - 1.0).abs() < 0.001);
        assert!((e1.cosine_similarity(&e3)).abs() < 0.001);
    }

    #[test]
    fn embedding_engine_generate() {
        let mut engine = EmbeddingEngine::default_engine();
        let emb = engine.embed_text("Surface Zenith OS").unwrap();
        assert_eq!(emb.dimension, crate::DEFAULT_EMBEDDING_DIM);
        assert_eq!(emb.vector.len(), crate::DEFAULT_EMBEDDING_DIM);
    }

    #[test]
    fn embedding_engine_cache() {
        let mut engine = EmbeddingEngine::default_engine();
        engine.embed_text("test text").unwrap();
        engine.embed_text("test text").unwrap(); // Should hit cache
        assert!(engine.cache_hit_rate() > 0.0);
    }

    #[test]
    fn embedding_top_k_similar() {
        let mut engine = EmbeddingEngine::default_engine();
        let query = engine.embed_text("quantum computing").unwrap();
        let candidates = vec![
            engine.embed_text("quantum circuits").unwrap(),
            engine.embed_text("machine learning").unwrap(),
            engine.embed_text("quantum entanglement").unwrap(),
        ];
        let top2 = engine.top_k_similar(&query, &candidates, 2);
        assert_eq!(top2.len(), 2);
    }

    #[test]
    fn embedding_normalize() {
        let mut emb = Embedding::new(vec![3.0, 4.0], "test", 2);
        emb.normalize();
        let norm: f32 = emb.vector.iter().map(|x| x * x).sum::<f32>().sqrt();
        assert!((norm - 1.0).abs() < 0.001);
    }
}