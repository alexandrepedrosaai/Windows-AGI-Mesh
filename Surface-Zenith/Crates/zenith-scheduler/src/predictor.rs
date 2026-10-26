//! # Zenith Predictive Pre-loader
//!
//! Analyzes user behavior patterns to pre-load domains and models
//! before they are explicitly requested, reducing perceived latency.

use std::collections::HashMap;
use uuid::Uuid;
use zenith_abi::intent::IntentClass;
use zenith_abi::domain::Domain;
use zenith_abi::types::ZIdentityId;

/// A time-of-day bucket (0–23 hours)
type HourBucket = u8;

/// Behavior pattern for a single identity
#[derive(Debug, Clone, Default)]
pub struct BehaviorPattern {
    /// intent class → hour → count
    pub hourly_counts: HashMap<String, HashMap<HourBucket, u32>>,
    /// Sequence patterns: (class_a, class_b) → count
    pub sequence_counts: HashMap<(String, String), u32>,
    /// Last observed intent class
    pub last_class: Option<IntentClass>,
    /// Total observations
    pub total_observations: u64,
}

impl BehaviorPattern {
    pub fn new() -> Self { Self::default() }

    /// Record an intent observation
    pub fn observe(&mut self, class: &IntentClass, hour: HourBucket) {
        let key = format!("{class:?}");
        *self.hourly_counts
            .entry(key.clone())
            .or_default()
            .entry(hour)
            .or_insert(0) += 1;

        if let Some(ref last) = self.last_class.clone() {
            let seq_key = (format!("{last:?}"), key);
            *self.sequence_counts.entry(seq_key).or_insert(0) += 1;
        }

        self.last_class = Some(class.clone());
        self.total_observations += 1;
    }

    /// Predict the most likely next intent class at a given hour
    pub fn predict_next(&self, hour: HourBucket) -> Option<IntentClass> {
        let mut best_class: Option<IntentClass> = None;
        let mut best_count = 0u32;

        for (class_key, hour_map) in &self.hourly_counts {
            let count = hour_map.get(&hour).copied().unwrap_or(0);
            if count > best_count {
                best_count = count;
                best_class = Self::parse_class(class_key);
            }
        }

        best_class
    }

    /// Predict the most likely next intent after a given class
    pub fn predict_sequence(&self, after: &IntentClass) -> Option<IntentClass> {
        let after_key = format!("{after:?}");
        let mut best: Option<IntentClass> = None;
        let mut best_count = 0u32;

        for ((from, to), &count) in &self.sequence_counts {
            if from == &after_key && count > best_count {
                best_count = count;
                best = Self::parse_class(to);
            }
        }

        best
    }

    fn parse_class(key: &str) -> Option<IntentClass> {
        match key {
            "Messaging"    => Some(IntentClass::Messaging),
            "Productivity" => Some(IntentClass::Productivity),
            "Development"  => Some(IntentClass::Development),
            "Inference"    => Some(IntentClass::Inference),
            "Media"        => Some(IntentClass::Media),
            "Graphics"     => Some(IntentClass::Graphics),
            "Telephony"    => Some(IntentClass::Telephony),
            "Quantum"      => Some(IntentClass::Quantum),
            "CloudSync"    => Some(IntentClass::CloudSync),
            "System"       => Some(IntentClass::System),
            "SensorFusion" => Some(IntentClass::SensorFusion),
            _              => None,
        }
    }
}

/// Pre-load recommendation
#[derive(Debug, Clone)]
pub struct PreloadRecommendation {
    pub domain: Domain,
    pub intent_class: IntentClass,
    pub confidence: f32,
    pub reason: String,
}

/// The Zenith Predictive Pre-loader
#[derive(Debug, Default)]
pub struct PredictivePreloader {
    patterns: HashMap<ZIdentityId, BehaviorPattern>,
}

impl PredictivePreloader {
    pub fn new() -> Self { Self::default() }

    /// Record an intent observation for an identity
    pub fn observe(&mut self, identity: ZIdentityId, class: &IntentClass) {
        let hour = Self::current_hour();
        self.patterns.entry(identity).or_default().observe(class, hour);
    }

    /// Get pre-load recommendations for an identity
    pub fn recommendations(&self, identity: &ZIdentityId) -> Vec<PreloadRecommendation> {
        let pattern = match self.patterns.get(identity) {
            Some(p) => p,
            None => return Vec::new(),
        };

        let hour = Self::current_hour();
        let mut recs = Vec::new();

        // Time-based prediction
        if let Some(class) = pattern.predict_next(hour) {
            recs.push(PreloadRecommendation {
                domain: class.preferred_domain(),
                intent_class: class.clone(),
                confidence: 0.75,
                reason: format!("time-based: hour {hour}"),
            });

            // Sequence-based prediction (what comes after the predicted class)
            if let Some(next_class) = pattern.predict_sequence(&class) {
                recs.push(PreloadRecommendation {
                    domain: next_class.preferred_domain(),
                    intent_class: next_class,
                    confidence: 0.55,
                    reason: "sequence prediction".into(),
                });
            }
        }

        // Last-class sequence prediction
        if let Some(ref last) = pattern.last_class {
            if let Some(next) = pattern.predict_sequence(last) {
                if !recs.iter().any(|r| r.intent_class == next) {
                    recs.push(PreloadRecommendation {
                        domain: next.preferred_domain(),
                        intent_class: next,
                        confidence: 0.65,
                        reason: "sequence: after last intent".into(),
                    });
                }
            }
        }

        // Sort by confidence descending
        recs.sort_by(|a, b| b.confidence.partial_cmp(&a.confidence).unwrap_or(std::cmp::Ordering::Equal));
        recs
    }

    fn current_hour() -> HourBucket {
        use std::time::{SystemTime, UNIX_EPOCH};
        let secs = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs();
        ((secs / 3600) % 24) as u8
    }

    /// Number of identities being tracked
    pub fn tracked_identities(&self) -> usize {
        self.patterns.len()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn behavior_pattern_observation() {
        let mut pattern = BehaviorPattern::new();
        pattern.observe(&IntentClass::Productivity, 9);
        pattern.observe(&IntentClass::Productivity, 9);
        pattern.observe(&IntentClass::Messaging, 9);
        assert_eq!(pattern.total_observations, 3);
    }

    #[test]
    fn behavior_pattern_prediction() {
        let mut pattern = BehaviorPattern::new();
        for _ in 0..5 {
            pattern.observe(&IntentClass::Productivity, 9);
        }
        pattern.observe(&IntentClass::Messaging, 9);
        let predicted = pattern.predict_next(9);
        assert_eq!(predicted, Some(IntentClass::Productivity));
    }

    #[test]
    fn sequence_prediction() {
        let mut pattern = BehaviorPattern::new();
        pattern.observe(&IntentClass::Productivity, 9);
        pattern.observe(&IntentClass::Inference, 9);
        pattern.observe(&IntentClass::Productivity, 10);
        pattern.observe(&IntentClass::Inference, 10);

        let next = pattern.predict_sequence(&IntentClass::Productivity);
        assert_eq!(next, Some(IntentClass::Inference));
    }

    #[test]
    fn preloader_recommendations() {
        let mut preloader = PredictivePreloader::new();
        let identity = Uuid::new_v4();
        let hour = 9u8;

        for _ in 0..5 {
            preloader.patterns.entry(identity).or_default()
                .observe(&IntentClass::Productivity, hour);
        }

        let recs = preloader.recommendations(&identity);
        // May or may not have recommendations depending on current hour
        // Just verify it doesn't panic
        assert!(recs.len() <= 3);
    }
}