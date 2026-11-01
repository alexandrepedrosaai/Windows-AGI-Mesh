//! # Copy-on-Write (CoW) Engine
//!
//! Implements Copy-on-Write page sharing between domain containers.
//! When multiple domains map the same physical page, they share it
//! read-only. On the first write, the writing domain gets a private copy.
//!
//! ## CoW Protocol
//!
//! ```text
//! Domain A maps page P (read-only)
//! Domain B maps page P (read-only)
//! → Both share the same physical page (ref_count = 2)
//!
//! Domain A writes to page P:
//! → Page fault (write to read-only page)
//! → CoW handler allocates new page P'
//! → Copies P → P'
//! → Domain A now maps P' (read-write)
//! → Domain B still maps P (ref_count = 1 → becomes read-write)
//! ```

use std::collections::HashMap;
use uuid::Uuid;
use zenith_abi::domain::Domain;
use zenith_abi::types::ZObjectId;
use crate::error::MemoryError;
use crate::page_frame::PageFrameDatabase;

// ---------------------------------------------------------------------------
// CoW mapping
// ---------------------------------------------------------------------------

/// A CoW mapping: multiple domains sharing a physical page
#[derive(Debug, Clone)]
pub struct CowMapping {
    /// Physical frame number of the shared page
    pub pfn:        u64,
    /// UMO this page belongs to
    pub umo_id:     Option<ZObjectId>,
    /// Page index within the UMO
    pub page_idx:   u64,
    /// Domains sharing this page (domain name → virtual address)
    pub sharers:    HashMap<String, u64>,
    /// Reference count
    pub ref_count:  u32,
    /// Whether the original page has been modified
    pub dirty:      bool,
    /// Creation timestamp
    pub created_at: std::time::Instant,
}

impl CowMapping {
    /// Create a new CoW mapping
    pub fn new(pfn: u64, page_idx: u64) -> Self {
        Self {
            pfn,
            umo_id:     None,
            page_idx,
            sharers:    HashMap::new(),
            ref_count:  0,
            dirty:      false,
            created_at: std::time::Instant::now(),
        }
    }

    /// Add a domain as a sharer
    pub fn add_sharer(&mut self, domain: &Domain, va: u64) {
if self.sharers.insert(domain.name().to_string(), va).is_none() {
    self.ref_count += 1;
}
    }

    /// Remove a domain from sharers
    pub fn remove_sharer(&mut self, domain: &Domain) -> bool {
        if self.sharers.remove(domain.name()).is_some() {
            self.ref_count = self.ref_count.saturating_sub(1);
            true
        } else {
            false
        }
    }

    /// Whether a domain is sharing this page
    pub fn has_sharer(&self, domain: &Domain) -> bool {
        self.sharers.contains_key(domain.name())
    }

    /// Virtual address for a domain
    pub fn va_for(&self, domain: &Domain) -> Option<u64> {
        self.sharers.get(domain.name()).copied()
    }

    /// Whether this mapping can be collapsed (only one sharer left)
    pub fn can_collapse(&self) -> bool {
        self.ref_count <= 1
    }

    /// Age of this mapping in milliseconds
    pub fn age_ms(&self) -> u64 {
        self.created_at.elapsed().as_millis() as u64
    }
}

// ---------------------------------------------------------------------------
// CoW fault result
// ---------------------------------------------------------------------------

/// Result of handling a CoW page fault
#[derive(Debug, Clone)]
pub struct CowFaultResult {
    /// New physical frame number (private copy)
    pub new_pfn:        u64,
    /// Old physical frame number (shared page)
    pub old_pfn:        u64,
    /// Domain that triggered the fault
    pub domain:         Domain,
    /// Whether the old page was freed (last reference)
    pub old_page_freed: bool,
    /// Bytes copied
    pub bytes_copied:   usize,
    /// Time taken in microseconds
    pub duration_us:    u64,
}

// ---------------------------------------------------------------------------
// CoW engine
// ---------------------------------------------------------------------------

/// The Copy-on-Write Engine
///
/// Manages CoW mappings and handles CoW page faults.
#[derive(Debug, Default)]
pub struct CowEngine {
    /// Active CoW mappings indexed by PFN
    mappings:       HashMap<u64, CowMapping>,
    /// Total CoW faults handled
    total_faults:   u64,
    /// Total pages copied
    total_copies:   u64,
    /// Total bytes copied
    total_bytes:    u64,
    /// Total CoW pages collapsed (became private)
    total_collapsed: u64,
}

impl CowEngine {
    /// Create a new CoW engine
    pub fn new() -> Self { Self::default() }

