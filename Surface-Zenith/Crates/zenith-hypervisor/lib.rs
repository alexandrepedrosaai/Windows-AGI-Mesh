//! # Zenith Hypervisor Layer (ZHL)
//!
//! The ZHL sits below all domain runtimes and above the microkernel.
//! It provides:
//!
//! - Domain container lifecycle management (start/stop/suspend/resume)
//! - Memory isolation between domains (page-level enforcement)
//! - Live task migration with dirty-page tracking
//! - Domain health monitoring and fault recovery
//! - Resource quota enforcement (CPU, memory, I/O)
//! - Inter-domain capability validation
//! - Hardware resource arbitration
//!
//! ## Architecture
//!
//! ```text
//! ┌─────────────────────────────────────────────────────┐
//! │              Zenith Orchestration Bus               │
//! ├──────────────┬──────────────┬──────────────────────┤
//! │ Android VM   │ Windows VM   │ AI VM  │ Quantum VM  │
//! ├──────────────┴──────────────┴────────┴─────────────┤
//! │              Zenith Hypervisor Layer (ZHL)          │
//! │  Container Manager · Memory Fabric · Fault Recovery │
//! ├─────────────────────────────────────────────────────┤
//! │              Zenith Microkernel                     │
//! └─────────────────────────────────────────────────────┘
//! ```

#![deny(missing_docs)]
#![warn(clippy::all)]

pub mod container;
pub mod error;
pub mod fabric;
pub mod fault;
pub mod hardware;
pub mod hypervisor;
pub mod isolation;
pub mod lifecycle;
pub mod memory_map;
pub mod metrics;
pub mod migration;
pub mod quota;
pub mod recovery;
pub mod scheduler_bridge;
pub mod snapshot;
pub mod supervisor;
pub mod vcpu;

pub use container::*;
pub use error::*;
pub use fabric::*;
pub use fault::*;
pub use hardware::*;
pub use hypervisor::*;
pub use isolation::*;
pub use lifecycle::*;
pub use memory_map::*;
pub use metrics::*;
pub use migration::*;
pub use quota::*;
pub use recovery::*;
pub use scheduler_bridge::*;
pub use snapshot::*;
pub use supervisor::*;
pub use vcpu::*;

/// ZHL version
pub const ZHL_VERSION: &str = "0.1.0";

/// Maximum number of domain containers
pub const MAX_DOMAIN_CONTAINERS: usize = 16;

/// Maximum number of vCPUs per domain
pub const MAX_VCPUS_PER_DOMAIN: usize = 16;

/// Memory page size (4 KB)
pub const PAGE_SIZE: usize = 4096;

/// Maximum memory per domain (16 GB)
pub const MAX_DOMAIN_MEMORY: u64 = 16 * 1024 * 1024 * 1024;

/// Heartbeat interval for domain health checks (milliseconds)
pub const HEALTH_CHECK_INTERVAL_MS: u64 = 500;

/// Maximum consecutive health check failures before domain restart
pub const MAX_HEALTH_FAILURES: u32 = 3;

/// Live migration dirty page threshold (trigger pre-copy when dirty pages exceed this %)
pub const LIVE_MIGRATION_DIRTY_THRESHOLD: f64 = 0.05;