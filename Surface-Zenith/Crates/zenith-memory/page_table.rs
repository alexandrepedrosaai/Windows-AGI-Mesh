//! # Page Table Manager
//!
//! Manages ARM64 4-level page tables for domain containers.
//! Implements the translation from virtual to physical addresses.

use std::collections::HashMap;
use zenith_abi::domain::Domain;
use crate::error::MemoryError;

/// Page table entry flags (ARM64)
pub mod pte_flags {
    pub const VALID:        u64 = 1 << 0;
    pub const TABLE:        u64 = 1 << 1;
    pub const PAGE:         u64 = 1 << 1;
    pub const AF:           u64 = 1 << 10;  // Access Flag
    pub const SH_INNER:     u64 = 3 << 8;   // Inner Shareable
    pub const AP_RW_EL1:    u64 = 0 << 6;   // EL1 R/W
    pub const AP_RW_ALL:    u64 = 1 << 6;   // All R/W
    pub const AP_RO_EL1:    u64 = 2 << 6;   // EL1 R/O
    pub const UXN:          u64 = 1 << 54;  // Unprivileged Execute Never
    pub const PXN:          u64 = 1 << 53;  // Privileged Execute Never
    pub const COW:          u64 = 1 << 55;  // Software: Copy-on-Write
    pub const DIRTY:        u64 = 1 << 58;  // Software: Dirty
    pub const SHARED:       u64 = 1 << 56;  // Software: Shared
    pub const MAIR_NORMAL:  u64 = 2 << 2;   // Normal WB cacheable
    pub const MAIR_DEVICE:  u64 = 0 << 2;   // Device nGnRnE
    pub const PAGE_MASK:    u64 = 0x0000_FFFF_FFFF_F000;
}

/// A page table entry
#[derive(Debug, Clone, Copy, Default)]
pub struct Pte(pub u64);

impl Pte {
    pub fn new(pa: u64, flags: u64) -> Self {
        Self((pa & pte_flags::PAGE_MASK) | flags)
    }

    pub fn is_valid(&self) -> bool { self.0 & pte_flags::VALID != 0 }
    pub fn is_table(&self) -> bool { self.0 & pte_flags::TABLE != 0 }
    pub fn is_cow(&self)   -> bool { self.0 & pte_flags::COW != 0 }
    pub fn is_dirty(&self) -> bool { self.0 & pte_flags::DIRTY != 0 }
    pub fn is_shared(&self)-> bool { self.0 & pte_flags::SHARED != 0 }

    pub fn pa(&self) -> u64 { self.0 & pte_flags::PAGE_MASK }

    pub fn set_dirty(&mut self) { self.0 |= pte_flags::DIRTY; }
    pub fn clear_dirty(&mut self) { self.0 &= !pte_flags::DIRTY; }
    pub fn set_cow(&mut self) { self.0 |= pte_flags::COW; }
    pub fn clear_cow(&mut self) { self.0 &= !pte_flags::COW; }
    pub fn set_af(&mut self) { self.0 |= pte_flags::AF; }

    pub fn make_read_only(&mut self) {
        self.0 = (self.0 & !(3 << 6)) | pte_flags::AP_RO_EL1;
    }

    pub fn make_read_write(&mut self) {
        self.0 = (self.0 & !(3 << 6)) | pte_flags::AP_RW_EL1;
    }
}

/// A page table (512 entries × 8 bytes = 4 KB)
#[derive(Debug, Clone)]
pub struct PageTable {
    pub entries: [Pte; 512],
    pub level:   u8,
}

impl PageTable {
    pub fn new(level: u8) -> Self {
        Self { entries: [Pte(0); 512], level }
    }

    pub fn get(&self, idx: usize) -> Pte { self.entries[idx] }
    pub fn set(&mut self, idx: usize, pte: Pte) { self.entries[idx] = pte; }
    pub fn clear(&mut self, idx: usize) { self.entries[idx] = Pte(0); }

    pub fn valid_count(&self) -> usize {
        self.entries.iter().filter(|e| e.is_valid()).count()
    }

    pub fn dirty_count(&self) -> usize {
        self.entries.iter().filter(|e| e.is_dirty()).count()
    }
}

/// Virtual address decomposition for ARM64 4-level page tables
pub struct VaDecomposition {
    pub l0_idx: usize,
    pub l1_idx: usize,
    pub l2_idx: usize,
    pub l3_idx: usize,
    pub offset: u64,
}

