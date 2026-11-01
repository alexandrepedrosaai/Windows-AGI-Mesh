//! # Domain Lifecycle Manager
//!
//! Manages the full lifecycle of domain containers from creation to destruction,
//! including form factor transitions and power state changes.

use serde::{Deserialize, Serialize};
use zenith_abi::domain::Domain;
use zenith_abi::session::FormFactor;
use zenith_abi::types::ZDomainId;
use crate::container::{ContainerConfig, ContainerState};
use crate::error::ZhlError;

/// Power state of the device
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum PowerState {
    /// Fully active — all domains running
    Active,
    /// Screen off — non-essential domains suspended
    ScreenOff,
    /// Low power — only essential domains running
    LowPower,
    /// Deep sleep — all domains suspended
    DeepSleep,
    /// Hibernate — all domains checkpointed and powered off
    Hibernate,
    /// Shutdown — all domains destroyed
    Shutdown,
}

impl PowerState {
    /// Domains that should remain active in this power state
    pub fn active_domains(&self) -> Vec<Domain> {
        match self {
            PowerState::Active => vec![
                Domain::Android, Domain::Windows, Domain::AI,
                Domain::Quantum, Domain::RealTime, Domain::Cloud,
            ],
            PowerState::ScreenOff => vec![
                Domain::Android, Domain::RealTime,
            ],
            PowerState::LowPower => vec![
                Domain::Android,
            ],
            PowerState::DeepSleep | PowerState::Hibernate | PowerState::Shutdown => vec![],
        }
    }

    /// Whether a domain should be suspended in this power state
    pub fn should_suspend(&self, domain: &Domain) -> bool {
        !self.active_domains().contains(domain)
    }
}

/// Form factor transition event
#[derive(Debug, Clone)]
pub struct FormFactorTransition {
    pub from:        FormFactor,
    pub to:          FormFactor,
    pub hinge_angle: f64,
    pub timestamp:   std::time::Instant,
}

impl FormFactorTransition {
    /// Whether this transition requires domain migration
    pub fn requires_migration(&self) -> bool {
        let from_desktop = matches!(self.from, FormFactor::Desktop | FormFactor::Laptop);
        let to_mobile    = matches!(self.to,   FormFactor::PhoneFolded | FormFactor::TabletUnfolded);
        let from_mobile  = matches!(self.from, FormFactor::PhoneFolded | FormFactor::TabletUnfolded);
        let to_desktop   = matches!(self.to,   FormFactor::Desktop | FormFactor::Laptop);
        (from_desktop && to_mobile) || (from_mobile && to_desktop)
    }

    /// Primary domain for the new form factor
    pub fn new_primary_domain(&self) -> Domain {
        self.to.recommended_domain()
    }
}

/// Lifecycle event log entry
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LifecycleEvent {
    pub id:        uuid::Uuid,
    pub event:     String,
    pub domain:    Option<String>,
    pub detail:    String,
    pub timestamp: zenith_abi::types::ZTimestamp,
}

impl LifecycleEvent {
    pub fn new(event: impl Into<String>, domain: Option<Domain>, detail: impl Into<String>) -> Self {
        Self {
            id: uuid::Uuid::new_v4(),
            event: event.into(),
            domain: domain.map(|d| d.name().to_string()),
            detail: detail.into(),
            timestamp: zenith_abi::types::ZTimestamp(
                std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .unwrap_or_default()
                    .as_micros() as i64,
            ),
        }
    }
}

/// Domain Lifecycle Manager
#[derive(Debug, Default)]
pub struct LifecycleManager {
    current_power_state: Option<PowerState>,
    current_form_factor: Option<FormFactor>,
    event_log:           Vec<LifecycleEvent>,
    transition_count:    u64,
}

impl LifecycleManager {
    pub fn new() -> Self { Self::default() }

    /// Handle a power state transition
    pub fn handle_power_transition(
        &mut self,
        new_state: PowerState,
    ) -> Vec<(Domain, bool)> { // (domain, should_suspend)
        let old_state = self.current_power_state.take();
        let domains = vec![
            Domain::Android, Domain::Windows, Domain::AI,
            Domain::Quantum, Domain::RealTime, Domain::Cloud,
        ];

        let actions: Vec<(Domain, bool)> = domains.iter()
            .map(|d| (d.clone(), new_state.should_suspend(d)))
            .collect();

        self.event_log.push(LifecycleEvent::new(
            "power_transition",
            None,
            format!("{:?} → {:?}", old_state, new_state),
        ));

        self.current_power_state = Some(new_state);
        self.transition_count += 1;
        actions
    }

