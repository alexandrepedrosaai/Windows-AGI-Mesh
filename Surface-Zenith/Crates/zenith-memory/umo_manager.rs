//! # Universal Memory Object Manager
//!
//! High-level manager for UMO lifecycle, access control, and cross-domain sharing.

use std::collections::HashMap;
use uuid::Uuid;
use zenith_abi::domain::Domain;
use zenith_abi::types::{ZObjectId, ZSessionId};
use zenith_abi::memory::{UniversalMemoryObject, UmoKind, MemoryFabric};
use crate::error::MemoryError;

/// UMO access statistics
#[derive(Debug, Clone, Default)]
pub struct UmoAccessStats {
    pub reads:        u64,
    pub writes:       u64,
    pub bytes_read:   u64,
    pub bytes_written: u64,
    pub lock_contentions: u64,
    pub last_access:  Option<std::time::Instant>,
}

impl UmoAccessStats {
    pub fn record_read(&mut self, bytes: u64) {
        self.reads += 1;
        self.bytes_read += bytes;
        self.last_access = Some(std::time::Instant::now());
    }

    pub fn record_write(&mut self, bytes: u64) {
        self.writes += 1;
        self.bytes_written += bytes;
        self.last_access = Some(std::time::Instant::now());
    }

    pub fn age_ms(&self) -> Option<u64> {
        self.last_access.map(|t| t.elapsed().as_millis() as u64)
    }
}

/// UMO metadata record
#[derive(Debug, Clone)]
pub struct UmoRecord {
    pub id:          ZObjectId,
    pub name:        String,
    pub kind:        UmoKind,
    pub session:     ZSessionId,
    pub creator:     Domain,
    pub stats:       UmoAccessStats,
    pub created_at:  std::time::Instant,
    pub tags:        Vec<String>,
}

impl UmoRecord {
    pub fn new(id: ZObjectId, name: impl Into<String>, kind: UmoKind,
               session: ZSessionId, creator: Domain) -> Self {
        Self {
            id,
            name: name.into(),
            kind,
            session,
            creator,
            stats: UmoAccessStats::default(),
            created_at: std::time::Instant::now(),
            tags: Vec::new(),
        }
    }

    pub fn age_ms(&self) -> u64 {
        self.created_at.elapsed().as_millis() as u64
    }

    pub fn tag(&mut self, tag: impl Into<String>) {
        self.tags.push(tag.into());
    }
}

/// The Universal Memory Object Manager
#[derive(Debug)]
pub struct UmoManager {
    fabric:  MemoryFabric,
    records: HashMap<ZObjectId, UmoRecord>,
    /// Session → UMO IDs
    session_index: HashMap<ZSessionId, Vec<ZObjectId>>,
    /// Tag → UMO IDs
    tag_index: HashMap<String, Vec<ZObjectId>>,
    total_created:   u64,
    total_destroyed: u64,
}

impl UmoManager {
    /// Create a new UMO manager
    pub fn new(capacity_bytes: u64) -> Self {
        Self {
            fabric:        MemoryFabric::new(capacity_bytes),
            records:       HashMap::new(),
            session_index: HashMap::new(),
            tag_index:     HashMap::new(),
            total_created: 0,
            total_destroyed: 0,
        }
    }

    /// Create a new UMO
    pub fn create(
        &mut self,
        name: impl Into<String>,
        kind: UmoKind,
        session: ZSessionId,
        creator: Domain,
    ) -> Result<ZObjectId, MemoryError> {
        let name = name.into();
        let umo = UniversalMemoryObject::new(name.clone(), kind.clone(), session, creator.clone());
        let id = self.fabric.register(umo)
            .map_err(|e| MemoryError::Internal { message: e })?;

        let record = UmoRecord::new(id, name, kind, session, creator);
        self.session_index.entry(session).or_default().push(id);
        self.records.insert(id, record);
        self.total_created += 1;
        Ok(id)
    }

    /// Destroy a UMO
    pub fn destroy(&mut self, id: &ZObjectId) -> Result<(), MemoryError> {
        let record = self.records.remove(id)
            .ok_or_else(|| MemoryError::UmoNotFound { id: id.to_string() })?;

        // Remove from session index
        if let Some(ids) = self.session_index.get_mut(&record.session) {
            ids.retain(|i| i != id);
        }

        // Remove from tag index
        for tag in &record.tags {
            if let Some(ids) = self.tag_index.get_mut(tag) {
                ids.retain(|i| i != id);
            }
        }

        self.fabric.deregister(id);
        self.total_destroyed += 1;
        Ok(())
    }

    /// Write to a UMO
    pub fn write(
        &mut self,
        id: &ZObjectId,
        offset: usize,
        data: &[u8],
        writer: Domain,
    ) -> Result<(), MemoryError> {
        let umo = self.fabric.get_mut(id)
            .ok_or_else(|| MemoryError::UmoNotFound { id: id.to_string() })?;

        umo.write_bytes(offset, data, writer)
            .map_err(|e| MemoryError::WriteLockConflict { holder: e })?;

        if let Some(record) = self.records.get_mut(id) {
            record.stats.record_write(data.len() as u64);
        }
        Ok(())
    }

