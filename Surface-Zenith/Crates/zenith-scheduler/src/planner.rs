//! # Zenith Execution Planner
//!
//! Transforms a classified intent + task DAG into a concrete execution plan
//! with resource allocations, timing estimates, and domain assignments.

use uuid::Uuid;
use std::collections::HashMap;
use zenith_abi::intent::{Intent, IntentClass};
use zenith_abi::domain::Domain;
use zenith_abi::task::{ZenithTask, HardwareResource};
use zenith_abi::types::{ZTaskId, ZSessionId, ZIdentityId};
use crate::dag::{SchedulerDag, DagNode, DagBuilder, DagError};
use crate::heuristic::select_best_domain;

// ---------------------------------------------------------------------------
// Execution plan
// ---------------------------------------------------------------------------

/// A concrete execution plan derived from an intent
#[derive(Debug, Clone)]
pub struct ExecutionPlan {
    /// Intent this plan is for
    pub intent_id: ZTaskId,
    /// Session context
    pub session_id: ZSessionId,
    /// Task DAG
    pub dag: SchedulerDag,
    /// Ordered list of tasks to execute
    pub tasks: Vec<ZenithTask>,
    /// Estimated total duration in milliseconds
    pub estimated_total_ms: u32,
    /// Estimated critical path in milliseconds
    pub critical_path_ms: u32,
    /// Total estimated memory requirement in bytes
    pub total_memory_bytes: u64,
    /// Domains involved in this plan
    pub domains_involved: Vec<Domain>,
    /// Whether this plan can be partially parallelized
    pub has_parallel_stages: bool,
    /// Plan creation timestamp
    pub created_at: std::time::Instant,
}

impl ExecutionPlan {
    /// Whether this plan involves multiple domains
    pub fn is_cross_domain(&self) -> bool {
        self.domains_involved.len() > 1
    }

    /// Whether this plan requires quantum hardware
    pub fn requires_quantum(&self) -> bool {
        self.domains_involved.contains(&Domain::Quantum)
    }

    /// Whether this plan requires AI inference
    pub fn requires_ai(&self) -> bool {
        self.domains_involved.contains(&Domain::AI)
    }

    /// Summary string for logging
    pub fn summary(&self) -> String {
        format!(
            "Plan[intent={}, tasks={}, domains={:?}, est={}ms, critical={}ms]",
            self.intent_id,
            self.tasks.len(),
            self.domains_involved,
            self.estimated_total_ms,
            self.critical_path_ms,
        )
    }
}

// ---------------------------------------------------------------------------
// Resource estimate
// ---------------------------------------------------------------------------

/// Resource requirements for a single task
#[derive(Debug, Clone)]
pub struct ResourceEstimate {
    pub cpu_cores: u8,
    pub gpu_vram_mb: u32,
    pub npu_tops: u32,
    pub memory_mb: u64,
    pub estimated_ms: u32,
    pub energy_mj: u32,
}

impl ResourceEstimate {
    /// Estimate resources for a hardware resource type
    pub fn for_hardware(hw: &HardwareResource, estimated_ms: u32) -> Self {
        match hw {
            HardwareResource::Cpu { cores } => Self {
                cpu_cores: *cores,
                gpu_vram_mb: 0,
                npu_tops: 0,
                memory_mb: 256,
                estimated_ms,
                energy_mj: (*cores as u32) * estimated_ms / 10,
            },
            HardwareResource::Gpu { vram_mb } => Self {
                cpu_cores: 1,
                gpu_vram_mb: *vram_mb,
                npu_tops: 0,
                memory_mb: (*vram_mb as u64) + 512,
                estimated_ms,
                energy_mj: vram_mb / 100 * estimated_ms,
            },
            HardwareResource::Npu { tops } => Self {
                cpu_cores: 0,
                gpu_vram_mb: 0,
                npu_tops: *tops,
                memory_mb: 512,
                estimated_ms,
                energy_mj: tops / 10 * estimated_ms / 100,
            },
            HardwareResource::Qpu => Self {
                cpu_cores: 2,
                gpu_vram_mb: 0,
                npu_tops: 0,
                memory_mb: 1024,
                estimated_ms,
                energy_mj: estimated_ms * 5,
            },
            _ => Self {
                cpu_cores: 1,
                gpu_vram_mb: 0,
                npu_tops: 0,
                memory_mb: 128,
                estimated_ms,
                energy_mj: estimated_ms / 10,
            },
        }
    }
}

// ---------------------------------------------------------------------------
// Execution planner
// ---------------------------------------------------------------------------

/// Transforms intents into concrete execution plans
pub struct ExecutionPlanner {
    /// Available domains
    available_domains: Vec<Domain>,
    /// Maximum parallel tasks
    max_parallel: usize,
}

impl ExecutionPlanner {
    /// Create a new planner
    pub fn new(available_domains: Vec<Domain>) -> Self {
        Self {
            available_domains,
            max_parallel: 8,
        }
    }

    /// Create a planner with all standard domains
    pub fn full() -> Self {
        Self::new(vec![
            Domain::Android,
            Domain::Windows,
            Domain::AI,
            Domain::Quantum,
            Domain::RealTime,
            Domain::Cloud,
        ])
    }

