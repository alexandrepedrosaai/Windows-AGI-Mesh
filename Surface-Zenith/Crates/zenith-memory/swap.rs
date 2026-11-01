//! # Swap Manager
//!
//! Manages swapping of cold pages to storage when memory pressure is high.

use std::collections::HashMap;
use zenith_abi::domain::Domain;
use crate::error::MemoryError;

/// Swap entry
#[derive(Debug, Clone)]
pub struct SwapEntry {
    pub pfn:        u64,
    pub offset:     u64,
    pub size:       u64,
    pub domain:     Option<Domain>,
    pub dirty:      bool,
    pub swapped_at: std::time::Instant,
}

/// Swap device
#[derive(Debug)]
pub struct SwapDevice {
    pub capacity_bytes: u64,
    pub used_bytes:     u64,
    pub entries:        HashMap<u64, SwapEntry>, // pfn → entry
    pub next_offset:    u64,
    pub swap_ins:       u64,
    pub swap_outs:      u64,
}

impl SwapDevice {
    pub fn new(capacity_bytes: u64) -> Self {
        Self {
            capacity_bytes,
            used_bytes:  0,
            entries:     HashMap::new(),
            next_offset: 0,
            swap_ins:    0,
            swap_outs:   0,
        }
    }

    /// Swap out a page
    pub fn swap_out(&mut self, pfn: u64, domain: Option<Domain>, dirty: bool) -> Result<u64, MemoryError> {
        if self.used_bytes + crate::PAGE_SIZE as u64 > self.capacity_bytes {
            return Err(MemoryError::SwapExhausted);
        }
        let offset = self.next_offset;
        self.next_offset += crate::PAGE_SIZE as u64;
        self.used_bytes  += crate::PAGE_SIZE as u64;
        self.swap_outs   += 1;

        self.entries.insert(pfn, SwapEntry {
            pfn,
            offset,
            size: crate::PAGE_SIZE as u64,
            domain,
            dirty,
            swapped_at: std::time::Instant::now(),
        });

        Ok(offset)
    }

    /// Swap in a page
    pub fn swap_in(&mut self, pfn: u64) -> Result<SwapEntry, MemoryError> {
        let entry = self.entries.remove(&pfn)
            .ok_or(MemoryError::InvalidPfn { pfn })?;
        self.used_bytes = self.used_bytes.saturating_sub(crate::PAGE_SIZE as u64);
        self.swap_ins += 1;
        Ok(entry)
    }

    /// Whether a page is swapped
    pub fn is_swapped(&self, pfn: u64) -> bool {
        self.entries.contains_key(&pfn)
    }

    /// Utilization ratio
    pub fn utilization(&self) -> f64 {
        if self.capacity_bytes == 0 { return 0.0; }
        self.used_bytes as f64 / self.capacity_bytes as f64
    }

    /// Swap entry count
    pub fn entry_count(&self) -> usize { self.entries.len() }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn swap_out_in() {
        let mut swap = SwapDevice::new(1024 * 1024);
        let offset = swap.swap_out(42, Some(Domain::Windows), false).unwrap();
        assert!(swap.is_swapped(42));
        assert_eq!(swap.entry_count(), 1);
        let entry = swap.swap_in(42).unwrap();
        assert_eq!(entry.pfn, 42);
        assert!(!swap.is_swapped(42));
    }

    #[test]
    fn swap_exhausted() {
        let mut swap = SwapDevice::new(crate::PAGE_SIZE as u64); // Only 1 page
        swap.swap_out(1, None, false).unwrap();
        assert!(swap.swap_out(2, None, false).is_err());
    }

    #[test]
    fn swap_utilization() {
        let mut swap = SwapDevice::new(10 * crate::PAGE_SIZE as u64);
        for i in 0..5 {
            swap.swap_out(i, None, false).unwrap();
        }
        assert!((swap.utilization() - 0.5).abs() < 0.01);
    }
}