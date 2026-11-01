//! # Tokenizer
//!
//! BPE-based tokenizer for the Zenith AI Core.

use std::collections::HashMap;

/// Token ID type
pub type TokenId = u32;

/// A simple BPE tokenizer (simplified implementation)
#[derive(Debug, Default)]
pub struct Tokenizer {
    vocab:         HashMap<String, TokenId>,
    reverse_vocab: HashMap<TokenId, String>,
    vocab_size:    usize,
    total_encoded: u64,
    total_decoded: u64,
}

impl Tokenizer {
    /// Create a new tokenizer with a basic vocabulary
    pub fn new() -> Self {
        let mut tokenizer = Self {
            vocab_size: 50_257, // GPT-2 compatible vocab size
            ..Default::default()
        };
        tokenizer.build_basic_vocab();
        tokenizer
    }

    fn build_basic_vocab(&mut self) {
        // Add special tokens
        let special_tokens = [
            ("<|endoftext|>", 50256u32),
            ("<|pad|>", 50257),
            ("<|unk|>", 50258),
            ("<|bos|>", 50259),
            ("<|eos|>", 50260),
        ];
        for (token, id) in &special_tokens {
            self.vocab.insert(token.to_string(), *id);
            self.reverse_vocab.insert(*id, token.to_string());
        }

        // Add common words (simplified)
        let common_words = [
            "the", "a", "an", "is", "are", "was", "were", "be", "been", "being",
            "have", "has", "had", "do", "does", "did", "will", "would", "could",
            "should", "may", "might", "shall", "can", "need", "dare", "ought",
            "and", "or", "but", "if", "then", "else", "when", "where", "how",
            "what", "which", "who", "whom", "whose", "that", "this", "these",
            "those", "it", "its", "they", "them", "their", "we", "our", "you",
            "your", "he", "she", "his", "her", "I", "my", "me", "mine",
            "zenith", "surface", "android", "windows", "domain", "intent",
            "scheduler", "memory", "quantum", "copilot", "ai", "kernel",
        ];

        for (i, word) in common_words.iter().enumerate() {
            let id = i as u32;
            self.vocab.insert(word.to_string(), id);
            self.reverse_vocab.insert(id, word.to_string());
        }
    }

    /// Encode text to token IDs (simplified word-level tokenization)
    pub fn encode(&mut self, text: &str) -> Vec<TokenId> {
        self.total_encoded += 1;
        let unk_id = *self.vocab.get("<|unk|>").unwrap_or(&50258);

        text.split_whitespace()
            .map(|word| {
                *self.vocab.get(&word.to_lowercase()).unwrap_or(&unk_id)
            })
            .collect()
    }

    /// Decode token IDs to text
    pub fn decode(&mut self, tokens: &[TokenId]) -> String {
        self.total_decoded += 1;
        tokens.iter()
            .filter_map(|id| self.reverse_vocab.get(id))
            .cloned()
            .collect::<Vec<_>>()
            .join(" ")
    }

    /// Count tokens in text (approximate)
    pub fn count_tokens(&self, text: &str) -> usize {
        // Approximate: 1 token ≈ 4 characters
        (text.len() + 3) / 4
    }

    /// Whether text fits within a context window
    pub fn fits_in_context(&self, text: &str, max_tokens: usize) -> bool {
        self.count_tokens(text) <= max_tokens
    }

    /// Truncate text to fit within a token limit
    pub fn truncate_to_tokens(&self, text: &str, max_tokens: usize) -> &str {
        let max_chars = max_tokens * 4;
        if text.len() <= max_chars {
            text
        } else {
            &text[..max_chars]
        }
    }

    pub fn vocab_size(&self) -> usize { self.vocab_size }
    pub fn total_encoded(&self) -> u64 { self.total_encoded }
    pub fn total_decoded(&self) -> u64 { self.total_decoded }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tokenizer_encode_decode() {
        let mut tok = Tokenizer::new();
        let text = "the zenith android windows";
        let tokens = tok.encode(text);
        assert!(!tokens.is_empty());
        let decoded = tok.decode(&tokens);
        assert!(!decoded.is_empty());
    }

    #[test]
    fn tokenizer_count_tokens() {
        let tok = Tokenizer::new();
        let text = "a".repeat(100);
        assert_eq!(tok.count_tokens(&text), 25);
    }

    #[test]
    fn tokenizer_fits_in_context() {
        let tok = Tokenizer::new();
        assert!(tok.fits_in_context("short text", 100));
        assert!(!tok.fits_in_context(&"x".repeat(10000), 100));
    }

    #[test]
    fn tokenizer_truncate() {
        let tok = Tokenizer::new();
        let long_text = "a".repeat(1000);
        let truncated = tok.truncate_to_tokens(&long_text, 10);
        assert!(truncated.len() <= 40);
    }
}