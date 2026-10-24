//! # Retrieval-Augmented Generation (RAG) Engine
//!
//! Implements RAG for grounding AI responses in actual documents and data.

use std::collections::HashMap;
use uuid::Uuid;
use serde::{Deserialize, Serialize};
use crate::embedding::{Embedding, EmbeddingEngine};
use crate::error::AiCoreError;

/// A document chunk for RAG
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DocumentChunk {
    pub id:          Uuid,
    pub document_id: Uuid,
    pub content:     String,
    pub chunk_index: usize,
    pub metadata:    HashMap<String, String>,
    pub embedding:   Option<Vec<f32>>,
}

impl DocumentChunk {
    pub fn new(document_id: Uuid, content: impl Into<String>, chunk_index: usize) -> Self {
        Self {
            id:          Uuid::new_v4(),
            document_id,
            content:     content.into(),
            chunk_index,
            metadata:    HashMap::new(),
            embedding:   None,
        }
    }

    pub fn set_embedding(&mut self, embedding: Vec<f32>) {
        self.embedding = Some(embedding);
    }

    pub fn word_count(&self) -> usize {
        self.content.split_whitespace().count()
    }
}

/// A document in the RAG knowledge base
#[derive(Debug, Clone)]
pub struct RagDocument {
    pub id:       Uuid,
    pub name:     String,
    pub source:   String,
    pub chunks:   Vec<DocumentChunk>,
    pub metadata: HashMap<String, String>,
    pub added_at: std::time::Instant,
}

impl RagDocument {
    pub fn new(name: impl Into<String>, source: impl Into<String>) -> Self {
        Self {
            id:       Uuid::new_v4(),
            name:     name.into(),
            source:   source.into(),
            chunks:   Vec::new(),
            metadata: HashMap::new(),
            added_at: std::time::Instant::now(),
        }
    }

    /// Split document content into chunks
    pub fn chunk_content(&mut self, content: &str, chunk_size: usize, overlap: usize) {
        let words: Vec<&str> = content.split_whitespace().collect();
        let mut start = 0;
        let mut chunk_index = 0;

        while start < words.len() {
            let end = (start + chunk_size).min(words.len());
            let chunk_content = words[start..end].join(" ");
            let mut chunk = DocumentChunk::new(self.id, chunk_content, chunk_index);
            chunk.metadata.insert("source".into(), self.source.clone());
            self.chunks.push(chunk);
            chunk_index += 1;

            if end >= words.len() { break; }
            start = end.saturating_sub(overlap);
        }
    }

    pub fn chunk_count(&self) -> usize { self.chunks.len() }
}

/// RAG retrieval result
#[derive(Debug, Clone)]
pub struct RetrievalResult {
    pub chunk:      DocumentChunk,
    pub score:      f32,
    pub document:   String,
    pub rank:       usize,
}

/// The RAG Engine
#[derive(Debug)]
pub struct RagEngine {
    documents:       HashMap<Uuid, RagDocument>,
    embedding_engine: EmbeddingEngine,
    total_queries:   u64,
    total_retrieved: u64,
    chunk_size:      usize,
    overlap:         usize,
}

impl RagEngine {
    pub fn new() -> Self {
        Self {
            documents:        HashMap::new(),
            embedding_engine: EmbeddingEngine::default_engine(),
            total_queries:    0,
            total_retrieved:  0,
            chunk_size:       200,
            overlap:          50,
        }
    }

    /// Add a document to the knowledge base
    pub fn add_document(&mut self, name: impl Into<String>, source: impl Into<String>, content: &str) -> Uuid {
        let mut doc = RagDocument::new(name, source);
        doc.chunk_content(content, self.chunk_size, self.overlap);

        // Generate embeddings for all chunks
        for chunk in &mut doc.chunks {
            if let Ok(emb) = self.embedding_engine.embed_text(&chunk.content) {
                chunk.set_embedding(emb.vector);
            }
        }

        let id = doc.id;
        self.documents.insert(id, doc);
        id
    }

