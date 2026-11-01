//! # ZIB Topic Router
//!
//! The router maps incoming messages to the correct domain handlers
//! based on topic, domain affinity, and routing rules.

use std::collections::HashMap;
use zenith_abi::domain::Domain;
use crate::topics::Topic;
use crate::message::ZMessage;
use crate::error::ZibError;

/// A routing rule: maps a topic to a target domain
#[derive(Debug, Clone)]
pub struct RoutingRule {
    pub topic: Topic,
    pub target: Domain,
    pub priority: u8,
}

/// The topic router — determines where messages should be delivered
#[derive(Debug, Default)]
pub struct TopicRouter {
    rules: Vec<RoutingRule>,
    /// Default domain for topics with no explicit rule
    default_domain: Option<Domain>,
}

impl TopicRouter {
    /// Create a new router
    pub fn new() -> Self {
        Self::default()
    }

    /// Create a router with default Zenith routing rules
    pub fn with_zenith_defaults() -> Self {
        let mut router = Self::new();
        router.default_domain = Some(Domain::Windows);

        // Android domain handles mobile/telephony topics
        for topic in [Topic::SessionOpened, Topic::HingeAngleChanged] {
            router.add_rule(RoutingRule { topic, target: Domain::Android, priority: 100 });
        }

        // AI domain handles inference topics
        for topic in [Topic::InferenceRequest, Topic::CopilotIntentClassified,
                      Topic::QuantumCircuitSubmit] {
            router.add_rule(RoutingRule { topic, target: Domain::AI, priority: 200 });
        }

        // Windows domain handles productivity topics
        for topic in [Topic::IntentSubmit, Topic::IntentPlanned, Topic::IntentAssigned] {
            router.add_rule(RoutingRule { topic, target: Domain::Windows, priority: 150 });
        }

        // Broadcast topics (no specific target)
        for topic in [Topic::DomainHealth, Topic::Heartbeat, Topic::SecurityViolation,
                      Topic::MetricsSnapshot, Topic::ThermalThrottle] {
            router.add_rule(RoutingRule { topic, target: Domain::Windows, priority: 50 });
        }

        router
    }

    /// Add a routing rule
    pub fn add_rule(&mut self, rule: RoutingRule) {
        self.rules.push(rule);
        // Keep sorted by priority descending
        self.rules.sort_by(|a, b| b.priority.cmp(&a.priority));
    }

    /// Resolve the target domain for a message
    pub fn resolve(&self, msg: &ZMessage) -> Option<Domain> {
        // If message has explicit target, use it
        if let Some(target) = msg.target() {
            return Some(target.clone());
        }

        // Find highest-priority matching rule
        self.rules
            .iter()
            .find(|r| &r.topic == msg.topic())
            .map(|r| r.target.clone())
            .or_else(|| self.default_domain.clone())
    }

    /// Get all rules for a topic
    pub fn rules_for_topic(&self, topic: &Topic) -> Vec<&RoutingRule> {
        self.rules.iter().filter(|r| &r.topic == topic).collect()
    }

    /// Number of routing rules
    pub fn rule_count(&self) -> usize {
        self.rules.len()
    }
}

/// Domain affinity table — tracks which domains prefer which topics
#[derive(Debug, Default)]
pub struct AffinityTable {
    /// domain → set of preferred topics
    affinities: HashMap<String, Vec<Topic>>,
}

impl AffinityTable {
    pub fn new() -> Self { Self::default() }

    /// Register a domain's affinity for a topic
    pub fn register(&mut self, domain: Domain, topic: Topic) {
        self.affinities.entry(domain.name().to_string()).or_default().push(topic);
    }

    /// Get all topics a domain has affinity for
    pub fn topics_for_domain(&self, domain: &Domain) -> Vec<&Topic> {
        self.affinities
            .get(domain.name())
            .map(|v| v.iter().collect())
            .unwrap_or_default()
    }

    /// Get all domains with affinity for a topic
    pub fn domains_for_topic(&self, topic: &Topic) -> Vec<Domain> {
        self.affinities
            .iter()
            .filter(|(_, topics)| topics.contains(topic))
            .map(|(name, _)| match name.as_str() {
                "android"  => Domain::Android,
                "windows"  => Domain::Windows,
                "ai"       => Domain::AI,
                "quantum"  => Domain::Quantum,
                "realtime" => Domain::RealTime,
                "cloud"    => Domain::Cloud,
                other      => Domain::Custom(other.to_string()),
            })
            .collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use uuid::Uuid;

    #[test]
    fn router_resolves_explicit_target() {
        let router = TopicRouter::with_zenith_defaults();
        let msg = ZMessage::directed(
            Uuid::new_v4(), Domain::Android, Domain::AI,
            Topic::InferenceRequest, b"data".to_vec(),
        );
        assert_eq!(router.resolve(&msg), Some(Domain::AI));
    }

    #[test]
    fn router_resolves_by_rule() {
        let router = TopicRouter::with_zenith_defaults();
        let msg = ZMessage::broadcast(
            Uuid::new_v4(), Domain::Android,
            Topic::IntentSubmit, b"data".to_vec(),
        );
        assert_eq!(router.resolve(&msg), Some(Domain::Windows));
    }

    #[test]
    fn router_falls_back_to_default() {
        let router = TopicRouter::with_zenith_defaults();
        let msg = ZMessage::broadcast(
            Uuid::new_v4(), Domain::Android,
            Topic::Custom("unknown.topic".into()), b"data".to_vec(),
        );
        assert_eq!(router.resolve(&msg), Some(Domain::Windows));
    }

    #[test]
    fn affinity_table() {
        let mut table = AffinityTable::new();
        table.register(Domain::Android, Topic::HingeAngleChanged);
        table.register(Domain::Android, Topic::DeviceAcquired);
        table.register(Domain::AI, Topic::InferenceRequest);

        assert_eq!(table.topics_for_domain(&Domain::Android).len(), 2);
        assert_eq!(table.domains_for_topic(&Topic::InferenceRequest).len(), 1);
    }
}