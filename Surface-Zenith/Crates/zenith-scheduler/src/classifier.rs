//! # Zenith Intent Classifier
//!
//! Classifies natural-language intent descriptions into IntentClass values.
//! In production this would use an on-device LLM (Phi-4 via NPU).
//! This implementation uses a keyword-based rule engine as a deterministic
//! fallback that works without a model loaded.

use zenith_abi::intent::{Intent, IntentClass};
use zenith_abi::domain::Domain;

// ---------------------------------------------------------------------------
// Keyword rules
// ---------------------------------------------------------------------------

/// A classification rule: if any keyword matches, assign the class
struct ClassificationRule {
    class: IntentClass,
    keywords: &'static [&'static str],
    confidence: f32,
}

/// Static keyword rule table
static RULES: &[ClassificationRule] = &[
    ClassificationRule {
        class: IntentClass::Messaging,
        keywords: &["message", "chat", "whatsapp", "telegram", "sms", "text",
                    "send", "reply", "inbox", "email", "mail", "teams", "slack"],
        confidence: 0.85,
    },
    ClassificationRule {
        class: IntentClass::Telephony,
        keywords: &["call", "phone", "dial", "voip", "video call", "facetime",
                    "ring", "answer", "hang up", "conference call"],
        confidence: 0.90,
    },
    ClassificationRule {
        class: IntentClass::Productivity,
        keywords: &["excel", "word", "document", "spreadsheet", "powerpoint",
                    "presentation", "pdf", "contract", "report", "analyze",
                    "compare", "edit", "write", "draft", "table", "formula",
                    "outlook", "calendar", "meeting", "schedule"],
        confidence: 0.88,
    },
    ClassificationRule {
        class: IntentClass::Development,
        keywords: &["code", "compile", "build", "debug", "visual studio",
                    "git", "deploy", "test", "run", "execute", "script",
                    "program", "function", "class", "api", "sdk", "cargo",
                    "npm", "python", "rust", "typescript", "c++", "java"],
        confidence: 0.92,
    },
    ClassificationRule {
        class: IntentClass::Graphics,
        keywords: &["photoshop", "illustrator", "render", "design", "image",
                    "photo", "edit photo", "3d", "blender", "figma", "sketch",
                    "draw", "paint", "vector", "texture", "shader"],
        confidence: 0.87,
    },
    ClassificationRule {
        class: IntentClass::Inference,
        keywords: &["copilot", "ai", "generate", "summarize", "translate",
                    "classify", "predict", "recommend", "gpt", "llm",
                    "inference", "model", "neural", "machine learning",
                    "recognize", "detect", "transcribe", "synthesize"],
        confidence: 0.91,
    },
    ClassificationRule {
        class: IntentClass::Media,
        keywords: &["play", "music", "video", "stream", "spotify", "netflix",
                    "youtube", "podcast", "audio", "movie", "song", "playlist",
                    "watch", "listen", "media"],
        confidence: 0.89,
    },
    ClassificationRule {
        class: IntentClass::SensorFusion,
        keywords: &["sensor", "accelerometer", "gyroscope", "location", "gps",
                    "compass", "barometer", "ar", "augmented reality",
                    "motion", "orientation", "imu"],
        confidence: 0.86,
    },
    ClassificationRule {
        class: IntentClass::Quantum,
        keywords: &["quantum", "qubit", "circuit", "qasm", "superposition",
                    "entanglement", "qpu", "quantum computing", "q#",
                    "quantum key", "qkd", "quantum algorithm"],
        confidence: 0.95,
    },
    ClassificationRule {
        class: IntentClass::CloudSync,
        keywords: &["sync", "upload", "download", "backup", "cloud", "onedrive",
                    "sharepoint", "azure", "s3", "dropbox", "google drive",
                    "synchronize", "replicate"],
        confidence: 0.84,
    },
    ClassificationRule {
        class: IntentClass::System,
        keywords: &["settings", "configure", "install", "update", "restart",
                    "shutdown", "permission", "security", "firewall", "network",
                    "wifi", "bluetooth", "display", "battery", "storage"],
        confidence: 0.83,
    },
];

// ---------------------------------------------------------------------------
// Classification result
// ---------------------------------------------------------------------------