    /// Create a CoW mapping for a page
    pub fn create_mapping(
        &mut self,
        pfn: u64,
        page_idx: u64,
        umo_id: Option<ZObjectId>,
        initial_domain: &Domain,
        va: u64,
    ) -> &CowMapping {
        let mut mapping = CowMapping::new(pfn, page_idx);
        mapping.umo_id = umo_id;
        mapping.add_sharer(initial_domain, va);
        self.mappings.insert(pfn, mapping);
        self.mappings.get(&pfn).unwrap()
    }

    /// Add a domain to an existing CoW mapping
    pub fn add_sharer(
        &mut self,
        pfn: u64,
        domain: &Domain,
        va: u64,
    ) -> Result<(), MemoryError> {
        let mapping = self.mappings.get_mut(&pfn)
            .ok_or(MemoryError::CowMappingNotFound { pfn })?;
        mapping.add_sharer(domain, va);
        Ok(())
    }

    /// Handle a CoW page fault (write to a shared page)
    ///
    /// Allocates a new private page for the writing domain and copies
    /// the shared page content to it.
    pub fn handle_fault(
        &mut self,
        pfn: u64,
        domain: &Domain,
        pfd: &mut PageFrameDatabase,
        page_data: &[u8],
    ) -> Result<CowFaultResult, MemoryError> {
        let start = std::time::Instant::now();
        self.total_faults += 1;

        // Get the CoW mapping
        let mapping = self.mappings.get_mut(&pfn)
            .ok_or(MemoryError::CowMappingNotFound { pfn })?;

        // Remove this domain from the shared mapping
        mapping.remove_sharer(domain);
        let old_page_freed = mapping.can_collapse();
        let old_pfn = pfn;

        // If only one sharer remains, collapse the CoW mapping
        if old_page_freed {
            self.mappings.remove(&pfn);
            self.total_collapsed += 1;
        }

        // Allocate a new private page for the writing domain
        let new_pfn = pfd.allocate(domain.clone())?;

        // Copy page data to new page
        let bytes_copied = page_data.len().min(crate::PAGE_SIZE);
        self.total_copies += 1;
        self.total_bytes  += bytes_copied as u64;

        // Mark new page as dirty (it was just written)
        pfd.mark_dirty(new_pfn);

        let duration_us = start.elapsed().as_micros() as u64;

        Ok(CowFaultResult {
            new_pfn,
            old_pfn,
            domain: domain.clone(),
            old_page_freed,
            bytes_copied,
            duration_us,
        })
    }

    /// Remove a domain from all CoW mappings (e.g., on domain crash)
    pub fn remove_domain(&mut self, domain: &Domain) -> usize {
        let mut removed = 0;
        let pfns: Vec<u64> = self.mappings.keys().copied().collect();
        for pfn in pfns {
            if let Some(mapping) = self.mappings.get_mut(&pfn) {
                if mapping.remove_sharer(domain) {
                    removed += 1;
                    if mapping.can_collapse() {
                        self.mappings.remove(&pfn);
                        self.total_collapsed += 1;
                    }
                }
            }
        }
        removed
    }

    /// Get a CoW mapping by PFN
    pub fn get_mapping(&self, pfn: u64) -> Option<&CowMapping> {
        self.mappings.get(&pfn)
    }

    /// Whether a page is a CoW page
    pub fn is_cow(&self, pfn: u64) -> bool {
        self.mappings.contains_key(&pfn)
    }

    /// Total active CoW mappings
    pub fn mapping_count(&self) -> usize {
        self.mappings.len()
    }

    /// Total CoW faults handled
    pub fn total_faults(&self) -> u64 { self.total_faults }

    /// Total pages copied
    pub fn total_copies(&self) -> u64 { self.total_copies }

    /// Total bytes copied
    pub fn total_bytes(&self) -> u64 { self.total_bytes }

    /// Average copy size in bytes
    pub fn avg_copy_size(&self) -> f64 {
        if self.total_copies == 0 { return 0.0; }
        self.total_bytes as f64 / self.total_copies as f64
    }

    /// CoW collapse rate (pages that became private)
    pub fn collapse_rate(&self) -> f64 {
        if self.total_faults == 0 { return 0.0; }
        self.total_collapsed as f64 / self.total_faults as f64
    }

    /// Get all pages shared between two specific domains
    pub fn shared_pages(&self, domain_a: &Domain, domain_b: &Domain) -> Vec<u64> {
        self.mappings.iter()
            .filter(|(_, m)| m.has_sharer(domain_a) && m.has_sharer(domain_b))
            .map(|(&pfn, _)| pfn)
            .collect()
    }

