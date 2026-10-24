//! # AI Session Context Manager
//!
//! Manages conversation context and memory for AI sessions.

use std::collections::VecDeque;
use uuid::Uuid;
use serde::{Deserialize, Serialize};
use zenith_abi::types::{ZSessionId, ZIdentityId};

/// A single conversation turn
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConversationTurn {
    pub user_message:      String,
    pub assistant_response: String,
    pub timestamp:         std::time::Instant,
    pub tokens_used:       u32,
}

/// Session context for AI interactions
#[derive(Debug, Clone)]
pub struct SessionContext {
    pub session_id:   ZSessionId,
    pub identity_id:  ZIdentityId,
    pub turns:        Vec<(String, String)>, // (user, assistant)
    pub turn_history: VecDeque<ConversationTurn>,
    pub total_tokens: u64,
    pub created_at:   std::time::Instant,
    pub last_active:  std::time::Instant,
    pub metadata:     std::collections::HashMap<String, String>,
}

impl SessionContext {
    /// Create a new session context
    pub fn new(session_id: ZSessionId, identity_id: ZIdentityId) -> Self {
        Self {
            session_id,
            identity_id,
            turns:        Vec::new(),
            turn_history: VecDeque::new(),
            total_tokens: 0,
            created_at:   std::time::Instant::now(),
            last_active:  std::time::Instant::now(),
            metadata:     std::collections::HashMap::new(),
        }
    }

    /// Add a conversation turn
    pub fn add_turn(&mut self, user: String, assistant: String) {
        let tokens = (user.len() + assistant.len()) as u32 / 4;
        self.turns.push((user.clone(), assistant.clone()));
        self.turn_history.push_back(ConversationTurn {
            user_message:       user,
            assistant_response: assistant,
            timestamp:          std::time::Instant::now(),
            tokens_used:        tokens,
        });
        self.total_tokens += tokens as u64;
        self.last_active   = std::time::Instant::now();

        // Keep only last 50 turns in memory
        if self.turn_history.len() > 50 {
            self.turn_history.pop_front();
        }
        if self.turns.len() > 50 {
            self.turns.remove(0);
        }
    }

    /// Get the last N turns as a formatted string
    pub fn recent_context(&self, n: usize) -> String {
        self.turn_history.iter().rev().take(n).rev()
            .map(|t| format!("User: {}\nAssistant: {}", t.user_message, t.assistant_response))
            .collect::<Vec<_>>()
            .join("\n\n")
    }

    /// Total turns in this session
    pub fn turn_count(&self) -> usize { self.turns.len() }

    /// Session age in seconds
    pub fn age_s(&self) -> u64 { self.created_at.elapsed().as_secs() }

    /// Idle time in seconds
    pub fn idle_s(&self) -> u64 { self.last_active.elapsed().as_secs() }

    /// Set metadata
    pub fn set_metadata(&mut self, key: impl Into<String>, value: impl Into<String>) {
        self.metadata.insert(key.into(), value.into());
    }

    /// Estimated token count for the current context
    pub fn estimated_context_tokens(&self) -> u64 {
        self.total_tokens.min(crate::MAX_CONTEXT_TOKENS as u64)
    }

    /// Whether the context window is near capacity
    pub fn is_near_capacity(&self) -> bool {
        self.estimated_context_tokens() > (crate::MAX_CONTEXT_TOKENS as u64 * 9 / 10)
    }
}

/// Session context registry
#[derive(Debug, Default)]
pub struct SessionContextRegistry {
    contexts:    std::collections::HashMap<ZSessionId, SessionContext>,
    total_turns: u64,
}

impl SessionContextRegistry {
    pub fn new() -> Self { Self::default() }

    pub fn get_or_create(&mut self, session_id: ZSessionId, identity_id: ZIdentityId) -> &mut SessionContext {
        self.contexts.entry(session_id).or_insert_with(|| {
            SessionContext::new(session_id, identity_id)
        })
    }

    pub fn get(&self, session_id: &ZSessionId) -> Option<&SessionContext> {
        self.contexts.get(session_id)
    }

    pub fn get_mut(&mut self, session_id: &ZSessionId) -> Option<&mut SessionContext> {
        self.contexts.get_mut(session_id)
    }

    pub fn remove(&mut self, session_id: &ZSessionId) -> Option<SessionContext> {
        self.contexts.remove(session_id)
    }

    pub fn count(&self) -> usize { self.contexts.len() }

    pub fn total_turns(&self) -> u64 { self.total_turns }

    /// Evict idle sessions (idle > threshold_s seconds)
    pub fn evict_idle(&mut self, threshold_s: u64) -> usize {
        let to_evict: Vec<ZSessionId> = self.contexts.iter()
            .filter(|(_, ctx)| ctx.idle_s() > threshold_s)
            .map(|(&id, _)| id)
            .collect();
        let count = to_evict.len();
        for id in to_evict {
            self.contexts.remove(&id);
        }
        count
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn session_context_turns() {
        let mut ctx = SessionContext::new(Uuid::new_v4(), Uuid::new_v4());
        ctx.add_turn("Hello".into(), "Hi there!".into());
        ctx.add_turn("How are you?".into(), "I'm doing well.".into());
        assert_eq!(ctx.turn_count(), 2);
        assert!(ctx.total_tokens > 0);
    }

    #[test]
    fn session_context_recent() {
        let mut ctx = SessionContext::new(Uuid::new_v4(), Uuid::new_v4());
        for i in 0..5 {
            ctx.add_turn(format!("Q{i}"), format!("A{i}"));
        }
        let recent = ctx.recent_context(3);
        assert!(recent.contains("Q2") || recent.contains("Q3") || recent.contains("Q4"));
    }

    #[test]
    fn session_registry_get_or_create() {
        let mut registry = SessionContextRegistry::new();
        let session = Uuid::new_v4();
        let identity = Uuid::new_v4();
        registry.get_or_create(session, identity);
        registry.get_or_create(session, identity); // Should return existing
        assert_eq!(registry.count(), 1);
    }

    #[test]
    fn session_registry_evict_idle() {
        let mut registry = SessionContextRegistry::new();
        let s1 = Uuid::new_v4();
        let s2 = Uuid::new_v4();
        registry.get_or_create(s1, Uuid::new_v4());
        registry.get_or_create(s2, Uuid::new_v4());
        // Evict with threshold 0 (all sessions are "idle")
        let evicted = registry.evict_idle(0);
        assert_eq!(evicted, 2);
        assert_eq!(registry.count(), 0);
    }
}