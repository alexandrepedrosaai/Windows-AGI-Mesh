//! # Memory Fabric Bridge
//!
//! Bridges the Zenith Hypervisor Layer with the Shared Memory Fabric.
//! Manages UMO mappings across domain containers.

use std::collections::HashMap;
use uuid::Uuid;
use zenith_abi::domain::Domain;
use zenith_abi::types::{ZObjectId, ZDomainId, ZSessionId};
use zenith_abi::memory::{UniversalMemoryObject, UmoKind, MemoryFabric};
use crate::error::ZhlError;

/// A cross-domain UMO mapping
#[derive(Debug, Clone)]
pub struct UmoMapping {
    pub object_id:   ZObjectId,
    pub session_id:  ZSessionId,
    pub owner:       Domain,
    pub readers:     Vec<Domain>,
    pub writers:     Vec<Domain>,
    pub va_per_domain: HashMap<String, u64>,
    pub pinned:      bool,
    pub created_at:  std::time::Instant,
}

impl UmoMapping {
    pub fn new(object_id: ZObjectId, session_id: ZSessionId, owner: Domain) -> Self {
        Self {
            object_id,
            session_id,
            owner,
            readers: Vec::new(),
            writers: Vec::new(),
            va_per_domain: HashMap::new(),
            pinned: false,
            created_at: std::time::Instant::now(),
        }
    }

    pub fn add_reader(&mut self, domain: Domain) {
        if !self.readers.contains(&domain) {
            self.readers.push(domain);
        }
    }

    pub fn add_writer(&mut self, domain: Domain) {
        self.add_reader(domain.clone());
        if !self.writers.contains(&domain) {
            self.writers.push(domain);
        }
    }

    pub fn can_read(&self, domain: &Domain) -> bool {
        &self.owner == domain || self.readers.contains(domain)
    }

    pub fn can_write(&self, domain: &Domain) -> bool {
        &self.owner == domain || self.writers.contains(domain)
    }

    pub fn map_to_domain(&mut self, domain: &Domain, va: u64) {
        self.va_per_domain.insert(domain.name().to_string(), va);
    }

    pub fn va_for_domain(&self, domain: &Domain) -> Option<u64> {
        self.va_per_domain.get(domain.name()).copied()
    }
}

/// The Memory Fabric Bridge — manages UMO lifecycle across domains
#[derive(Debug)]
pub struct MemoryFabricBridge {
    fabric:   MemoryFabric,
    mappings: HashMap<ZObjectId, UmoMapping>,
    total_mapped: u64,
    total_unmapped: u64,
}

impl MemoryFabricBridge {
    /// Create a new bridge with a given memory capacity
    pub fn new(capacity_bytes: u64) -> Self {
        Self {
            fabric:         MemoryFabric::new(capacity_bytes),
            mappings:       HashMap::new(),
            total_mapped:   0,
            total_unmapped: 0,
        }
    }

    /// Create a new UMO and register it
    pub fn create_umo(
        &mut self,
        name: impl Into<String>,
        kind: UmoKind,
        session: ZSessionId,
        creator: Domain,
    ) -> Result<ZObjectId, ZhlError> {
        let umo = UniversalMemoryObject::new(name, kind, session, creator.clone());
        let id = self.fabric.register(umo).map_err(|e| ZhlError::MemoryAllocationFailed {
            bytes: 0,
        })?;

        let mapping = UmoMapping::new(id, session, creator);
        self.mappings.insert(id, mapping);
        self.total_mapped += 1;
        Ok(id)
    }

    /// Map a UMO into a domain's address space
    pub fn map_into_domain(
        &mut self,
        object_id: &ZObjectId,
        domain: Domain,
        va: u64,
        write_access: bool,
    ) -> Result<(), ZhlError> {
        let mapping = self.mappings.get_mut(object_id)
            .ok_or_else(|| ZhlError::Internal { message: format!("UMO {object_id} not found") })?;

        if write_access {
            mapping.add_writer(domain.clone());
        } else {
            mapping.add_reader(domain.clone());
        }
        mapping.map_to_domain(&domain, va);
        Ok(())
    }