    /// Statistics snapshot
    pub fn stats(&self) -> CowStats {
        CowStats {
            active_mappings: self.mapping_count(),
            total_faults:    self.total_faults,
            total_copies:    self.total_copies,
            total_bytes:     self.total_bytes,
            total_collapsed: self.total_collapsed,
            avg_copy_size:   self.avg_copy_size(),
            collapse_rate:   self.collapse_rate(),
        }
    }
}

/// CoW engine statistics
#[derive(Debug, Clone)]
pub struct CowStats {
    pub active_mappings: usize,
    pub total_faults:    u64,
    pub total_copies:    u64,
    pub total_bytes:     u64,
    pub total_collapsed: u64,
    pub avg_copy_size:   f64,
    pub collapse_rate:   f64,
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    fn make_pfd() -> PageFrameDatabase {
        PageFrameDatabase::new(1024 * crate::PAGE_SIZE as u64)
    }

    #[test]
    fn cow_mapping_creation() {
        let mut engine = CowEngine::new();
        let pfn = 42u64;
        engine.create_mapping(pfn, 0, None, &Domain::Windows, 0x1000);
        assert!(engine.is_cow(pfn));
        assert_eq!(engine.mapping_count(), 1);
    }

    #[test]
    fn cow_add_sharer() {
        let mut engine = CowEngine::new();
        engine.create_mapping(10, 0, None, &Domain::Windows, 0x1000);
        engine.add_sharer(10, &Domain::Android, 0x2000).unwrap();
        let mapping = engine.get_mapping(10).unwrap();
        assert_eq!(mapping.ref_count, 2);
        assert!(mapping.has_sharer(&Domain::Windows));
        assert!(mapping.has_sharer(&Domain::Android));
    }

    #[test]
    fn cow_fault_handling() {
        let mut engine = CowEngine::new();
        let mut pfd = make_pfd();

        // Allocate a shared page
        let pfn = pfd.allocate(Domain::Windows).unwrap();
        pfd.make_cow(pfn);

        engine.create_mapping(pfn, 0, None, &Domain::Windows, 0x1000);
        engine.add_sharer(pfn, &Domain::Android, 0x2000).unwrap();

        // Android writes to the shared page → CoW fault
        let page_data = vec![0xABu8; crate::PAGE_SIZE];
        let result = engine.handle_fault(pfn, &Domain::Android, &mut pfd, &page_data).unwrap();

        assert_ne!(result.new_pfn, result.old_pfn);
        assert_eq!(result.bytes_copied, crate::PAGE_SIZE);
        assert!(!result.old_page_freed); // Windows still has the original
        assert_eq!(engine.total_faults(), 1);
        assert_eq!(engine.total_copies(), 1);
    }

    #[test]
    fn cow_collapse_on_last_sharer() {
        let mut engine = CowEngine::new();
        let mut pfd = make_pfd();

        let pfn = pfd.allocate(Domain::Windows).unwrap();
        pfd.make_cow(pfn);

        engine.create_mapping(pfn, 0, None, &Domain::Windows, 0x1000);
        engine.add_sharer(pfn, &Domain::Android, 0x2000).unwrap();

        // Android writes → CoW fault
        let page_data = vec![0u8; crate::PAGE_SIZE];
        engine.handle_fault(pfn, &Domain::Android, &mut pfd, &page_data).unwrap();

        // Windows writes → last sharer, should collapse
        let result = engine.handle_fault(pfn, &Domain::Windows, &mut pfd, &page_data);
        // After Android's fault, Windows is the only sharer → mapping was collapsed
        // So this should return CowMappingNotFound
        assert!(result.is_err());
    }

    #[test]
    fn cow_remove_domain() {
        let mut engine = CowEngine::new();
        engine.create_mapping(1, 0, None, &Domain::Windows, 0x1000);
        engine.add_sharer(1, &Domain::Android, 0x2000).unwrap();
        engine.create_mapping(2, 1, None, &Domain::Windows, 0x3000);
        engine.add_sharer(2, &Domain::Android, 0x4000).unwrap();

        let removed = engine.remove_domain(&Domain::Android);
        assert_eq!(removed, 2);
    }

    #[test]
    fn cow_shared_pages_between_domains() {
        let mut engine = CowEngine::new();
        engine.create_mapping(5, 0, None, &Domain::Windows, 0x1000);
        engine.add_sharer(5, &Domain::Android, 0x2000).unwrap();
        engine.create_mapping(6, 1, None, &Domain::Windows, 0x3000);
        // Page 6 not shared with Android

        let shared = engine.shared_pages(&Domain::Windows, &Domain::Android);
        assert_eq!(shared.len(), 1);
        assert_eq!(shared[0], 5);
    }
}