impl VaDecomposition {
    pub fn from_va(va: u64) -> Self {
        Self {
            l0_idx: ((va >> 39) & 0x1FF) as usize,
            l1_idx: ((va >> 30) & 0x1FF) as usize,
            l2_idx: ((va >> 21) & 0x1FF) as usize,
            l3_idx: ((va >> 12) & 0x1FF) as usize,
            offset: va & 0xFFF,
        }
    }
}

/// Page table walker for a domain
#[derive(Debug)]
pub struct PageTableWalker {
    /// Domain this walker belongs to
    pub domain:  Domain,
    /// L0 page table (PGD)
    pub pgd:     PageTable,
    /// L1 tables (PUD) indexed by L0 entry index
    l1_tables:   HashMap<usize, PageTable>,
    /// L2 tables (PMD) indexed by (L0, L1) indices
    l2_tables:   HashMap<(usize, usize), PageTable>,
    /// L3 tables (PTE) indexed by (L0, L1, L2) indices
    l3_tables:   HashMap<(usize, usize, usize), PageTable>,
    /// Total mapped pages
    mapped_pages: u64,
    /// Total dirty pages
    dirty_pages:  u64,
}

impl PageTableWalker {
    pub fn new(domain: Domain) -> Self {
        Self {
            domain,
            pgd:          PageTable::new(0),
            l1_tables:    HashMap::new(),
            l2_tables:    HashMap::new(),
            l3_tables:    HashMap::new(),
            mapped_pages: 0,
            dirty_pages:  0,
        }
    }

    /// Map a virtual address to a physical address
    pub fn map(&mut self, va: u64, pa: u64, flags: u64) -> Result<(), MemoryError> {
        let d = VaDecomposition::from_va(va);

        // Ensure L1 table exists
        if !self.pgd.get(d.l0_idx).is_valid() {
            let l1_pa = 0u64; // Simplified: use 0 as placeholder PA
            self.pgd.set(d.l0_idx, Pte::new(l1_pa, pte_flags::VALID | pte_flags::TABLE));
            self.l1_tables.insert(d.l0_idx, PageTable::new(1));
        }

        // Ensure L2 table exists
        let l1 = self.l1_tables.entry(d.l0_idx).or_insert_with(|| PageTable::new(1));
        if !l1.get(d.l1_idx).is_valid() {
            l1.set(d.l1_idx, Pte::new(0, pte_flags::VALID | pte_flags::TABLE));
            self.l2_tables.insert((d.l0_idx, d.l1_idx), PageTable::new(2));
        }

        // Ensure L3 table exists
        let l2 = self.l2_tables.entry((d.l0_idx, d.l1_idx)).or_insert_with(|| PageTable::new(2));
        if !l2.get(d.l2_idx).is_valid() {
            l2.set(d.l2_idx, Pte::new(0, pte_flags::VALID | pte_flags::TABLE));
            self.l3_tables.insert((d.l0_idx, d.l1_idx, d.l2_idx), PageTable::new(3));
        }

        // Set L3 entry (leaf)
        let l3 = self.l3_tables
            .entry((d.l0_idx, d.l1_idx, d.l2_idx))
            .or_insert_with(|| PageTable::new(3));

        let was_mapped = l3.get(d.l3_idx).is_valid();
        let mut pte = Pte::new(pa, flags | pte_flags::VALID | pte_flags::PAGE | pte_flags::AF);
        l3.set(d.l3_idx, pte);

        if !was_mapped {
            self.mapped_pages += 1;
        }

        Ok(())
    }

    /// Unmap a virtual address
    pub fn unmap(&mut self, va: u64) -> bool {
        let d = VaDecomposition::from_va(va);
        if let Some(l3) = self.l3_tables.get_mut(&(d.l0_idx, d.l1_idx, d.l2_idx)) {
            let pte = l3.get(d.l3_idx);
            if pte.is_valid() {
                l3.clear(d.l3_idx);
                self.mapped_pages = self.mapped_pages.saturating_sub(1);
                if pte.is_dirty() { self.dirty_pages = self.dirty_pages.saturating_sub(1); }
                return true;
            }
        }
        false
    }

    /// Translate a virtual address to physical
    pub fn translate(&self, va: u64) -> Option<u64> {
        let d = VaDecomposition::from_va(va);
        let l3 = self.l3_tables.get(&(d.l0_idx, d.l1_idx, d.l2_idx))?;
        let pte = l3.get(d.l3_idx);
        if pte.is_valid() {
            Some(pte.pa() | d.offset)
        } else {
            None
        }
    }

