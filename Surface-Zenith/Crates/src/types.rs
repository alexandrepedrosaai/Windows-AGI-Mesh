//! # Zenith Primitive Types
//!
//! Fundamental type aliases used throughout the entire Surface Zenith OS.
//! All IDs are 128-bit UUIDs to guarantee global uniqueness across
//! distributed sessions, devices, and cloud nodes.

use serde::{Deserialize, Serialize};
use uuid::Uuid;

// ---------------------------------------------------------------------------
// Core ID types
// ---------------------------------------------------------------------------

/// Unique identifier for a Zenith session (user-level computation context)
pub type ZSessionId = Uuid;

/// Unique identifier for a Zenith task (unit of scheduled work)
pub type ZTaskId = Uuid;

/// Unique identifier for a Universal Memory Object
pub type ZObjectId = Uuid;

/// Unique identifier for a domain instance (Android, Windows, AI, …)
pub type ZDomainId = Uuid;

/// Unique identifier for a Zenith identity (user / service account)
pub type ZIdentityId = Uuid;

/// Unique identifier for a device node
pub type ZDeviceId = Uuid;

/// Unique identifier for an IPC message
pub type ZMessageId = Uuid;

/// Unique identifier for a capability token
pub type ZCapabilityId = Uuid;

/// Unique identifier for a memory page
pub type ZPageId = u64;

/// Unique identifier for an inference request
pub type ZInferenceId = Uuid;

// ---------------------------------------------------------------------------
// Scalar types
// ---------------------------------------------------------------------------

/// Priority level (0 = lowest, 255 = highest)
pub type Priority = u8;

/// Energy cost estimate (arbitrary units, lower = cheaper)
pub type EnergyCost = u32;

/// Latency budget in milliseconds
pub type LatencyBudgetMs = u32;

/// Memory size in bytes
pub type MemoryBytes = u64;

/// CPU quota in nanoseconds per scheduling period
pub type CpuQuotaNs = u64;

/// Version number (major.minor.patch encoded as u32)
pub type VersionCode = u32;

// ---------------------------------------------------------------------------
// Timestamp
// ---------------------------------------------------------------------------

/// Unix timestamp in microseconds
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
pub struct ZTimestamp(pub i64);

impl ZTimestamp {
    /// Create a timestamp representing "now" (requires std)
    #[cfg(feature = "std")]
    pub fn now() -> Self {
        use std::time::{SystemTime, UNIX_EPOCH};
        let us = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_micros() as i64;
        Self(us)
    }

    /// Elapsed microseconds since this timestamp
    #[cfg(feature = "std")]
    pub fn elapsed_us(&self) -> i64 {
        Self::now().0 - self.0
    }
}

impl Default for ZTimestamp {
    fn default() -> Self {
        Self(0)
    }
}

// ---------------------------------------------------------------------------
// Result alias
// ---------------------------------------------------------------------------

/// Standard result type for Zenith ABI operations
pub type ZResult<T> = Result<T, crate::error::ZenithError>;