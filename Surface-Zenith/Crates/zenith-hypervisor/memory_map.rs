//! # Memory Map Management
//!
//! Manages the virtual memory layout for each domain container.

use std::collections::BTreeMap;
use serde::{Deserialize, Serialize};
use zenith_abi::domain::Domain;

/// Memory region permissions
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct MemoryPermissions {
    pub read:    bool,
    pub write:   bool,
    pub execute: bool,
    pub user:    bool,
}

impl MemoryPermissions {
    pub fn rx()  -> Self { Self { read: true,  write: false, execute: true,  user: true } }
    pub fn rw()  -> Self { Self { read: true,  write: true,  execute: false, user: true } }
    pub fn ro()  -> Self { Self { read: true,  write: false, execute: false, user: true } }
    pub fn rwx() -> Self { Self { read: true,  write: true,  execute: true,  user: true } }
    pub fn none()-> Self { Self { read: false, write: false, execute: false, user: false } }
}

/// A virtual memory area (VMA)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VirtualMemoryArea {
    pub start:       u64,
    pub end:         u64,
    pub permissions: MemoryPermissions,
    pub name:        String,
    pub file_backed: bool,
    pub shared:      bool,
    pub page_count:  u64,
}

impl VirtualMemoryArea {
    pub fn new(start: u64, size: u64, perms: MemoryPermissions, name: impl Into<String>) -> Self {
        let page_count = (size + 4095) / 4096;
        Self {
            start,
            end: start + size,
            permissions: perms,
            name: name.into(),
            file_backed: false,
            shared: false,
            page_count,
        }
    }

    pub fn size(&self) -> u64 { self.end - self.start }
    pub fn contains(&self, va: u64) -> bool { va >= self.start && va < self.end }
}

/// Virtual memory map for a domain container
#[derive(Debug, Default)]
pub struct DomainMemoryMap {
    pub domain:  Option<Domain>,
    /// VMAs sorted by start address
    areas:       BTreeMap<u64, VirtualMemoryArea>,
    total_mapped: u64,
}

impl DomainMemoryMap {
    pub fn new(domain: Domain) -> Self {
        Self { domain: Some(domain), ..Default::default() }
    }

    /// Create a standard ARM64 memory map for a domain
    pub fn standard_arm64(domain: Domain) -> Self {
        let mut map = Self::new(domain);
        // Kernel space (EL1)
        map.add_area(VirtualMemoryArea::new(
            0xFFFF_0000_0000_0000, 0x0001_0000_0000,
            MemoryPermissions::rx(), "kernel-text",
        ));
        map.add_area(VirtualMemoryArea::new(
            0xFFFF_0001_0000_0000, 0x0001_0000_0000,
            MemoryPermissions::rw(), "kernel-data",
        ));
        // User space (EL0)
        map.add_area(VirtualMemoryArea::new(
            0x0000_0000_0040_0000, 0x0000_0001_0000_0000,
            MemoryPermissions::rx(), "user-text",
        ));
        map.add_area(VirtualMemoryArea::new(
            0x0000_0001_0000_0000, 0x0000_0010_0000_0000,
            MemoryPermissions::rw(), "user-heap",
        ));
        map.add_area(VirtualMemoryArea::new(
            0x0000_7FFF_F000_0000, 0x0000_0001_0000_0000,
            MemoryPermissions::rw(), "user-stack",
        ));
        map
    }

    /// Add a VMA to the map
    pub fn add_area(&mut self, area: VirtualMemoryArea) -> bool {
        // Check for overlap
        if self.overlaps(area.start, area.end) {
            return false;
        }
        self.total_mapped += area.size();
        self.areas.insert(area.start, area);
        true
    }

    /// Remove a VMA
    pub fn remove_area(&mut self, start: u64) -> Option<VirtualMemoryArea> {
        if let Some(area) = self.areas.remove(&start) {
            self.total_mapped = self.total_mapped.saturating_sub(area.size());
            Some(area)
        } else {
            None
        }
    }

    /// Find the VMA containing a virtual address
    pub fn find_vma(&self, va: u64) -> Option<&VirtualMemoryArea> {
        self.areas.range(..=va).next_back()
            .map(|(_, vma)| vma)
            .filter(|vma| vma.contains(va))
    }

    /// Check if a range overlaps any existing VMA
    pub fn overlaps(&self, start: u64, end: u64) -> bool {
        self.areas.range(..end).next_back()
            .map(|(_, vma)| vma.end > start)
            .unwrap_or(false)
    }

    /// Total mapped bytes
    pub fn total_mapped(&self) -> u64 { self.total_mapped }

    /// Number of VMAs
    pub fn vma_count(&self) -> usize { self.areas.len() }

    /// All VMAs
    pub fn areas(&self) -> impl Iterator<Item = &VirtualMemoryArea> {
        self.areas.values()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn memory_map_add_find() {
        let mut map = DomainMemoryMap::new(Domain::Windows);
        let area = VirtualMemoryArea::new(0x1000, 0x1000, MemoryPermissions::rw(), "heap");
        assert!(map.add_area(area));
        assert!(map.find_vma(0x1000).is_some());
        assert!(map.find_vma(0x1FFF).is_some());
        assert!(map.find_vma(0x2000).is_none());
    }

    #[test]
    fn memory_map_overlap_detection() {
        let mut map = DomainMemoryMap::new(Domain::Android);
        map.add_area(VirtualMemoryArea::new(0x1000, 0x2000, MemoryPermissions::rw(), "region1"));
        // Overlapping region should be rejected
        assert!(!map.add_area(VirtualMemoryArea::new(0x2000, 0x1000, MemoryPermissions::rw(), "overlap")));
    }

    #[test]
    fn standard_arm64_map() {
        let map = DomainMemoryMap::standard_arm64(Domain::Windows);
        assert!(map.vma_count() >= 5);
        assert!(map.total_mapped() > 0);
    }

    #[test]
    fn memory_permissions() {
        let rx = MemoryPermissions::rx();
        assert!(rx.read && rx.execute && !rx.write);
        let rw = MemoryPermissions::rw();
        assert!(rw.read && rw.write && !rw.execute);
    }
}