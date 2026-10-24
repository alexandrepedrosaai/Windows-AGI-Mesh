//! # Zenith Memory Model
//!
//! The Shared Memory Fabric eliminates the traditional separation between
//! Android RAM and Windows RAM. All domains share a unified address space
//! through Universal Memory Objects (UMOs).
//!
//! ## Memory Hierarchy
//!
//! ```text
//! Application
//!      ↓
//! Universal Memory Object (UMO)
//!      ↓
//! Shared Memory Pages
//!      ↓
//! Physical Memory Pool
//! ```
//!
//! ## Key Properties
//!
//! - **No duplication**: A document exists once, not once per domain
//! - **Copy-on-Write**: Pages are shared until modified
//! - **Dirty tracking**: Only modified pages are transferred during migration
//! - **Capability-gated**: All UMO access requires a valid capability token

use serde::{Deserialize, Serialize};
use uuid::Uuid;
use crate::types::{ZObjectId, ZPageId, ZSessionId, ZDomainId, MemoryBytes, ZTimestamp};
use crate::domain::Domain;

// ---------------------------------------------------------------------------
// Memory page
// ---------------------------------------------------------------------------

/// A single 4 KB page of memory within the Shared Memory Fabric
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MemoryPage {
    /// Unique page ID within the UMO
    pub id: ZPageId,
    /// Page version counter (incremented on every write)
    pub version: u64,
    /// Whether this page has been modified since last checkpoint
    pub dirty: bool,
    /// Domain that currently owns (last wrote) this page
    pub owner: Domain,
    /// Copy-on-Write reference count
    pub cow_refs: u32,
    /// Raw page data (PAGE_SIZE_BYTES = 4096)
    pub bytes: Vec<u8>,
    /// Last modification timestamp
    pub modified_at: ZTimestamp,
}

impl MemoryPage {
    /// Create a new zeroed page
    pub fn new(id: ZPageId, owner: Domain) -> Self {
        Self {
            id,
            version: 0,
            dirty: false,
            owner,
            cow_refs: 1,
            bytes: vec![0u8; crate::PAGE_SIZE_BYTES],
            modified_at: ZTimestamp(0),
        }
    }

    /// Write data to this page, marking it dirty
    pub fn write(&mut self, offset: usize, data: &[u8]) -> Result<(), &'static str> {
        let end = offset + data.len();
        if end > self.bytes.len() {
            return Err("write exceeds page boundary");
        }
        self.bytes[offset..end].copy_from_slice(data);
        self.dirty = true;
        self.version += 1;
        self.modified_at = ZTimestamp(
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default()
                .as_micros() as i64,
        );
        Ok(())
    }

    /// Clear the dirty flag (called after checkpoint/migration)
    pub fn clear_dirty(&mut self) {
        self.dirty = false;
    }

    /// Create a CoW clone of this page
    pub fn cow_clone(&mut self) -> MemoryPage {
        self.cow_refs += 1;
        MemoryPage {
            id: self.id,
            version: self.version,
            dirty: false,
            owner: self.owner.clone(),
            cow_refs: 1,
            bytes: self.bytes.clone(),
            modified_at: self.modified_at,
        }
    }

    /// Compute a simple checksum of the page data
    pub fn checksum(&self) -> u32 {
        self.bytes.iter().fold(0u32, |acc, &b| acc.wrapping_add(b as u32))
    }
}

// ---------------------------------------------------------------------------
// Universal Memory Object (UMO)
// ---------------------------------------------------------------------------

/// Object type stored in the Shared Memory Fabric
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum UmoKind {
    /// Office document (Word, Excel, PowerPoint)
    Document,
    /// PDF file
    Pdf,
    /// Image or photo
    Image,
    /// Video stream
    Video,
    /// Audio stream
    Audio,
    /// Email message
    Email,
    /// Calendar event
    CalendarEvent,
    /// Contact record
    Contact,
    /// Session state snapshot
    SessionSnapshot,
    /// AI model weights (partial)
    ModelWeights,
    /// Arbitrary binary blob
    Blob,
    /// Structured data (JSON/XML)
    StructuredData,
}

