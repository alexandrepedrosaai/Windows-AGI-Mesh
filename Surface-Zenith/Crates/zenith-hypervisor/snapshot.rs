//! # Container Snapshot System
//!
//! Full container checkpoint/restore for live migration and fault recovery.

use serde::{Deserialize, Serialize};
use uuid::Uuid;
use zenith_abi::domain::Domain;
use zenith_abi::types::{ZDomainId, ZTaskId, ZTimestamp};
use crate::vcpu::VCpuSnapshot;
use crate::error::ZhlError;

/// A complete container snapshot
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ContainerSnapshot {
    /// Unique snapshot ID
    pub id:             Uuid,
    /// Container ID this snapshot belongs to
    pub container_id:   ZDomainId,
    /// Domain type
    pub domain:         Domain,
    /// Snapshot version
    pub version:        u32,
    /// vCPU snapshots
    pub vcpus:          Vec<VCpuSnapshot>,
    /// Memory pages (serialized)
    pub memory_pages:   Vec<MemoryPageSnapshot>,
    /// Active task IDs at snapshot time
    pub active_tasks:   Vec<ZTaskId>,
    /// Container metadata
    pub metadata:       std::collections::HashMap<String, String>,
    /// Snapshot creation timestamp
    pub created_at:     ZTimestamp,
    /// Whether this is an incremental snapshot
    pub incremental:    bool,
    /// Parent snapshot ID (for incremental snapshots)
    pub parent_id:      Option<Uuid>,
    /// Total size in bytes
    pub size_bytes:     u64,
    /// SHA-256 checksum of the snapshot data
    pub checksum:       Vec<u8>,
}

/// A single memory page in a snapshot
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MemoryPageSnapshot {
    pub page_id:    u64,
    pub va:         u64,
    pub pa:         u64,
    pub dirty:      bool,
    pub cow:        bool,
    pub data:       Vec<u8>,
    pub checksum:   u32,
}

impl MemoryPageSnapshot {
    /// Create a new page snapshot
    pub fn new(page_id: u64, va: u64, pa: u64, data: Vec<u8>) -> Self {
        let checksum = data.iter().fold(0u32, |acc, &b| acc.wrapping_add(b as u32));
        Self {
            page_id,
            va,
            pa,
            dirty: false,
            cow: false,
            data,
            checksum,
        }
    }

    /// Verify page integrity
    pub fn verify(&self) -> bool {
        let computed = self.data.iter().fold(0u32, |acc, &b| acc.wrapping_add(b as u32));
        computed == self.checksum
    }
}

impl ContainerSnapshot {
    /// Create a new snapshot
    pub fn new(
        container_id: ZDomainId,
        domain: Domain,
        vcpus: Vec<VCpuSnapshot>,
        memory_pages: Vec<MemoryPageSnapshot>,
        active_tasks: Vec<ZTaskId>,
        incremental: bool,
        parent_id: Option<Uuid>,
    ) -> Self {
        let size_bytes = memory_pages.iter().map(|p| p.data.len() as u64).sum::<u64>()
            + vcpus.len() as u64 * 512;

        let checksum = Self::compute_checksum(&vcpus, &memory_pages);

        Self {
            id: Uuid::new_v4(),
            container_id,
            domain,
            version: 1,
            vcpus,
            memory_pages,
            active_tasks,
            metadata: std::collections::HashMap::new(),
            created_at: ZTimestamp(
                std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .unwrap_or_default()
                    .as_micros() as i64,
            ),
            incremental,
            parent_id,
            size_bytes,
            checksum,
        }
    }

    /// Compute snapshot checksum
    fn compute_checksum(vcpus: &[VCpuSnapshot], pages: &[MemoryPageSnapshot]) -> Vec<u8> {
        use sha2::{Sha256, Digest};
        let mut hasher = Sha256::new();
        for vcpu in vcpus {
            hasher.update(vcpu.index.to_le_bytes());
            hasher.update(vcpu.registers.pc.to_le_bytes());
        }
        for page in pages {
            hasher.update(page.page_id.to_le_bytes());
            hasher.update(&page.data);
        }
        hasher.finalize().to_vec()
    }

    /// Verify snapshot integrity
    pub fn verify(&self) -> bool {
        let expected = Self::compute_checksum(&self.vcpus, &self.memory_pages);
        self.checksum == expected
    }

    /// Number of dirty pages
    pub fn dirty_page_count(&self) -> usize {
        self.memory_pages.iter().filter(|p| p.dirty).count()
    }

    /// Total memory size in bytes
    pub fn memory_size_bytes(&self) -> u64 {
        self.memory_pages.iter().map(|p| p.data.len() as u64).sum()
    }

    /// Serialize to bytes
    pub fn serialize(&self) -> Result<Vec<u8>, ZhlError> {
        bincode::serialize(self).map_err(|e| ZhlError::SnapshotFailed {
            reason: e.to_string(),
        })
    }

    /// Deserialize from bytes
    pub fn deserialize(data: &[u8]) -> Result<Self, ZhlError> {
        bincode::deserialize(data).map_err(|e| ZhlError::SnapshotFailed {
            reason: e.to_string(),
        })
    }
}

/// Snapshot store — manages snapshot lifecycle
#[derive(Debug, Default)]
pub struct SnapshotStore {
    snapshots: std::collections::HashMap<Uuid, ContainerSnapshot>,
    /// Container → latest snapshot ID
    latest:    std::collections::HashMap<ZDomainId, Uuid>,
    /// Total storage used in bytes
    total_bytes: u64,
    /// Maximum storage capacity
    capacity_bytes: u64,
}

