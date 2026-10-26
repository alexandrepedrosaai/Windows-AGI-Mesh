//! # Dirty Page Tracker
//!
//! Tracks which pages have been modified since the last checkpoint.
//! Used by the live migration engine to transfer only changed pages.

use std::collections::{HashMap, HashSet, BTreeSet};
use zenith_abi::domain::Domain;
use zenith_abi::types::ZObjectId;

/// Dirty page tracking mode
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TrackingMode {
    /// Track all dirty pages globally
    Global,
    /// Track dirty pages per domain
    PerDomain,
    /// Track dirty pages per UMO
    PerUmo,
    /// Track dirty pages per domain and UMO
    Full,
}

/// A dirty page record
#[derive(Debug, Clone)]
pub struct DirtyRecord {
    pub pfn:       u64,
    pub domain:    Option<Domain>,
    pub umo_id:    Option<ZObjectId>,
    pub page_idx:  u64,
    pub version:   u64,
    pub marked_at: std::time::Instant,
}

/// Dirty page bitmap for efficient tracking
#[derive(Debug, Clone, Default)]
pub struct DirtyBitmap {
    /// Bitmap words (each bit = one page)
    words:      Vec<u64>,
    /// Total pages tracked
    total_pages: u64,
    /// Number of dirty pages
    dirty_count: u64,
}

impl DirtyBitmap {
    /// Create a new bitmap for a given number of pages
    pub fn new(total_pages: u64) -> Self {
        let words = vec![0u64; ((total_pages + 63) / 64) as usize];
        Self { words, total_pages, dirty_count: 0 }
    }

    /// Mark a page as dirty
    pub fn mark(&mut self, pfn: u64) -> bool {
        if pfn >= self.total_pages { return false; }
        let word_idx = (pfn / 64) as usize;
        let bit_idx  = pfn % 64;
        let was_clean = (self.words[word_idx] & (1 << bit_idx)) == 0;
        self.words[word_idx] |= 1 << bit_idx;
        if was_clean { self.dirty_count += 1; }
        was_clean
    }

    /// Clear a page's dirty bit
    pub fn clear(&mut self, pfn: u64) -> bool {
        if pfn >= self.total_pages { return false; }
        let word_idx = (pfn / 64) as usize;
        let bit_idx  = pfn % 64;
        let was_dirty = (self.words[word_idx] & (1 << bit_idx)) != 0;
        self.words[word_idx] &= !(1 << bit_idx);
        if was_dirty { self.dirty_count = self.dirty_count.saturating_sub(1); }
        was_dirty
    }

    /// Check if a page is dirty
    pub fn is_dirty(&self, pfn: u64) -> bool {
        if pfn >= self.total_pages { return false; }
        let word_idx = (pfn / 64) as usize;
        let bit_idx  = pfn % 64;
        (self.words[word_idx] & (1 << bit_idx)) != 0
    }

    /// Get all dirty page PFNs
    pub fn dirty_pfns(&self) -> Vec<u64> {
        let mut pfns = Vec::with_capacity(self.dirty_count as usize);
        for (word_idx, &word) in self.words.iter().enumerate() {
            if word == 0 { continue; }
            for bit in 0..64u64 {
                if (word & (1 << bit)) != 0 {
                    let pfn = word_idx as u64 * 64 + bit;
                    if pfn < self.total_pages {
                        pfns.push(pfn);
                    }
                }
            }
        }
        pfns
    }

    /// Clear all dirty bits
    pub fn clear_all(&mut self) {
        for word in &mut self.words {
            *word = 0;
        }
        self.dirty_count = 0;
    }

    /// Number of dirty pages
    pub fn dirty_count(&self) -> u64 { self.dirty_count }

    /// Dirty ratio (0.0–1.0)
    pub fn dirty_ratio(&self) -> f64 {
        if self.total_pages == 0 { return 0.0; }
        self.dirty_count as f64 / self.total_pages as f64
    }

    /// Merge another bitmap into this one (OR operation)
    pub fn merge(&mut self, other: &DirtyBitmap) {
        let len = self.words.len().min(other.words.len());
        for i in 0..len {
            let before = self.words[i].count_ones() as u64;
            self.words[i] |= other.words[i];
            let after = self.words[i].count_ones() as u64;
            self.dirty_count += after - before;
        }
    }

    /// Compute the XOR delta between two bitmaps (pages that changed)
    pub fn delta(&self, other: &DirtyBitmap) -> DirtyBitmap {
        let len = self.words.len().max(other.words.len());
        let mut result = DirtyBitmap::new(self.total_pages.max(other.total_pages));
        for i in 0..len {
            let a = if i < self.words.len()  { self.words[i]  } else { 0 };
            let b = if i < other.words.len() { other.words[i] } else { 0 };
            let xor = a ^ b;
            result.words[i] = xor;
            result.dirty_count += xor.count_ones() as u64;
        }
        result
    }
}

