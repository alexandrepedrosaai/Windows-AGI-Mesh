//! # ZIB Subscription Management
//!
//! Subscription registry and lifecycle management for ZenithBus subscribers.

use std::collections::HashMap;
use uuid::Uuid;
use zenith_abi::domain::Domain;
use crate::topics::Topic;

/// Subscription metadata record
#[derive(Debug, Clone)]
pub struct SubscriptionRecord {
    pub id: Uuid,
    pub topic: Topic,
    pub domain: Domain,
    pub created_at: std::time::Instant,
    pub messages_received: u64,
    pub active: bool,
}

impl SubscriptionRecord {
    pub fn new(topic: Topic, domain: Domain) -> Self {
        Self {
            id: Uuid::new_v4(),
            topic,
            domain,
            created_at: std::time::Instant::now(),
            messages_received: 0,
            active: true,
        }
    }

    pub fn record_message(&mut self) {
        self.messages_received += 1;
    }

    pub fn deactivate(&mut self) {
        self.active = false;
    }

    pub fn uptime_ms(&self) -> u64 {
        self.created_at.elapsed().as_millis() as u64
    }
}

/// Registry of all active subscriptions
#[derive(Debug, Default)]
pub struct SubscriptionRegistry {
    records: HashMap<Uuid, SubscriptionRecord>,
}

impl SubscriptionRegistry {
    pub fn new() -> Self { Self::default() }

    pub fn register(&mut self, record: SubscriptionRecord) -> Uuid {
        let id = record.id;
        self.records.insert(id, record);
        id
    }

    pub fn get(&self, id: &Uuid) -> Option<&SubscriptionRecord> {
        self.records.get(id)
    }

    pub fn get_mut(&mut self, id: &Uuid) -> Option<&mut SubscriptionRecord> {
        self.records.get_mut(id)
    }

    pub fn deactivate(&mut self, id: &Uuid) -> bool {
        if let Some(r) = self.records.get_mut(id) {
            r.deactivate();
            true
        } else {
            false
        }
    }

    pub fn active_count(&self) -> usize {
        self.records.values().filter(|r| r.active).count()
    }

    pub fn subscriptions_for_topic(&self, topic: &Topic) -> Vec<&SubscriptionRecord> {
        self.records.values().filter(|r| r.active && &r.topic == topic).collect()
    }

    pub fn subscriptions_for_domain(&self, domain: &Domain) -> Vec<&SubscriptionRecord> {
        self.records.values().filter(|r| r.active && &r.domain == domain).collect()
    }

    pub fn total_messages_received(&self) -> u64 {
        self.records.values().map(|r| r.messages_received).sum()
    }
}

/// Wire format for subscription negotiation
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct SubscribeRequest {
    pub subscriber_id: Uuid,
    pub domain: Domain,
    pub topics: Vec<Topic>,
    pub filter_tags: Vec<String>,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct SubscribeResponse {
    pub subscription_ids: Vec<Uuid>,
    pub success: bool,
    pub error: Option<String>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn subscription_registry() {
        let mut registry = SubscriptionRegistry::new();
        let r1 = SubscriptionRecord::new(Topic::IntentSubmit, Domain::Windows);
        let r2 = SubscriptionRecord::new(Topic::DomainHealth, Domain::Android);
        let id1 = registry.register(r1);
        registry.register(r2);

        assert_eq!(registry.active_count(), 2);
        assert_eq!(registry.subscriptions_for_topic(&Topic::IntentSubmit).len(), 1);
        registry.deactivate(&id1);
        assert_eq!(registry.active_count(), 1);
    }
}