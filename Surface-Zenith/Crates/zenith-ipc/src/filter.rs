//! # ZIB Message Filter Chain
//!
//! Filters are applied to every message before delivery.
//! They can reject, modify, or log messages.

use crate::message::ZMessage;
use zenith_abi::domain::Domain;
use crate::topics::Topic;

/// A message filter — returns true if the message should be delivered
pub trait MessageFilter {
    /// Return true to allow delivery, false to reject
    fn allow(&self, msg: &ZMessage) -> bool;
    /// Human-readable filter name
    fn name(&self) -> &str;
}

/// A chain of filters applied in order
pub struct FilterChain {
    filters: Vec<Box<dyn MessageFilter + Send + Sync>>,
}

impl FilterChain {
    /// Create an empty filter chain
    pub fn new() -> Self {
        Self { filters: Vec::new() }
    }

    /// Add a filter to the chain
    pub fn add(&mut self, filter: Box<dyn MessageFilter + Send + Sync>) {
        self.filters.push(filter);
    }

    /// Apply all filters — returns true only if ALL filters allow the message
    pub fn allow(&self, msg: &ZMessage) -> bool {
        self.filters.iter().all(|f| f.allow(msg))
    }

    /// Number of filters in the chain
    pub fn len(&self) -> usize {
        self.filters.len()
    }

    /// Whether the chain is empty
    pub fn is_empty(&self) -> bool {
        self.filters.is_empty()
    }
}

impl Default for FilterChain {
    fn default() -> Self { Self::new() }
}

// ---------------------------------------------------------------------------
// Built-in filters
// ---------------------------------------------------------------------------

/// Filter that blocks messages from a specific domain
pub struct DomainBlockFilter {
    blocked_domain: Domain,
}

impl DomainBlockFilter {
    pub fn new(domain: Domain) -> Self {
        Self { blocked_domain: domain }
    }
}

impl MessageFilter for DomainBlockFilter {
    fn allow(&self, msg: &ZMessage) -> bool {
        msg.source() != &self.blocked_domain
    }
    fn name(&self) -> &str { "DomainBlockFilter" }
}

/// Filter that only allows messages for specific topics
pub struct TopicAllowlistFilter {
    allowed: Vec<Topic>,
}

impl TopicAllowlistFilter {
    pub fn new(allowed: Vec<Topic>) -> Self {
        Self { allowed }
    }
}

impl MessageFilter for TopicAllowlistFilter {
    fn allow(&self, msg: &ZMessage) -> bool {
        self.allowed.contains(msg.topic())
    }
    fn name(&self) -> &str { "TopicAllowlistFilter" }
}

/// Filter that blocks messages exceeding a payload size limit
pub struct PayloadSizeFilter {
    max_bytes: usize,
}

impl PayloadSizeFilter {
    pub fn new(max_bytes: usize) -> Self {
        Self { max_bytes }
    }
}

impl MessageFilter for PayloadSizeFilter {
    fn allow(&self, msg: &ZMessage) -> bool {
        msg.payload_size() <= self.max_bytes
    }
    fn name(&self) -> &str { "PayloadSizeFilter" }
}

/// Filter that blocks expired messages
pub struct ExpiryFilter;

impl MessageFilter for ExpiryFilter {
    fn allow(&self, msg: &ZMessage) -> bool {
        !msg.is_expired()
    }
    fn name(&self) -> &str { "ExpiryFilter" }
}

/// Filter that only allows messages tagged with a specific tag
pub struct TagFilter {
    required_tag: String,
}

impl TagFilter {
    pub fn new(tag: impl Into<String>) -> Self {
        Self { required_tag: tag.into() }
    }
}

impl MessageFilter for TagFilter {
    fn allow(&self, msg: &ZMessage) -> bool {
        msg.tags.contains(&self.required_tag)
    }
    fn name(&self) -> &str { "TagFilter" }
}

#[cfg(test)]
mod tests {
    use super::*;
    use uuid::Uuid;

    fn make_msg(source: Domain, topic: Topic, payload: Vec<u8>) -> ZMessage {
        ZMessage::new(Uuid::new_v4(), source, None, topic, payload)
    }

    #[test]
    fn domain_block_filter() {
        let filter = DomainBlockFilter::new(Domain::Android);
        let android_msg = make_msg(Domain::Android, Topic::Heartbeat, b"beat".to_vec());
        let windows_msg = make_msg(Domain::Windows, Topic::Heartbeat, b"beat".to_vec());
        assert!(!filter.allow(&android_msg));
        assert!(filter.allow(&windows_msg));
    }

    #[test]
    fn topic_allowlist_filter() {
        let filter = TopicAllowlistFilter::new(vec![Topic::IntentSubmit, Topic::DomainHealth]);
        let allowed = make_msg(Domain::AI, Topic::IntentSubmit, b"data".to_vec());
        let blocked = make_msg(Domain::AI, Topic::Heartbeat, b"beat".to_vec());
        assert!(filter.allow(&allowed));
        assert!(!filter.allow(&blocked));
    }

    #[test]
    fn payload_size_filter() {
        let filter = PayloadSizeFilter::new(10);
        let small = make_msg(Domain::Windows, Topic::Heartbeat, b"small".to_vec());
        let large = make_msg(Domain::Windows, Topic::Heartbeat, vec![0u8; 100]);
        assert!(filter.allow(&small));
        assert!(!filter.allow(&large));
    }

    #[test]
    fn filter_chain_all_must_pass() {
        let mut chain = FilterChain::new();
        chain.add(Box::new(DomainBlockFilter::new(Domain::Android)));
        chain.add(Box::new(PayloadSizeFilter::new(20)));

        let ok_msg  = make_msg(Domain::Windows, Topic::Heartbeat, b"ok".to_vec());
        let bad_src = make_msg(Domain::Android, Topic::Heartbeat, b"ok".to_vec());
        let too_big = make_msg(Domain::Windows, Topic::Heartbeat, vec![0u8; 100]);

        assert!(chain.allow(&ok_msg));
        assert!(!chain.allow(&bad_src));
        assert!(!chain.allow(&too_big));
    }
}