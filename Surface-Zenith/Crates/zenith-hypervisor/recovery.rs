//! # Domain Recovery Manager

use crate::container::{DomainContainer, ContainerState};
use crate::error::ZhlError;

/// Recovery strategy
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RecoveryStrategy {
    /// Restart the container in place
    Restart,
    /// Restore from the last checkpoint
    RestoreCheckpoint,
    /// Migrate all tasks to another domain and restart
    MigrateAndRestart,
    /// Permanently disable the domain
    Disable,
}

/// Recovery manager — orchestrates domain recovery after failures
#[derive(Debug, Default)]
pub struct RecoveryManager {
    recovery_count:  u64,
    failure_count:   u64,
}

impl RecoveryManager {
    /// Create a new recovery manager
    pub fn new() -> Self { Self::default() }

    /// Determine the recovery strategy for a crashed container
    pub fn strategy(&self, container: &DomainContainer) -> RecoveryStrategy {
        match container.crash_count {
            0..=1 => RecoveryStrategy::Restart,
            2..=3 => RecoveryStrategy::RestoreCheckpoint,
            4..=5 => RecoveryStrategy::MigrateAndRestart,
            _     => RecoveryStrategy::Disable,
        }
    }

    /// Attempt to recover a crashed container
    pub fn recover(&mut self, container: &mut DomainContainer) -> Result<(), ZhlError> {
        if !container.state.needs_recovery() {
            return Err(ZhlError::InvalidStateTransition {
                from: format!("{:?}", container.state),
                to:   "Recovering".into(),
            });
        }

        let strategy = self.strategy(container);
        tracing::info!(
            "Recovering container {} with strategy {:?} (crash #{}))",
            container.id, strategy, container.crash_count
        );

        match strategy {
            RecoveryStrategy::Restart => {
                container.transition(ContainerState::Restarting);
                container.start()?;
                container.health_failures = 0;
                self.recovery_count += 1;
                tracing::info!("Container {} restarted successfully", container.id);
                Ok(())
            }
            RecoveryStrategy::RestoreCheckpoint => {
                // In production: restore from last checkpoint
                container.transition(ContainerState::Restarting);
                container.start()?;
                container.health_failures = 0;
                self.recovery_count += 1;
                Ok(())
            }
            RecoveryStrategy::MigrateAndRestart => {
                // In production: migrate tasks first, then restart
                container.active_tasks.clear();
                container.transition(ContainerState::Restarting);
                container.start()?;
                container.health_failures = 0;
                self.recovery_count += 1;
                Ok(())
            }
            RecoveryStrategy::Disable => {
                self.failure_count += 1;
                Err(ZhlError::RecoveryFailed {
                    reason: format!(
                        "Container {} exceeded maximum crash count ({})",
                        container.id, container.crash_count
                    ),
                })
            }
        }
    }

    /// Total successful recoveries
    pub fn recovery_count(&self) -> u64 { self.recovery_count }

    /// Total permanent failures
    pub fn failure_count(&self) -> u64 { self.failure_count }

    /// Recovery success rate
    pub fn success_rate(&self) -> f64 {
        let total = self.recovery_count + self.failure_count;
        if total == 0 { return 1.0; }
        self.recovery_count as f64 / total as f64
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::container::ContainerConfig;
    use zenith_abi::domain::Domain;

    fn make_crashed_container(crash_count: u32) -> DomainContainer {
        let mut c = DomainContainer::new(ContainerConfig::default_for_domain(Domain::Windows));
        c.crash_count = crash_count;
        c.state = ContainerState::Crashed {
            reason: "test".into(),
            crash_count,
        };
        c
    }

    #[test]
    fn recovery_strategy_escalation() {
        let manager = RecoveryManager::new();
        assert_eq!(manager.strategy(&make_crashed_container(0)), RecoveryStrategy::Restart);
        assert_eq!(manager.strategy(&make_crashed_container(2)), RecoveryStrategy::RestoreCheckpoint);
        assert_eq!(manager.strategy(&make_crashed_container(4)), RecoveryStrategy::MigrateAndRestart);
        assert_eq!(manager.strategy(&make_crashed_container(6)), RecoveryStrategy::Disable);
    }

    #[test]
    fn recovery_restart_success() {
        let mut manager = RecoveryManager::new();
        let mut container = make_crashed_container(0);
        manager.recover(&mut container).unwrap();
        assert_eq!(container.state, ContainerState::Running);
        assert_eq!(manager.recovery_count(), 1);
    }

    #[test]
    fn recovery_disable_fails() {
        let mut manager = RecoveryManager::new();
        let mut container = make_crashed_container(10);
        assert!(manager.recover(&mut container).is_err());
        assert_eq!(manager.failure_count(), 1);
    }
}