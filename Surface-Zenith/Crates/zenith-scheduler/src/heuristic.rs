//! # Zenith Intent Score Heuristic
//!
//! The scoring formula determines which intent gets scheduled next.
//!
//! ## Formula
//!
//! ```text
//! score = (priority × 5)
//!       + (context  × 4)
//!       + (latency_inv × 2)
//!       - energy_cost
//!       + security_bonus
//!       + domain_affinity_bonus
//! ```
//!
//! Where:
//! - `priority`     = 0–255 (user-assigned importance)
//! - `context`      = 0–255 (how relevant to current session context)
//! - `latency_inv`  = 255 - latency_budget_ms.min(255) (lower budget = higher urgency)
//! - `energy_cost`  = 0–255 (estimated power consumption)
//! - `security_bonus` = 0–500 (elevated for security-critical intents)
//! - `domain_affinity_bonus` = 0–100 (bonus when preferred domain is available)

use zenith_abi::intent::{Intent, IntentClass};
use zenith_abi::domain::Domain;

// ---------------------------------------------------------------------------
// Score weights
// ---------------------------------------------------------------------------

/// Scoring weights for the ZIS heuristic
#[derive(Debug, Clone)]
pub struct ScoreWeights {
    pub priority_weight:        i64,
    pub context_weight:         i64,
    pub latency_inv_weight:     i64,
    pub energy_penalty:         i64,
    pub security_bonus_max:     i64,
    pub domain_affinity_bonus:  i64,
    pub starvation_increment:   i64,
}

impl Default for ScoreWeights {
    fn default() -> Self {
        Self {
            priority_weight:       5,
            context_weight:        4,
            latency_inv_weight:    2,
            energy_penalty:        1,
            security_bonus_max:    500,
            domain_affinity_bonus: 100,
            starvation_increment:  10,
        }
    }
}

// ---------------------------------------------------------------------------
// Score computation
// ---------------------------------------------------------------------------

/// Compute the scheduling score for an intent
///
/// Higher score = scheduled sooner.
pub fn compute_score(intent: &Intent, weights: &ScoreWeights, available_domains: &[Domain]) -> i64 {
    let p = intent.priority as i64;
    let c = intent.context_score as i64;
    let l = 255i64 - (intent.latency_budget_ms.min(255) as i64);
    let e = intent.energy_cost as i64;

    let base = (p * weights.priority_weight)
        + (c * weights.context_weight)
        + (l * weights.latency_inv_weight)
        - (e * weights.energy_penalty);

    // Security bonus for high-security intents
    let security_bonus = if intent.security_level >= 200 {
        weights.security_bonus_max
    } else if intent.security_level >= 100 {
        weights.security_bonus_max / 2
    } else {
        0
    };

    // Domain affinity bonus
    let affinity_bonus = if let Some(ref preferred) = intent.preferred_domain {
        if available_domains.contains(preferred) {
            weights.domain_affinity_bonus
        } else {
            0
        }
    } else {
        0
    };

    base + security_bonus + affinity_bonus
}

/// Compute score with default weights
pub fn compute_score_default(intent: &Intent, available_domains: &[Domain]) -> i64 {
    compute_score(intent, &ScoreWeights::default(), available_domains)
}

// ---------------------------------------------------------------------------
// Starvation prevention
// ---------------------------------------------------------------------------

/// Anti-starvation aging: increment score for intents waiting too long
///
/// Every `aging_period_ms` milliseconds an intent waits, its score
/// increases by `starvation_increment` to prevent indefinite deferral.
pub fn apply_aging(score: i64, wait_ms: u64, aging_period_ms: u64, increment: i64) -> i64 {
    if aging_period_ms == 0 {
        return score;
    }
    let periods = (wait_ms / aging_period_ms) as i64;
    score + (periods * increment)
}

// ---------------------------------------------------------------------------
// Domain routing score
// ---------------------------------------------------------------------------