    /// Get the PTE for a virtual address
    pub fn get_pte(&self, va: u64) -> Option<Pte> {
        let d = VaDecomposition::from_va(va);
        let l3 = self.l3_tables.get(&(d.l0_idx, d.l1_idx, d.l2_idx))?;
        let pte = l3.get(d.l3_idx);
        if pte.is_valid() { Some(pte) } else { None }
    }

    /// Mark a page as dirty
    pub fn mark_dirty(&mut self, va: u64) -> bool {
        let d = VaDecomposition::from_va(va);
        if let Some(l3) = self.l3_tables.get_mut(&(d.l0_idx, d.l1_idx, d.l2_idx)) {
            let mut pte = l3.get(d.l3_idx);
            if pte.is_valid() && !pte.is_dirty() {
                pte.set_dirty();
                l3.set(d.l3_idx, pte);
                self.dirty_pages += 1;
                return true;
            }
        }
        false
    }

    /// Get all dirty virtual addresses
    pub fn dirty_vas(&self) -> Vec<u64> {
        let mut vas = Vec::new();
        for (&(l0, l1, l2), l3) in &self.l3_tables {
            for (l3_idx, pte) in l3.entries.iter().enumerate() {
                if pte.is_valid() && pte.is_dirty() {
                    let va = ((l0 as u64) << 39)
                           | ((l1 as u64) << 30)
                           | ((l2 as u64) << 21)
                           | ((l3_idx as u64) << 12);
                    vas.push(va);
                }
            }
        }
        vas
    }

    /// Total mapped pages
    pub fn mapped_pages(&self) -> u64 { self.mapped_pages }

    /// Total dirty pages
    pub fn dirty_pages(&self) -> u64 { self.dirty_pages }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn pte_flags() {
        let mut pte = Pte::new(0x1000, pte_flags::VALID | pte_flags::AP_RW_EL1);
        assert!(pte.is_valid());
        assert!(!pte.is_dirty());
        pte.set_dirty();
        assert!(pte.is_dirty());
        pte.clear_dirty();
        assert!(!pte.is_dirty());
        assert_eq!(pte.pa(), 0x1000);
    }

    #[test]
    fn va_decomposition() {
        let va = 0x0000_0001_0020_3456u64;
        let d = VaDecomposition::from_va(va);
        assert_eq!(d.offset, 0x456);
        assert_eq!(d.l3_idx, 0x203 & 0x1FF);
    }

    #[test]
    fn page_table_walker_map_translate() {
        let mut walker = PageTableWalker::new(Domain::Windows);
        let va = 0x0000_0000_0040_0000u64;
        let pa = 0x0000_0000_1000_0000u64;
        walker.map(va, pa, pte_flags::AP_RW_EL1).unwrap();
        let translated = walker.translate(va);
        assert_eq!(translated, Some(pa));
        assert_eq!(walker.mapped_pages(), 1);
    }

    #[test]
    fn page_table_walker_unmap() {
        let mut walker = PageTableWalker::new(Domain::Android);
        let va = 0x0000_0000_0080_0000u64;
        walker.map(va, 0x2000_0000, pte_flags::AP_RW_EL1).unwrap();
        assert!(walker.translate(va).is_some());
        assert!(walker.unmap(va));
        assert!(walker.translate(va).is_none());
        assert_eq!(walker.mapped_pages(), 0);
    }

    #[test]
    fn page_table_walker_dirty_tracking() {
        let mut walker = PageTableWalker::new(Domain::AI);
        let va = 0x0000_0000_00C0_0000u64;
        walker.map(va, 0x3000_0000, pte_flags::AP_RW_EL1).unwrap();
        assert!(walker.mark_dirty(va));
        assert_eq!(walker.dirty_pages(), 1);
        let dirty_vas = walker.dirty_vas();
        assert_eq!(dirty_vas.len(), 1);
    }

    #[test]
    fn page_table_walker_multiple_pages() {
        let mut walker = PageTableWalker::new(Domain::Windows);
        for i in 0..10u64 {
            let va = 0x0000_0000_0100_0000 + i * 0x1000;
            let pa = 0x4000_0000 + i * 0x1000;
            walker.map(va, pa, pte_flags::AP_RW_EL1).unwrap();
        }
        assert_eq!(walker.mapped_pages(), 10);
        for i in 0..10u64 {
            let va = 0x0000_0000_0100_0000 + i * 0x1000;
            let pa = 0x4000_0000 + i * 0x1000;
            assert_eq!(walker.translate(va), Some(pa));
        }
    }
}