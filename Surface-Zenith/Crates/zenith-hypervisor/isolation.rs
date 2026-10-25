//! # Memory Isolation Enforcement
//!
//! Enforces memory isolation between domain containers.
//! No domain can read or write another domain's memory without
//! an explicit capability token and a UMO mapping.

use std::collections::{HashMap, HashSet};
use uuid::Uuid;
use zenith_abi::domain::Domain;
use zenith_abi::types::{ZObjectId, ZDomainId};
use zenith_abi::capability::CapabilityToken;
use zenith_abi::domain::{ResourceClass, AccessLevel};
use crate::error::ZhlError;

/// Memory region type
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum MemoryRegionKind {
    /// Private to a single domain (not shareable)
    Private,
    /// Shared via UMO (requires capability)
    Shared,
    /// Read-only shared (e.g., kernel code)
    ReadOnlyShared,
    /// Device-mapped memory (MMIO)
    DeviceMapped,
    /// DMA buffer
    DmaBuffer,
}

/// A memory region in a domain's address space
#[derive(Debug, Clone)]
pub struct MemoryRegion {
    /// Region ID
    pub id:         Uuid,
    /// Start virtual address
    pub va_start:   u64,
    /// End virtual address (exclusive)
    pub va_end:     u64,
    /// Physical address (if mapped)
    pub pa:         Option<u64>,
    /// Region kind
    pub kind:       MemoryRegionKind,
    /// Owner domain
    pub owner:      Domain,
    /// Domains that have read access
    pub readers:    HashSet<String>,
    /// Domains that have write access
    pub writers:    HashSet<String>,
    /// Associated UMO ID (for shared regions)
    pub umo_id:     Option<ZObjectId>,
    /// Whether this region is currently mapped
    pub mapped:     bool,
    /// Page count
    pub page_count: u64,
}

impl MemoryRegion {
    /// Create a new private memory region
    pub fn private(va_start: u64, size_bytes: u64, owner: Domain) -> Self {
        let page_count = (size_bytes + crate::PAGE_SIZE as u64 - 1) / crate::PAGE_SIZE as u64;
        Self {
            id:         Uuid::new_v4(),
            va_start,
            va_end:     va_start + size_bytes,
            pa:         None,
            kind:       MemoryRegionKind::Private,
            owner:      owner.clone(),
            readers:    {
                let mut s = HashSet::new();
                s.insert(owner.name().to_string());
                s
            },
            writers:    {
                let mut s = HashSet::new();
                s.insert(owner.name().to_string());
                s
            },
            umo_id:     None,
            mapped:     false,
            page_count,
        }
    }

    /// Create a shared memory region backed by a UMO
    pub fn shared(va_start: u64, size_bytes: u64, owner: Domain, umo_id: ZObjectId) -> Self {
        let page_count = (size_bytes + crate::PAGE_SIZE as u64 - 1) / crate::PAGE_SIZE as u64;
        Self {
            id:         Uuid::new_v4(),
            va_start,
            va_end:     va_start + size_bytes,
            pa:         None,
            kind:       MemoryRegionKind::Shared,
            owner:      owner.clone(),
            readers:    {
                let mut s = HashSet::new();
                s.insert(owner.name().to_string());
                s
            },
            writers:    {
                let mut s = HashSet::new();
                s.insert(owner.name().to_string());
                s
            },
            umo_id:     Some(umo_id),
            mapped:     false,
            page_count,
        }
    }

    /// Grant read access to a domain
    pub fn grant_read(&mut self, domain: &Domain) {
        self.readers.insert(domain.name().to_string());
    }

    /// Grant write access to a domain
    pub fn grant_write(&mut self, domain: &Domain) {
        self.readers.insert(domain.name().to_string());
        self.writers.insert(domain.name().to_string());
    }

    /// Revoke all access for a domain
    pub fn revoke(&mut self, domain: &Domain) {
        let name = domain.name().to_string();
        self.readers.remove(&name);
        self.writers.remove(&name);
    }

    /// Check if a domain can read this region
    pub fn can_read(&self, domain: &Domain) -> bool {
        self.readers.contains(domain.name())
    }

    /// Check if a domain can write this region
    pub fn can_write(&self, domain: &Domain) -> bool {
        self.writers.contains(domain.name())
    }

    /// Size in bytes
    pub fn size_bytes(&self) -> u64 {
        self.va_end - self.va_start
    }

    /// Whether a virtual address falls within this region
    pub fn contains_va(&self, va: u64) -> bool {
        va >= self.va_start && va < self.va_end
    }
}

/// Cross-domain access request
#[derive(Debug, Clone)]
pub struct AccessRequest {
    /// Requesting domain
    pub requester:  Domain,
    /// Target domain
    pub target:     Domain,
    /// Target UMO ID
    pub umo_id:     ZObjectId,
    /// Requested access level
    pub access:     AccessLevel,
    /// Capability token authorizing this request
    pub capability: CapabilityToken,
}

/// Isolation violation record
#[derive(Debug, Clone)]
pub struct IsolationViolation {
    pub requester:  Domain,
    pub target:     Domain,
    pub va:         u64,
    pub reason:     String,
    pub timestamp:  std::time::Instant,
}

/// Memory isolation enforcer
///
/// Maintains the isolation boundary between domain containers.
/// All cross-domain memory access must be validated here.
#[derive(Debug, Default)]
pub struct IsolationEnforcer {
    /// Memory regions per domain
    regions:    HashMap<String, Vec<MemoryRegion>>,
    /// Violation log
    violations: Vec<IsolationViolation>,
    /// Total access checks performed
    check_count: u64,
    /// Total violations detected
    violation_count: u64,
}