/// Score a domain for executing a specific intent class
///
/// Returns a domain fitness score (higher = better fit).
pub fn domain_fitness(class: &IntentClass, domain: &Domain) -> u32 {
    match (class, domain) {
        // Perfect matches
        (IntentClass::Messaging,    Domain::Android)  => 100,
        (IntentClass::Telephony,    Domain::Android)  => 100,
        (IntentClass::SensorFusion, Domain::RealTime) => 100,
        (IntentClass::Productivity, Domain::Windows)  => 100,
        (IntentClass::Development,  Domain::Windows)  => 100,
        (IntentClass::Graphics,     Domain::Windows)  => 95,
        (IntentClass::Inference,    Domain::AI)       => 100,
        (IntentClass::Quantum,      Domain::Quantum)  => 100,
        (IntentClass::CloudSync,    Domain::Cloud)    => 100,

        // Good matches
        (IntentClass::Media,        Domain::Android)  => 85,
        (IntentClass::Media,        Domain::Windows)  => 80,
        (IntentClass::Inference,    Domain::Windows)  => 60,
        (IntentClass::Productivity, Domain::Android)  => 50,

        // Poor matches
        (IntentClass::Development,  Domain::Android)  => 20,
        (IntentClass::Telephony,    Domain::Windows)  => 10,

        // Unknown — let AI decide
        (IntentClass::Unknown,      Domain::AI)       => 70,
        (IntentClass::Unknown,      _)                => 30,

        // Default
        _                                             => 40,
    }
}

/// Select the best domain for an intent class from available domains
pub fn select_best_domain(class: &IntentClass, available: &[Domain]) -> Option<Domain> {
    available
        .iter()
        .max_by_key(|d| domain_fitness(class, d))
        .cloned()
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;
    use uuid::Uuid;
    use zenith_abi::intent::{Intent, IntentClass, IntentState};

    fn make_intent(priority: u8, context: u8, energy: u32, latency: u32) -> Intent {
        let mut i = Intent::new(
            Uuid::new_v4(), Uuid::new_v4(),
            "test goal", IntentClass::Productivity, priority,
        );
        i.context_score    = context;
        i.energy_cost      = energy;
        i.latency_budget_ms = latency;
        i
    }

    #[test]
    fn high_priority_scores_higher() {
        let high = make_intent(200, 128, 50, 100);
        let low  = make_intent(10,  128, 50, 100);
        let domains = vec![Domain::Windows];
        assert!(
            compute_score_default(&high, &domains) >
            compute_score_default(&low,  &domains)
        );
    }

    #[test]
    fn low_energy_scores_higher() {
        let efficient = make_intent(128, 128, 10,  100);
        let expensive = make_intent(128, 128, 200, 100);
        let domains = vec![Domain::Windows];
        assert!(
            compute_score_default(&efficient, &domains) >
            compute_score_default(&expensive, &domains)
        );
    }

    #[test]
    fn tight_latency_scores_higher() {
        let urgent  = make_intent(128, 128, 50, 10);
        let relaxed = make_intent(128, 128, 50, 200);
        let domains = vec![Domain::Windows];
        assert!(
            compute_score_default(&urgent,  &domains) >
            compute_score_default(&relaxed, &domains)
        );
    }

    #[test]
    fn domain_affinity_bonus_applied() {
        let mut intent = make_intent(128, 128, 50, 100);
        intent.preferred_domain = Some(Domain::Windows);
        let with_domain    = compute_score_default(&intent, &[Domain::Windows]);
        let without_domain = compute_score_default(&intent, &[Domain::Android]);
        assert!(with_domain > without_domain);
    }

    #[test]
    fn starvation_aging() {
        let base_score = 1000i64;
        let aged = apply_aging(base_score, 5000, 1000, 10);
        assert_eq!(aged, 1050); // 5 periods × 10 increment
    }

    #[test]
    fn domain_fitness_perfect_matches() {
        assert_eq!(domain_fitness(&IntentClass::Messaging,    &Domain::Android), 100);
        assert_eq!(domain_fitness(&IntentClass::Productivity, &Domain::Windows), 100);
        assert_eq!(domain_fitness(&IntentClass::Inference,    &Domain::AI),      100);
        assert_eq!(domain_fitness(&IntentClass::Quantum,      &Domain::Quantum), 100);
    }

    #[test]
    fn select_best_domain_productivity() {
        let available = vec![Domain::Android, Domain::Windows, Domain::AI];
        let best = select_best_domain(&IntentClass::Productivity, &available);
        assert_eq!(best, Some(Domain::Windows));
    }

    #[test]
    fn select_best_domain_inference() {
        let available = vec![Domain::Android, Domain::Windows, Domain::AI];
        let best = select_best_domain(&IntentClass::Inference, &available);
        assert_eq!(best, Some(Domain::AI));
    }
}