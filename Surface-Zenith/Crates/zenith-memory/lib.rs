//! # Zenith Shared Memory Fabric
//!
//! The Shared Memory Fabric is the central memory management subsystem
//! of the Surface Zenith OS. It provides:
//!
//! - Universal Memory Objects (UMOs) — domain-agnostic data containers
//! - Copy-on-Write (CoW) page sharing between domains
//! - Dirty page tracking for incremental migration
//! - Memory pressure management and balloon driver
//! - NUMA-aware page placement
//! - Huge page support (2MB, 1GB)
//! - Memory-mapped I/O (MMIO) management
//! - Swap/eviction for cold pages
//!
//! ## Memory Hierarchy
//!
//! ```text
//! Application
//!      ↓
//! Universal Memory Object (UMO)
//!      ↓
//! Page Table (4-level ARM64)
//!      ↓
//! Physical Page Frame
//!      ↓
//! DRAM / Storage (swap)
//! ```

#![deny(missing_docs)]
#![warn(clippy::all)]

pub mod allocator;
pub mod balloon;
pub mod broker;
pub mod cache;
pub mod cow;
pub mod dirty;
pub mod error;
pub mod eviction;
pub mod huge_pages;
pub mod metrics;
pub mod mmio;
pub mod numa;
pub mod page_frame;
pub mod page_table;
pub mod pressure;
pub mod swap;
pub mod umo_manager;
pub mod zero_page;

pub use allocator::*;
pub use balloon::*;
pub use broker::*;
pub use cache::*;
pub use cow::*;
pub use dirty::*;
pub use error::*;
pub use eviction::*;
pub use huge_pages::*;
pub use metrics::*;
pub use mmio::*;
pub use numa::*;
pub use page_frame::*;
pub use page_table::*;
pub use pressure::*;
pub use swap::*;
pub use umo_manager::*;
pub use zero_page::*;

/// Page size (4 KB)
pub const PAGE_SIZE: usize = 4096;

/// Huge page size (2 MB)
pub const HUGE_PAGE_SIZE: usize = 2 * 1024 * 1024;

/// Gigantic page size (1 GB)
pub const GIGA_PAGE_SIZE: usize = 1024 * 1024 * 1024;

/// Maximum physical memory supported (128 GB)
pub const MAX_PHYSICAL_MEMORY: u64 = 128 * 1024 * 1024 * 1024;

/// Zero page physical address (shared read-only zero page)
pub const ZERO_PAGE_PA: u64 = 0x0000_0000_0000_1000;

/// Memory pressure thresholds
pub const PRESSURE_LOW:      f64 = 0.70;
pub const PRESSURE_MEDIUM:   f64 = 0.85;
pub const PRESSURE_HIGH:     f64 = 0.95;
pub const PRESSURE_CRITICAL: f64 = 0.99;