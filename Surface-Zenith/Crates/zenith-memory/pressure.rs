//! # Memory Pressure Manager

use serde::{Deserialize, Serialize};

/// Memory pressure level
#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
pub enum PressureLevel {
    /// Normal operation
    Normal,
    /// Low pressure — start background reclaim
    Low,
    /// Medium pressure — aggressive reclaim
    Medium,
    /// High pressure — suspend non-essential domains
    High,
    /// Critical — emergency reclaim, OOM possible
    Critical,
}

impl PressureLevel {
    pub fn from_utilization(util: f64) -> Self {
        if util < crate::PRESSURE_LOW      { PressureLevel::Normal }
        else if util < crate::PRESSURE_MEDIUM { PressureLevel::Low }
        else if util < crate::PRESSURE_HIGH   { PressureLevel::Medium }
        else if util < crate::PRESSURE_CRITICAL { PressureLevel::High }
        else                                   { PressureLevel::Critical }
    }

    pub fn requires_action(&self) -> bool {
        !matches!(self, PressureLevel::Normal)
    }
}

/// Memory pressure event
#[derive(Debug, Clone)]
pub struct PressureEvent {
    pub level:       PressureLevel,
    pub utilization: f64,
    pub timestamp:   std::time::Instant,
}

/// Memory pressure manager
#[derive(Debug)]
pub struct MemoryPressureManager {
    threshold:       f64,
    current_level:   PressureLevel,
    events:          Vec<PressureEvent>,
    total_events:    u64,
    oom_events:      u64,
}

impl MemoryPressureManager {
    pub fn new(threshold: f64) -> Self {
        Self {
            threshold,
            current_level: PressureLevel::Normal,
            events:        Vec::new(),
            total_events:  0,
            oom_events:    0,
        }
    }

    pub fn record_pressure_event(&mut self, utilization: f64) {
        let level = PressureLevel::from_utilization(utilization);
        if level == PressureLevel::Critical {
            self.oom_events += 1;
        }
        self.current_level = level.clone();
        self.total_events += 1;
        self.events.push(PressureEvent {
            level,
            utilization,
            timestamp: std::time::Instant::now(),
        });
        if self.events.len() > 1000 {
            self.events.drain(0..100);
        }
    }

    pub fn current_level(&self) -> &PressureLevel { &self.current_level }
    pub fn total_events(&self) -> u64 { self.total_events }
    pub fn oom_events(&self) -> u64 { self.oom_events }

    pub fn recent_events(&self, count: usize) -> &[PressureEvent] {
        let len = self.events.len();
        &self.events[len.saturating_sub(count)..]
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn pressure_level_from_utilization() {
        assert_eq!(PressureLevel::from_utilization(0.5), PressureLevel::Normal);
        assert_eq!(PressureLevel::from_utilization(0.75), PressureLevel::Low);
        assert_eq!(PressureLevel::from_utilization(0.88), PressureLevel::Medium);
        assert_eq!(PressureLevel::from_utilization(0.97), PressureLevel::High);
        assert_eq!(PressureLevel::from_utilization(0.999), PressureLevel::Critical);
    }

    #[test]
    fn pressure_manager_events() {
        let mut mgr = MemoryPressureManager::new(0.85);
        mgr.record_pressure_event(0.90);
        mgr.record_pressure_event(0.999);
        assert_eq!(mgr.total_events(), 2);
        assert_eq!(mgr.oom_events(), 1);
    }
}