impl IsolationEnforcer {
    /// Create a new isolation enforcer
    pub fn new() -> Self { Self::default() }

    /// Register a memory region for a domain
    pub fn register_region(&mut self, region: MemoryRegion) {
        self.regions
            .entry(region.owner.name().to_string())
            .or_default()
            .push(region);
    }

    /// Validate a cross-domain memory access
    pub fn validate_access(
        &mut self,
        requester: &Domain,
        target: &Domain,
        va: u64,
        write: bool,
    ) -> Result<(), ZhlError> {
        self.check_count += 1;

        // Same domain — always allowed
        if requester == target {
            return Ok(());
        }

        // Find the region at this VA in the target domain
        let target_regions = self.regions.get(target.name()).cloned().unwrap_or_default();
        let region = target_regions.iter().find(|r| r.contains_va(va));

        match region {
            None => {
                // No region at this VA — access denied
                self.record_violation(requester.clone(), target.clone(), va, "no region at VA");
                Err(ZhlError::IsolationViolation {
                    from: requester.name().to_string(),
                    to:   target.name().to_string(),
                })
            }
            Some(r) => {
                // Check access permissions
                let allowed = if write {
                    r.can_write(requester)
                } else {
                    r.can_read(requester)
                };

                if allowed {
                    Ok(())
                } else {
                    self.record_violation(
                        requester.clone(), target.clone(), va,
                        &format!("{} access denied", if write { "write" } else { "read" }),
                    );
                    Err(ZhlError::IsolationViolation {
                        from: requester.name().to_string(),
                        to:   target.name().to_string(),
                    })
                }
            }
        }
    }

    /// Grant cross-domain access to a UMO
    pub fn grant_umo_access(
        &mut self,
        umo_id: &ZObjectId,
        requester: &Domain,
        access: &AccessLevel,
    ) -> bool {
        for regions in self.regions.values_mut() {
            for region in regions.iter_mut() {
                if region.umo_id.as_ref() == Some(umo_id) {
                    match access {
                        AccessLevel::Read => {
                            region.grant_read(requester);
                        }
                        AccessLevel::Write | AccessLevel::ReadWrite => {
                            region.grant_write(requester);
                        }
                        _ => {}
                    }
                    return true;
                }
            }
        }
        false
    }

    /// Revoke all cross-domain access for a domain (e.g., on domain crash)
    pub fn revoke_all_access(&mut self, domain: &Domain) {
        for regions in self.regions.values_mut() {
            for region in regions.iter_mut() {
                if &region.owner != domain {
                    region.revoke(domain);
                }
            }
        }
    }

    fn record_violation(&mut self, requester: Domain, target: Domain, va: u64, reason: &str) {
        self.violation_count += 1;
        self.violations.push(IsolationViolation {
            requester,
            target,
            va,
            reason: reason.to_string(),
            timestamp: std::time::Instant::now(),
        });
        if self.violations.len() > 10_000 {
            self.violations.drain(0..1000);
        }
    }

    /// Total access checks
    pub fn check_count(&self) -> u64 { self.check_count }

    /// Total violations detected
    pub fn violation_count(&self) -> u64 { self.violation_count }

    /// Recent violations
    pub fn recent_violations(&self, count: usize) -> &[IsolationViolation] {
        let len = self.violations.len();
        &self.violations[len.saturating_sub(count)..]
    }

    /// Violation rate (0.0–1.0)
    pub fn violation_rate(&self) -> f64 {
        if self.check_count == 0 { return 0.0; }
        self.violation_count as f64 / self.check_count as f64
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn private_region_same_domain_allowed() {
        let mut enforcer = IsolationEnforcer::new();
        let region = MemoryRegion::private(0x1000, 0x1000, Domain::Windows);
        enforcer.register_region(region);
        assert!(enforcer.validate_access(&Domain::Windows, &Domain::Windows, 0x1000, false).is_ok());
    }

    #[test]
    fn private_region_cross_domain_denied() {
        let mut enforcer = IsolationEnforcer::new();
        let region = MemoryRegion::private(0x1000, 0x1000, Domain::Windows);
        enforcer.register_region(region);
        assert!(enforcer.validate_access(&Domain::Android, &Domain::Windows, 0x1000, false).is_err());
        assert_eq!(enforcer.violation_count(), 1);
    }

    #[test]
    fn shared_region_with_grant() {
        let mut enforcer = IsolationEnforcer::new();
        let umo_id = Uuid::new_v4();
        let mut region = MemoryRegion::shared(0x2000, 0x1000, Domain::Windows, umo_id);
        region.grant_read(&Domain::Android);
        enforcer.register_region(region);
        assert!(enforcer.validate_access(&Domain::Android, &Domain::Windows, 0x2000, false).is_ok());
        assert!(enforcer.validate_access(&Domain::Android, &Domain::Windows, 0x2000, true).is_err());
    }

    #[test]
    fn region_contains_va() {
        let region = MemoryRegion::private(0x1000, 0x2000, Domain::AI);
        assert!(region.contains_va(0x1000));
        assert!(region.contains_va(0x2FFF));
        assert!(!region.contains_va(0x3000));
        assert!(!region.contains_va(0x0FFF));
    }

    #[test]
    fn revoke_all_access() {
        let mut enforcer = IsolationEnforcer::new();
        let mut region = MemoryRegion::private(0x1000, 0x1000, Domain::Windows);
        region.grant_read(&Domain::Android);
        enforcer.register_region(region);
        enforcer.revoke_all_access(&Domain::Android);
        assert!(enforcer.validate_access(&Domain::Android, &Domain::Windows, 0x1000, false).is_err());
    }
}