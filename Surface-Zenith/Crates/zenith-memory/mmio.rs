//! # Memory-Mapped I/O (MMIO) Manager

use std::collections::HashMap;
use zenith_abi::domain::Domain;
use crate::error::MemoryError;

/// MMIO region type
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum MmioKind {
    /// Device registers
    DeviceRegisters,
    /// Frame buffer (display)
    FrameBuffer,
    /// DMA buffer
    DmaBuffer,
    /// PCIe BAR
    PciBar,
    /// GIC (interrupt controller)
    Gic,
    /// Timer
    Timer,
    /// UART
    Uart,
    /// Custom
    Custom(String),
}

/// An MMIO region
#[derive(Debug, Clone)]
pub struct MmioRegion {
    pub id:         uuid::Uuid,
    pub name:       String,
    pub kind:       MmioKind,
    pub pa_start:   u64,
    pub pa_end:     u64,
    pub owner:      Option<Domain>,
    pub cacheable:  bool,
    pub read_only:  bool,
    pub mapped_at:  std::time::Instant,
}

impl MmioRegion {
    pub fn new(name: impl Into<String>, kind: MmioKind, pa_start: u64, size: u64) -> Self {
        Self {
            id:        uuid::Uuid::new_v4(),
            name:      name.into(),
            kind,
            pa_start,
            pa_end:    pa_start + size,
            owner:     None,
            cacheable: false,
            read_only: false,
            mapped_at: std::time::Instant::now(),
        }
    }

    pub fn size(&self) -> u64 { self.pa_end - self.pa_start }

    pub fn contains(&self, pa: u64) -> bool {
        pa >= self.pa_start && pa < self.pa_end
    }

    pub fn overlaps(&self, other: &MmioRegion) -> bool {
        self.pa_start < other.pa_end && self.pa_end > other.pa_start
    }
}

/// MMIO manager
#[derive(Debug, Default)]
pub struct MmioManager {
    regions:     HashMap<uuid::Uuid, MmioRegion>,
    total_mapped: u64,
}

impl MmioManager {
    pub fn new() -> Self { Self::default() }

    /// Register an MMIO region
    pub fn register(&mut self, region: MmioRegion) -> Result<uuid::Uuid, MemoryError> {
        // Check for conflicts
        for existing in self.regions.values() {
            if existing.overlaps(&region) {
                return Err(MemoryError::MmioConflict {
                    addr: region.pa_start,
                    end:  region.pa_end,
                });
            }
        }
        let id = region.id;
        self.total_mapped += region.size();
        self.regions.insert(id, region);
        Ok(id)
    }

    /// Unregister an MMIO region
    pub fn unregister(&mut self, id: &uuid::Uuid) -> bool {
        if let Some(region) = self.regions.remove(id) {
            self.total_mapped = self.total_mapped.saturating_sub(region.size());
            true
        } else {
            false
        }
    }

    /// Find the MMIO region containing a physical address
    pub fn find_by_pa(&self, pa: u64) -> Option<&MmioRegion> {
        self.regions.values().find(|r| r.contains(pa))
    }

    /// Get a region by ID
    pub fn get(&self, id: &uuid::Uuid) -> Option<&MmioRegion> {
        self.regions.get(id)
    }

    /// Register standard Surface Zenith MMIO regions
    pub fn register_surface_zenith_mmio(&mut self) {
        let regions = vec![
            MmioRegion::new("GIC-Distributor",  MmioKind::Gic,             0x0800_0000, 0x10000),
            MmioRegion::new("GIC-Redistributor",MmioKind::Gic,             0x080A_0000, 0x100000),
            MmioRegion::new("Generic-Timer",    MmioKind::Timer,           0x0900_0000, 0x10000),
            MmioRegion::new("UART0",            MmioKind::Uart,            0x0901_0000, 0x1000),
            MmioRegion::new("Display-FB",       MmioKind::FrameBuffer,     0x1000_0000, 0x0400_0000),
            MmioRegion::new("GPU-Registers",    MmioKind::DeviceRegisters, 0x2000_0000, 0x0100_0000),
            MmioRegion::new("NPU-Registers",    MmioKind::DeviceRegisters, 0x3000_0000, 0x0100_0000),
            MmioRegion::new("Modem-Registers",  MmioKind::DeviceRegisters, 0x4000_0000, 0x0010_0000),
        ];

        for region in regions {
            let _ = self.register(region);
        }
    }

    /// Total MMIO regions
    pub fn count(&self) -> usize { self.regions.len() }

    /// Total mapped MMIO bytes
    pub fn total_mapped_bytes(&self) -> u64 { self.total_mapped }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn mmio_register_find() {
        let mut mgr = MmioManager::new();
        let region = MmioRegion::new("test-device", MmioKind::DeviceRegisters, 0x1000_0000, 0x10000);
        let id = mgr.register(region).unwrap();
        assert!(mgr.find_by_pa(0x1000_0000).is_some());
        assert!(mgr.find_by_pa(0x1000_FFFF).is_some());
        assert!(mgr.find_by_pa(0x1001_0000).is_none());
        mgr.unregister(&id);
        assert!(mgr.find_by_pa(0x1000_0000).is_none());
    }

    #[test]
    fn mmio_conflict_detection() {
        let mut mgr = MmioManager::new();
        let r1 = MmioRegion::new("r1", MmioKind::DeviceRegisters, 0x1000, 0x1000);
        let r2 = MmioRegion::new("r2", MmioKind::DeviceRegisters, 0x1800, 0x1000); // overlaps
        mgr.register(r1).unwrap();
        assert!(mgr.register(r2).is_err());
    }

    #[test]
    fn mmio_surface_zenith_regions() {
        let mut mgr = MmioManager::new();
        mgr.register_surface_zenith_mmio();
        assert!(mgr.count() >= 6);
        assert!(mgr.find_by_pa(0x0800_0000).is_some()); // GIC
    }
}