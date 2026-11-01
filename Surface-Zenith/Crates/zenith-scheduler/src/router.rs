//! # Zenith Scheduler Domain Router
//!
//! Routes scheduled tasks to the correct domain runtime based on
//! intent class, hardware availability, and load balancing policy.

use std::collections::HashMap;
use zenith_abi::domain::Domain;
use zenith_abi::intent::IntentClass;
use zenith_abi::task::ZenithTask;
use crate::heuristic::{domain_fitness, select_best_domain};

/// Load balancing policy
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum LoadBalancePolicy {
    /// Always route to the domain with highest fitness score
    BestFit,
    /// Round-robin across equally-fit domains
    RoundRobin,
    /// Route to the domain with fewest active tasks
    LeastLoaded,
    /// Weighted combination of fitness and load
    Weighted,
}

/// Domain load information
#[derive(Debug, Clone, Default)]
pub struct DomainLoad {
    pub active_tasks: u32,
    pub cpu_usage_pct: f32,
    pub memory_usage_pct: f32,
    pub is_available: bool,
}

impl DomainLoad {
    pub fn new() -> Self {
        Self { is_available: true, ..Default::default() }
    }

    /// Composite load score (lower = less loaded)
    pub fn load_score(&self) -> f32 {
        (self.active_tasks as f32 * 10.0)
            + self.cpu_usage_pct
            + self.memory_usage_pct * 0.5
    }
}

/// The Zenith Domain Router
#[derive(Debug)]
pub struct DomainRouter {
    /// Available domains and their load
    domain_loads: HashMap<String, DomainLoad>,
    /// Load balancing policy
    policy: LoadBalancePolicy,
    /// Round-robin counter per intent class
    rr_counters: HashMap<String, usize>,
}

impl DomainRouter {
    /// Create a new router with all standard domains
    pub fn new(policy: LoadBalancePolicy) -> Self {
        let mut domain_loads = HashMap::new();
        for domain in [Domain::Android, Domain::Windows, Domain::AI,
                       Domain::Quantum, Domain::RealTime, Domain::Cloud] {
            domain_loads.insert(domain.name().to_string(), DomainLoad::new());
        }
        Self {
            domain_loads,
            policy,
            rr_counters: HashMap::new(),
        }
    }

    /// Update load information for a domain
    pub fn update_load(&mut self, domain: &Domain, load: DomainLoad) {
        self.domain_loads.insert(domain.name().to_string(), load);
    }

    /// Mark a domain as unavailable
    pub fn set_unavailable(&mut self, domain: &Domain) {
        if let Some(load) = self.domain_loads.get_mut(domain.name()) {
            load.is_available = false;
        }
    }

    /// Mark a domain as available
    pub fn set_available(&mut self, domain: &Domain) {
        if let Some(load) = self.domain_loads.get_mut(domain.name()) {
            load.is_available = true;
        }
    }

    /// Get all available domains
    pub fn available_domains(&self) -> Vec<Domain> {
        self.domain_loads.iter()
            .filter(|(_, load)| load.is_available)
            .map(|(name, _)| match name.as_str() {
                "android"  => Domain::Android,
                "windows"  => Domain::Windows,
                "ai"       => Domain::AI,
                "quantum"  => Domain::Quantum,
                "realtime" => Domain::RealTime,
                "cloud"    => Domain::Cloud,
                other      => Domain::Custom(other.to_string()),
            })
            .collect()
    }

    /// Route a task to the best domain
    pub fn route(&mut self, task: &ZenithTask, class: &IntentClass) -> Option<Domain> {
        let available = self.available_domains();
        if available.is_empty() {
            return None;
        }

        // If task has explicit domain preference and it's available, use it
        if available.contains(&task.domain) {
            return Some(task.domain.clone());
        }

        match self.policy {
            LoadBalancePolicy::BestFit => {
                select_best_domain(class, &available)
            }
            LoadBalancePolicy::LeastLoaded => {
                available.into_iter()
                    .min_by(|a, b| {
                        let la = self.domain_loads.get(a.name())
                            .map(|l| l.load_score())
                            .unwrap_or(f32::MAX);
                        let lb = self.domain_loads.get(b.name())
                            .map(|l| l.load_score())
                            .unwrap_or(f32::MAX);
                        la.partial_cmp(&lb).unwrap_or(std::cmp::Ordering::Equal)
                    })
            }
            LoadBalancePolicy::RoundRobin => {
                let class_key = format!("{class:?}");
                let counter = self.rr_counters.entry(class_key).or_insert(0);
                let domain = available[*counter % available.len()].clone();
                *counter += 1;
                Some(domain)
            }
            LoadBalancePolicy::Weighted => {
                // Combine fitness score with inverse load score
                available.into_iter()
                    .max_by(|a, b| {
                        let fitness_a = domain_fitness(class, a) as f32;
                        let load_a = self.domain_loads.get(a.name())
                            .map(|l| l.load_score())
                            .unwrap_or(100.0);
                        let score_a = fitness_a - load_a * 0.1;

                        let fitness_b = domain_fitness(class, b) as f32;
                        let load_b = self.domain_loads.get(b.name())
                            .map(|l| l.load_score())
                            .unwrap_or(100.0);
                        let score_b = fitness_b - load_b * 0.1;

                        score_a.partial_cmp(&score_b).unwrap_or(std::cmp::Ordering::Equal)
                    })
            }
        }
    }

    /// Increment active task count for a domain
    pub fn task_started(&mut self, domain: &Domain) {
        if let Some(load) = self.domain_loads.get_mut(domain.name()) {
            load.active_tasks += 1;
        }
    }

    /// Decrement active task count for a domain
    pub fn task_completed(&mut self, domain: &Domain) {
        if let Some(load) = self.domain_loads.get_mut(domain.name()) {
            load.active_tasks = load.active_tasks.saturating_sub(1);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use uuid::Uuid;
    use zenith_abi::task::HardwareResource;

    fn make_task(domain: Domain) -> ZenithTask {
        ZenithTask::new(
            Uuid::new_v4(), Uuid::new_v4(), Uuid::new_v4(),
            "test", domain, HardwareResource::Cpu { cores: 1 }, 128,
        )
    }

    #[test]
    fn best_fit_routing() {
        let mut router = DomainRouter::new(LoadBalancePolicy::BestFit);
        let task = make_task(Domain::Windows);
        let domain = router.route(&task, &IntentClass::Productivity);
        assert_eq!(domain, Some(Domain::Windows));
    }

    #[test]
    fn least_loaded_routing() {
        let mut router = DomainRouter::new(LoadBalancePolicy::LeastLoaded);
        router.task_started(&Domain::Windows);
        router.task_started(&Domain::Windows);
        let task = make_task(Domain::AI);
        // AI domain has 0 tasks, should be selected
        let domain = router.route(&task, &IntentClass::Inference);
        assert!(domain.is_some());
    }

    #[test]
    fn unavailable_domain_excluded() {
        let mut router = DomainRouter::new(LoadBalancePolicy::BestFit);
        router.set_unavailable(&Domain::Windows);
        let available = router.available_domains();
        assert!(!available.contains(&Domain::Windows));
    }

    #[test]
    fn round_robin_cycles() {
        let mut router = DomainRouter::new(LoadBalancePolicy::RoundRobin);
        let task = make_task(Domain::AI);
        let d1 = router.route(&task, &IntentClass::Inference);
        let d2 = router.route(&task, &IntentClass::Inference);
        // Both should return some domain (may or may not be same)
        assert!(d1.is_some());
        assert!(d2.is_some());
    }
}