    /// Handle a form factor transition
    pub fn handle_form_factor_transition(
        &mut self,
        transition: FormFactorTransition,
    ) -> Option<(Domain, Domain)> { // (from_domain, to_domain) if migration needed
        let migration = if transition.requires_migration() {
            let from = self.current_form_factor
                .as_ref()
                .map(|f| f.recommended_domain())
                .unwrap_or_else(|| transition.from.recommended_domain());
            let to = transition.new_primary_domain();
            Some((from, to))
        } else {
            None
        };

        self.event_log.push(LifecycleEvent::new(
            "form_factor_transition",
            None,
            format!("{:?} → {:?} (angle: {:.1}°)",
                transition.from, transition.to, transition.hinge_angle),
        ));

        self.current_form_factor = Some(transition.to);
        self.transition_count += 1;
        migration
    }

    /// Log a domain lifecycle event
    pub fn log_event(&mut self, event: impl Into<String>, domain: Option<Domain>, detail: impl Into<String>) {
        self.event_log.push(LifecycleEvent::new(event, domain, detail));
        if self.event_log.len() > 10_000 {
            self.event_log.drain(0..1000);
        }
    }

    /// Current power state
    pub fn power_state(&self) -> Option<&PowerState> {
        self.current_power_state.as_ref()
    }

    /// Current form factor
    pub fn form_factor(&self) -> Option<&FormFactor> {
        self.current_form_factor.as_ref()
    }

    /// Total transitions
    pub fn transition_count(&self) -> u64 { self.transition_count }

    /// Recent events
    pub fn recent_events(&self, count: usize) -> &[LifecycleEvent] {
        let len = self.event_log.len();
        &self.event_log[len.saturating_sub(count)..]
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn power_state_active_domains() {
        assert_eq!(PowerState::Active.active_domains().len(), 6);
        assert_eq!(PowerState::LowPower.active_domains().len(), 1);
        assert_eq!(PowerState::DeepSleep.active_domains().len(), 0);
    }

    #[test]
    fn power_state_suspend_decision() {
        assert!(!PowerState::Active.should_suspend(&Domain::Windows));
        assert!(PowerState::LowPower.should_suspend(&Domain::Windows));
        assert!(PowerState::DeepSleep.should_suspend(&Domain::Android));
    }

    #[test]
    fn form_factor_transition_requires_migration() {
        let t = FormFactorTransition {
            from:        FormFactor::Desktop,
            to:          FormFactor::PhoneFolded,
            hinge_angle: 0.0,
            timestamp:   std::time::Instant::now(),
        };
        assert!(t.requires_migration());

        let t2 = FormFactorTransition {
            from:        FormFactor::PhoneFolded,
            to:          FormFactor::TabletUnfolded,
            hinge_angle: 90.0,
            timestamp:   std::time::Instant::now(),
        };
        assert!(!t2.requires_migration());
    }

    #[test]
    fn lifecycle_manager_power_transition() {
        let mut mgr = LifecycleManager::new();
        let actions = mgr.handle_power_transition(PowerState::LowPower);
        assert!(!actions.is_empty());
        let windows_action = actions.iter().find(|(d, _)| d == &Domain::Windows);
        assert!(windows_action.map(|(_, suspend)| *suspend).unwrap_or(false));
    }

    #[test]
    fn lifecycle_manager_form_factor_transition() {
        let mut mgr = LifecycleManager::new();
        mgr.current_form_factor = Some(FormFactor::Desktop);
        let t = FormFactorTransition {
            from:        FormFactor::Desktop,
            to:          FormFactor::PhoneFolded,
            hinge_angle: 0.0,
            timestamp:   std::time::Instant::now(),
        };
        let migration = mgr.handle_form_factor_transition(t);
        assert!(migration.is_some());
        let (from, to) = migration.unwrap();
        assert_eq!(from, Domain::Windows);
        assert_eq!(to, Domain::Android);
    }
}