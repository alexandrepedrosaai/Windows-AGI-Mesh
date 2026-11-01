//! # Physical Memory Allocator
//!
//! Implements multiple allocation strategies for the Zenith memory fabric:
//!   - Buddy allocator (for power-of-2 sized allocations)
//!   - Slab allocator (for fixed-size object pools)
//!   - NUMA-aware allocator (prefers local NUMA node)

use std::collections::{BTreeMap, HashMap};
use zenith_abi::domain::Domain;
use crate::error::MemoryError;

// ---------------------------------------------------------------------------
// Buddy allocator
// ---------------------------------------------------------------------------

/// Order of a buddy block (block size = PAGE_SIZE × 2^order)
pub type BuddyOrder = u8;

/// Maximum buddy order (2^11 = 2048 pages = 8 MB)
pub const MAX_BUDDY_ORDER: BuddyOrder = 11;

/// A buddy allocator for physical memory
///
/// Manages free memory in power-of-2 sized blocks.
/// Merges adjacent free blocks (buddies) to reduce fragmentation.
#[derive(Debug)]
pub struct BuddyAllocator {
    /// Free lists indexed by order
    free_lists: Vec<Vec<u64>>,
    /// Total pages managed
    total_pages: u64,
    /// Free pages
    free_pages:  u64,
    /// Allocation count
    alloc_count: u64,
    /// Free count
    free_count:  u64,
    /// Fragmentation events (failed merges)
    frag_events: u64,
}

impl BuddyAllocator {
    /// Create a new buddy allocator for a given memory size
    pub fn new(total_pages: u64) -> Self {
        let mut allocator = Self {
            free_lists:  vec![Vec::new(); (MAX_BUDDY_ORDER + 1) as usize],
            total_pages,
            free_pages:  0,
            alloc_count: 0,
            free_count:  0,
            frag_events: 0,
        };

        // Initialize free lists with the largest possible blocks
        let mut remaining = total_pages;
        let mut base_pfn  = 0u64;

        while remaining > 0 {
            // Find the largest order that fits
            let order = (remaining as f64).log2().floor() as u8;
            let order = order.min(MAX_BUDDY_ORDER);
            let block_size = 1u64 << order;

            if block_size <= remaining {
                allocator.free_lists[order as usize].push(base_pfn);
                allocator.free_pages += block_size;
                base_pfn  += block_size;
                remaining -= block_size;
            } else {
                break;
            }
        }

        allocator
    }

    /// Allocate a block of 2^order pages
    pub fn allocate(&mut self, order: BuddyOrder) -> Result<u64, MemoryError> {
        if order > MAX_BUDDY_ORDER {
            return Err(MemoryError::InvalidOrder { order });
        }

        // Find the smallest available block >= requested order
        for current_order in order..=MAX_BUDDY_ORDER {
            if !self.free_lists[current_order as usize].is_empty() {
                let pfn = self.free_lists[current_order as usize].pop().unwrap();

                // Split larger blocks down to the requested order
                let mut split_pfn = pfn;
                let mut split_order = current_order;

                while split_order > order {
                    split_order -= 1;
                    let buddy_pfn = split_pfn + (1u64 << split_order);
                    self.free_lists[split_order as usize].push(buddy_pfn);
                }

                let block_size = 1u64 << order;
                self.free_pages  = self.free_pages.saturating_sub(block_size);
                self.alloc_count += 1;
                return Ok(split_pfn);
            }
        }

        Err(MemoryError::OutOfMemory)
    }

