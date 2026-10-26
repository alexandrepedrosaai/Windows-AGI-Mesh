//! # Physical Page Frame Allocator
//!
//! Manages the physical page frame database (PFD) — the master record
//! of every physical memory page in the system.

use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, VecDeque};
use zenith_abi::domain::Domain;
use zenith_abi::types::ZObjectId;
use crate::error::MemoryError;

// ---------------------------------------------------------------------------
// Page frame state
// ---------------------------------------------------------------------------

/// State of a physical page frame
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum PageFrameState {
    /// Page is free and available for allocation
    Free,
    /// Page is allocated and in use
    Allocated,
    /// Page is a zero page (shared read-only)
    Zero,
    /// Page is Copy-on-Write (shared, will be copied on write)
    CopyOnWrite { ref_count: u32 },
    /// Page is pinned (cannot be swapped or migrated)
    Pinned,
    /// Page has been swapped out to storage
    Swapped { swap_offset: u64 },
    /// Page is being migrated between domains
    Migrating,
    /// Page is reserved (firmware, MMIO, etc.)
    Reserved,
    /// Page is a huge page (2MB or 1GB)
    HugePage { size: usize },
    /// Page is dirty (modified since last checkpoint)
    Dirty,
}

impl PageFrameState {
    /// Whether this page can be allocated
    pub fn is_free(&self) -> bool {
        matches!(self, PageFrameState::Free | PageFrameState::Zero)
    }

    /// Whether this page is in active use
    pub fn is_active(&self) -> bool {
        matches!(
            self,
            PageFrameState::Allocated
                | PageFrameState::CopyOnWrite { .. }
                | PageFrameState::Pinned
                | PageFrameState::Dirty
        )
    }

    /// Whether this page can be reclaimed under memory pressure
    pub fn is_reclaimable(&self) -> bool {
        matches!(
            self,
            PageFrameState::Allocated | PageFrameState::CopyOnWrite { .. } | PageFrameState::Dirty
        )
    }

    /// Whether this page is a CoW page
    pub fn is_cow(&self) -> bool {
        matches!(self, PageFrameState::CopyOnWrite { .. })
    }

    /// CoW reference count (0 if not CoW)
    pub fn cow_ref_count(&self) -> u32 {
        if let PageFrameState::CopyOnWrite { ref_count } = self {
            *ref_count
        } else {
            0
        }
    }
}

// ---------------------------------------------------------------------------
// Page frame descriptor
// ---------------------------------------------------------------------------

/// Descriptor for a single physical page frame
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PageFrame {
    /// Physical frame number (PFN)
    pub pfn:         u64,
    /// Physical address (pfn × PAGE_SIZE)
    pub pa:          u64,
    /// Current state
    pub state:       PageFrameState,
    /// Domain that owns this page
    pub owner:       Option<Domain>,
    /// UMO this page belongs to (if any)
    pub umo_id:      Option<ZObjectId>,
    /// Page index within the UMO
    pub umo_page_idx: Option<u64>,
    /// Access count (for LRU eviction)
    pub access_count: u64,
    /// Last access timestamp (nanoseconds since boot)
    pub last_access:  u64,
    /// Whether this page has been modified since last checkpoint
    pub dirty:        bool,
    /// NUMA node this page is on
    pub numa_node:    u8,
    /// Page flags (architecture-specific)
    pub flags:        u64,
}

impl PageFrame {
    /// Create a new free page frame
    pub fn new_free(pfn: u64, numa_node: u8) -> Self {
        Self {
            pfn,
            pa:           pfn * crate::PAGE_SIZE as u64,
            state:        PageFrameState::Free,
            owner:        None,
            umo_id:       None,
            umo_page_idx: None,
            access_count: 0,
            last_access:  0,
            dirty:        false,
            numa_node,
            flags:        0,
        }
    }

    /// Allocate this page to a domain
    pub fn allocate(&mut self, owner: Domain) {
        self.state  = PageFrameState::Allocated;
        self.owner  = Some(owner);
        self.dirty  = false;
        self.access_count = 0;
    }

    /// Free this page
    pub fn free(&mut self) {
        self.state        = PageFrameState::Free;
        self.owner        = None;
        self.umo_id       = None;
        self.umo_page_idx = None;
        self.dirty        = false;
        self.flags        = 0;
    }

