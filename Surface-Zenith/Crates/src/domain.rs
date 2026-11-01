//! # Zenith Domain Model
//!
//! Domains are isolated execution environments managed by the Zenith Hypervisor Layer.
//! Neither Android nor Windows is the "primary" OS — both are domain containers.
//!
//! ```text
//!          Zenith Hypervisor Layer (ZHL)
//!                     │
//!          ┌──────────┼──────────┐
//!          │          │          │
//!    Android VM  Windows VM   AI VM
//! ```

use serde::{Deserialize, Serialize};
use uuid::Uuid;
use crate::types::{ZDomainId, Priority, MemoryBytes, CpuQuotaNs};

// ---------------------------------------------------------------------------
// Domain enum
// ---------------------------------------------------------------------------

/// Execution domain within the Zenith Hypervisor Layer.
///
/// Each domain is an isolated container with its own runtime, memory space,
/// and capability set. The Zenith Orchestration Bus routes workloads to the
/// most appropriate domain based on intent classification.
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum Domain {
    /// Android subsystem — mobile apps, telephony, sensors, camera
    Android,
    /// Windows subsystem — Win32, .NET, desktop productivity, enterprise apps
    Windows,
    /// AI/ML subsystem — LLM inference, NPU workloads, Copilot core
    AI,
    /// Quantum subsystem — Q# programs, QKD security, QPU scheduling
    Quantum,
    /// Real-time subsystem — DSP, audio, sensor fusion, low-latency I/O
    RealTime,
    /// Cloud relay — offload to Azure/edge when local resources are insufficient
    Cloud,
    /// Custom user-defined domain (plugin architecture)
    Custom(String),
}

impl Domain {
    /// Human-readable name of the domain
    pub fn name(&self) -> &str {
        match self {
            Domain::Android   => "android",
            Domain::Windows   => "windows",
            Domain::AI        => "ai",
            Domain::Quantum   => "quantum",
            Domain::RealTime  => "realtime",
            Domain::Cloud     => "cloud",
            Domain::Custom(n) => n.as_str(),
        }
    }

    /// Whether this domain supports live migration of tasks
    pub fn supports_migration(&self) -> bool {
        matches!(self, Domain::Android | Domain::Windows | Domain::AI)
    }

    /// Whether this domain can host quantum workloads
    pub fn is_quantum_capable(&self) -> bool {
        matches!(self, Domain::Quantum | Domain::AI)
    }

    /// Default priority weight for scheduling decisions
    pub fn default_priority_weight(&self) -> u8 {
        match self {
            Domain::RealTime => 255,
            Domain::AI       => 200,
            Domain::Windows  => 150,
            Domain::Android  => 140,
            Domain::Quantum  => 180,
            Domain::Cloud    => 80,
            Domain::Custom(_)=> 100,
        }
    }
}

impl std::fmt::Display for Domain {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.name())
    }
}

// ---------------------------------------------------------------------------
// Domain health
// ---------------------------------------------------------------------------

/// Health state of a domain container
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum DomainHealth {
    /// Domain is fully operational
    Healthy,
    /// Domain is operational but under resource pressure
    Degraded { reason: String },
    /// Domain has crashed and is being restarted
    Failed { reason: String, crash_count: u32 },
    /// Domain is starting up
    Initializing,
    /// Domain is being shut down gracefully
    ShuttingDown,
    /// Domain is suspended (power saving)
    Suspended,
}

impl DomainHealth {
    /// Returns true if the domain can accept new workloads
    pub fn can_accept_workloads(&self) -> bool {
        matches!(self, DomainHealth::Healthy | DomainHealth::Degraded { .. })
    }

    /// Returns true if the domain requires recovery action
    pub fn requires_recovery(&self) -> bool {
        matches!(self, DomainHealth::Failed { .. })
    }
}

// ---------------------------------------------------------------------------
// Domain descriptor
// ---------------------------------------------------------------------------

/// Full descriptor of a domain instance registered with the Zenith Hypervisor
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DomainDescriptor {
    /// Unique instance ID (multiple Android instances could exist)
    pub id: ZDomainId,
    /// Domain type
    pub domain: Domain,
    /// Human-readable label
    pub label: String,
    /// Memory limit for this domain container
    pub memory_limit: MemoryBytes,
    /// CPU quota per scheduling period
    pub cpu_quota: CpuQuotaNs,
    /// Scheduling priority
    pub priority: Priority,
    /// Current health state
    pub health: DomainHealth,
    /// Whether this domain is the primary instance of its type
    pub is_primary: bool,
    /// API version supported by this domain runtime
    pub api_version: String,
}

