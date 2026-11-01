//! # Memory Broker
//!
//! The Memory Broker is the top-level interface for all memory operations
//! in the Zenith OS. It coordinates the allocator, CoW engine, dirty tracker,
//! UMO manager, and pressure manager.

use std::sync::Arc;
use parking_lot::RwLock;
use uuid::Uuid;
use zenith_abi::domain::Domain;
use zenith_abi::types::{ZObjectId, ZSessionId};
use zenith_abi::memory::{UniversalMemoryObject, UmoKind, MemoryFabric};
use crate::allocator::BuddyAllocator;
use crate::cow::CowEngine;
use crate::dirty::{DirtyPageTracker, TrackingMode};
use crate::page_frame::PageFrameDatabase;
use crate::pressure::MemoryPressureManager;
use crate::metrics::MemoryMetrics;
use crate::error::MemoryError;

/// Memory broker configuration
#[derive(Debug, Clone)]
pub struct MemoryBrokerConfig {
    pub total_memory_bytes:  u64,
    pub swap_size_bytes:     u64,
    pub enable_huge_pages:   bool,
    pub enable_numa:         bool,
    pub dirty_tracking_mode: TrackingMode,
    pub pressure_threshold:  f64,
}

impl Default for MemoryBrokerConfig {
    fn default() -> Self {
        Self {
            total_memory_bytes:  16 * 1024 * 1024 * 1024, // 16 GB
            swap_size_bytes:     8  * 1024 * 1024 * 1024, // 8 GB
            enable_huge_pages:   true,
            enable_numa:         false,
            dirty_tracking_mode: TrackingMode::Full,
            pressure_threshold:  crate::PRESSURE_HIGH,
        }
    }
}

/// Inner state of the Memory Broker
struct BrokerInner {
    config:          MemoryBrokerConfig,
    pfd:             PageFrameDatabase,
    buddy:           BuddyAllocator,
    cow_engine:      CowEngine,
    dirty_tracker:   DirtyPageTracker,
    fabric:          MemoryFabric,
    pressure_mgr:    MemoryPressureManager,
    metrics:         MemoryMetrics,
}

impl BrokerInner {
    fn new(config: MemoryBrokerConfig) -> Self {
        let total_pages = config.total_memory_bytes / crate::PAGE_SIZE as u64;
        Self {
            pfd:           PageFrameDatabase::new(config.total_memory_bytes),
            buddy:         BuddyAllocator::new(total_pages),
            cow_engine:    CowEngine::new(),
            dirty_tracker: DirtyPageTracker::new(total_pages, config.dirty_tracking_mode.clone()),
            fabric:        MemoryFabric::new(config.total_memory_bytes),
            pressure_mgr:  MemoryPressureManager::new(config.pressure_threshold),
            metrics:       MemoryMetrics::new(),
            config,
        }
    }
}

/// The Zenith Memory Broker — central memory management interface
#[derive(Clone)]
pub struct MemoryBroker {
    inner: Arc<RwLock<BrokerInner>>,
}

impl MemoryBroker {
    /// Create a new memory broker with default configuration
    pub fn new() -> Self {
        Self::with_config(MemoryBrokerConfig::default())
    }

    /// Create a memory broker with custom configuration
    pub fn with_config(config: MemoryBrokerConfig) -> Self {
        Self {
            inner: Arc::new(RwLock::new(BrokerInner::new(config))),
        }
    }

    // ── Page allocation ──────────────────────────────────────────────────────

    /// Allocate a single physical page for a domain
    pub fn allocate_page(&self, domain: Domain) -> Result<u64, MemoryError> {
        let mut inner = self.inner.write();

        // Check memory pressure
        let utilization = inner.pfd.utilization();
        if utilization >= inner.config.pressure_threshold {
            inner.pressure_mgr.record_pressure_event(utilization);
            return Err(MemoryError::MemoryPressure { utilization: utilization * 100.0 });
        }

        let pfn = inner.pfd.allocate(domain)?;
        inner.metrics.record_allocation(crate::PAGE_SIZE as u64);
        Ok(pfn)
    }

    /// Allocate multiple pages for a domain
    pub fn allocate_pages(&self, domain: Domain, count: u64) -> Result<Vec<u64>, MemoryError> {
        let mut inner = self.inner.write();
        let pfns = inner.pfd.allocate_contiguous(count, domain)?;
        inner.metrics.record_allocation(count * crate::PAGE_SIZE as u64);
        Ok(pfns)
    }