    /// Mark this page as dirty
    pub fn mark_dirty(&mut self) {
        self.dirty = true;
        if self.state == PageFrameState::Allocated {
            self.state = PageFrameState::Dirty;
        }
    }

    /// Clear dirty flag
    pub fn clear_dirty(&mut self) {
        self.dirty = false;
        if self.state == PageFrameState::Dirty {
            self.state = PageFrameState::Allocated;
        }
    }

    /// Convert to CoW page
    pub fn make_cow(&mut self) {
        self.state = PageFrameState::CopyOnWrite { ref_count: 2 };
    }

    /// Increment CoW reference count
    pub fn cow_ref(&mut self) {
        if let PageFrameState::CopyOnWrite { ref_count } = &mut self.state {
            *ref_count += 1;
        }
    }

    /// Decrement CoW reference count; returns true if page should be freed
    pub fn cow_unref(&mut self) -> bool {
        if let PageFrameState::CopyOnWrite { ref_count } = &mut self.state {
            *ref_count -= 1;
            if *ref_count == 0 {
                self.free();
                return true;
            }
        }
        false
    }

    /// Pin this page (prevent eviction)
    pub fn pin(&mut self) {
        self.state = PageFrameState::Pinned;
    }

    /// Unpin this page
    pub fn unpin(&mut self) {
        self.state = PageFrameState::Allocated;
    }

    /// Record an access to this page
    pub fn record_access(&mut self, timestamp_ns: u64) {
        self.access_count += 1;
        self.last_access   = timestamp_ns;
    }

    /// Age of this page (nanoseconds since last access)
    pub fn age_ns(&self, now_ns: u64) -> u64 {
        now_ns.saturating_sub(self.last_access)
    }

    /// Whether this page is eligible for eviction
    pub fn is_evictable(&self) -> bool {
        self.state.is_reclaimable() && !matches!(self.state, PageFrameState::Pinned)
    }
}

// ---------------------------------------------------------------------------
// Physical page frame database
// ---------------------------------------------------------------------------

/// The Physical Page Frame Database (PFD)
///
/// Tracks the state of every physical memory page in the system.
/// This is the authoritative source of truth for physical memory.
#[derive(Debug)]
pub struct PageFrameDatabase {
    /// All page frames indexed by PFN
    frames:         BTreeMap<u64, PageFrame>,
    /// Free page list (PFNs)
    free_list:      VecDeque<u64>,
    /// Total physical pages
    total_pages:    u64,
    /// Free pages
    free_pages:     u64,
    /// Allocated pages
    allocated_pages: u64,
    /// CoW pages
    cow_pages:      u64,
    /// Dirty pages
    dirty_pages:    u64,
    /// Pinned pages
    pinned_pages:   u64,
    /// Swapped pages
    swapped_pages:  u64,
}

impl PageFrameDatabase {
    /// Create a new PFD for a given physical memory size
    pub fn new(memory_bytes: u64) -> Self {
        let total_pages = memory_bytes / crate::PAGE_SIZE as u64;
        let mut frames  = BTreeMap::new();
        let mut free_list = VecDeque::with_capacity(total_pages as usize);

        for pfn in 0..total_pages {
            let numa_node = (pfn / (total_pages / 2).max(1)) as u8;
            frames.insert(pfn, PageFrame::new_free(pfn, numa_node));
            free_list.push_back(pfn);
        }

        Self {
            frames,
            free_list,
            total_pages,
            free_pages:      total_pages,
            allocated_pages: 0,
            cow_pages:       0,
            dirty_pages:     0,
            pinned_pages:    0,
            swapped_pages:   0,
        }
    }

    /// Allocate a free page frame
    pub fn allocate(&mut self, owner: Domain) -> Result<u64, MemoryError> {
        let pfn = self.free_list.pop_front()
            .ok_or(MemoryError::OutOfMemory)?;

        if let Some(frame) = self.frames.get_mut(&pfn) {
            frame.allocate(owner);
            self.free_pages      = self.free_pages.saturating_sub(1);
            self.allocated_pages += 1;
        }

        Ok(pfn)
    }