    /// Free a block of 2^order pages starting at pfn
    pub fn free(&mut self, pfn: u64, order: BuddyOrder) -> Result<(), MemoryError> {
        if order > MAX_BUDDY_ORDER {
            return Err(MemoryError::InvalidOrder { order });
        }

        let block_size = 1u64 << order;
        self.free_pages += block_size;
        self.free_count += 1;

        // Try to merge with buddy
        let mut current_pfn   = pfn;
        let mut current_order = order;

        while current_order < MAX_BUDDY_ORDER {
            let buddy_pfn = current_pfn ^ (1u64 << current_order);
            let list = &mut self.free_lists[current_order as usize];

            if let Some(pos) = list.iter().position(|&p| p == buddy_pfn) {
                // Found buddy — merge
                list.remove(pos);
                current_pfn   = current_pfn.min(buddy_pfn);
                current_order += 1;
            } else {
                self.frag_events += 1;
                break;
            }
        }

        self.free_lists[current_order as usize].push(current_pfn);
        Ok(())
    }

    /// Allocate a single page
    pub fn allocate_page(&mut self) -> Result<u64, MemoryError> {
        self.allocate(0)
    }

    /// Free a single page
    pub fn free_page(&mut self, pfn: u64) -> Result<(), MemoryError> {
        self.free(pfn, 0)
    }

    /// Free pages
    pub fn free_pages(&self) -> u64 { self.free_pages }

    /// Total pages
    pub fn total_pages(&self) -> u64 { self.total_pages }

    /// Utilization ratio
    pub fn utilization(&self) -> f64 {
        if self.total_pages == 0 { return 0.0; }
        (self.total_pages - self.free_pages) as f64 / self.total_pages as f64
    }

    /// Fragmentation index (0.0 = no fragmentation, 1.0 = fully fragmented)
    pub fn fragmentation_index(&self) -> f64 {
        if self.alloc_count == 0 { return 0.0; }
        self.frag_events as f64 / self.alloc_count as f64
    }

    /// Allocation statistics
    pub fn stats(&self) -> BuddyStats {
        BuddyStats {
            total_pages:    self.total_pages,
            free_pages:     self.free_pages,
            alloc_count:    self.alloc_count,
            free_count:     self.free_count,
            frag_events:    self.frag_events,
            utilization:    self.utilization(),
            fragmentation:  self.fragmentation_index(),
        }
    }
}

/// Buddy allocator statistics
#[derive(Debug, Clone)]
pub struct BuddyStats {
    pub total_pages:   u64,
    pub free_pages:    u64,
    pub alloc_count:   u64,
    pub free_count:    u64,
    pub frag_events:   u64,
    pub utilization:   f64,
    pub fragmentation: f64,
}

// ---------------------------------------------------------------------------
// Slab allocator
// ---------------------------------------------------------------------------

/// A slab cache for fixed-size objects
#[derive(Debug)]
pub struct SlabCache {
    /// Object size in bytes
    pub object_size: usize,
    /// Objects per slab (page)
    pub objects_per_slab: usize,
    /// Free object indices
    free_objects: Vec<(u64, usize)>, // (pfn, object_index)
    /// Allocated object count
    allocated: u64,
    /// Total slabs allocated
    slab_count: u64,
}

impl SlabCache {
    /// Create a new slab cache for objects of a given size
    pub fn new(object_size: usize) -> Self {
        let objects_per_slab = crate::PAGE_SIZE / object_size.max(1);
        Self {
            object_size,
            objects_per_slab,
            free_objects: Vec::new(),
            allocated: 0,
            slab_count: 0,
        }
    }

    /// Add a new slab (page) to the cache
    pub fn add_slab(&mut self, pfn: u64) {
        for i in 0..self.objects_per_slab {
            self.free_objects.push((pfn, i));
        }
        self.slab_count += 1;
    }

    /// Allocate an object from the cache
    pub fn allocate(&mut self) -> Option<(u64, usize)> {
        if let Some(obj) = self.free_objects.pop() {
            self.allocated += 1;
            Some(obj)
        } else {
            None
        }
    }

    /// Free an object back to the cache
    pub fn free(&mut self, pfn: u64, index: usize) {
        self.free_objects.push((pfn, index));
        self.allocated = self.allocated.saturating_sub(1);
    }

    /// Number of free objects
    pub fn free_count(&self) -> usize { self.free_objects.len() }

