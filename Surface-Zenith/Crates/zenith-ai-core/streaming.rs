//! # Streaming Inference Engine

use std::collections::HashMap;
use uuid::Uuid;
use serde::{Deserialize, Serialize};
use crate::error::AiCoreError;

/// A streaming token chunk
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StreamChunk {
    pub request_id:  Uuid,
    pub chunk_index: u32,
    pub token:       String,
    pub is_final:    bool,
    pub finish_reason: Option<String>,
    pub timestamp:   std::time::Instant,
}

impl StreamChunk {
    pub fn token(request_id: Uuid, index: u32, token: impl Into<String>) -> Self {
        Self {
            request_id,
            chunk_index: index,
            token: token.into(),
            is_final: false,
            finish_reason: None,
            timestamp: std::time::Instant::now(),
        }
    }

    pub fn final_chunk(request_id: Uuid, index: u32, reason: impl Into<String>) -> Self {
        Self {
            request_id,
            chunk_index: index,
            token: String::new(),
            is_final: true,
            finish_reason: Some(reason.into()),
            timestamp: std::time::Instant::now(),
        }
    }
}

/// A streaming session
#[derive(Debug)]
pub struct StreamSession {
    pub id:           Uuid,
    pub request_id:   Uuid,
    pub chunks:       Vec<StreamChunk>,
    pub complete:     bool,
    pub total_tokens: u32,
    pub started_at:   std::time::Instant,
}

impl StreamSession {
    pub fn new(request_id: Uuid) -> Self {
        Self {
            id:           Uuid::new_v4(),
            request_id,
            chunks:       Vec::new(),
            complete:     false,
            total_tokens: 0,
            started_at:   std::time::Instant::now(),
        }
    }

    pub fn add_chunk(&mut self, chunk: StreamChunk) {
        if chunk.is_final {
            self.complete = true;
        } else {
            self.total_tokens += 1;
        }
        self.chunks.push(chunk);
    }

    pub fn assembled_text(&self) -> String {
        self.chunks.iter()
            .filter(|c| !c.is_final)
            .map(|c| c.token.as_str())
            .collect::<Vec<_>>()
            .join("")
    }

    pub fn elapsed_ms(&self) -> u64 {
        self.started_at.elapsed().as_millis() as u64
    }

    pub fn tokens_per_second(&self) -> f64 {
        let elapsed_s = self.elapsed_ms() as f64 / 1000.0;
        if elapsed_s == 0.0 { return 0.0; }
        self.total_tokens as f64 / elapsed_s
    }
}

/// Streaming inference manager
#[derive(Debug, Default)]
pub struct StreamingManager {
    sessions:        HashMap<Uuid, StreamSession>,
    total_sessions:  u64,
    total_tokens:    u64,
}

impl StreamingManager {
    pub fn new() -> Self { Self::default() }

    /// Create a new streaming session
    pub fn create_session(&mut self, request_id: Uuid) -> Uuid {
        let session = StreamSession::new(request_id);
        let id = session.id;
        self.sessions.insert(id, session);
        self.total_sessions += 1;
        id
    }

    /// Simulate streaming a response
    pub fn stream_response(
        &mut self,
        session_id: Uuid,
        text: &str,
    ) -> Result<(), AiCoreError> {
        let session = self.sessions.get_mut(&session_id)
            .ok_or_else(|| AiCoreError::SessionNotFound { id: session_id.to_string() })?;

        // Stream word by word
        for (i, word) in text.split_whitespace().enumerate() {
            let chunk = StreamChunk::token(session.request_id, i as u32, format!("{word} "));
            session.add_chunk(chunk);
            self.total_tokens += 1;
        }

        // Add final chunk
        let final_idx = session.chunks.len() as u32;
        session.add_chunk(StreamChunk::final_chunk(session.request_id, final_idx, "stop"));
        Ok(())
    }

    /// Get assembled text for a session
    pub fn get_text(&self, session_id: &Uuid) -> Option<String> {
        self.sessions.get(session_id).map(|s| s.assembled_text())
    }

    /// Get all chunks for a session
    pub fn get_chunks(&self, session_id: &Uuid) -> Option<&[StreamChunk]> {
        self.sessions.get(session_id).map(|s| s.chunks.as_slice())
    }

    /// Whether a session is complete
    pub fn is_complete(&self, session_id: &Uuid) -> bool {
        self.sessions.get(session_id).map(|s| s.complete).unwrap_or(false)
    }

    /// Remove a completed session
    pub fn close_session(&mut self, session_id: &Uuid) -> bool {
        self.sessions.remove(session_id).is_some()
    }

    pub fn total_sessions(&self) -> u64 { self.total_sessions }
    pub fn total_tokens(&self) -> u64 { self.total_tokens }
    pub fn active_sessions(&self) -> usize { self.sessions.len() }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn streaming_session_lifecycle() {
        let mut mgr = StreamingManager::new();
        let request_id = Uuid::new_v4();
        let session_id = mgr.create_session(request_id);
        assert_eq!(mgr.active_sessions(), 1);

        mgr.stream_response(session_id, "Hello from Zenith AI").unwrap();
        assert!(mgr.is_complete(&session_id));

        let text = mgr.get_text(&session_id).unwrap();
        assert!(text.contains("Hello"));

        mgr.close_session(&session_id);
        assert_eq!(mgr.active_sessions(), 0);
    }

    #[test]
    fn streaming_chunk_assembly() {
        let mut session = StreamSession::new(Uuid::new_v4());
        session.add_chunk(StreamChunk::token(session.request_id, 0, "Hello "));
        session.add_chunk(StreamChunk::token(session.request_id, 1, "World"));
        session.add_chunk(StreamChunk::final_chunk(session.request_id, 2, "stop"));
        assert!(session.complete);
        assert_eq!(session.total_tokens, 2);
        assert!(session.assembled_text().contains("Hello"));
    }

    #[test]
    fn streaming_metrics() {
        let mut mgr = StreamingManager::new();
        for _ in 0..3 {
            let id = mgr.create_session(Uuid::new_v4());
            mgr.stream_response(id, "test response text").unwrap();
        }
        assert_eq!(mgr.total_sessions(), 3);
        assert!(mgr.total_tokens() > 0);
    }
}