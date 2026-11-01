//! # Zenith Scheduler Errors

use thiserror::Error;

/// Errors from the Zenith Intent Scheduler
#[derive(Debug, Error, Clone)]
pub enum SchedulerError {
    #[error("queue full: depth={depth}, max={max}")]
    QueueFull { depth: usize, max: usize },

    #[error("intent not found: {id}")]
    IntentNotFound { id: String },

    #[error("intent already completed: {id}")]
    IntentAlreadyCompleted { id: String },

    #[error("planning failed for intent {intent_id}: {reason}")]
    PlanningFailed { intent_id: String, reason: String },

    #[error("migration failed: {reason}")]
    MigrationFailed { reason: String },

    #[error("domain unavailable: {domain}")]
    DomainUnavailable { domain: String },

    #[error("task not found: {id}")]
    TaskNotFound { id: String },

    #[error("cycle detected in task graph")]
    CycleDetected,

    #[error("scheduler internal error: {message}")]
    Internal { message: String },
}

impl SchedulerError {
    pub fn is_recoverable(&self) -> bool {
        matches!(
            self,
            SchedulerError::QueueFull { .. }
                | SchedulerError::DomainUnavailable { .. }
        )
    }
}