    /// Number of allocated objects
    pub fn allocated_count(&self) -> u64 { self.allocated }

    /// Cache utilization
    pub fn utilization(&self) -> f64 {
        let total = self.slab_count as usize * self.objects_per_slab;
        if total == 0 { return 0.0; }
        self.allocated as f64 / total as f64
    }
}

/// Slab allocator managing multiple caches
#[derive(Debug, Default)]
pub struct SlabAllocator {
    caches: HashMap<usize, SlabCache>,
}

impl SlabAllocator {
    pub fn new() -> Self { Self::default() }

    /// Get or create a cache for a given object size
    pub fn get_cache(&mut self, size: usize) -> &mut SlabCache {
        self.caches.entry(size).or_insert_with(|| SlabCache::new(size))
    }

    /// Allocate an object of a given size
    pub fn allocate(&mut self, size: usize) -> Option<(u64, usize)> {
        self.caches.get_mut(&size)?.allocate()
    }

    /// Free an object
    pub fn free(&mut self, size: usize, pfn: u64, index: usize) {
        if let Some(cache) = self.caches.get_mut(&size) {
            cache.free(pfn, index);
        }
    }

    /// Add a slab to a cache
    pub fn add_slab(&mut self, size: usize, pfn: u64) {
        self.get_cache(size).add_slab(pfn);
    }

    /// Total allocated objects across all caches
    pub fn total_allocated(&self) -> u64 {
        self.caches.values().map(|c| c.allocated_count()).sum()
    }
}

// ---------------------------------------------------------------------------
// NUMA-aware allocator
// ---------------------------------------------------------------------------

/// NUMA node descriptor
#[derive(Debug, Clone)]
pub struct NumaNode {
    pub id:          u8,
    pub total_pages: u64,
    pub free_pages:  u64,
    pub latency_ns:  u32, // Memory access latency in nanoseconds
}

impl NumaNode {
    pub fn new(id: u8, total_pages: u64, latency_ns: u32) -> Self {
        Self { id, total_pages, free_pages: total_pages, latency_ns }
    }

    pub fn utilization(&self) -> f64 {
        if self.total_pages == 0 { return 0.0; }
        (self.total_pages - self.free_pages) as f64 / self.total_pages as f64
    }
}

/// NUMA-aware memory allocator
#[derive(Debug, Default)]
pub struct NumaAllocator {
    nodes:           Vec<NumaNode>,
    /// Domain → preferred NUMA node
    domain_affinity: HashMap<String, u8>,
}

impl NumaAllocator {
    pub fn new() -> Self { Self::default() }

    /// Add a NUMA node
    pub fn add_node(&mut self, node: NumaNode) {
        self.nodes.push(node);
    }

    /// Set domain affinity for a NUMA node
    pub fn set_affinity(&mut self, domain: &Domain, node_id: u8) {
        self.domain_affinity.insert(domain.name().to_string(), node_id);
    }

    /// Get the preferred NUMA node for a domain
    pub fn preferred_node(&self, domain: &Domain) -> Option<u8> {
        self.domain_affinity.get(domain.name()).copied()
    }

    /// Allocate from the preferred NUMA node for a domain
    pub fn allocate_for_domain(&mut self, domain: &Domain, pages: u64) -> Result<u8, MemoryError> {
        let preferred = self.preferred_node(domain);

        // Try preferred node first
        if let Some(node_id) = preferred {
            if let Some(node) = self.nodes.iter_mut().find(|n| n.id == node_id) {
                if node.free_pages >= pages {
                    node.free_pages -= pages;
                    return Ok(node_id);
                }
            }
        }

        // Fall back to least-loaded node
        let node = self.nodes.iter_mut()
            .filter(|n| n.free_pages >= pages)
            .min_by_key(|n| n.latency_ns);

        if let Some(node) = node {
            node.free_pages -= pages;
            Ok(node.id)
        } else {
            Err(MemoryError::OutOfMemory)
        }
    }