    /// Allocate multiple contiguous pages
    pub fn allocate_contiguous(&mut self, count: u64, owner: Domain) -> Result<Vec<u64>, MemoryError> {
        if self.free_pages < count {
            return Err(MemoryError::OutOfMemory);
        }

        let mut pfns = Vec::with_capacity(count as usize);
        for _ in 0..count {
            pfns.push(self.allocate(owner.clone())?);
        }
        Ok(pfns)
    }

    /// Free a page frame
    pub fn free(&mut self, pfn: u64) -> Result<(), MemoryError> {
        let frame = self.frames.get_mut(&pfn)
            .ok_or(MemoryError::InvalidPfn { pfn })?;

        let was_dirty  = frame.dirty;
        let was_cow    = frame.state.is_cow();
        let was_pinned = matches!(frame.state, PageFrameState::Pinned);

        frame.free();
        self.free_list.push_back(pfn);
        self.free_pages      += 1;
        self.allocated_pages  = self.allocated_pages.saturating_sub(1);
        if was_dirty  { self.dirty_pages  = self.dirty_pages.saturating_sub(1); }
        if was_cow    { self.cow_pages    = self.cow_pages.saturating_sub(1); }
        if was_pinned { self.pinned_pages = self.pinned_pages.saturating_sub(1); }

        Ok(())
    }

    /// Get a page frame by PFN
    pub fn get(&self, pfn: u64) -> Option<&PageFrame> {
        self.frames.get(&pfn)
    }

    /// Get a mutable page frame by PFN
    pub fn get_mut(&mut self, pfn: u64) -> Option<&mut PageFrame> {
        self.frames.get_mut(&pfn)
    }

    /// Mark a page as dirty
    pub fn mark_dirty(&mut self, pfn: u64) {
        if let Some(frame) = self.frames.get_mut(&pfn) {
            if !frame.dirty {
                frame.mark_dirty();
                self.dirty_pages += 1;
            }
        }
    }

    /// Clear dirty flag on a page
    pub fn clear_dirty(&mut self, pfn: u64) {
        if let Some(frame) = self.frames.get_mut(&pfn) {
            if frame.dirty {
                frame.clear_dirty();
                self.dirty_pages = self.dirty_pages.saturating_sub(1);
            }
        }
    }

    /// Convert a page to CoW
    pub fn make_cow(&mut self, pfn: u64) {
        if let Some(frame) = self.frames.get_mut(&pfn) {
            if !frame.state.is_cow() {
                frame.make_cow();
                self.cow_pages += 1;
                self.allocated_pages = self.allocated_pages.saturating_sub(1);
            }
        }
    }

    /// Pin a page
    pub fn pin(&mut self, pfn: u64) {
        if let Some(frame) = self.frames.get_mut(&pfn) {
            if !matches!(frame.state, PageFrameState::Pinned) {
                frame.pin();
                self.pinned_pages += 1;
            }
        }
    }

    /// Unpin a page
    pub fn unpin(&mut self, pfn: u64) {
        if let Some(frame) = self.frames.get_mut(&pfn) {
            if matches!(frame.state, PageFrameState::Pinned) {
                frame.unpin();
                self.pinned_pages = self.pinned_pages.saturating_sub(1);
            }
        }
    }

    /// Get all dirty pages for a domain
    pub fn dirty_pages_for_domain(&self, domain: &Domain) -> Vec<u64> {
        self.frames.values()
            .filter(|f| f.dirty && f.owner.as_ref() == Some(domain))
            .map(|f| f.pfn)
            .collect()
    }

    /// Get all pages for a UMO
    pub fn pages_for_umo(&self, umo_id: &ZObjectId) -> Vec<u64> {
        self.frames.values()
            .filter(|f| f.umo_id.as_ref() == Some(umo_id))
            .map(|f| f.pfn)
            .collect()
    }

    /// Memory utilization ratio (0.0–1.0)
    pub fn utilization(&self) -> f64 {
        if self.total_pages == 0 { return 0.0; }
        (self.total_pages - self.free_pages) as f64 / self.total_pages as f64
    }

