//! # AI Safety Filter
//!
//! Content safety filtering for AI-generated responses.

use serde::{Deserialize, Serialize};

/// Safety category
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum SafetyCategory {
    Hate,
    Violence,
    SelfHarm,
    Sexual,
    Privacy,
    Misinformation,
    Malware,
    Safe,
}

/// Safety check result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SafetyResult {
    pub safe:       bool,
    pub category:   SafetyCategory,
    pub confidence: f32,
    pub reason:     Option<String>,
}

impl SafetyResult {
    pub fn safe() -> Self {
        Self { safe: true, category: SafetyCategory::Safe, confidence: 0.99, reason: None }
    }

    pub fn unsafe_content(category: SafetyCategory, reason: impl Into<String>) -> Self {
        Self { safe: false, category, confidence: 0.95, reason: Some(reason.into()) }
    }
}

/// AI Safety Filter
#[derive(Debug, Default)]
pub struct SafetyFilter {
    total_checks:   u64,
    blocked_count:  u64,
    allowed_count:  u64,
}

impl SafetyFilter {
    pub fn new() -> Self { Self::default() }

    /// Check if content is safe
    pub fn check(&mut self, content: &str) -> SafetyResult {
        self.total_checks += 1;
        let lower = content.to_lowercase();

        // Basic keyword-based safety check (production: use dedicated safety model)
        let unsafe_patterns = [
            ("hate", SafetyCategory::Hate),
            ("violence", SafetyCategory::Violence),
            ("malware", SafetyCategory::Malware),
        ];

        for (pattern, category) in &unsafe_patterns {
            if lower.contains(pattern) && lower.contains("how to") {
                self.blocked_count += 1;
                return SafetyResult::unsafe_content(
                    category.clone(),
                    format!("Potentially unsafe content detected: {pattern}"),
                );
            }
        }

        self.allowed_count += 1;
        SafetyResult::safe()
    }

    /// Check both input and output
    pub fn check_pair(&mut self, input: &str, output: &str) -> SafetyResult {
        let input_result = self.check(input);
        if !input_result.safe { return input_result; }
        self.check(output)
    }

    pub fn total_checks(&self) -> u64 { self.total_checks }
    pub fn blocked_count(&self) -> u64 { self.blocked_count }
    pub fn block_rate(&self) -> f64 {
        if self.total_checks == 0 { return 0.0; }
        self.blocked_count as f64 / self.total_checks as f64
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn safety_filter_safe_content() {
        let mut filter = SafetyFilter::new();
        let result = filter.check("Analyze this Excel spreadsheet for Q4 trends");
        assert!(result.safe);
        assert_eq!(result.category, SafetyCategory::Safe);
    }

    #[test]
    fn safety_filter_metrics() {
        let mut filter = SafetyFilter::new();
        filter.check("safe content");
        filter.check("another safe query");
        assert_eq!(filter.total_checks(), 2);
        assert_eq!(filter.allowed_count, 2);
    }
}