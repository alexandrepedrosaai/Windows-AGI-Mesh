//! # Huge Page Manager
//!
//! Manages 2MB and 1GB huge pages for performance-critical workloads.

use std::collections::HashMap;
use zenith_abi::domain::Domain;
use crate::error::MemoryError;

/// Huge page size
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub enum HugePageSize {
    /// 2 MB huge page (512 × 4KB pages)
    TwoMb,
    /// 1 GB gigantic page (512 × 2MB pages)
    OneGb,
}

impl HugePageSize {
    pub fn bytes(&self) -> u64 {
        match self {
            HugePageSize::TwoMb => crate::HUGE_PAGE_SIZE as u64,
            HugePageSize::OneGb => crate::GIGA_PAGE_SIZE as u64,
        }
    }

    pub fn page_count(&self) -> u64 {
        self.bytes() / crate::PAGE_SIZE as u64
    }

    pub fn alignment(&self) -> u64 {
        self.bytes()
    }
}

/// A huge page allocation
#[derive(Debug, Clone)]
pub struct HugePage {
    pub id:       uuid::Uuid,
    pub base_pfn: u64,
    pub size:     HugePageSize,
    pub domain:   Domain,
    pub pinned:   bool,
    pub allocated_at: std::time::Instant,
}

impl HugePage {
    pub fn new(base_pfn: u64, size: HugePageSize, domain: Domain) -> Self {
        Self {
            id:           uuid::Uuid::new_v4(),
            base_pfn,
            size,
            domain,
            pinned:       false,
            allocated_at: std::time::Instant::now(),
        }
    }

    pub fn end_pfn(&self) -> u64 {
        self.base_pfn + self.size.page_count()
    }

    pub fn contains_pfn(&self, pfn: u64) -> bool {
        pfn >= self.base_pfn && pfn < self.end_pfn()
    }

    pub fn size_bytes(&self) -> u64 {
        self.size.bytes()
    }
}

/// Huge page manager
#[derive(Debug, Default)]
pub struct HugePageManager {
    /// Allocated huge pages
    pages:           HashMap<uuid::Uuid, HugePage>,
    /// Free huge page base PFNs by size
    free_2mb:        Vec<u64>,
    free_1gb:        Vec<u64>,
    total_2mb:       u64,
    total_1gb:       u64,
    alloc_count:     u64,
    free_count:      u64,
}

impl HugePageManager {
    pub fn new() -> Self { Self::default() }

    /// Register free huge pages
    pub fn register_free_2mb(&mut self, base_pfn: u64) {
        self.free_2mb.push(base_pfn);
        self.total_2mb += 1;
    }

    pub fn register_free_1gb(&mut self, base_pfn: u64) {
        self.free_1gb.push(base_pfn);
        self.total_1gb += 1;
    }

    /// Allocate a huge page
    pub fn allocate(&mut self, size: HugePageSize, domain: Domain) -> Result<uuid::Uuid, MemoryError> {
        let base_pfn = match size {
            HugePageSize::TwoMb => self.free_2mb.pop(),
            HugePageSize::OneGb => self.free_1gb.pop(),
        }.ok_or(MemoryError::OutOfMemory)?;

        let page = HugePage::new(base_pfn, size, domain);
        let id = page.id;
        self.pages.insert(id, page);
        self.alloc_count += 1;
        Ok(id)
    }

    /// Free a huge page
    pub fn free(&mut self, id: &uuid::Uuid) -> Result<(), MemoryError> {
        let page = self.pages.remove(id)
            .ok_or(MemoryError::UmoNotFound { id: id.to_string() })?;

        match page.size {
            HugePageSize::TwoMb => self.free_2mb.push(page.base_pfn),
            HugePageSize::OneGb => self.free_1gb.push(page.base_pfn),
        }
        self.free_count += 1;
        Ok(())
    }

    /// Get a huge page by ID
    pub fn get(&self, id: &uuid::Uuid) -> Option<&HugePage> {
        self.pages.get(id)
    }

    /// Find the huge page containing a PFN
    pub fn find_by_pfn(&self, pfn: u64) -> Option<&HugePage> {
        self.pages.values().find(|p| p.contains_pfn(pfn))
    }

    /// Total allocated huge pages
    pub fn allocated_count(&self) -> usize { self.pages.len() }

    /// Free 2MB pages
    pub fn free_2mb_count(&self) -> usize { self.free_2mb.len() }

    /// Free 1GB pages
    pub fn free_1gb_count(&self) -> usize { self.free_1gb.len() }

    /// Total memory in huge pages (bytes)
    pub fn total_huge_memory_bytes(&self) -> u64 {
        self.pages.values().map(|p| p.size_bytes()).sum()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn huge_page_size_bytes() {
        assert_eq!(HugePageSize::TwoMb.bytes(), 2 * 1024 * 1024);
        assert_eq!(HugePageSize::OneGb.bytes(), 1024 * 1024 * 1024);
        assert_eq!(HugePageSize::TwoMb.page_count(), 512);
    }

    #[test]
    fn huge_page_manager_allocate_free() {
        let mut mgr = HugePageManager::new();
        mgr.register_free_2mb(0);
        mgr.register_free_2mb(512);
        let id = mgr.allocate(HugePageSize::TwoMb, Domain::AI).unwrap();
        assert_eq!(mgr.allocated_count(), 1);
        assert_eq!(mgr.free_2mb_count(), 1);
        mgr.free(&id).unwrap();
        assert_eq!(mgr.allocated_count(), 0);
        assert_eq!(mgr.free_2mb_count(), 2);
    }

    #[test]
    fn huge_page_contains_pfn() {
        let page = HugePage::new(0, HugePageSize::TwoMb, Domain::Windows);
        assert!(page.contains_pfn(0));
        assert!(page.contains_pfn(511));
        assert!(!page.contains_pfn(512));
    }

    #[test]
    fn huge_page_out_of_memory() {
        let mut mgr = HugePageManager::new();
        assert!(mgr.allocate(HugePageSize::TwoMb, Domain::Windows).is_err());
    }
}