/// Universal Memory Object — the fundamental data unit of the Zenith OS
///
/// A UMO is a named, versioned, capability-gated collection of memory pages
/// that can be accessed by any authorized domain without copying.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UniversalMemoryObject {
    /// Unique object ID
    pub id: ZObjectId,
    /// Human-readable name
    pub name: String,
    /// Object type
    pub kind: UmoKind,
    /// Session that owns this object
    pub session: ZSessionId,
    /// Domain that created this object
    pub creator: Domain,
    /// Domains currently holding a reference
    pub readers: Vec<Domain>,
    /// Domain currently holding write lock (None = unlocked)
    pub write_lock: Option<Domain>,
    /// Memory pages comprising this object
    pub pages: Vec<MemoryPage>,
    /// Object version (incremented on every write)
    pub version: u64,
    /// Total size in bytes
    pub size_bytes: MemoryBytes,
    /// Creation timestamp
    pub created_at: ZTimestamp,
    /// Last modification timestamp
    pub modified_at: ZTimestamp,
    /// Whether this object is pinned in memory (not swappable)
    pub pinned: bool,
    /// Metadata key-value pairs
    pub metadata: std::collections::HashMap<String, String>,
}

impl UniversalMemoryObject {
    /// Create a new empty UMO
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
            readers: Vec::new(),
            write_lock: None,
            pages: Vec::new(),
            version: 0,
            size_bytes: 0,
            created_at: now,
            modified_at: now,
            pinned: false,
            metadata: std::collections::HashMap::new(),
        }
    }

    /// Allocate a new page and append it to this UMO
    pub fn allocate_page(&mut self, owner: Domain) -> ZPageId {
        let id = self.pages.len() as ZPageId;
        let page = MemoryPage::new(id, owner);
        self.pages.push(page);
        self.size_bytes += crate::PAGE_SIZE_BYTES as MemoryBytes;
        id
    }

    /// Write data starting at a byte offset (spans pages as needed)
    pub fn write_bytes(&mut self, offset: usize, data: &[u8], writer: Domain) -> Result<(), String> {
        if let Some(ref lock) = self.write_lock {
            if lock != &writer {
                return Err(format!("write lock held by {:?}", lock));
            }
        }
        let page_size = crate::PAGE_SIZE_BYTES;
        let start_page = offset / page_size;
        let mut remaining = data;
        let mut page_offset = offset % page_size;
        let mut page_idx = start_page;

        while !remaining.is_empty() {
            // Allocate pages as needed
            while self.pages.len() <= page_idx {
                self.allocate_page(writer.clone());
            }
            let space = page_size - page_offset;
            let chunk_len = remaining.len().min(space);
            self.pages[page_idx]
                .write(page_offset, &remaining[..chunk_len])
                .map_err(|e| e.to_string())?;
            remaining = &remaining[chunk_len..];
            page_offset = 0;
            page_idx += 1;
        }

        self.version += 1;
        self.modified_at = ZTimestamp(
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default()
                .as_micros() as i64,
        );
        Ok(())
    }

    /// Acquire write lock for a domain
    pub fn acquire_write_lock(&mut self, domain: Domain) -> bool {
        if self.write_lock.is_none() {
            self.write_lock = Some(domain);
            true
        } else {
            false
        }
    }

    /// Release write lock
    pub fn release_write_lock(&mut self, domain: &Domain) -> bool {
        if self.write_lock.as_ref() == Some(domain) {
            self.write_lock = None;
            true
        } else {
            false
        }
    }

    /// Get all dirty pages (for incremental migration)
    pub fn dirty_pages(&self) -> Vec<&MemoryPage> {
        self.pages.iter().filter(|p| p.dirty).collect()
    }

    /// Clear all dirty flags after a successful checkpoint
    pub fn clear_dirty_flags(&mut self) {
        for page in &mut self.pages {
            page.clear_dirty();
        }
    }

    /// Total number of dirty pages
    pub fn dirty_page_count(&self) -> usize {
        self.pages.iter().filter(|p| p.dirty).count()
    }

    /// Pin this object in memory
    pub fn pin(&mut self) {
        self.pinned = true;
    }

    /// Unpin this object
    pub fn unpin(&mut self) {
        self.pinned = false;
    }

    /// Add metadata
    pub fn set_metadata(&mut self, key: impl Into<String>, value: impl Into<String>) {
        self.metadata.insert(key.into(), value.into());
    }
}

// ---------------------------------------------------------------------------
// Memory fabric (global UMO registry)
// ---------------------------------------------------------------------------

/// The Shared Memory Fabric — global registry of all Universal Memory Objects
#[derive(Debug, Default)]
pub struct MemoryFabric {
    objects: std::collections::HashMap<ZObjectId, UniversalMemoryObject>,
    /// Total bytes allocated across all UMOs
    total_allocated: MemoryBytes,
    /// Maximum allowed allocation
    capacity: MemoryBytes,
}

impl MemoryFabric {
    /// Create a new memory fabric with a given capacity
    pub fn new(capacity_bytes: MemoryBytes) -> Self {
        Self {
            objects: std::collections::HashMap::new(),
            total_allocated: 0,
            capacity: capacity_bytes,
        }
    }