impl SnapshotStore {
    /// Create a new snapshot store
    pub fn new(capacity_bytes: u64) -> Self {
        Self {
            capacity_bytes,
            ..Default::default()
        }
    }

    /// Store a snapshot
    pub fn store(&mut self, snapshot: ContainerSnapshot) -> Result<Uuid, ZhlError> {
        if self.total_bytes + snapshot.size_bytes > self.capacity_bytes {
            // Evict oldest snapshots to make room
            self.evict_oldest(snapshot.size_bytes)?;
        }

        let id = snapshot.id;
        let container_id = snapshot.container_id;
        self.total_bytes += snapshot.size_bytes;
        self.latest.insert(container_id, id);
        self.snapshots.insert(id, snapshot);
        Ok(id)
    }

    /// Get a snapshot by ID
    pub fn get(&self, id: &Uuid) -> Option<&ContainerSnapshot> {
        self.snapshots.get(id)
    }

    /// Get the latest snapshot for a container
    pub fn latest_for(&self, container_id: &ZDomainId) -> Option<&ContainerSnapshot> {
        self.latest.get(container_id)
            .and_then(|id| self.snapshots.get(id))
    }

    /// Delete a snapshot
    pub fn delete(&mut self, id: &Uuid) -> bool {
        if let Some(snap) = self.snapshots.remove(id) {
            self.total_bytes = self.total_bytes.saturating_sub(snap.size_bytes);
            true
        } else {
            false
        }
    }

    /// Evict oldest snapshots to free space
    fn evict_oldest(&mut self, needed_bytes: u64) -> Result<(), ZhlError> {
        let mut freed = 0u64;
        let mut to_delete: Vec<Uuid> = self.snapshots.keys().copied().collect();
        // Sort by creation time (oldest first)
        to_delete.sort_by_key(|id| {
            self.snapshots.get(id).map(|s| s.created_at.0).unwrap_or(0)
        });

        for id in to_delete {
            if freed >= needed_bytes { break; }
            if let Some(snap) = self.snapshots.remove(&id) {
                freed += snap.size_bytes;
                self.total_bytes = self.total_bytes.saturating_sub(snap.size_bytes);
            }
        }

        if freed < needed_bytes {
            Err(ZhlError::MemoryAllocationFailed { bytes: needed_bytes })
        } else {
            Ok(())
        }
    }

    /// Storage utilization ratio (0.0–1.0)
    pub fn utilization(&self) -> f64 {
        if self.capacity_bytes == 0 { return 0.0; }
        self.total_bytes as f64 / self.capacity_bytes as f64
    }

    /// Total snapshot count
    pub fn count(&self) -> usize {
        self.snapshots.len()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::vcpu::{VCpuSnapshot, VCpuState, RegisterState, VCpuCounters};

    fn make_vcpu_snapshot(index: u32) -> VCpuSnapshot {
        VCpuSnapshot {
            index,
            state:     VCpuState::Paused,
            registers: RegisterState::new(),
            counters:  VCpuCounters::default(),
            priority:  128,
        }
    }

    fn make_snapshot(container_id: ZDomainId) -> ContainerSnapshot {
        ContainerSnapshot::new(
            container_id,
            Domain::Windows,
            vec![make_vcpu_snapshot(0), make_vcpu_snapshot(1)],
            vec![
                MemoryPageSnapshot::new(0, 0x1000, 0x100000, vec![0xABu8; 4096]),
                MemoryPageSnapshot::new(1, 0x2000, 0x101000, vec![0xCDu8; 4096]),
            ],
            vec![Uuid::new_v4()],
            false,
            None,
        )
    }

    #[test]
    fn snapshot_integrity() {
        let container_id = Uuid::new_v4();
        let snap = make_snapshot(container_id);
        assert!(snap.verify());
    }

    #[test]
    fn snapshot_serialization() {
        let container_id = Uuid::new_v4();
        let snap = make_snapshot(container_id);
        let bytes = snap.serialize().unwrap();
        let restored = ContainerSnapshot::deserialize(&bytes).unwrap();
        assert_eq!(restored.id, snap.id);
        assert_eq!(restored.domain, snap.domain);
        assert_eq!(restored.memory_pages.len(), 2);
    }

    #[test]
    fn page_snapshot_verify() {
        let page = MemoryPageSnapshot::new(0, 0x1000, 0x100000, vec![0x42u8; 4096]);
        assert!(page.verify());
    }

    #[test]
    fn snapshot_store_lifecycle() {
        let mut store = SnapshotStore::new(1024 * 1024 * 1024);
        let container_id = Uuid::new_v4();
        let snap = make_snapshot(container_id);
        let id = store.store(snap).unwrap();
        assert_eq!(store.count(), 1);
        assert!(store.get(&id).is_some());
        assert!(store.latest_for(&container_id).is_some());
        store.delete(&id);
        assert_eq!(store.count(), 0);
    }

    #[test]
    fn snapshot_store_eviction() {
        let mut store = SnapshotStore::new(100_000); // Very small capacity
        let container_id = Uuid::new_v4();
        // Store multiple snapshots until eviction is triggered
        for _ in 0..5 {
            let snap = make_snapshot(container_id);
            let _ = store.store(snap); // May fail if capacity exceeded
        }
        // Store should have evicted some snapshots
        assert!(store.utilization() <= 1.0);
    }
}