    /// Retrieve relevant chunks for a query
    pub fn retrieve(&mut self, query: &str, top_k: usize) -> Result<Vec<RetrievalResult>, AiCoreError> {
        self.total_queries += 1;

        // Generate query embedding
        let query_emb = self.embedding_engine.embed_text(query)?;

        // Score all chunks
        let mut scored: Vec<(f32, &DocumentChunk, &str)> = Vec::new();

        for doc in self.documents.values() {
            for chunk in &doc.chunks {
                if let Some(ref chunk_vec) = chunk.embedding {
                    let chunk_emb = Embedding::new(chunk_vec.clone(), "cached", chunk.content.len());
                    let score = query_emb.cosine_similarity(&chunk_emb);
                    scored.push((score, chunk, &doc.name));
                }
            }
        }

        // Sort by score descending
        scored.sort_by(|(a, _, _), (b, _, _)| b.partial_cmp(a).unwrap_or(std::cmp::Ordering::Equal));

        let results: Vec<RetrievalResult> = scored.into_iter()
            .take(top_k.min(crate::MAX_RAG_CHUNKS))
            .enumerate()
            .map(|(rank, (score, chunk, doc_name))| RetrievalResult {
                chunk:    chunk.clone(),
                score,
                document: doc_name.to_string(),
                rank,
            })
            .collect();

        self.total_retrieved += results.len() as u64;
        Ok(results)
    }

    /// Build a RAG-augmented prompt
    pub fn augment_prompt(&mut self, query: &str, base_prompt: &str) -> Result<String, AiCoreError> {
        let results = self.retrieve(query, 3)?;

        if results.is_empty() {
            return Ok(base_prompt.to_string());
        }

        let context = results.iter()
            .map(|r| format!("[From: {}]\n{}", r.document, r.chunk.content))
            .collect::<Vec<_>>()
            .join("\n\n---\n\n");

        Ok(format!(
            "Context from knowledge base:\n\n{}\n\n---\n\n{}\n\nBased on the context above, {}",
            context, base_prompt, query
        ))
    }

    /// Remove a document from the knowledge base
    pub fn remove_document(&mut self, id: &Uuid) -> bool {
        self.documents.remove(id).is_some()
    }

    pub fn document_count(&self) -> usize { self.documents.len() }
    pub fn total_chunks(&self) -> usize {
        self.documents.values().map(|d| d.chunk_count()).sum()
    }
    pub fn total_queries(&self) -> u64 { self.total_queries }
}

impl Default for RagEngine {
    fn default() -> Self { Self::new() }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rag_add_document() {
        let mut engine = RagEngine::new();
        let content = "Surface Zenith OS is a post-smartphone operating system. \
                       It uses Android and Windows as execution domains. \
                       The Intent Scheduler routes workloads to optimal hardware.";
        let id = engine.add_document("zenith-overview", "internal", content);
        assert_eq!(engine.document_count(), 1);
        assert!(engine.total_chunks() > 0);
    }

    #[test]
    fn rag_retrieve() {
        let mut engine = RagEngine::new();
        engine.add_document("doc1", "test",
            "The quantum computing module uses Q# for circuit execution. \
             Grover's algorithm provides quadratic speedup for search problems.");
        engine.add_document("doc2", "test",
            "The memory fabric uses Copy-on-Write pages for efficient sharing. \
             Dirty page tracking enables incremental migration.");

        let results = engine.retrieve("quantum circuits", 2).unwrap();
        assert!(!results.is_empty());
        assert!(results[0].score >= 0.0);
    }

    #[test]
    fn rag_augment_prompt() {
        let mut engine = RagEngine::new();
        engine.add_document("zenith", "docs",
            "The Zenith Intent Scheduler classifies user goals into IntentClass values.");
        let augmented = engine.augment_prompt("How does scheduling work?", "Explain the scheduler").unwrap();
        assert!(augmented.len() > "Explain the scheduler".len());
    }

    #[test]
    fn document_chunking() {
        let mut doc = RagDocument::new("test", "test-source");
        let content = "word ".repeat(500);
        doc.chunk_content(&content, 100, 20);
        assert!(doc.chunk_count() > 1);
    }

    #[test]
    fn rag_remove_document() {
        let mut engine = RagEngine::new();
        let id = engine.add_document("temp", "test", "temporary content");
        assert_eq!(engine.document_count(), 1);
        assert!(engine.remove_document(&id));
        assert_eq!(engine.document_count(), 0);
    }
}