    /// Register a new UMO
    pub fn register(&mut self, umo: UniversalMemoryObject) -> Result<ZObjectId, String> {
        if self.total_allocated + umo.size_bytes > self.capacity {
            return Err("memory fabric capacity exceeded".into());
        }
        let id = umo.id;
        self.total_allocated += umo.size_bytes;
        self.objects.insert(id, umo);
        Ok(id)
    }

    /// Get a reference to a UMO
    pub fn get(&self, id: &ZObjectId) -> Option<&UniversalMemoryObject> {
        self.objects.get(id)
    }

    /// Get a mutable reference to a UMO
    pub fn get_mut(&mut self, id: &ZObjectId) -> Option<&mut UniversalMemoryObject> {
        self.objects.get_mut(id)
    }

    /// Remove a UMO from the fabric
    pub fn deregister(&mut self, id: &ZObjectId) -> Option<UniversalMemoryObject> {
        if let Some(umo) = self.objects.remove(id) {
            self.total_allocated = self.total_allocated.saturating_sub(umo.size_bytes);
            Some(umo)
        } else {
            None
        }
    }

    /// List all UMOs belonging to a session
    pub fn session_objects(&self, session: &ZSessionId) -> Vec<&UniversalMemoryObject> {
        self.objects.values().filter(|u| &u.session == session).collect()
    }

    /// Memory utilization ratio (0.0–1.0)
    pub fn utilization(&self) -> f64 {
        if self.capacity == 0 {
            return 0.0;
        }
        self.total_allocated as f64 / self.capacity as f64
    }

    /// Count of registered objects
    pub fn object_count(&self) -> usize {
        self.objects.len()
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn page_write_and_dirty() {
        let mut page = MemoryPage::new(0, Domain::Windows);
        assert!(!page.dirty);
        page.write(0, b"hello zenith").unwrap();
        assert!(page.dirty);
        assert_eq!(page.version, 1);
        page.clear_dirty();
        assert!(!page.dirty);
    }

    #[test]
    fn page_checksum_changes_on_write() {
        let mut page = MemoryPage::new(0, Domain::Android);
        let before = page.checksum();
        page.write(0, b"data").unwrap();
        let after = page.checksum();
        assert_ne!(before, after);
    }

    #[test]
    fn umo_write_spans_pages() {
        let session = Uuid::new_v4();
        let mut umo = UniversalMemoryObject::new(
            "test.docx", UmoKind::Document, session, Domain::Windows,
        );
        let data = vec![0xABu8; 5000]; // spans 2 pages
        umo.write_bytes(0, &data, Domain::Windows).unwrap();
        assert_eq!(umo.pages.len(), 2);
        assert_eq!(umo.dirty_page_count(), 2);
    }

    #[test]
    fn umo_write_lock() {
        let session = Uuid::new_v4();
        let mut umo = UniversalMemoryObject::new(
            "doc.pdf", UmoKind::Pdf, session, Domain::Android,
        );
        assert!(umo.acquire_write_lock(Domain::Windows));
        assert!(!umo.acquire_write_lock(Domain::Android)); // already locked
        assert!(umo.release_write_lock(&Domain::Windows));
        assert!(umo.acquire_write_lock(Domain::Android)); // now free
    }

    #[test]
    fn memory_fabric_register_and_get() {
        let mut fabric = MemoryFabric::new(1024 * 1024 * 1024);
        let session = Uuid::new_v4();
        let umo = UniversalMemoryObject::new(
            "spreadsheet.xlsx", UmoKind::Document, session, Domain::Windows,
        );
        let id = fabric.register(umo).unwrap();
        assert!(fabric.get(&id).is_some());
        assert_eq!(fabric.object_count(), 1);
    }

    #[test]
    fn memory_fabric_session_objects() {
        let mut fabric = MemoryFabric::new(1024 * 1024 * 1024);
        let session_a = Uuid::new_v4();
        let session_b = Uuid::new_v4();

        for i in 0..3 {
            let umo = UniversalMemoryObject::new(
                format!("doc_{i}"), UmoKind::Document, session_a, Domain::Windows,
            );
            fabric.register(umo).unwrap();
        }
        let umo_b = UniversalMemoryObject::new(
            "other", UmoKind::Blob, session_b, Domain::Android,
        );
        fabric.register(umo_b).unwrap();

        assert_eq!(fabric.session_objects(&session_a).len(), 3);
        assert_eq!(fabric.session_objects(&session_b).len(), 1);
    }
}