/// The Dirty Page Tracker
///
/// Maintains dirty page bitmaps per domain and per UMO for efficient
/// incremental migration and checkpoint operations.
#[derive(Debug)]
pub struct DirtyPageTracker {
    /// Global dirty bitmap
    global:         DirtyBitmap,
    /// Per-domain dirty bitmaps
    per_domain:     HashMap<String, DirtyBitmap>,
    /// Per-UMO dirty bitmaps
    per_umo:        HashMap<ZObjectId, DirtyBitmap>,
    /// Tracking mode
    mode:           TrackingMode,
    /// Total pages tracked
    total_pages:    u64,
    /// Total dirty events recorded
    total_events:   u64,
    /// Checkpoint history (bitmap snapshots)
    checkpoints:    Vec<(std::time::Instant, DirtyBitmap)>,
}

impl DirtyPageTracker {
    /// Create a new dirty page tracker
    pub fn new(total_pages: u64, mode: TrackingMode) -> Self {
        Self {
            global:      DirtyBitmap::new(total_pages),
            per_domain:  HashMap::new(),
            per_umo:     HashMap::new(),
            mode,
            total_pages,
            total_events: 0,
            checkpoints: Vec::new(),
        }
    }

    /// Mark a page as dirty
    pub fn mark_dirty(
        &mut self,
        pfn: u64,
        domain: Option<&Domain>,
        umo_id: Option<&ZObjectId>,
    ) {
        self.total_events += 1;
        self.global.mark(pfn);

        if let Some(d) = domain {
            if matches!(self.mode, TrackingMode::PerDomain | TrackingMode::Full) {
                self.per_domain
                    .entry(d.name().to_string())
                    .or_insert_with(|| DirtyBitmap::new(self.total_pages))
                    .mark(pfn);
            }
        }

        if let Some(id) = umo_id {
            if matches!(self.mode, TrackingMode::PerUmo | TrackingMode::Full) {
                self.per_umo
                    .entry(*id)
                    .or_insert_with(|| DirtyBitmap::new(self.total_pages))
                    .mark(pfn);
            }
        }
    }

    /// Clear a page's dirty bit
    pub fn clear_dirty(&mut self, pfn: u64, domain: Option<&Domain>, umo_id: Option<&ZObjectId>) {
        self.global.clear(pfn);
        if let Some(d) = domain {
            if let Some(bitmap) = self.per_domain.get_mut(d.name()) {
                bitmap.clear(pfn);
            }
        }
        if let Some(id) = umo_id {
            if let Some(bitmap) = self.per_umo.get_mut(id) {
                bitmap.clear(pfn);
            }
        }
    }

    /// Get all globally dirty pages
    pub fn global_dirty_pfns(&self) -> Vec<u64> {
        self.global.dirty_pfns()
    }

    /// Get dirty pages for a specific domain
    pub fn domain_dirty_pfns(&self, domain: &Domain) -> Vec<u64> {
        self.per_domain
            .get(domain.name())
            .map(|b| b.dirty_pfns())
            .unwrap_or_default()
    }

    /// Get dirty pages for a specific UMO
    pub fn umo_dirty_pfns(&self, umo_id: &ZObjectId) -> Vec<u64> {
        self.per_umo
            .get(umo_id)
            .map(|b| b.dirty_pfns())
            .unwrap_or_default()
    }

    /// Create a checkpoint (snapshot current dirty state)
    pub fn checkpoint(&mut self) -> usize {
        let snapshot = self.global.clone();
        self.checkpoints.push((std::time::Instant::now(), snapshot));
        if self.checkpoints.len() > 10 {
            self.checkpoints.remove(0);
        }
        self.global.dirty_count() as usize
    }

    /// Get pages that became dirty since the last checkpoint
    pub fn dirty_since_checkpoint(&self) -> Vec<u64> {
        if let Some((_, last_checkpoint)) = self.checkpoints.last() {
            self.global.delta(last_checkpoint).dirty_pfns()
        } else {
            self.global.dirty_pfns()
        }
    }

    /// Clear all dirty bits after a successful migration/checkpoint
    pub fn clear_all(&mut self) {
        self.global.clear_all();
        for bitmap in self.per_domain.values_mut() {
            bitmap.clear_all();
        }
        for bitmap in self.per_umo.values_mut() {
            bitmap.clear_all();
        }
    }

    /// Global dirty page count
    pub fn global_dirty_count(&self) -> u64 {
        self.global.dirty_count()
    }

