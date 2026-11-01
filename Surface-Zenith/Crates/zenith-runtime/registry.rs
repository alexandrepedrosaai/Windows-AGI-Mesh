//! # Domain Runtime Registry
//!
//! Central registry of all active domain runtimes.

use std::collections::HashMap;
use zenith_abi::domain::{Domain, DomainHealth};
use zenith_abi::contract::IZDomainRuntime;
use crate::android::AndroidRuntime;
use crate::windows::WindowsRuntime;
use crate::ai::AiRuntime;
use crate::quantum::QuantumRuntime;
use crate::realtime::RealTimeRuntime;
use crate::cloud::CloudRuntime;
use crate::error::RuntimeError;

/// A boxed domain runtime
pub type BoxedRuntime = Box<dyn IZDomainRuntime + Send + Sync>;

/// Runtime registry entry
pub struct RuntimeEntry {
    pub domain:  Domain,
    pub runtime: BoxedRuntime,
    pub started: bool,
}

/// The Domain Runtime Registry
pub struct RuntimeRegistry {
    runtimes: HashMap<String, RuntimeEntry>,
}

impl RuntimeRegistry {
    /// Create a new empty registry
    pub fn new() -> Self {
        Self { runtimes: HashMap::new() }
    }

    /// Create a registry with all standard Zenith runtimes
    pub fn build_standard() -> Self {
        let mut registry = Self::new();
        registry.register(Domain::Android,  Box::new(AndroidRuntime::new()));
        registry.register(Domain::Windows,  Box::new(WindowsRuntime::new()));
        registry.register(Domain::AI,       Box::new(AiRuntime::new()));
        registry.register(Domain::Quantum,  Box::new(QuantumRuntime::new()));
        registry.register(Domain::RealTime, Box::new(RealTimeRuntime::new()));
        registry.register(Domain::Cloud,    Box::new(CloudRuntime::new()));
        registry
    }

    /// Register a runtime
    pub fn register(&mut self, domain: Domain, runtime: BoxedRuntime) {
        let key = domain.name().to_string();
        self.runtimes.insert(key, RuntimeEntry { domain, runtime, started: false });
    }

    /// Start all runtimes
    pub fn start_all(&mut self) -> Vec<(Domain, Result<(), zenith_abi::types::ZResult<()>>)> {
        let mut results = Vec::new();
        for entry in self.runtimes.values_mut() {
            let result = entry.runtime.start();
            if result.is_ok() {
                entry.started = true;
            }
            results.push((entry.domain.clone(), Ok(result)));
        }
        results
    }

    /// Stop all runtimes
    pub fn stop_all(&mut self) {
        for entry in self.runtimes.values_mut() {
            let _ = entry.runtime.stop();
            entry.started = false;
        }
    }

    /// Get health of all runtimes
    pub fn health_all(&self) -> HashMap<String, DomainHealth> {
        self.runtimes.iter()
            .map(|(k, e)| (k.clone(), e.runtime.health()))
            .collect()
    }

    /// Count of registered runtimes
    pub fn count(&self) -> usize { self.runtimes.len() }

    /// Count of started runtimes
    pub fn started_count(&self) -> usize {
        self.runtimes.values().filter(|e| e.started).count()
    }

    /// Count of healthy runtimes
    pub fn healthy_count(&self) -> usize {
        self.runtimes.values()
            .filter(|e| matches!(e.runtime.health(), DomainHealth::Healthy))
            .count()
    }
}

impl Default for RuntimeRegistry {
    fn default() -> Self { Self::new() }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn registry_build_standard() {
        let registry = RuntimeRegistry::build_standard();
        assert_eq!(registry.count(), 6);
    }

    #[test]
    fn registry_health_all() {
        let registry = RuntimeRegistry::build_standard();
        let health = registry.health_all();
        assert_eq!(health.len(), 6);
        // All should be Initializing before start
        for (_, h) in &health {
            assert_eq!(*h, DomainHealth::Initializing);
        }
    }

    #[test]
    fn registry_started_count() {
        let mut registry = RuntimeRegistry::build_standard();
        assert_eq!(registry.started_count(), 0);
        registry.start_all();
        assert_eq!(registry.started_count(), 6);
    }
}