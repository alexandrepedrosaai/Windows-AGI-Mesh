//! # Hardware Resource Arbitration
//!
//! Manages physical hardware resources (CPU cores, GPU, NPU, QPU)
//! and arbitrates access between domain containers.

use std::collections::HashMap;
use serde::{Deserialize, Serialize};
use zenith_abi::domain::Domain;
use zenith_abi::types::ZDomainId;
use crate::error::ZhlError;

/// Physical hardware resource type
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum PhysicalResource {
    CpuCore(u32),
    GpuEngine(u32),
    NpuEngine(u32),
    QpuRegister(u32),
    DspCore(u32),
    ModemChannel(u32),
    StorageController(u32),
    NetworkInterface(u32),
    Camera(u32),
    Display(u32),
}

impl PhysicalResource {
    pub fn name(&self) -> String {
        match self {
            PhysicalResource::CpuCore(i)          => format!("cpu-core-{i}"),
            PhysicalResource::GpuEngine(i)         => format!("gpu-engine-{i}"),
            PhysicalResource::NpuEngine(i)         => format!("npu-engine-{i}"),
            PhysicalResource::QpuRegister(i)       => format!("qpu-register-{i}"),
            PhysicalResource::DspCore(i)           => format!("dsp-core-{i}"),
            PhysicalResource::ModemChannel(i)      => format!("modem-channel-{i}"),
            PhysicalResource::StorageController(i) => format!("storage-ctrl-{i}"),
            PhysicalResource::NetworkInterface(i)  => format!("net-if-{i}"),
            PhysicalResource::Camera(i)            => format!("camera-{i}"),
            PhysicalResource::Display(i)           => format!("display-{i}"),
        }
    }

    /// Whether this resource supports shared access
    pub fn is_shareable(&self) -> bool {
        matches!(
            self,
            PhysicalResource::StorageController(_)
                | PhysicalResource::NetworkInterface(_)
                | PhysicalResource::Display(_)
        )
    }
}

/// Hardware resource allocation record
#[derive(Debug, Clone)]
pub struct ResourceAllocation {
    pub resource:    PhysicalResource,
    pub owner:       ZDomainId,
    pub domain:      Domain,
    pub exclusive:   bool,
    pub allocated_at: std::time::Instant,
    pub usage_pct:   f64,
}

/// Hardware resource arbitrator
#[derive(Debug, Default)]
pub struct HardwareArbitrator {
    /// resource name → allocation
    allocations: HashMap<String, ResourceAllocation>,
    /// Available resources
    available:   HashMap<String, PhysicalResource>,
    /// Total allocation count
    total_allocs: u64,
    /// Total release count
    total_releases: u64,
}

impl HardwareArbitrator {
    /// Create a new arbitrator
    pub fn new() -> Self { Self::default() }

    /// Register a physical resource as available
    pub fn register_resource(&mut self, resource: PhysicalResource) {
        self.available.insert(resource.name(), resource);
    }

    /// Register the standard Surface Zenith hardware set
    pub fn register_surface_zenith_hardware(&mut self) {
        // CPU cores (8-core ARM64)
        for i in 0..8 {
            self.register_resource(PhysicalResource::CpuCore(i));
        }
        // GPU engines (Adreno 850)
        for i in 0..4 {
            self.register_resource(PhysicalResource::GpuEngine(i));
        }
        // NPU engines (300 TOPS)
        for i in 0..2 {
            self.register_resource(PhysicalResource::NpuEngine(i));
        }
        // QPU registers (simulated)
        for i in 0..50 {
            self.register_resource(PhysicalResource::QpuRegister(i));
        }
        // DSP cores
        for i in 0..2 {
            self.register_resource(PhysicalResource::DspCore(i));
        }
        // Modem channels
        for i in 0..4 {
            self.register_resource(PhysicalResource::ModemChannel(i));
        }
        // Storage controllers
        self.register_resource(PhysicalResource::StorageController(0));
        // Network interfaces
        self.register_resource(PhysicalResource::NetworkInterface(0)); // WiFi
        self.register_resource(PhysicalResource::NetworkInterface(1)); // 5G
        // Cameras
        self.register_resource(PhysicalResource::Camera(0)); // Rear
        self.register_resource(PhysicalResource::Camera(1)); // Front
        // Displays
        self.register_resource(PhysicalResource::Display(0)); // Inner
        self.register_resource(PhysicalResource::Display(1)); // Outer
    }