    /// Global dirty ratio
    pub fn global_dirty_ratio(&self) -> f64 {
        self.global.dirty_ratio()
    }

    /// Total dirty events recorded
    pub fn total_events(&self) -> u64 { self.total_events }

    /// Whether dirty ratio exceeds the live migration threshold
    pub fn exceeds_migration_threshold(&self) -> bool {
        self.global.dirty_ratio() > crate::PRESSURE_LOW
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn dirty_bitmap_mark_clear() {
        let mut bitmap = DirtyBitmap::new(1024);
        assert!(!bitmap.is_dirty(42));
        bitmap.mark(42);
        assert!(bitmap.is_dirty(42));
        assert_eq!(bitmap.dirty_count(), 1);
        bitmap.clear(42);
        assert!(!bitmap.is_dirty(42));
        assert_eq!(bitmap.dirty_count(), 0);
    }

    #[test]
    fn dirty_bitmap_pfns() {
        let mut bitmap = DirtyBitmap::new(256);
        bitmap.mark(0);
        bitmap.mark(63);
        bitmap.mark(64);
        bitmap.mark(255);
        let pfns = bitmap.dirty_pfns();
        assert_eq!(pfns.len(), 4);
        assert!(pfns.contains(&0));
        assert!(pfns.contains(&63));
        assert!(pfns.contains(&64));
        assert!(pfns.contains(&255));
    }

    #[test]
    fn dirty_bitmap_clear_all() {
        let mut bitmap = DirtyBitmap::new(64);
        for i in 0..64 {
            bitmap.mark(i);
        }
        assert_eq!(bitmap.dirty_count(), 64);
        bitmap.clear_all();
        assert_eq!(bitmap.dirty_count(), 0);
    }

    #[test]
    fn dirty_bitmap_merge() {
        let mut a = DirtyBitmap::new(128);
        let mut b = DirtyBitmap::new(128);
        a.mark(10);
        b.mark(20);
        a.merge(&b);
        assert!(a.is_dirty(10));
        assert!(a.is_dirty(20));
        assert_eq!(a.dirty_count(), 2);
    }

    #[test]
    fn dirty_bitmap_delta() {
        let mut a = DirtyBitmap::new(128);
        let mut b = DirtyBitmap::new(128);
        a.mark(5);
        a.mark(10);
        b.mark(10);
        b.mark(15);
        let delta = a.delta(&b);
        // Pages 5 and 15 differ; page 10 is same
        assert!(delta.is_dirty(5));
        assert!(delta.is_dirty(15));
        assert!(!delta.is_dirty(10));
    }

    #[test]
    fn dirty_tracker_global() {
        let mut tracker = DirtyPageTracker::new(1024, TrackingMode::Global);
        tracker.mark_dirty(100, Some(&Domain::Windows), None);
        tracker.mark_dirty(200, Some(&Domain::Android), None);
        assert_eq!(tracker.global_dirty_count(), 2);
        let pfns = tracker.global_dirty_pfns();
        assert!(pfns.contains(&100));
        assert!(pfns.contains(&200));
    }

    #[test]
    fn dirty_tracker_per_domain() {
        let mut tracker = DirtyPageTracker::new(1024, TrackingMode::Full);
        tracker.mark_dirty(50, Some(&Domain::Windows), None);
        tracker.mark_dirty(60, Some(&Domain::Android), None);
        tracker.mark_dirty(70, Some(&Domain::Windows), None);

        let windows_dirty = tracker.domain_dirty_pfns(&Domain::Windows);
        assert_eq!(windows_dirty.len(), 2);
        let android_dirty = tracker.domain_dirty_pfns(&Domain::Android);
        assert_eq!(android_dirty.len(), 1);
    }

    #[test]
    fn dirty_tracker_checkpoint() {
        let mut tracker = DirtyPageTracker::new(1024, TrackingMode::Global);
        tracker.mark_dirty(1, None, None);
        tracker.mark_dirty(2, None, None);
        let count = tracker.checkpoint();
        assert_eq!(count, 2);

        // Mark more pages after checkpoint
        tracker.mark_dirty(3, None, None);
        let since = tracker.dirty_since_checkpoint();
        // Page 3 is new since checkpoint
        assert!(since.contains(&3));
    }

    #[test]
    fn dirty_tracker_clear_all() {
        let mut tracker = DirtyPageTracker::new(1024, TrackingMode::Full);
        for i in 0..100 {
            tracker.mark_dirty(i, Some(&Domain::Windows), None);
        }
        assert_eq!(tracker.global_dirty_count(), 100);
        tracker.clear_all();
        assert_eq!(tracker.global_dirty_count(), 0);
    }
}