    /// Statistics snapshot
    pub fn stats(&self) -> PageFrameStats {
        PageFrameStats {
            total_pages:     self.total_pages,
            free_pages:      self.free_pages,
            allocated_pages: self.allocated_pages,
            cow_pages:       self.cow_pages,
            dirty_pages:     self.dirty_pages,
            pinned_pages:    self.pinned_pages,
            swapped_pages:   self.swapped_pages,
            utilization:     self.utilization(),
        }
    }

    /// Total pages
    pub fn total_pages(&self) -> u64 { self.total_pages }

    /// Free pages
    pub fn free_pages(&self) -> u64 { self.free_pages }

    /// Allocated pages
    pub fn allocated_pages(&self) -> u64 { self.allocated_pages }

    /// Dirty pages
    pub fn dirty_pages(&self) -> u64 { self.dirty_pages }
}

/// Page frame statistics snapshot
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PageFrameStats {
    pub total_pages:     u64,
    pub free_pages:      u64,
    pub allocated_pages: u64,
    pub cow_pages:       u64,
    pub dirty_pages:     u64,
    pub pinned_pages:    u64,
    pub swapped_pages:   u64,
    pub utilization:     f64,
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    fn make_pfd(pages: u64) -> PageFrameDatabase {
        PageFrameDatabase::new(pages * crate::PAGE_SIZE as u64)
    }

    #[test]
    fn pfd_allocate_free() {
        let mut pfd = make_pfd(1024);
        assert_eq!(pfd.free_pages(), 1024);
        let pfn = pfd.allocate(Domain::Windows).unwrap();
        assert_eq!(pfd.free_pages(), 1023);
        assert_eq!(pfd.allocated_pages(), 1);
        pfd.free(pfn).unwrap();
        assert_eq!(pfd.free_pages(), 1024);
        assert_eq!(pfd.allocated_pages(), 0);
    }

    #[test]
    fn pfd_out_of_memory() {
        let mut pfd = make_pfd(2);
        pfd.allocate(Domain::Android).unwrap();
        pfd.allocate(Domain::Android).unwrap();
        assert!(pfd.allocate(Domain::Android).is_err());
    }

    #[test]
    fn pfd_dirty_tracking() {
        let mut pfd = make_pfd(64);
        let pfn = pfd.allocate(Domain::Windows).unwrap();
        assert_eq!(pfd.dirty_pages(), 0);
        pfd.mark_dirty(pfn);
        assert_eq!(pfd.dirty_pages(), 1);
        pfd.clear_dirty(pfn);
        assert_eq!(pfd.dirty_pages(), 0);
    }

    #[test]
    fn pfd_cow_tracking() {
        let mut pfd = make_pfd(64);
        let pfn = pfd.allocate(Domain::Windows).unwrap();
        pfd.make_cow(pfn);
        let frame = pfd.get(pfn).unwrap();
        assert!(frame.state.is_cow());
        assert_eq!(frame.state.cow_ref_count(), 2);
    }

    #[test]
    fn pfd_pin_unpin() {
        let mut pfd = make_pfd(64);
        let pfn = pfd.allocate(Domain::AI).unwrap();
        pfd.pin(pfn);
        assert!(!pfd.get(pfn).unwrap().is_evictable());
        pfd.unpin(pfn);
        assert!(pfd.get(pfn).unwrap().is_evictable());
    }

    #[test]
    fn pfd_utilization() {
        let mut pfd = make_pfd(100);
        for _ in 0..50 {
            pfd.allocate(Domain::Windows).unwrap();
        }
        assert!((pfd.utilization() - 0.5).abs() < 0.01);
    }

    #[test]
    fn pfd_contiguous_allocation() {
        let mut pfd = make_pfd(256);
        let pfns = pfd.allocate_contiguous(16, Domain::AI).unwrap();
        assert_eq!(pfns.len(), 16);
        assert_eq!(pfd.allocated_pages(), 16);
    }

    #[test]
    fn page_frame_lifecycle() {
        let mut frame = PageFrame::new_free(42, 0);
        assert!(frame.state.is_free());
        frame.allocate(Domain::Windows);
        assert!(frame.state.is_active());
        frame.mark_dirty();
        assert!(frame.dirty);
        frame.clear_dirty();
        assert!(!frame.dirty);
        frame.free();
        assert!(frame.state.is_free());
    }
}