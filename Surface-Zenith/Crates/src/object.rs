//! # Zenith Object Model
//!
//! Everything in the Zenith OS is an object. Files, sessions, contacts,
//! emails, prompts, and even running tasks are first-class objects
//! managed by the Universal Object Bus.

use serde::{Deserialize, Serialize};
use uuid::Uuid;
use crate::types::{ZObjectId, ZSessionId, ZTimestamp};
use crate::domain::Domain;
use crate::memory::UmoKind;

/// Object lifecycle state
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum ObjectState {
    /// Object is live and accessible
    Live,
    /// Object is archived (cold storage)
    Archived,
    /// Object is being transferred between domains
    InTransit,
    /// Object is pending deletion
    PendingDelete,
    /// Object has been deleted
    Deleted,
}

/// Object access pattern hint for the memory fabric
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum AccessPattern {
    /// Frequently accessed (keep in hot cache)
    Hot,
    /// Occasionally accessed
    Warm,
    /// Rarely accessed (candidate for archival)
    Cold,
    /// Streaming (sequential access)
    Sequential,
    /// Random access
    Random,
}

/// A lightweight handle to a Universal Memory Object
///
/// Handles are cheap to clone and pass between domains.
/// The actual data lives in the Memory Fabric.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ObjectHandle {
    /// Object ID in the Memory Fabric
    pub id: ZObjectId,
    /// Human-readable name
    pub name: String,
    /// Object type
    pub kind: UmoKind,
    /// Owning session
    pub session: ZSessionId,
    /// Domain that created this handle
    pub creator: Domain,
    /// Current lifecycle state
    pub state: ObjectState,
    /// Access pattern hint
    pub access_pattern: AccessPattern,
    /// Size in bytes
    pub size_bytes: u64,
    /// Creation timestamp
    pub created_at: ZTimestamp,
    /// Last access timestamp
    pub last_accessed: ZTimestamp,
    /// MIME type (optional)
    pub mime_type: Option<String>,
    /// Content hash (SHA-256, optional)
    pub content_hash: Option<Vec<u8>>,
    /// Tags for search and filtering
    pub tags: Vec<String>,
}

impl ObjectHandle {
    /// Create a new object handle
    pub fn new(
        name: impl Into<String>,
        kind: UmoKind,
        session: ZSessionId,
        creator: Domain,
    ) -> Self {
        let now = ZTimestamp(
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default()
                .as_micros() as i64,
        );
        Self {
            id: Uuid::new_v4(),
            name: name.into(),
            kind,
            session,
            creator,
            state: ObjectState::Live,
            access_pattern: AccessPattern::Warm,
            size_bytes: 0,
            created_at: now,
            last_accessed: now,
            mime_type: None,
            content_hash: None,
            tags: Vec::new(),
        }
    }

    /// Mark this handle as accessed (updates last_accessed)
    pub fn touch(&mut self) {
        self.last_accessed = ZTimestamp(
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default()
                .as_micros() as i64,
        );
    }

    /// Add a tag
    pub fn tag(&mut self, tag: impl Into<String>) {
        self.tags.push(tag.into());
    }

    /// Set MIME type
    pub fn set_mime(&mut self, mime: impl Into<String>) {
        self.mime_type = Some(mime.into());
    }

    /// Mark as archived
    pub fn archive(&mut self) {
        self.state = ObjectState::Archived;
    }

    /// Mark as deleted
    pub fn delete(&mut self) {
        self.state = ObjectState::Deleted;
    }

    /// Whether this object is accessible
    pub fn is_accessible(&self) -> bool {
        matches!(self.state, ObjectState::Live | ObjectState::InTransit)
    }
}

/// Universal Object Bus — routes object access requests between domains
#[derive(Debug, Default)]
pub struct UniversalObjectBus {
    handles: std::collections::HashMap<ZObjectId, ObjectHandle>,
    /// Index: session → object IDs
    session_index: std::collections::HashMap<ZSessionId, Vec<ZObjectId>>,
    /// Index: tag → object IDs
    tag_index: std::collections::HashMap<String, Vec<ZObjectId>>,
}

impl UniversalObjectBus {
    /// Create a new bus
    pub fn new() -> Self {
        Self::default()
    }

    /// Register an object handle
    pub fn register(&mut self, handle: ObjectHandle) -> ZObjectId {
        let id = handle.id;
        let session = handle.session;

        // Update tag index
        for tag in &handle.tags {
            self.tag_index
                .entry(tag.clone())
                .or_default()
                .push(id);
        }

        // Update session index
        self.session_index.entry(session).or_default().push(id);

        self.handles.insert(id, handle);
        id
    }

    /// Get a handle by ID
    pub fn get(&self, id: &ZObjectId) -> Option<&ObjectHandle> {
        self.handles.get(id)
    }

    /// Get a mutable handle by ID
    pub fn get_mut(&mut self, id: &ZObjectId) -> Option<&mut ObjectHandle> {
        self.handles.get_mut(id)
    }

    /// Search objects by tag
    pub fn search_by_tag(&self, tag: &str) -> Vec<&ObjectHandle> {
        self.tag_index
            .get(tag)
            .map(|ids| {
                ids.iter()
                    .filter_map(|id| self.handles.get(id))
                    .collect()
            })
            .unwrap_or_default()
    }

    /// Get all objects for a session
    pub fn session_objects(&self, session: &ZSessionId) -> Vec<&ObjectHandle> {
        self.session_index
            .get(session)
            .map(|ids| {
                ids.iter()
                    .filter_map(|id| self.handles.get(id))
                    .collect()
            })
            .unwrap_or_default()
    }

    /// Remove an object
    pub fn remove(&mut self, id: &ZObjectId) -> Option<ObjectHandle> {
        self.handles.remove(id)
    }

    /// Total object count
    pub fn count(&self) -> usize {
        self.handles.len()
    }

    /// Count of live objects
    pub fn live_count(&self) -> usize {
        self.handles.values().filter(|h| h.is_accessible()).count()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn object_handle_lifecycle() {
        let session = Uuid::new_v4();
        let mut handle = ObjectHandle::new(
            "contract.pdf", UmoKind::Pdf, session, Domain::Windows,
        );
        assert!(handle.is_accessible());
        handle.archive();
        assert!(!handle.is_accessible());
    }

    #[test]
    fn object_bus_tag_search() {
        let mut bus = UniversalObjectBus::new();
        let session = Uuid::new_v4();

        let mut h1 = ObjectHandle::new("doc1.docx", UmoKind::Document, session, Domain::Windows);
        h1.tag("legal");
        h1.tag("contract");

        let mut h2 = ObjectHandle::new("doc2.pdf", UmoKind::Pdf, session, Domain::Android);
        h2.tag("legal");

        bus.register(h1);
        bus.register(h2);

        let legal = bus.search_by_tag("legal");
        assert_eq!(legal.len(), 2);

        let contract = bus.search_by_tag("contract");
        assert_eq!(contract.len(), 1);
    }

    #[test]
    fn object_bus_session_index() {
        let mut bus = UniversalObjectBus::new();
        let s1 = Uuid::new_v4();
        let s2 = Uuid::new_v4();

        for i in 0..4 {
            let h = ObjectHandle::new(format!("file_{i}"), UmoKind::Blob, s1, Domain::Windows);
            bus.register(h);
        }
        let h = ObjectHandle::new("other", UmoKind::Blob, s2, Domain::Android);
        bus.register(h);

        assert_eq!(bus.session_objects(&s1).len(), 4);
        assert_eq!(bus.session_objects(&s2).len(), 1);
        assert_eq!(bus.live_count(), 5);
    }
}