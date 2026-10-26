//! # Page Eviction Engine
//!
//! Implements LRU and clock-based page eviction for memory reclaim.

use std::collections::{HashMap, VecDeque};
use zenith_abi::domain::Domain;
use crate::page_frame::{PageFrame, PageFrameDatabase};
use crate::error::MemoryError;

/// Eviction policy
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum EvictionPolicy {
    /// Least Recently Used
    Lru,
    /// Clock algorithm (approximation of LRU)
    Clock,
    /// Random eviction
    Random,
    /// Domain-aware (prefer evicting from least-critical domains)
    DomainAware,
}

/// Eviction candidate
#[derive(Debug, Clone)]
pub struct EvictionCandidate {
    pub pfn:         u64,
    pub domain:      Option<Domain>,
    pub age_ns:      u64,
    pub access_count: u64,
    pub dirty:       bool,
    pub score:       f64,
}

impl EvictionCandidate {
    /// Compute eviction score (higher = more likely to be evicted)
    pub fn compute_score(frame: &PageFrame, now_ns: u64) -> f64 {
        let age_factor    = frame.age_ns(now_ns) as f64 / 1_000_000_000.0; // seconds
        let access_factor = 1.0 / (frame.access_count as f64 + 1.0);
        let dirty_penalty = if frame.dirty { 0.5 } else { 1.0 };
        age_factor * access_factor * dirty_penalty
    }
}

/// LRU eviction list
#[derive(Debug, Default)]
pub struct LruList {
    /// PFNs in LRU order (front = most recently used, back = least recently used)
    list:    VecDeque<u64>,
    /// PFN → position in list (for O(1) lookup)
    index:   HashMap<u64, usize>,
}

impl LruList {
    pub fn new() -> Self { Self::default() }

    /// Record an access to a page (move to front)
    pub fn access(&mut self, pfn: u64) {
        self.list.retain(|&p| p != pfn);
        self.list.push_front(pfn);
        // Rebuild index
        self.index.clear();
        for (i, &p) in self.list.iter().enumerate() {
            self.index.insert(p, i);
        }
    }

    /// Add a new page to the LRU list
    pub fn add(&mut self, pfn: u64) {
        if !self.index.contains_key(&pfn) {
            self.list.push_front(pfn);
            self.index.insert(pfn, 0);
        }
    }

    /// Remove a page from the LRU list
    pub fn remove(&mut self, pfn: u64) {
        self.list.retain(|&p| p != pfn);
        self.index.remove(&pfn);
    }

    /// Get the least recently used page
    pub fn lru_candidate(&self) -> Option<u64> {
        self.list.back().copied()
    }

    /// Pop the least recently used page
    pub fn pop_lru(&mut self) -> Option<u64> {
        let pfn = self.list.pop_back()?;
        self.index.remove(&pfn);
        Some(pfn)
    }

    /// Number of pages in the list
    pub fn len(&self) -> usize { self.list.len() }

    /// Whether the list is empty
    pub fn is_empty(&self) -> bool { self.list.is_empty() }
}

/// The Page Eviction Engine
#[derive(Debug)]
pub struct EvictionEngine {
    policy:          EvictionPolicy,
    lru_list:        LruList,
    /// Clock hand position
    clock_hand:      usize,
    /// Clock reference bits (pfn → referenced)
    clock_bits:      HashMap<u64, bool>,
    total_evictions: u64,
    dirty_evictions: u64,
    clean_evictions: u64,
}

impl EvictionEngine {
    /// Create a new eviction engine
    pub fn new(policy: EvictionPolicy) -> Self {
        Self {
            policy,
            lru_list:        LruList::new(),
            clock_hand:      0,
            clock_bits:      HashMap::new(),
            total_evictions: 0,
            dirty_evictions: 0,
            clean_evictions: 0,
        }
    }

    /// Register a page with the eviction engine
    pub fn register(&mut self, pfn: u64) {
        self.lru_list.add(pfn);
        self.clock_bits.insert(pfn, false);
    }

    /// Record a page access
    pub fn record_access(&mut self, pfn: u64) {
        self.lru_list.access(pfn);
        self.clock_bits.insert(pfn, true);
    }

    /// Unregister a page (freed or pinned)
    pub fn unregister(&mut self, pfn: u64) {
        self.lru_list.remove(pfn);
        self.clock_bits.remove(&pfn);
    }

    /// Select pages for eviction
    pub fn select_victims(
        &mut self,
        count: usize,
        pfd: &PageFrameDatabase,
    ) -> Result<Vec<u64>, MemoryError> {
        match self.policy {
            EvictionPolicy::Lru         => self.select_lru(count, pfd),
            EvictionPolicy::Clock       => self.select_clock(count, pfd),
            EvictionPolicy::Random      => self.select_random(count, pfd),
            EvictionPolicy::DomainAware => self.select_domain_aware(count, pfd),
        }
    }