    /// Build an execution plan for an intent
    pub fn plan(&self, intent: &Intent) -> Result<ExecutionPlan, PlannerError> {
        // Build the task DAG
        let dag = DagBuilder::build(intent)
            .map_err(|e| PlannerError::DagError(e))?;

        if dag.nodes.is_empty() {
            return Err(PlannerError::EmptyPlan);
        }

        // Convert DAG nodes to ZenithTasks
        let tasks = self.dag_to_tasks(intent, &dag);

        // Collect involved domains
        let mut domains: Vec<Domain> = tasks.iter()
            .map(|t| t.domain.clone())
            .collect::<std::collections::HashSet<_>>()
            .into_iter()
            .collect();
        domains.sort_by_key(|d| d.name().to_string());

        // Check for parallel stages
        let has_parallel = dag.nodes.values().any(|n| n.node.parallelizable);

        // Total memory
        let total_memory = dag.nodes.values().map(|n| n.memory_bytes).sum();

        Ok(ExecutionPlan {
            intent_id: intent.id,
            session_id: intent.session,
            dag,
            tasks,
            estimated_total_ms: dag.total_estimated_ms(),
            critical_path_ms: dag.critical_path_ms,
            total_memory_bytes: total_memory,
            domains_involved: domains,
            has_parallel_stages: has_parallel,
            created_at: std::time::Instant::now(),
        })
    }

    /// Convert DAG nodes to ZenithTask instances
    fn dag_to_tasks(&self, intent: &Intent, dag: &SchedulerDag) -> Vec<ZenithTask> {
        // Follow topological order
        dag.topo_order.iter()
            .filter_map(|id| dag.nodes.get(id))
            .map(|dag_node| {
                // Select best available domain for this node
                let domain = if self.available_domains.contains(dag_node.domain()) {
                    dag_node.domain().clone()
                } else {
                    select_best_domain(&intent.class, &self.available_domains)
                        .unwrap_or(Domain::Windows)
                };

                let mut task = ZenithTask::new(
                    intent.id,
                    intent.session,
                    intent.identity,
                    dag_node.label(),
                    domain,
                    dag_node.hardware.clone(),
                    intent.priority,
                );
                task.latency_budget_ms = intent.latency_budget_ms;
                task.energy_cost = ResourceEstimate::for_hardware(
                    &dag_node.hardware,
                    dag_node.node.estimated_ms,
                ).energy_mj;
                task
            })
            .collect()
    }

    /// Estimate total energy cost for a plan
    pub fn estimate_energy(&self, plan: &ExecutionPlan) -> u32 {
        plan.tasks.iter().map(|t| t.energy_cost).sum()
    }

    /// Check if all required domains are available
    pub fn check_domain_availability(&self, plan: &ExecutionPlan) -> Vec<Domain> {
        plan.domains_involved.iter()
            .filter(|d| !self.available_domains.contains(d))
            .cloned()
            .collect()
    }
}

// ---------------------------------------------------------------------------
// Planner error
// ---------------------------------------------------------------------------

/// Errors from the execution planner
#[derive(Debug, Clone, thiserror::Error)]
pub enum PlannerError {
    #[error("DAG construction failed: {0}")]
    DagError(#[from] DagError),
    #[error("empty execution plan")]
    EmptyPlan,
    #[error("no available domain for intent class: {class:?}")]
    NoDomainAvailable { class: IntentClass },
    #[error("resource limit exceeded: {resource}")]
    ResourceLimitExceeded { resource: String },
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;
    use zenith_abi::intent::{Intent, IntentClass};

    fn make_intent(class: IntentClass) -> Intent {
        Intent::new(
            Uuid::new_v4(), Uuid::new_v4(),
            "test goal", class, 128,
        )
    }

    #[test]
    fn plan_productivity_intent() {
        let planner = ExecutionPlanner::full();
        let intent = make_intent(IntentClass::Productivity);
        let plan = planner.plan(&intent).unwrap();

        assert!(!plan.tasks.is_empty());
        assert!(plan.estimated_total_ms > 0);
        assert!(plan.critical_path_ms > 0);
        assert!(plan.is_cross_domain() || !plan.domains_involved.is_empty());
    }

    #[test]
    fn plan_quantum_intent() {
        let planner = ExecutionPlanner::full();
        let intent = make_intent(IntentClass::Quantum);
        let plan = planner.plan(&intent).unwrap();

        assert!(plan.requires_quantum());
        assert!(plan.domains_involved.contains(&Domain::Quantum));
    }

    #[test]
    fn plan_inference_intent() {
        let planner = ExecutionPlanner::full();
        let intent = make_intent(IntentClass::Inference);
        let plan = planner.plan(&intent).unwrap();

        assert!(plan.requires_ai());
    }

    #[test]
    fn plan_cross_domain_detection() {
        let planner = ExecutionPlanner::full();
        let intent = make_intent(IntentClass::Productivity);
        let plan = planner.plan(&intent).unwrap();
        // Productivity involves Windows + AI
        assert!(plan.is_cross_domain());
    }

    #[test]
    fn plan_summary_non_empty() {
        let planner = ExecutionPlanner::full();
        let intent = make_intent(IntentClass::Messaging);
        let plan = planner.plan(&intent).unwrap();
        assert!(!plan.summary().is_empty());
    }

    #[test]
    fn resource_estimate_cpu() {
        let est = ResourceEstimate::for_hardware(
            &HardwareResource::Cpu { cores: 4 }, 100,
        );
        assert_eq!(est.cpu_cores, 4);
        assert!(est.energy_mj > 0);
    }

    #[test]
    fn resource_estimate_npu() {
        let est = ResourceEstimate::for_hardware(
            &HardwareResource::Npu { tops: 300 }, 200,
        );
        assert_eq!(est.npu_tops, 300);
    }
}