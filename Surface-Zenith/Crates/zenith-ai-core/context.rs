//! # Context Window Manager

use std::collections::VecDeque;
use serde::{Deserialize, Serialize};

/// A message in the context window
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ContextMessage {
    pub role:      String,
    pub content:   String,
    pub tokens:    usize,
    pub timestamp: std::time::Instant,
}

impl ContextMessage {
    pub fn system(content: impl Into<String>) -> Self {
        let content = content.into();
        let tokens = content.len() / 4;
        Self { role: "system".into(), content, tokens, timestamp: std::time::Instant::now() }
    }

    pub fn user(content: impl Into<String>) -> Self {
        let content = content.into();
        let tokens = content.len() / 4;
        Self { role: "user".into(), content, tokens, timestamp: std::time::Instant::now() }
    }

    pub fn assistant(content: impl Into<String>) -> Self {
        let content = content.into();
        let tokens = content.len() / 4;
        Self { role: "assistant".into(), content, tokens, timestamp: std::time::Instant::now() }
    }
}

/// Context window manager
#[derive(Debug)]
pub struct ContextWindow {
    messages:      VecDeque<ContextMessage>,
    max_tokens:    usize,
    current_tokens: usize,
    system_prompt: Option<ContextMessage>,
}

impl ContextWindow {
    pub fn new(max_tokens: usize) -> Self {
        Self {
            messages:       VecDeque::new(),
            max_tokens,
            current_tokens: 0,
            system_prompt:  None,
        }
    }

    pub fn with_system_prompt(mut self, prompt: impl Into<String>) -> Self {
        let msg = ContextMessage::system(prompt);
        self.current_tokens += msg.tokens;
        self.system_prompt = Some(msg);
        self
    }

    pub fn add_message(&mut self, message: ContextMessage) {
        // Evict old messages if needed
        while self.current_tokens + message.tokens > self.max_tokens && !self.messages.is_empty() {
            if let Some(evicted) = self.messages.pop_front() {
                self.current_tokens = self.current_tokens.saturating_sub(evicted.tokens);
            }
        }
        self.current_tokens += message.tokens;
        self.messages.push_back(message);
    }

    pub fn add_user(&mut self, content: impl Into<String>) {
        self.add_message(ContextMessage::user(content));
    }

    pub fn add_assistant(&mut self, content: impl Into<String>) {
        self.add_message(ContextMessage::assistant(content));
    }

    pub fn to_prompt_string(&self) -> String {
        let mut parts = Vec::new();
        if let Some(ref sys) = self.system_prompt {
            parts.push(format!("[System]: {}", sys.content));
        }
        for msg in &self.messages {
            parts.push(format!("[{}]: {}", msg.role, msg.content));
        }
        parts.join("\n")
    }

    pub fn message_count(&self) -> usize { self.messages.len() }
    pub fn current_tokens(&self) -> usize { self.current_tokens }
    pub fn remaining_tokens(&self) -> usize { self.max_tokens.saturating_sub(self.current_tokens) }
    pub fn utilization(&self) -> f64 {
        if self.max_tokens == 0 { return 0.0; }
        self.current_tokens as f64 / self.max_tokens as f64
    }
    pub fn is_near_capacity(&self) -> bool { self.utilization() > 0.9 }
    pub fn clear(&mut self) {
        self.messages.clear();
        self.current_tokens = self.system_prompt.as_ref().map(|s| s.tokens).unwrap_or(0);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn context_window_add_messages() {
        let mut ctx = ContextWindow::new(1000);
        ctx.add_user("Hello");
        ctx.add_assistant("Hi there!");
        assert_eq!(ctx.message_count(), 2);
    }

    #[test]
    fn context_window_eviction() {
        let mut ctx = ContextWindow::new(50); // Very small window
        for i in 0..20 {
            ctx.add_user(format!("Message {i} with some content to fill tokens"));
        }
        // Should have evicted old messages
        assert!(ctx.current_tokens() <= 50);
    }

    #[test]
    fn context_window_system_prompt() {
        let ctx = ContextWindow::new(1000)
            .with_system_prompt("You are Zenith Copilot.");
        assert!(ctx.system_prompt.is_some());
        let prompt = ctx.to_prompt_string();
        assert!(prompt.contains("Zenith Copilot"));
    }

    #[test]
    fn context_window_utilization() {
        let mut ctx = ContextWindow::new(100);
        ctx.add_user("a".repeat(200)); // 50 tokens
        assert!(ctx.utilization() > 0.0);
    }
}