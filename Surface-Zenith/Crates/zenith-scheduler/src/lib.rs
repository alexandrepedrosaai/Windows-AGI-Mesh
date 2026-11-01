//! # Zenith Intent Scheduler (ZIS)
//!
//! The ZIS is the heart of the Surface Zenith OS. Unlike traditional schedulers
//! that manage threads and processes, the ZIS manages **goals**.
//!
//! ## Scheduler Hierarchy
//!
//! ```text
//! Generation 1: FIFO / Round Robin  → "Which process executes?"
//! Generation 2: Linux CFS / NT      → "Which thread gets CPU?"
//! Generation 3: Zenith ZIS          → "Which intention should be realized?"
//! ```
//!
//! ## ZIS Pipeline
//!
//! ```text
//! User Input
//!      ↓
//! Intent Parser (NLP classification)
//!      ↓
//! Task Graph Builder (DAG construction)
//!      ↓
//! Execution Planner (resource estimation)
//!      ↓
//! Domain Router (Android / Windows / AI / Quantum)
//!      ↓
//! Hardware Scheduler (CPU / GPU / NPU / QPU)
//!      ↓
//! Execution
//!      ↓
//! Result Aggregator
//! ```

#![deny(missing_docs)]
#![warn(clippy::all)]

pub mod classifier;
pub mod dag;
pub mod engine;
pub mod error;
pub mod heuristic;
pub mod migration;
pub mod planner;
pub mod predictor;
pub mod priority_queue;
pub mod router;
pub mod scheduler;
pub mod stats;

pub use classifier::*;
pub use dag::*;
pub use engine::*;
pub use error::*;
pub use heuristic::*;
pub use migration::*;
pub use planner::*;
pub use predictor::*;
pub use priority_queue::*;
pub use router::*;
pub use scheduler::*;
pub use stats::*;

/// Maximum number of intents in the scheduler queue
pub const MAX_QUEUE_DEPTH: usize = 65536;

/// Scheduling period in milliseconds
pub const SCHEDULING_PERIOD_MS: u64 = 10;

/// Maximum task graph depth (prevents infinite loops)
pub const MAX_GRAPH_DEPTH: usize = 64;

/// Minimum score for an intent to be scheduled
pub const MIN_SCHEDULABLE_SCORE: i64 = -1000;