/// Result of intent classification
#[derive(Debug, Clone)]
pub struct ClassificationResult {
    /// Assigned intent class
    pub class: IntentClass,
    /// Confidence score (0.0–1.0)
    pub confidence: f32,
    /// Suggested execution domain
    pub suggested_domain: Domain,
    /// All matching classes with their scores (for debugging)
    pub candidates: Vec<(IntentClass, f32)>,
}

// ---------------------------------------------------------------------------
// Classifier
// ---------------------------------------------------------------------------

/// Keyword-based intent classifier (deterministic fallback)
pub struct IntentClassifier;

impl IntentClassifier {
    /// Classify an intent from its goal description
    pub fn classify(goal: &str) -> ClassificationResult {
        let lower = goal.to_lowercase();
        let mut candidates: Vec<(IntentClass, f32)> = Vec::new();

        for rule in RULES {
            let match_count = rule.keywords.iter()
                .filter(|&&kw| lower.contains(kw))
                .count();

            if match_count > 0 {
                // Scale confidence by number of keyword matches
                let scaled = rule.confidence
                    * (1.0 + (match_count as f32 - 1.0) * 0.05).min(1.2);
                candidates.push((rule.class.clone(), scaled.min(1.0)));
            }
        }

        // Sort by confidence descending
        candidates.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap_or(std::cmp::Ordering::Equal));

        let (class, confidence) = candidates.first()
            .cloned()
            .unwrap_or((IntentClass::Unknown, 0.5));

        let suggested_domain = class.preferred_domain();

        ClassificationResult {
            class,
            confidence,
            suggested_domain,
            candidates,
        }
    }

    /// Apply classification result to an intent
    pub fn apply(intent: &mut Intent, result: &ClassificationResult) {
        intent.class = result.class.clone();
        if intent.preferred_domain.is_none() {
            intent.preferred_domain = Some(result.suggested_domain.clone());
        }
    }

    /// Classify and apply in one step
    pub fn classify_and_apply(intent: &mut Intent) -> ClassificationResult {
        let result = Self::classify(&intent.goal.clone());
        Self::apply(intent, &result);
        result
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn classify_productivity() {
        let result = IntentClassifier::classify("analyze this contract and compare with Excel Q4");
        assert_eq!(result.class, IntentClass::Productivity);
        assert!(result.confidence > 0.8);
        assert_eq!(result.suggested_domain, Domain::Windows);
    }

    #[test]
    fn classify_inference() {
        let result = IntentClassifier::classify("use Copilot to summarize this document");
        assert_eq!(result.class, IntentClass::Inference);
        assert!(result.confidence > 0.8);
    }

    #[test]
    fn classify_quantum() {
        let result = IntentClassifier::classify("run quantum circuit with 50 qubits");
        assert_eq!(result.class, IntentClass::Quantum);
        assert!(result.confidence > 0.9);
        assert_eq!(result.suggested_domain, Domain::Quantum);
    }

    #[test]
    fn classify_messaging() {
        let result = IntentClassifier::classify("send a WhatsApp message to Alice");
        assert_eq!(result.class, IntentClass::Messaging);
        assert_eq!(result.suggested_domain, Domain::Android);
    }

    #[test]
    fn classify_development() {
        let result = IntentClassifier::classify("compile and run the Rust project");
        assert_eq!(result.class, IntentClass::Development);
        assert_eq!(result.suggested_domain, Domain::Windows);
    }

    #[test]
    fn classify_unknown_falls_back() {
        let result = IntentClassifier::classify("do something completely unrecognized xyz123");
        assert_eq!(result.class, IntentClass::Unknown);
        assert_eq!(result.confidence, 0.5);
    }

    #[test]
    fn classify_and_apply_updates_intent() {
        let mut intent = Intent::new(
            uuid::Uuid::new_v4(), uuid::Uuid::new_v4(),
            "play music on Spotify", IntentClass::Unknown, 128,
        );
        let result = IntentClassifier::classify_and_apply(&mut intent);
        assert_eq!(intent.class, IntentClass::Media);
        assert_eq!(intent.preferred_domain, Some(Domain::Android));
    }

    #[test]
    fn multi_keyword_boosts_confidence() {
        let single = IntentClassifier::classify("excel");
        let multi  = IntentClassifier::classify("excel spreadsheet analyze compare report");
        assert!(multi.confidence >= single.confidence);
    }
}