    /// Allocate a resource to a domain
    pub fn allocate(
        &mut self,
        resource: &PhysicalResource,
        owner: ZDomainId,
        domain: Domain,
        exclusive: bool,
    ) -> Result<(), ZhlError> {
        let name = resource.name();

        // Check if resource exists
        if !self.available.contains_key(&name) {
            return Err(ZhlError::HardwareUnavailable { resource: name });
        }

        // Check if already allocated exclusively
        if let Some(alloc) = self.allocations.get(&name) {
            if alloc.exclusive {
                return Err(ZhlError::HardwareUnavailable {
                    resource: format!("{} (exclusively held by {:?})", name, alloc.domain),
                });
            }
            if exclusive {
                return Err(ZhlError::HardwareUnavailable {
                    resource: format!("{} (already allocated, cannot take exclusive)", name),
                });
            }
        }

        self.allocations.insert(name, ResourceAllocation {
            resource: resource.clone(),
            owner,
            domain,
            exclusive,
            allocated_at: std::time::Instant::now(),
            usage_pct: 0.0,
        });
        self.total_allocs += 1;
        Ok(())
    }

    /// Release a resource
    pub fn release(&mut self, resource: &PhysicalResource, owner: ZDomainId) -> bool {
        let name = resource.name();
        if let Some(alloc) = self.allocations.get(&name) {
            if alloc.owner == owner {
                self.allocations.remove(&name);
                self.total_releases += 1;
                return true;
            }
        }
        false
    }

    /// Release all resources held by a domain (e.g., on crash)
    pub fn release_all_for_domain(&mut self, owner: ZDomainId) -> usize {
        let to_release: Vec<String> = self.allocations
            .iter()
            .filter(|(_, a)| a.owner == owner)
            .map(|(k, _)| k.clone())
            .collect();
        let count = to_release.len();
        for key in to_release {
            self.allocations.remove(&key);
            self.total_releases += 1;
        }
        count
    }

    /// Update usage percentage for a resource
    pub fn update_usage(&mut self, resource: &PhysicalResource, usage_pct: f64) {
        if let Some(alloc) = self.allocations.get_mut(&resource.name()) {
            alloc.usage_pct = usage_pct.clamp(0.0, 100.0);
        }
    }

    /// Get all allocations for a domain
    pub fn domain_allocations(&self, owner: ZDomainId) -> Vec<&ResourceAllocation> {
        self.allocations.values().filter(|a| a.owner == owner).collect()
    }

    /// Whether a resource is available
    pub fn is_available(&self, resource: &PhysicalResource) -> bool {
        let name = resource.name();
        self.available.contains_key(&name)
            && !self.allocations.get(&name).map(|a| a.exclusive).unwrap_or(false)
    }

    /// Total registered resources
    pub fn resource_count(&self) -> usize { self.available.len() }

    /// Total allocated resources
    pub fn allocated_count(&self) -> usize { self.allocations.len() }

    /// Hardware utilization ratio
    pub fn utilization(&self) -> f64 {
        if self.available.is_empty() { return 0.0; }
        self.allocations.len() as f64 / self.available.len() as f64
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use uuid::Uuid;

    #[test]
    fn hardware_allocate_release() {
        let mut arb = HardwareArbitrator::new();
        arb.register_resource(PhysicalResource::CpuCore(0));
        let owner = Uuid::new_v4();
        arb.allocate(&PhysicalResource::CpuCore(0), owner, Domain::Windows, true).unwrap();
        assert_eq!(arb.allocated_count(), 1);
        assert!(arb.release(&PhysicalResource::CpuCore(0), owner));
        assert_eq!(arb.allocated_count(), 0);
    }

    #[test]
    fn hardware_exclusive_conflict() {
        let mut arb = HardwareArbitrator::new();
        arb.register_resource(PhysicalResource::NpuEngine(0));
        let owner1 = Uuid::new_v4();
        let owner2 = Uuid::new_v4();
        arb.allocate(&PhysicalResource::NpuEngine(0), owner1, Domain::AI, true).unwrap();
        assert!(arb.allocate(&PhysicalResource::NpuEngine(0), owner2, Domain::Windows, false).is_err());
    }

    #[test]
    fn hardware_surface_zenith_set() {
        let mut arb = HardwareArbitrator::new();
        arb.register_surface_zenith_hardware();
        assert!(arb.resource_count() >= 20);
        assert!(arb.is_available(&PhysicalResource::CpuCore(0)));
        assert!(arb.is_available(&PhysicalResource::NpuEngine(0)));
        assert!(arb.is_available(&PhysicalResource::QpuRegister(0)));
    }

    #[test]
    fn hardware_release_all_for_domain() {
        let mut arb = HardwareArbitrator::new();
        for i in 0..4 {
            arb.register_resource(PhysicalResource::CpuCore(i));
        }
        let owner = Uuid::new_v4();
        for i in 0..4 {
            arb.allocate(&PhysicalResource::CpuCore(i), owner, Domain::Windows, true).unwrap();
        }
        assert_eq!(arb.allocated_count(), 4);
        let released = arb.release_all_for_domain(owner);
        assert_eq!(released, 4);
        assert_eq!(arb.allocated_count(), 0);
    }
}