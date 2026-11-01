//! # Zenith Interdomain Bus (ZIB)
//!
//! The ZIB replaces COM, Binder, Named Pipes, D-Bus, and RPC with a single
//! unified, typed, capability-gated message bus.
//!
//! ## Architecture
//!
//! ```text
//! Android Domain ──┐
//!                  ├──► ZenithBus ──► Topic Router ──► Subscriber
//! Windows Domain ──┤                       │
//!                  │               Payload Validator
//! AI Domain ───────┘                       │
//!                                   QoS / TTL Filter
//! ```
//!
//! ## Key Properties
//!
//! - **Typed topics**: All messages use strongly-typed `Topic` enum (no raw strings)
//! - **Payload validation**: Each topic has a schema contract
//! - **QoS**: Messages have TTL and priority
//! - **Capability-gated**: Publishing requires a valid capability token
//! - **Broadcast**: Multiple subscribers receive every message
//! - **Metrics**: Built-in counters for published/delivered/rejected/expired

#![deny(missing_docs)]
#![warn(clippy::all)]

pub mod bus;
pub mod error;
pub mod message;
pub mod metrics;
pub mod payload;
pub mod router;
pub mod subscription;
pub mod topics;
pub mod wire;
pub mod qos;
pub mod filter;
pub mod codec;

pub use bus::*;
pub use error::*;
pub use message::*;
pub use metrics::*;
pub use payload::*;
pub use router::*;
pub use subscription::*;
pub use topics::*;
pub use qos::*;
pub use filter::*;
pub use codec::*;

/// Maximum number of subscribers per topic
pub const MAX_SUBSCRIBERS_PER_TOPIC: usize = 256;

/// Default message TTL in milliseconds
pub const DEFAULT_TTL_MS: u64 = 5_000;

/// Maximum message payload size (16 MB)
pub const MAX_PAYLOAD_BYTES: usize = 16 * 1024 * 1024;

/// ZIB protocol version
pub const ZIB_PROTOCOL_VERSION: u8 = 3;