//! # Zero Page Manager
//!
//! Manages the shared zero page — a single read-only page of zeros
//! that all domains map for uninitialized memory, reducing physical
//! memory usage for sparse allocations.

use std::collections::HashMap;
use zenith_abi::domain::Domain;

/// Zero page mapping record
#[derive(Debug, Clone)]
pub struct ZeroPageMapping {
    pub domain:  Domain,
    pub va:      u64,
    pub count:   u64, // Number of virtual pages mapped to zero page
}

/// Zero page manager
#[derive(Debug, Default)]
pub struct ZeroPageManager {
    /// Domain → zero page mappings
    mappings:        HashMap<String, Vec<ZeroPageMapping>>,
    /// Total zero page references
    total_refs:      u64,
    /// Total CoW faults from zero page
    cow_faults:      u64,
    /// Bytes saved by zero page sharing
    bytes_saved:     u64,
}

impl ZeroPageManager {
    pub fn new() -> Self { Self::default() }

    /// Map a virtual address to the zero page for a domain
    pub fn map_zero_page(&mut self, domain: Domain, va: u64) {
        let mapping = ZeroPageMapping {
            domain: domain.clone(),
            va,
            count: 1,
        };
        self.mappings.entry(domain.name().to_string()).or_default().push(mapping);
        self.total_refs += 1;
        self.bytes_saved += crate::PAGE_SIZE as u64;
    }

    /// Unmap a zero page reference (CoW fault occurred)
    pub fn unmap_zero_page(&mut self, domain: &Domain, va: u64) -> bool {
        if let Some(mappings) = self.mappings.get_mut(domain.name()) {
            let before = mappings.len();
            mappings.retain(|m| m.va != va);
            let removed = mappings.len() < before;
            if removed {
                self.total_refs = self.total_refs.saturating_sub(1);
                self.bytes_saved = self.bytes_saved.saturating_sub(crate::PAGE_SIZE as u64);
                self.cow_faults += 1;
            }
            removed
        } else {
            false
        }
    }

    /// Number of zero page references for a domain
    pub fn domain_ref_count(&self, domain: &Domain) -> usize {
        self.mappings.get(domain.name()).map(|m| m.len()).unwrap_or(0)
    }

    /// Total zero page references
    pub fn total_refs(&self) -> u64 { self.total_refs }

    /// Total CoW faults from zero page
    pub fn cow_faults(&self) -> u64 { self.cow_faults }

    /// Bytes saved by zero page sharing
    pub fn bytes_saved(&self) -> u64 { self.bytes_saved }

    /// Zero page physical address
    pub fn zero_page_pa() -> u64 { crate::ZERO_PAGE_PA }

    /// Whether a physical address is the zero page
    pub fn is_zero_page(pa: u64) -> bool { pa == crate::ZERO_PAGE_PA }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn zero_page_map_unmap() {
        let mut mgr = ZeroPageManager::new();
        mgr.map_zero_page(Domain::Windows, 0x1000);
        mgr.map_zero_page(Domain::Windows, 0x2000);
        mgr.map_zero_page(Domain::Android, 0x3000);
        assert_eq!(mgr.total_refs(), 3);
        assert_eq!(mgr.domain_ref_count(&Domain::Windows), 2);
        assert!(mgr.unmap_zero_page(&Domain::Windows, 0x1000));
        assert_eq!(mgr.cow_faults(), 1);
        assert_eq!(mgr.domain_ref_count(&Domain::Windows), 1);
    }

    #[test]
    fn zero_page_bytes_saved() {
        let mut mgr = ZeroPageManager::new();
        for i in 0..10 {
            mgr.map_zero_page(Domain::AI, i * 0x1000);
        }
        assert_eq!(mgr.bytes_saved(), 10 * crate::PAGE_SIZE as u64);
    }

    #[test]
    fn zero_page_address() {
        assert_eq!(ZeroPageManager::zero_page_pa(), crate::ZERO_PAGE_PA);
        assert!(ZeroPageManager::is_zero_page(crate::ZERO_PAGE_PA));
        assert!(!ZeroPageManager::is_zero_page(0x2000));
    }
}