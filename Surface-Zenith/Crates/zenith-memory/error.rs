//! # Memory Subsystem Errors

use thiserror::Error;

/// All errors from the Zenith memory subsystem
#[derive(Debug, Error, Clone)]
pub enum MemoryError {
    #[error("out of physical memory")]
    OutOfMemory,

    #[error("invalid page frame number: {pfn}")]
    InvalidPfn { pfn: u64 },

    #[error("invalid buddy order: {order}")]
    InvalidOrder { order: u8 },

    #[error("CoW mapping not found for PFN: {pfn}")]
    CowMappingNotFound { pfn: u64 },

    #[error("UMO not found: {id}")]
    UmoNotFound { id: String },

    #[error("page already allocated: {pfn}")]
    PageAlreadyAllocated { pfn: u64 },

    #[error("page not allocated: {pfn}")]
    PageNotAllocated { pfn: u64 },

    #[error("write lock conflict: held by {holder}")]
    WriteLockConflict { holder: String },

    #[error("memory pressure too high: {utilization:.1}%")]
    MemoryPressure { utilization: f64 },

    #[error("swap space exhausted")]
    SwapExhausted,

    #[error("NUMA node not found: {node_id}")]
    NumaNodeNotFound { node_id: u8 },

    #[error("huge page alignment error: address {addr:#x} not aligned to {size} bytes")]
    HugePageAlignment { addr: u64, size: usize },

    #[error("MMIO region conflict: {addr:#x}–{end:#x}")]
    MmioConflict { addr: u64, end: u64 },

    #[error("balloon operation failed: {reason}")]
    BalloonFailed { reason: String },

    #[error("eviction failed: no reclaimable pages")]
    EvictionFailed,

    #[error("serialization failed: {reason}")]
    SerializationFailed { reason: String },

    #[error("internal memory error: {message}")]
    Internal { message: String },
}

impl MemoryError {
    /// Whether this error is recoverable
    pub fn is_recoverable(&self) -> bool {
        matches!(
            self,
            MemoryError::MemoryPressure { .. }
                | MemoryError::WriteLockConflict { .. }
        )
    }
}