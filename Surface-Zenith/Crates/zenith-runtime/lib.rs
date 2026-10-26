//! # Zenith Domain Runtimes
//!
//! This crate provides the runtime adapters for each Zenith execution domain.
//! Each domain runtime implements the `IZDomainRuntime` trait from zenith-abi,
//! providing a uniform interface for the hypervisor to manage all domains.
//!
//! ## Domain Runtimes
//!
//! - **AndroidRuntime**: Wraps the Android Runtime (ART) and Android framework
//! - **WindowsRuntime**: Wraps Win32, .NET, and Windows subsystems
//! - **AiRuntime**: Manages NPU/GPU inference workloads
//! - **QuantumRuntime**: Manages QPU circuits and Q# execution
//! - **RealTimeRuntime**: Manages DSP, audio, and sensor fusion
//! - **CloudRuntime**: Manages Azure offload and edge computing
//!
//! ## Architecture
//!
//! ```text
//! Zenith Hypervisor Layer
//!         ↓
//! IZDomainRuntime trait
//!         ↓
//! ┌──────────┬──────────┬──────────┬──────────┬──────────┬──────────┐
//! │ Android  │ Windows  │    AI    │ Quantum  │ RealTime │  Cloud   │
//! │ Runtime  │ Runtime  │ Runtime  │ Runtime  │ Runtime  │ Runtime  │
//! └──────────┴──────────┴──────────┴──────────┴──────────┴──────────┘
//!         ↓
//! Physical Hardware (CPU/GPU/NPU/QPU/DSP/Modem)
//! ```

#![deny(missing_docs)]
#![warn(clippy::all)]

pub mod android;
pub mod windows;
pub mod ai;
pub mod quantum;
pub mod realtime;
pub mod cloud;
pub mod error;
pub mod ipc_bridge;
pub mod metrics;
pub mod registry;
pub mod task_executor;
pub mod domain_api;
pub mod capability_validator;
pub mod event_loop;
pub mod resource_monitor;

pub use android::*;
pub use windows::*;
pub use ai::*;
pub use quantum::*;
pub use realtime::*;
pub use cloud::*;
pub use error::*;
pub use ipc_bridge::*;
pub use metrics::*;
pub use registry::*;
pub use task_executor::*;
pub use domain_api::*;
pub use capability_validator::*;
pub use event_loop::*;
pub use resource_monitor::*;

/// Runtime version
pub const RUNTIME_VERSION: &str = "0.1.0";

/// Maximum tasks per domain runtime
pub const MAX_TASKS_PER_RUNTIME: usize = 1024;

/// Health check interval in milliseconds
pub const HEALTH_CHECK_INTERVAL_MS: u64 = 500;

/// Task execution timeout in milliseconds
pub const TASK_TIMEOUT_MS: u64 = 30_000;

/// Maximum IPC message queue depth per runtime
pub const IPC_QUEUE_DEPTH: usize = 4096;