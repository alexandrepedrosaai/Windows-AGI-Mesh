//! # Zenith ABI — Universal Application Binary Interface
//!
//! The Zenith ABI is the foundational contract layer of the Surface Zenith OS.
//! Applications do not compile against Win32 or Android Framework.
//! They compile against the Zenith Universal ABI (ZUABI).
//!
//! ## Architecture
//!
//! ```text
//! +----------------------+
//! | Application          |
//! +----------------------+
//! | Zenith Universal ABI |
//! +----------------------+
//! | Android  | Windows   |
//! | Adapter  | Adapter   |
//! +----------------------+
//! | Zenith Microkernel   |
//! +----------------------+
//! ```

#![deny(missing_docs)]
#![deny(unsafe_op_in_unsafe_fn)]
#![warn(clippy::all)]

pub mod capability;
pub mod domain;
pub mod error;
pub mod identity;
pub mod intent;
pub mod memory;
pub mod object;
pub mod session;
pub mod task;
pub mod types;
pub mod version;
pub mod security;
pub mod device;
pub mod inference;
pub mod contract;

pub use capability::*;
pub use domain::*;
pub use error::*;
pub use identity::*;
pub use intent::*;
pub use memory::*;
pub use object::*;
pub use session::*;
pub use task::*;
pub use types::*;
pub use version::*;
pub use security::*;
pub use device::*;
pub use inference::*;
pub use contract::*;

/// Zenith ABI version string
pub const ZENITH_ABI_VERSION: &str = "0.1.0";

/// Maximum number of concurrent sessions per identity
pub const MAX_SESSIONS_PER_IDENTITY: usize = 64;

/// Maximum number of tasks per session
pub const MAX_TASKS_PER_SESSION: usize = 1024;

/// Maximum payload size for IPC messages (16 MB)
pub const MAX_IPC_PAYLOAD_BYTES: usize = 16 * 1024 * 1024;

/// Maximum number of memory pages per Universal Memory Object
pub const MAX_UMO_PAGES: usize = 65536;

/// Page size in bytes (4 KB)
pub const PAGE_SIZE_BYTES: usize = 4096;

/// Zenith capability token size in bytes
pub const CAPABILITY_TOKEN_SIZE: usize = 64;