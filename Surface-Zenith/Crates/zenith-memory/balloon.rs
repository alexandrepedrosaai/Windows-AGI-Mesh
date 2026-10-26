//! # Memory Balloon Driver
//!
//! Implements memory ballooning for dynamic memory adjustment between domains.
//! The balloon driver inflates (reclaims pages from domain) or deflates
//! (returns pages to domain) to adjust memory allocation dynamically.

use zenith_abi::domain::Domain;
use crate::error::MemoryError;

/// Balloon state
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BalloonState {
    Idle,
    Inflating { target_pages: u64 },
    Deflating { target_pages: u64 },
    Stable { inflated_pages: u64 },
}

/// Memory balloon for a domain
#[derive(Debug)]
pub struct MemoryBalloon {
    pub domain:         Domain,
    pub inflated_pages: u64,
    pub max_pages:      u64,
    pub state:          BalloonState,
    pub inflate_count:  u64,
    pub deflate_count:  u64,
}

impl MemoryBalloon {
    pub fn new(domain: Domain, max_pages: u64) -> Self {
        Self {
            domain,
            inflated_pages: 0,
            max_pages,
            state:          BalloonState::Idle,
            inflate_count:  0,
            deflate_count:  0,
        }
    }

    /// Inflate the balloon by a given number of pages (reclaim from domain)
    pub fn inflate(&mut self, pages: u64) -> Result<u64, MemoryError> {
        let available = self.max_pages - self.inflated_pages;
        let to_inflate = pages.min(available);
        if to_inflate == 0 {
            return Err(MemoryError::BalloonFailed {
                reason: "balloon at maximum size".into(),
            });
        }
        self.inflated_pages += to_inflate;
        self.inflate_count  += 1;
        self.state = BalloonState::Stable { inflated_pages: self.inflated_pages };
        tracing::info!("Balloon inflated by {} pages for domain {:?}", to_inflate, self.domain);
        Ok(to_inflate)
    }

    /// Deflate the balloon by a given number of pages (return to domain)
    pub fn deflate(&mut self, pages: u64) -> Result<u64, MemoryError> {
        let to_deflate = pages.min(self.inflated_pages);
        if to_deflate == 0 {
            return Err(MemoryError::BalloonFailed {
                reason: "balloon already empty".into(),
            });
        }
        self.inflated_pages -= to_deflate;
        self.deflate_count  += 1;
        self.state = if self.inflated_pages == 0 {
            BalloonState::Idle
        } else {
            BalloonState::Stable { inflated_pages: self.inflated_pages }
        };
        tracing::info!("Balloon deflated by {} pages for domain {:?}", to_deflate, self.domain);
        Ok(to_deflate)
    }

    /// Inflated pages count
    pub fn inflated_pages(&self) -> u64 { self.inflated_pages }

    /// Inflation ratio (0.0–1.0)
    pub fn inflation_ratio(&self) -> f64 {
        if self.max_pages == 0 { return 0.0; }
        self.inflated_pages as f64 / self.max_pages as f64
    }

    /// Whether the balloon is fully inflated
    pub fn is_full(&self) -> bool { self.inflated_pages >= self.max_pages }

    /// Whether the balloon is empty
    pub fn is_empty(&self) -> bool { self.inflated_pages == 0 }
}

/// Balloon manager — coordinates balloons across all domains
#[derive(Debug, Default)]
pub struct BalloonManager {
    balloons:        std::collections::HashMap<String, MemoryBalloon>,
    total_inflated:  u64,
}

impl BalloonManager {
    pub fn new() -> Self { Self::default() }

    /// Register a balloon for a domain
    pub fn register(&mut self, domain: Domain, max_pages: u64) {
        let balloon = MemoryBalloon::new(domain.clone(), max_pages);
        self.balloons.insert(domain.name().to_string(), balloon);
    }

    /// Inflate a domain's balloon
    pub fn inflate(&mut self, domain: &Domain, pages: u64) -> Result<u64, MemoryError> {
        let balloon = self.balloons.get_mut(domain.name())
            .ok_or_else(|| MemoryError::Internal { message: format!("no balloon for {:?}", domain) })?;
        let inflated = balloon.inflate(pages)?;
        self.total_inflated += inflated;
        Ok(inflated)
    }

    /// Deflate a domain's balloon
    pub fn deflate(&mut self, domain: &Domain, pages: u64) -> Result<u64, MemoryError> {
        let balloon = self.balloons.get_mut(domain.name())
            .ok_or_else(|| MemoryError::Internal { message: format!("no balloon for {:?}", domain) })?;
        let deflated = balloon.deflate(pages)?;
        self.total_inflated = self.total_inflated.saturating_sub(deflated);
        Ok(deflated)
    }

    /// Total inflated pages across all domains
    pub fn total_inflated_pages(&self) -> u64 { self.total_inflated }

    /// Get balloon for a domain
    pub fn get(&self, domain: &Domain) -> Option<&MemoryBalloon> {
        self.balloons.get(domain.name())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn balloon_inflate_deflate() {
        let mut balloon = MemoryBalloon::new(Domain::Windows, 1000);
        assert!(balloon.is_empty());
        let inflated = balloon.inflate(500).unwrap();
        assert_eq!(inflated, 500);
        assert_eq!(balloon.inflated_pages(), 500);
        assert!((balloon.inflation_ratio() - 0.5).abs() < 0.01);
        let deflated = balloon.deflate(200).unwrap();
        assert_eq!(deflated, 200);
        assert_eq!(balloon.inflated_pages(), 300);
    }

    #[test]
    fn balloon_max_size_clamped() {
        let mut balloon = MemoryBalloon::new(Domain::Android, 100);
        balloon.inflate(150).unwrap(); // Should clamp to 100
        assert_eq!(balloon.inflated_pages(), 100);
        assert!(balloon.is_full());
    }

    #[test]
    fn balloon_empty_deflate_fails() {
        let mut balloon = MemoryBalloon::new(Domain::AI, 100);
        assert!(balloon.deflate(10).is_err());
    }

    #[test]
    fn balloon_manager() {
        let mut mgr = BalloonManager::new();
        mgr.register(Domain::Windows, 1000);
        mgr.register(Domain::Android, 500);
        mgr.inflate(&Domain::Windows, 300).unwrap();
        mgr.inflate(&Domain::Android, 200).unwrap();
        assert_eq!(mgr.total_inflated_pages(), 500);
        mgr.deflate(&Domain::Windows, 100).unwrap();
        assert_eq!(mgr.total_inflated_pages(), 400);
    }
}