    /// Free a physical page
    pub fn free_page(&self, pfn: u64) -> Result<(), MemoryError> {
        let mut inner = self.inner.write();
        inner.pfd.free(pfn)?;
        inner.metrics.record_free(crate::PAGE_SIZE as u64);
        Ok(())
    }

    // ── UMO management ───────────────────────────────────────────────────────

    /// Create a new Universal Memory Object
    pub fn create_umo(
        &self,
        name: impl Into<String>,
        kind: UmoKind,
        session: ZSessionId,
        creator: Domain,
    ) -> Result<ZObjectId, MemoryError> {
        let mut inner = self.inner.write();
        let umo = UniversalMemoryObject::new(name, kind, session, creator);
        let id = inner.fabric.register(umo).map_err(|e| MemoryError::Internal { message: e })?;
        inner.metrics.record_umo_created();
        Ok(id)
    }

    /// Write to a UMO
    pub fn write_umo(
        &self,
        id: &ZObjectId,
        offset: usize,
        data: &[u8],
        writer: Domain,
    ) -> Result<(), MemoryError> {
        let mut inner = self.inner.write();
        let umo = inner.fabric.get_mut(id)
            .ok_or_else(|| MemoryError::UmoNotFound { id: id.to_string() })?;

        umo.write_bytes(offset, data, writer.clone())
            .map_err(|e| MemoryError::WriteLockConflict { holder: e })?;

        // Track dirty pages
        let dirty_count = umo.dirty_page_count();
        for i in 0..dirty_count as u64 {
            inner.dirty_tracker.mark_dirty(i, Some(&writer), Some(id));
        }

        inner.metrics.record_write(data.len() as u64);
        Ok(())
    }

    /// Read from a UMO
    pub fn read_umo(
        &self,
        id: &ZObjectId,
        offset: usize,
        len: usize,
    ) -> Result<Vec<u8>, MemoryError> {
        let inner = self.inner.read();
        let umo = inner.fabric.get(id)
            .ok_or_else(|| MemoryError::UmoNotFound { id: id.to_string() })?;

        // Read from pages
        let mut result = Vec::with_capacity(len);
        let page_size = crate::PAGE_SIZE;
        let start_page = offset / page_size;
        let mut remaining = len;
        let mut page_offset = offset % page_size;
        let mut page_idx = start_page;

        while remaining > 0 && page_idx < umo.pages.len() {
            let page = &umo.pages[page_idx];
            let available = page_size - page_offset;
            let to_read = remaining.min(available).min(page.bytes.len().saturating_sub(page_offset));
            result.extend_from_slice(&page.bytes[page_offset..page_offset + to_read]);
            remaining -= to_read;
            page_offset = 0;
            page_idx += 1;
        }

        Ok(result)
    }

    /// Destroy a UMO
    pub fn destroy_umo(&self, id: &ZObjectId) -> Result<(), MemoryError> {
        let mut inner = self.inner.write();
        inner.fabric.deregister(id)
            .ok_or_else(|| MemoryError::UmoNotFound { id: id.to_string() })?;
        inner.metrics.record_umo_destroyed();
        Ok(())
    }

    // ── CoW operations ───────────────────────────────────────────────────────

    /// Create a CoW mapping for a page
    pub fn create_cow_mapping(
        &self,
        pfn: u64,
        page_idx: u64,
        umo_id: Option<ZObjectId>,
        domain: &Domain,
        va: u64,
    ) {
        let mut inner = self.inner.write();
        inner.cow_engine.create_mapping(pfn, page_idx, umo_id, domain, va);
        inner.pfd.make_cow(pfn);
        inner.metrics.record_cow_created();
    }

    /// Handle a CoW page fault
    pub fn handle_cow_fault(
        &self,
        pfn: u64,
        domain: &Domain,
        page_data: &[u8],
    ) -> Result<u64, MemoryError> {
        let mut inner = self.inner.write();
        let result = inner.cow_engine.handle_fault(pfn, domain, &mut inner.pfd, page_data)?;
        inner.metrics.record_cow_fault();
        Ok(result.new_pfn)
    }

    // ── Dirty tracking ───────────────────────────────────────────────────────