    /// Total free pages across all nodes
    pub fn total_free_pages(&self) -> u64 {
        self.nodes.iter().map(|n| n.free_pages).sum()
    }

    /// Average NUMA utilization
    pub fn avg_utilization(&self) -> f64 {
        if self.nodes.is_empty() { return 0.0; }
        self.nodes.iter().map(|n| n.utilization()).sum::<f64>() / self.nodes.len() as f64
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn buddy_allocate_single_page() {
        let mut buddy = BuddyAllocator::new(1024);
        let pfn = buddy.allocate_page().unwrap();
        assert_eq!(buddy.free_pages(), 1023);
        buddy.free_page(pfn).unwrap();
        assert_eq!(buddy.free_pages(), 1024);
    }

    #[test]
    fn buddy_allocate_block() {
        let mut buddy = BuddyAllocator::new(1024);
        let pfn = buddy.allocate(3).unwrap(); // 8 pages
        assert_eq!(buddy.free_pages(), 1016);
        buddy.free(pfn, 3).unwrap();
        assert_eq!(buddy.free_pages(), 1024);
    }

    #[test]
    fn buddy_out_of_memory() {
        let mut buddy = BuddyAllocator::new(4);
        buddy.allocate_page().unwrap();
        buddy.allocate_page().unwrap();
        buddy.allocate_page().unwrap();
        buddy.allocate_page().unwrap();
        assert!(buddy.allocate_page().is_err());
    }

    #[test]
    fn buddy_merge_buddies() {
        let mut buddy = BuddyAllocator::new(8);
        let pfn0 = buddy.allocate_page().unwrap();
        let pfn1 = buddy.allocate_page().unwrap();
        buddy.free_page(pfn0).unwrap();
        buddy.free_page(pfn1).unwrap();
        // After freeing both, they should merge into a 2-page block
        assert_eq!(buddy.free_pages(), 8);
    }

    #[test]
    fn slab_cache_allocate_free() {
        let mut cache = SlabCache::new(64);
        cache.add_slab(0);
        let obj = cache.allocate().unwrap();
        assert_eq!(cache.allocated_count(), 1);
        cache.free(obj.0, obj.1);
        assert_eq!(cache.allocated_count(), 0);
    }

    #[test]
    fn slab_allocator_multi_size() {
        let mut slab = SlabAllocator::new();
        slab.add_slab(64, 0);
        slab.add_slab(128, 1);
        let obj64  = slab.allocate(64).unwrap();
        let obj128 = slab.allocate(128).unwrap();
        assert_eq!(slab.total_allocated(), 2);
        slab.free(64, obj64.0, obj64.1);
        slab.free(128, obj128.0, obj128.1);
        assert_eq!(slab.total_allocated(), 0);
    }

    #[test]
    fn numa_allocator_affinity() {
        let mut numa = NumaAllocator::new();
        numa.add_node(NumaNode::new(0, 1024, 80));
        numa.add_node(NumaNode::new(1, 1024, 120));
        numa.set_affinity(&Domain::Windows, 0);
        numa.set_affinity(&Domain::Android, 1);

        let node = numa.allocate_for_domain(&Domain::Windows, 10).unwrap();
        assert_eq!(node, 0); // Should use preferred node

        let node2 = numa.allocate_for_domain(&Domain::Android, 10).unwrap();
        assert_eq!(node2, 1);
    }

    #[test]
    fn numa_fallback_on_full_node() {
        let mut numa = NumaAllocator::new();
        numa.add_node(NumaNode::new(0, 5, 80));
        numa.add_node(NumaNode::new(1, 1024, 120));
        numa.set_affinity(&Domain::Windows, 0);

        // Exhaust node 0
        numa.allocate_for_domain(&Domain::Windows, 5).unwrap();

        // Should fall back to node 1
        let node = numa.allocate_for_domain(&Domain::Windows, 10).unwrap();
        assert_eq!(node, 1);
    }
}