//! # Page Cache
//!
//! Caches frequently accessed pages in a hot tier for fast access.

use std::collections::{HashMap, VecDeque};
use zenith_abi::domain::Domain;

/// Cache tier
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum CacheTier {
    /// Hot tier — frequently accessed pages (in DRAM)
    Hot,
    /// Warm tier — occasionally accessed pages
    Warm,
    /// Cold tier — rarely accessed pages (candidate for eviction)
    Cold,
}

/// A cached page entry
#[derive(Debug, Clone)]
pub struct CacheEntry {
    pub pfn:          u64,
    pub tier:         CacheTier,
    pub domain:       Option<Domain>,
    pub access_count: u64,
    pub last_access:  std::time::Instant,
    pub size_bytes:   u64,
}

impl CacheEntry {
    pub fn new(pfn: u64, domain: Option<Domain>) -> Self {
        Self {
            pfn,
            tier:         CacheTier::Warm,
            domain,
            access_count: 0,
            last_access:  std::time::Instant::now(),
            size_bytes:   crate::PAGE_SIZE as u64,
        }
    }

    pub fn record_access(&mut self) {
        self.access_count += 1;
        self.last_access   = std::time::Instant::now();
        // Promote to hot tier after 10 accesses
        if self.access_count >= 10 {
            self.tier = CacheTier::Hot;
        }
    }

    pub fn age_ms(&self) -> u64 {
        self.last_access.elapsed().as_millis() as u64
    }

    pub fn demote(&mut self) {
        self.tier = match self.tier {
            CacheTier::Hot  => CacheTier::Warm,
            CacheTier::Warm => CacheTier::Cold,
            CacheTier::Cold => CacheTier::Cold,
        };
    }
}

/// Two-level page cache (hot + warm tiers)
#[derive(Debug, Default)]
pub struct PageCache {
    entries:       HashMap<u64, CacheEntry>,
    hot_list:      VecDeque<u64>,
    warm_list:     VecDeque<u64>,
    capacity:      u64,
    used:          u64,
    hits:          u64,
    misses:        u64,
    evictions:     u64,
    promotions:    u64,
    demotions:     u64,
}

impl PageCache {
    pub fn new(capacity_bytes: u64) -> Self {
        Self {
            capacity: capacity_bytes,
            ..Default::default()
        }
    }

    /// Insert a page into the cache
pub fn insert(&mut self, pfn: u64, domain: Option<Domain>) -> bool {
        if self.used + crate::PAGE_SIZE as u64 > self.capacity {
            if !self.evict_one() {
                return false;
            }
        }
        let entry = CacheEntry::new(pfn, domain);
        self.warm_list.push_front(pfn);
        self.entries.insert(pfn, entry);
        self.used += crate::PAGE_SIZE as u64;
        true
    }

    /// Access a cached page
    pub fn access(&mut self, pfn: u64) -> bool {
        if let Some(entry) = self.entries.get_mut(&pfn) {
            let was_warm = entry.tier == CacheTier::Warm;
            entry.record_access();
            if was_warm && entry.tier == CacheTier::Hot {
                // Promote to hot list
                self.warm_list.retain(|&p| p != pfn);
                self.hot_list.push_front(pfn);
                self.promotions += 1;
            }
            self.hits += 1;
            true
        } else {
            self.misses += 1;
            false
        }
    }

    /// Remove a page from the cache
    pub fn remove(&mut self, pfn: u64) -> bool {
        if self.entries.remove(&pfn).is_some() {
            self.hot_list.retain(|&p| p != pfn);
            self.warm_list.retain(|&p| p != pfn);
            self.used = self.used.saturating_sub(crate::PAGE_SIZE as u64);
            true
        } else {
            false
        }
    }

    /// Evict one page (from cold end of warm list)
    fn evict_one(&mut self) -> bool {
        // Try warm list first (cold end)
        if let Some(pfn) = self.warm_list.pop_back() {
            self.entries.remove(&pfn);
            self.used = self.used.saturating_sub(crate::PAGE_SIZE as u64);
            self.evictions += 1;
            return true;
        }
        // Fall back to hot list
        if let Some(pfn) = self.hot_list.pop_back() {
            self.entries.remove(&pfn);
            self.used = self.used.saturating_sub(crate::PAGE_SIZE as u64);
            self.evictions += 1;
            return true;
        }
        false
    }

    /// Demote pages that haven't been accessed recently
    pub fn demote_cold_pages(&mut self, age_threshold_ms: u64) {
        let cold_pfns: Vec<u64> = self.entries.iter()
            .filter(|(_, e)| e.tier == CacheTier::Hot && e.age_ms() > age_threshold_ms)
            .map(|(&pfn, _)| pfn)
            .collect();

        for pfn in cold_pfns {
            if let Some(entry) = self.entries.get_mut(&pfn) {
                entry.demote();
                self.hot_list.retain(|&p| p != pfn);
                self.warm_list.push_front(pfn);
                self.demotions += 1;
            }
        }
    }

    /// Cache hit rate
    pub fn hit_rate(&self) -> f64 {
        let total = self.hits + self.misses;
        if total == 0 { return 0.0; }
        self.hits as f64 / total as f64
    }

    /// Cache utilization
    pub fn utilization(&self) -> f64 {
        if self.capacity == 0 { return 0.0; }
        self.used as f64 / self.capacity as f64
    }

    /// Number of cached pages
    pub fn page_count(&self) -> usize { self.entries.len() }

    /// Hot page count
    pub fn hot_count(&self) -> usize { self.hot_list.len() }

    /// Warm page count
    pub fn warm_count(&self) -> usize { self.warm_list.len() }

    /// Total hits
    pub fn hits(&self) -> u64 { self.hits }

    /// Total misses
    pub fn misses(&self) -> u64 { self.misses }

    /// Total evictions
    pub fn evictions(&self) -> u64 { self.evictions }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cache_insert_access() {
        let mut cache = PageCache::new(100 * crate::PAGE_SIZE as u64);
        assert!(cache.insert(1, Some(Domain::Windows)));
        assert!(cache.access(1));
        assert_eq!(cache.hits(), 1);
        assert!(!cache.access(999));
        assert_eq!(cache.misses(), 1);
    }

    #[test]
    fn cache_promotion() {
        let mut cache = PageCache::new(100 * crate::PAGE_SIZE as u64);
        cache.insert(42, Some(Domain::AI));
        for _ in 0..10 {
            cache.access(42);
        }
        assert_eq!(cache.hot_count(), 1);
    }

    #[test]
    fn cache_eviction_on_full() {
        let mut cache = PageCache::new(3 * crate::PAGE_SIZE as u64);
        cache.insert(1, None);
        cache.insert(2, None);
        cache.insert(3, None);
        // Cache is full — inserting 4 should evict one
        assert!(cache.insert(4, None));
        assert_eq!(cache.page_count(), 3);
        assert_eq!(cache.evictions(), 1);
    }

    #[test]
    fn cache_hit_rate() {
        let mut cache = PageCache::new(100 * crate::PAGE_SIZE as u64);
        cache.insert(1, None);
        cache.access(1); // hit
        cache.access(2); // miss
        cache.access(1); // hit
        assert!((cache.hit_rate() - 2.0/3.0).abs() < 0.01);
    }

    #[test]
    fn cache_remove() {
        let mut cache = PageCache::new(100 * crate::PAGE_SIZE as u64);
        cache.insert(10, Some(Domain::Windows));
        assert_eq!(cache.page_count(), 1);
        assert!(cache.remove(10));
        assert_eq!(cache.page_count(), 0);
    }
}