    /// Mark a page as dirty
    pub fn mark_dirty(&self, pfn: u64, domain: Option<&Domain>, umo_id: Option<&ZObjectId>) {
        let mut inner = self.inner.write();
        inner.dirty_tracker.mark_dirty(pfn, domain, umo_id);
        inner.pfd.mark_dirty(pfn);
    }

    /// Get all dirty pages for a domain
    pub fn dirty_pages_for_domain(&self, domain: &Domain) -> Vec<u64> {
        self.inner.read().dirty_tracker.domain_dirty_pfns(domain)
    }

    /// Create a checkpoint
    pub fn checkpoint(&self) -> usize {
        self.inner.write().dirty_tracker.checkpoint()
    }

    /// Clear all dirty flags after migration
    pub fn clear_dirty_all(&self) {
        let mut inner = self.inner.write();
        inner.dirty_tracker.clear_all();
    }

    // ── Metrics ──────────────────────────────────────────────────────────────

    /// Get memory metrics snapshot
    pub fn metrics(&self) -> MemoryMetrics {
        self.inner.read().metrics.clone()
    }

    /// Current memory utilization (0.0–1.0)
    pub fn utilization(&self) -> f64 {
        self.inner.read().pfd.utilization()
    }

    /// Free pages
    pub fn free_pages(&self) -> u64 {
        self.inner.read().pfd.free_pages()
    }

    /// Total pages
    pub fn total_pages(&self) -> u64 {
        self.inner.read().pfd.total_pages()
    }

    /// Dirty page count
    pub fn dirty_page_count(&self) -> u64 {
        self.inner.read().dirty_tracker.global_dirty_count()
    }

    /// CoW mapping count
    pub fn cow_mapping_count(&self) -> usize {
        self.inner.read().cow_engine.mapping_count()
    }

    /// UMO count
    pub fn umo_count(&self) -> usize {
        self.inner.read().fabric.object_count()
    }
}

impl Default for MemoryBroker {
    fn default() -> Self { Self::new() }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn make_broker() -> MemoryBroker {
        MemoryBroker::with_config(MemoryBrokerConfig {
            total_memory_bytes: 64 * 1024 * 1024, // 64 MB for tests
            ..Default::default()
        })
    }

    #[test]
    fn broker_allocate_free() {
        let broker = make_broker();
        let initial_free = broker.free_pages();
        let pfn = broker.allocate_page(Domain::Windows).unwrap();
        assert_eq!(broker.free_pages(), initial_free - 1);
        broker.free_page(pfn).unwrap();
        assert_eq!(broker.free_pages(), initial_free);
    }

    #[test]
    fn broker_create_umo() {
        let broker = make_broker();
        let session = Uuid::new_v4();
        let id = broker.create_umo("test.docx", UmoKind::Document, session, Domain::Windows).unwrap();
        assert_eq!(broker.umo_count(), 1);
        broker.destroy_umo(&id).unwrap();
        assert_eq!(broker.umo_count(), 0);
    }

    #[test]
    fn broker_write_read_umo() {
        let broker = make_broker();
        let session = Uuid::new_v4();
        let id = broker.create_umo("data.bin", UmoKind::Blob, session, Domain::Windows).unwrap();
        let data = b"Hello, Surface Zenith!";
        broker.write_umo(&id, 0, data, Domain::Windows).unwrap();
        let read_back = broker.read_umo(&id, 0, data.len()).unwrap();
        assert_eq!(read_back, data);
    }

    #[test]
    fn broker_dirty_tracking() {
        let broker = make_broker();
        let pfn = broker.allocate_page(Domain::Windows).unwrap();
        assert_eq!(broker.dirty_page_count(), 0);
        broker.mark_dirty(pfn, Some(&Domain::Windows), None);
        assert_eq!(broker.dirty_page_count(), 1);
        broker.clear_dirty_all();
        assert_eq!(broker.dirty_page_count(), 0);
    }

    #[test]
    fn broker_cow_mapping() {
        let broker = make_broker();
        let pfn = broker.allocate_page(Domain::Windows).unwrap();
        broker.create_cow_mapping(pfn, 0, None, &Domain::Windows, 0x1000);
        assert_eq!(broker.cow_mapping_count(), 1);
    }

    #[test]
    fn broker_utilization() {
        let broker = make_broker();
        let total = broker.total_pages();
        for _ in 0..100 {
            broker.allocate_page(Domain::AI).unwrap();
        }
        let util = broker.utilization();
        assert!(util > 0.0);
        assert!(util < 1.0);
    }
}