    fn select_lru(&mut self, count: usize, pfd: &PageFrameDatabase) -> Result<Vec<u64>, MemoryError> {
        let mut victims = Vec::new();
        let mut attempts = 0;
        while victims.len() < count && attempts < self.lru_list.len() * 2 {
            if let Some(pfn) = self.lru_list.pop_lru() {
                if let Some(frame) = pfd.get(pfn) {
                    if frame.is_evictable() {
                        victims.push(pfn);
                        continue;
                    }
                }
                // Not evictable — put back at front
                self.lru_list.add(pfn);
            }
            attempts += 1;
        }
        if victims.is_empty() {
            Err(MemoryError::EvictionFailed)
        } else {
            Ok(victims)
        }
    }

    fn select_clock(&mut self, count: usize, pfd: &PageFrameDatabase) -> Result<Vec<u64>, MemoryError> {
        let pfns: Vec<u64> = self.clock_bits.keys().copied().collect();
        if pfns.is_empty() {
            return Err(MemoryError::EvictionFailed);
        }

        let mut victims = Vec::new();
        let mut passes = 0;

        while victims.len() < count && passes < 2 {
            let pfn = pfns[self.clock_hand % pfns.len()];
            self.clock_hand = (self.clock_hand + 1) % pfns.len();

            if let Some(referenced) = self.clock_bits.get_mut(&pfn) {
                if *referenced {
                    *referenced = false; // Give a second chance
                } else if let Some(frame) = pfd.get(pfn) {
                    if frame.is_evictable() {
                        victims.push(pfn);
                        self.clock_bits.remove(&pfn);
                    }
                }
            }

            if self.clock_hand == 0 {
                passes += 1;
            }
        }

        if victims.is_empty() {
            Err(MemoryError::EvictionFailed)
        } else {
            Ok(victims)
        }
    }

    fn select_random(&mut self, count: usize, pfd: &PageFrameDatabase) -> Result<Vec<u64>, MemoryError> {
        let candidates: Vec<u64> = self.clock_bits.keys()
            .filter(|&&pfn| pfd.get(pfn).map(|f| f.is_evictable()).unwrap_or(false))
            .copied()
            .take(count)
            .collect();

        if candidates.is_empty() {
            Err(MemoryError::EvictionFailed)
        } else {
            Ok(candidates)
        }
    }

    fn select_domain_aware(&mut self, count: usize, pfd: &PageFrameDatabase) -> Result<Vec<u64>, MemoryError> {
        // Prefer evicting from Cloud domain first, then Android, then Windows, then AI
        let domain_priority = [Domain::Cloud, Domain::Android, Domain::Windows, Domain::AI];
        let mut victims = Vec::new();

        for domain in &domain_priority {
            if victims.len() >= count { break; }
            let domain_pages: Vec<u64> = self.clock_bits.keys()
                .filter(|&&pfn| {
                    pfd.get(pfn)
                        .map(|f| f.is_evictable() && f.owner.as_ref() == Some(domain))
                        .unwrap_or(false)
                })
                .copied()
                .take(count - victims.len())
                .collect();
            victims.extend(domain_pages);
        }

        if victims.is_empty() {
            Err(MemoryError::EvictionFailed)
        } else {
            Ok(victims)
        }
    }

    /// Record an eviction
    pub fn record_eviction(&mut self, pfn: u64, dirty: bool) {
        self.total_evictions += 1;
        if dirty {
            self.dirty_evictions += 1;
        } else {
            self.clean_evictions += 1;
        }
        self.unregister(pfn);
    }

    /// Total evictions
    pub fn total_evictions(&self) -> u64 { self.total_evictions }

    /// Dirty eviction ratio
    pub fn dirty_eviction_ratio(&self) -> f64 {
        if self.total_evictions == 0 { return 0.0; }
        self.dirty_evictions as f64 / self.total_evictions as f64
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn lru_list_ordering() {
        let mut lru = LruList::new();
        lru.add(1);
        lru.add(2);
        lru.add(3);
        // 3 is most recent (added last)
        lru.access(1); // 1 is now most recent
        assert_eq!(lru.lru_candidate(), Some(2)); // 2 is LRU
    }

    #[test]
    fn lru_list_remove() {
        let mut lru = LruList::new();
        lru.add(10);
        lru.add(20);
        lru.remove(10);
        assert_eq!(lru.len(), 1);
        assert_eq!(lru.pop_lru(), Some(20));
    }

    #[test]
    fn eviction_engine_register() {
        let mut engine = EvictionEngine::new(EvictionPolicy::Lru);
        engine.register(1);
        engine.register(2);
        engine.register(3);
        assert_eq!(engine.lru_list.len(), 3);
    }

    #[test]
    fn eviction_engine_access_updates_lru() {
        let mut engine = EvictionEngine::new(EvictionPolicy::Lru);
        engine.register(1);
        engine.register(2);
        engine.register(3);
        engine.record_access(1); // 1 is now MRU
        assert_eq!(engine.lru_list.lru_candidate(), Some(2)); // 2 is LRU
    }
}