impl DomainDescriptor {
    /// Create a new domain descriptor with default resource limits
    pub fn new(domain: Domain, label: impl Into<String>) -> Self {
        Self {
            id: Uuid::new_v4(),
            domain,
            label: label.into(),
            memory_limit: 4 * 1024 * 1024 * 1024, // 4 GB default
            cpu_quota: 1_000_000_000,               // 1 second per period
            priority: 128,
            health: DomainHealth::Initializing,
            is_primary: true,
            api_version: crate::ZENITH_ABI_VERSION.to_string(),
        }
    }

    /// Mark domain as healthy
    pub fn set_healthy(&mut self) {
        self.health = DomainHealth::Healthy;
    }

    /// Mark domain as failed
    pub fn set_failed(&mut self, reason: impl Into<String>, crash_count: u32) {
        self.health = DomainHealth::Failed {
            reason: reason.into(),
            crash_count,
        };
    }
}

// ---------------------------------------------------------------------------
// Domain capability matrix
// ---------------------------------------------------------------------------

/// Describes what a domain can read/write/execute for a given resource class
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum AccessLevel {
    /// No access
    None,
    /// Read-only access
    Read,
    /// Write-only access
    Write,
    /// Full read/write access
    ReadWrite,
    /// AI-assisted access (mediated by the AI core)
    Assisted,
}

/// Resource class for capability matrix
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum ResourceClass {
    Files,
    Camera,
    Clipboard,
    Contacts,
    Telephony,
    Gpu,
    Npu,
    Email,
    Calendar,
    Documents,
    Sessions,
    Sensors,
    Network,
    Bluetooth,
    Location,
    Microphone,
    Display,
    Storage,
}

/// Capability matrix entry for a domain/resource pair
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CapabilityEntry {
    pub domain: Domain,
    pub resource: ResourceClass,
    pub access: AccessLevel,
}

/// Full capability matrix for all domains
pub fn build_capability_matrix() -> Vec<CapabilityEntry> {
    use Domain::*;
    use ResourceClass::*;
    use AccessLevel::*;

    vec![
        // Files
        CapabilityEntry { domain: Android, resource: Files,     access: ReadWrite },
        CapabilityEntry { domain: Windows, resource: Files,     access: ReadWrite },
        CapabilityEntry { domain: AI,      resource: Files,     access: ReadWrite },
        // Camera
        CapabilityEntry { domain: Android, resource: Camera,    access: ReadWrite },
        CapabilityEntry { domain: Windows, resource: Camera,    access: Read      },
        CapabilityEntry { domain: AI,      resource: Camera,    access: Read      },
        // Clipboard
        CapabilityEntry { domain: Android, resource: Clipboard, access: ReadWrite },
        CapabilityEntry { domain: Windows, resource: Clipboard, access: ReadWrite },
        CapabilityEntry { domain: AI,      resource: Clipboard, access: ReadWrite },
        // Telephony
        CapabilityEntry { domain: Android, resource: Telephony, access: ReadWrite },
        CapabilityEntry { domain: Windows, resource: Telephony, access: Read      },
        CapabilityEntry { domain: AI,      resource: Telephony, access: Assisted  },
        // GPU
        CapabilityEntry { domain: Android, resource: Gpu,       access: ReadWrite },
        CapabilityEntry { domain: Windows, resource: Gpu,       access: ReadWrite },
        CapabilityEntry { domain: AI,      resource: Gpu,       access: ReadWrite },
        // NPU
        CapabilityEntry { domain: Android, resource: Npu,       access: ReadWrite },
        CapabilityEntry { domain: Windows, resource: Npu,       access: ReadWrite },
        CapabilityEntry { domain: AI,      resource: Npu,       access: ReadWrite },
        // Sensors
        CapabilityEntry { domain: Android, resource: Sensors,   access: ReadWrite },
        CapabilityEntry { domain: Windows, resource: Sensors,   access: Read      },
        CapabilityEntry { domain: AI,      resource: Sensors,   access: Assisted  },
        // Location
        CapabilityEntry { domain: Android, resource: Location,  access: ReadWrite },
        CapabilityEntry { domain: Windows, resource: Location,  access: Read      },
        CapabilityEntry { domain: AI,      resource: Location,  access: Assisted  },
    ]
}