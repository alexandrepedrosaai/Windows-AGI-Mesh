//! # AI Intent Classifier
//!
//! Classifies natural language intents using the on-device LLM.
//! Bridges the AI Core with the Zenith Intent Scheduler.

use serde::{Deserialize, Serialize};
use zenith_abi::intent::{Intent, IntentClass};
use zenith_abi::domain::Domain;

/// Classification confidence threshold
pub const MIN_CONFIDENCE: f32 = 0.6;

/// Classification result from the AI model
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AiClassificationResult {
    pub class:            IntentClass,
    pub confidence:       f32,
    pub suggested_domain: Domain,
    pub reasoning:        String,
    pub alternative_classes: Vec<(IntentClass, f32)>,
    pub latency_ms:       u32,
}

/// AI-powered intent classifier
#[derive(Debug, Default)]
pub struct AiIntentClassifier {
    total_classifications: u64,
    high_confidence_count: u64,
    low_confidence_count:  u64,
    avg_latency_ms:        f64,
}

impl AiIntentClassifier {
    pub fn new() -> Self { Self::default() }

    /// Classify an intent using AI (simulated)
    pub fn classify(&mut self, goal: &str) -> AiClassificationResult {
        let start = std::time::Instant::now();
        self.total_classifications += 1;

        // Keyword-based classification (mirrors Rust scheduler classifier)
        let lower = goal.to_lowercase();
        let (class, confidence, reasoning) = self.classify_by_keywords(&lower);
        let suggested_domain = class.preferred_domain();

        let latency_ms = start.elapsed().as_millis() as u32;
        let alpha = 0.1f64;
        self.avg_latency_ms = alpha * latency_ms as f64 + (1.0 - alpha) * self.avg_latency_ms;

        if confidence >= MIN_CONFIDENCE {
            self.high_confidence_count += 1;
        } else {
            self.low_confidence_count += 1;
        }

        AiClassificationResult {
            class,
            confidence,
            suggested_domain,
            reasoning,
            alternative_classes: Vec::new(),
            latency_ms,
        }
    }

    fn classify_by_keywords(&self, lower: &str) -> (IntentClass, f32, String) {
        if lower.contains("quantum") || lower.contains("qubit") || lower.contains("circuit") {
            (IntentClass::Quantum, 0.95, "Quantum computing keywords detected".into())
        } else if lower.contains("excel") || lower.contains("word") || lower.contains("document")
               || lower.contains("contract") || lower.contains("report") || lower.contains("analyze") {
            (IntentClass::Productivity, 0.90, "Productivity application keywords detected".into())
        } else if lower.contains("code") || lower.contains("compile") || lower.contains("debug")
               || lower.contains("function") || lower.contains("rust") || lower.contains("python") {
            (IntentClass::Development, 0.92, "Software development keywords detected".into())
        } else if lower.contains("message") || lower.contains("whatsapp") || lower.contains("email")
               || lower.contains("chat") || lower.contains("send") {
            (IntentClass::Messaging, 0.88, "Communication keywords detected".into())
        } else if lower.contains("call") || lower.contains("phone") || lower.contains("dial") {
            (IntentClass::Telephony, 0.91, "Telephony keywords detected".into())
        } else if lower.contains("copilot") || lower.contains("ai") || lower.contains("generate")
               || lower.contains("summarize") || lower.contains("translate") {
            (IntentClass::Inference, 0.89, "AI inference keywords detected".into())
        } else if lower.contains("music") || lower.contains("video") || lower.contains("play")
               || lower.contains("spotify") || lower.contains("netflix") {
            (IntentClass::Media, 0.87, "Media playback keywords detected".into())
        } else if lower.contains("sync") || lower.contains("cloud") || lower.contains("backup") {
            (IntentClass::CloudSync, 0.85, "Cloud synchronization keywords detected".into())
        } else {
            (IntentClass::Unknown, 0.50, "No clear classification found".into())
        }
    }

    /// Apply AI classification to an intent
    pub fn apply_to_intent(&mut self, intent: &mut Intent) -> AiClassificationResult {
        let result = self.classify(&intent.goal.clone());
        if result.confidence >= MIN_CONFIDENCE {
            intent.class = result.class.clone();
            if intent.preferred_domain.is_none() {
                intent.preferred_domain = Some(result.suggested_domain.clone());
            }
        }
        result
    }

    pub fn total_classifications(&self) -> u64 { self.total_classifications }
    pub fn high_confidence_rate(&self) -> f64 {
        if self.total_classifications == 0 { return 0.0; }
        self.high_confidence_count as f64 / self.total_classifications as f64
    }
    pub fn avg_latency_ms(&self) -> f64 { self.avg_latency_ms }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn classifier_quantum() {
        let mut clf = AiIntentClassifier::new();
        let result = clf.classify("run quantum circuit with 50 qubits");
        assert_eq!(result.class, IntentClass::Quantum);
        assert!(result.confidence > 0.9);
    }

    #[test]
    fn classifier_productivity() {
        let mut clf = AiIntentClassifier::new();
        let result = clf.classify("analyze this Excel spreadsheet");
        assert_eq!(result.class, IntentClass::Productivity);
    }

    #[test]
    fn classifier_development() {
        let mut clf = AiIntentClassifier::new();
        let result = clf.classify("compile and debug the Rust code");
        assert_eq!(result.class, IntentClass::Development);
    }

    #[test]
    fn classifier_unknown() {
        let mut clf = AiIntentClassifier::new();
        let result = clf.classify("xyzzy frobnicate the quux");
        assert_eq!(result.class, IntentClass::Unknown);
        assert!(result.confidence <= 0.6);
    }

    #[test]
    fn classifier_metrics() {
        let mut clf = AiIntentClassifier::new();
        clf.classify("open excel");
        clf.classify("play music");
        clf.classify("quantum circuit");
        assert_eq!(clf.total_classifications(), 3);
        assert!(clf.high_confidence_rate() > 0.0);
    }
}