    /// Unmap a UMO from a domain
    pub fn unmap_from_domain(&mut self, object_id: &ZObjectId, domain: &Domain) -> bool {
        if let Some(mapping) = self.mappings.get_mut(object_id) {
            mapping.va_per_domain.remove(domain.name());
            mapping.readers.retain(|d| d != domain);
            mapping.writers.retain(|d| d != domain);
            true
        } else {
            false
        }
    }

    /// Destroy a UMO
    pub fn destroy_umo(&mut self, object_id: &ZObjectId) -> bool {
        self.mappings.remove(object_id);
        self.fabric.deregister(object_id).is_some()
    }

    /// Get a UMO mapping
    pub fn get_mapping(&self, object_id: &ZObjectId) -> Option<&UmoMapping> {
        self.mappings.get(object_id)
    }

    /// Get all UMOs for a session
    pub fn session_umos(&self, session: &ZSessionId) -> Vec<ZObjectId> {
        self.mappings
            .iter()
            .filter(|(_, m)| &m.session_id == session)
            .map(|(id, _)| *id)
            .collect()
    }

    /// Unmap all UMOs from a domain (e.g., on domain crash)
    pub fn unmap_all_for_domain(&mut self, domain: &Domain) -> usize {
        let ids: Vec<ZObjectId> = self.mappings.keys().copied().collect();
        let mut count = 0;
        for id in ids {
            if self.unmap_from_domain(&id, domain) {
                count += 1;
            }
        }
        count
    }

    /// Memory fabric utilization
    pub fn utilization(&self) -> f64 {
        self.fabric.utilization()
    }

    /// Total UMO count
    pub fn umo_count(&self) -> usize {
        self.mappings.len()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn fabric_bridge_create_umo() {
        let mut bridge = MemoryFabricBridge::new(1024 * 1024 * 1024);
        let session = Uuid::new_v4();
        let id = bridge.create_umo("test.docx", UmoKind::Document, session, Domain::Windows).unwrap();
        assert_eq!(bridge.umo_count(), 1);
        assert!(bridge.get_mapping(&id).is_some());
    }

    #[test]
    fn fabric_bridge_map_domain() {
        let mut bridge = MemoryFabricBridge::new(1024 * 1024 * 1024);
        let session = Uuid::new_v4();
        let id = bridge.create_umo("shared.pdf", UmoKind::Pdf, session, Domain::Windows).unwrap();
        bridge.map_into_domain(&id, Domain::Android, 0x10000, false).unwrap();
        let mapping = bridge.get_mapping(&id).unwrap();
        assert!(mapping.can_read(&Domain::Android));
        assert!(!mapping.can_write(&Domain::Android));
        assert_eq!(mapping.va_for_domain(&Domain::Android), Some(0x10000));
    }

    #[test]
    fn fabric_bridge_write_access() {
        let mut bridge = MemoryFabricBridge::new(1024 * 1024 * 1024);
        let session = Uuid::new_v4();
        let id = bridge.create_umo("data.xlsx", UmoKind::Document, session, Domain::Windows).unwrap();
        bridge.map_into_domain(&id, Domain::AI, 0x20000, true).unwrap();
        let mapping = bridge.get_mapping(&id).unwrap();
        assert!(mapping.can_write(&Domain::AI));
    }

    #[test]
    fn fabric_bridge_unmap_domain() {
        let mut bridge = MemoryFabricBridge::new(1024 * 1024 * 1024);
        let session = Uuid::new_v4();
        let id = bridge.create_umo("doc.pdf", UmoKind::Pdf, session, Domain::Windows).unwrap();
        bridge.map_into_domain(&id, Domain::Android, 0x1000, false).unwrap();
        bridge.unmap_from_domain(&id, &Domain::Android);
        let mapping = bridge.get_mapping(&id).unwrap();
        assert!(!mapping.can_read(&Domain::Android));
    }

    #[test]
    fn fabric_bridge_session_umos() {
        let mut bridge = MemoryFabricBridge::new(1024 * 1024 * 1024);
        let session = Uuid::new_v4();
        for i in 0..3 {
            bridge.create_umo(format!("doc_{i}"), UmoKind::Document, session, Domain::Windows).unwrap();
        }
        let other_session = Uuid::new_v4();
        bridge.create_umo("other", UmoKind::Blob, other_session, Domain::Android).unwrap();
        assert_eq!(bridge.session_umos(&session).len(), 3);
        assert_eq!(bridge.session_umos(&other_session).len(), 1);
    }
}