    /// Read from a UMO
    pub fn read(
        &self,
        id: &ZObjectId,
        offset: usize,
        len: usize,
    ) -> Result<Vec<u8>, MemoryError> {
        let umo = self.fabric.get(id)
            .ok_or_else(|| MemoryError::UmoNotFound { id: id.to_string() })?;

        let mut result = Vec::with_capacity(len);
        let page_size = crate::PAGE_SIZE;
        let start_page = offset / page_size;
        let mut remaining = len;
        let mut page_offset = offset % page_size;
        let mut page_idx = start_page;

        while remaining > 0 && page_idx < umo.pages.len() {
            let page = &umo.pages[page_idx];
            let available = page_size - page_offset;
            let to_read = remaining.min(available).min(
                page.bytes.len().saturating_sub(page_offset)
            );
            if to_read == 0 { break; }
            result.extend_from_slice(&page.bytes[page_offset..page_offset + to_read]);
            remaining -= to_read;
            page_offset = 0;
            page_idx += 1;
        }

        Ok(result)
    }

    /// Add a tag to a UMO
    pub fn tag_umo(&mut self, id: &ZObjectId, tag: impl Into<String>) -> bool {
        let tag = tag.into();
        if let Some(record) = self.records.get_mut(id) {
            record.tag(tag.clone());
            self.tag_index.entry(tag).or_default().push(*id);
            true
        } else {
            false
        }
    }

    /// Search UMOs by tag
    pub fn search_by_tag(&self, tag: &str) -> Vec<&UmoRecord> {
        self.tag_index.get(tag)
            .map(|ids| ids.iter().filter_map(|id| self.records.get(id)).collect())
            .unwrap_or_default()
    }

    /// Get all UMOs for a session
    pub fn session_umos(&self, session: &ZSessionId) -> Vec<&UmoRecord> {
        self.session_index.get(session)
            .map(|ids| ids.iter().filter_map(|id| self.records.get(id)).collect())
            .unwrap_or_default()
    }

    /// Get a UMO record
    pub fn get_record(&self, id: &ZObjectId) -> Option<&UmoRecord> {
        self.records.get(id)
    }

    /// Get a mutable UMO record
    pub fn get_record_mut(&mut self, id: &ZObjectId) -> Option<&mut UmoRecord> {
        self.records.get_mut(id)
    }

    /// Total UMO count
    pub fn count(&self) -> usize { self.records.len() }

    /// Total created
    pub fn total_created(&self) -> u64 { self.total_created }

    /// Total destroyed
    pub fn total_destroyed(&self) -> u64 { self.total_destroyed }

    /// Active UMOs
    pub fn active_count(&self) -> u64 {
        self.total_created.saturating_sub(self.total_destroyed)
    }

    /// Memory fabric utilization
    pub fn fabric_utilization(&self) -> f64 {
        self.fabric.utilization()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn make_manager() -> UmoManager {
        UmoManager::new(1024 * 1024 * 1024)
    }

    #[test]
    fn umo_manager_create_destroy() {
        let mut mgr = make_manager();
        let session = Uuid::new_v4();
        let id = mgr.create("test.docx", UmoKind::Document, session, Domain::Windows).unwrap();
        assert_eq!(mgr.count(), 1);
        mgr.destroy(&id).unwrap();
        assert_eq!(mgr.count(), 0);
    }

    #[test]
    fn umo_manager_write_read() {
        let mut mgr = make_manager();
        let session = Uuid::new_v4();
        let id = mgr.create("data.bin", UmoKind::Blob, session, Domain::Windows).unwrap();
        let data = b"Surface Zenith UMO test data";
        mgr.write(&id, 0, data, Domain::Windows).unwrap();
        let read_back = mgr.read(&id, 0, data.len()).unwrap();
        assert_eq!(read_back, data);
    }

    #[test]
    fn umo_manager_tag_search() {
        let mut mgr = make_manager();
        let session = Uuid::new_v4();
        let id1 = mgr.create("contract.pdf", UmoKind::Pdf, session, Domain::Windows).unwrap();
        let id2 = mgr.create("invoice.pdf", UmoKind::Pdf, session, Domain::Windows).unwrap();
        mgr.tag_umo(&id1, "legal");
        mgr.tag_umo(&id2, "legal");
        mgr.tag_umo(&id1, "contract");

        let legal = mgr.search_by_tag("legal");
        assert_eq!(legal.len(), 2);
        let contract = mgr.search_by_tag("contract");
        assert_eq!(contract.len(), 1);
    }

    #[test]
    fn umo_manager_session_index() {
        let mut mgr = make_manager();
        let session_a = Uuid::new_v4();
        let session_b = Uuid::new_v4();
        for i in 0..3 {
            mgr.create(format!("doc_{i}"), UmoKind::Document, session_a, Domain::Windows).unwrap();
        }
        mgr.create("other", UmoKind::Blob, session_b, Domain::Android).unwrap();
        assert_eq!(mgr.session_umos(&session_a).len(), 3);
        assert_eq!(mgr.session_umos(&session_b).len(), 1);
    }

    #[test]
    fn umo_manager_stats_tracking() {
        let mut mgr = make_manager();
        let session = Uuid::new_v4();
        let id = mgr.create("stats_test", UmoKind::Blob, session, Domain::AI).unwrap();
        mgr.write(&id, 0, b"hello", Domain::AI).unwrap();
        let record = mgr.get_record(&id).unwrap();
        assert_eq!(record.stats.writes, 1);
        assert_eq!(record.stats.bytes_written, 5);
    }
}