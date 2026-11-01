//! # Zenith Intent Model
//!
//! The Intent is the fundamental unit of computation in the Surface Zenith OS.
//! The scheduler does not manage processes or threads — it manages **goals**.
//!
//! ## Intent Lifecycle
//!
//! ```text
//! User Input → Intent Parser → Task Graph Builder → Execution Planner
//!           → Domain Router → Hardware Scheduler → Execution → Result
//! ```
//!
//! ## Intent-Based Scheduling
//!
//! Traditional schedulers ask: "Which thread gets CPU time?"
//! The Zenith Intent Scheduler asks: "Where should this goal execute?"

use serde::{Deserialize, Serialize};
use uuid::Uuid;
use crate::types::{
    ZTaskId, ZSessionId, ZIdentityId, Priority, EnergyCost,
    LatencyBudgetMs, ZTimestamp,
};
use crate::domain::Domain;
use crate::capability::CapabilityToken;

// ---------------------------------------------------------------------------
// Intent classification
// ---------------------------------------------------------------------------

/// High-level classification of an intent's computational nature
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum IntentClass {
    /// Messaging and communication (WhatsApp, Teams, SMS)
    Messaging,
    /// Document productivity (Word, Excel, PDF)
    Productivity,
    /// Graphics and media rendering (Photoshop, video)
    Graphics,
    /// Software development (Visual Studio, compilers)
    Development,
    /// AI/ML inference (Copilot, image recognition)
    Inference,
    /// Media playback (music, video streaming)
    Media,
    /// Telephony and VoIP
    Telephony,
    /// System administration and configuration
    System,
    /// Real-time sensor processing
    SensorFusion,
    /// Quantum computation
    Quantum,
    /// Cloud synchronization
    CloudSync,
    /// Unknown / to be classified by AI
    Unknown,
}

impl IntentClass {
    /// Preferred domain for this intent class
    pub fn preferred_domain(&self) -> Domain {
        match self {
            IntentClass::Messaging    => Domain::Android,
            IntentClass::Telephony    => Domain::Android,
            IntentClass::SensorFusion => Domain::RealTime,
            IntentClass::Productivity => Domain::Windows,
            IntentClass::Development  => Domain::Windows,
            IntentClass::Graphics     => Domain::Windows,
            IntentClass::Inference    => Domain::AI,
            IntentClass::Quantum      => Domain::Quantum,
            IntentClass::CloudSync    => Domain::Cloud,
            IntentClass::Media        => Domain::Android,
            IntentClass::System       => Domain::Windows,
            IntentClass::Unknown      => Domain::AI,
        }
    }

    /// Base energy cost for this intent class
    pub fn base_energy_cost(&self) -> EnergyCost {
        match self {
            IntentClass::Messaging    => 10,
            IntentClass::Telephony    => 20,
            IntentClass::SensorFusion => 15,
            IntentClass::Productivity => 40,
            IntentClass::Development  => 80,
            IntentClass::Graphics     => 90,
            IntentClass::Inference    => 70,
            IntentClass::Quantum      => 100,
            IntentClass::CloudSync    => 30,
            IntentClass::Media        => 50,
            IntentClass::System       => 25,
            IntentClass::Unknown      => 50,
        }
    }
}

// ---------------------------------------------------------------------------
// Intent state machine
// ---------------------------------------------------------------------------

/// Current state of an intent in the scheduler
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum IntentState {
    /// Submitted but not yet scheduled
    Pending,
    /// Being analyzed by the intent classifier
    Classifying,
    /// Task graph is being built
    Planning,
    /// Assigned to a domain, waiting for resources
    Queued { domain: Domain },
    /// Actively executing
    Running { domain: Domain },
    /// Suspended (e.g., device folded, screen off)
    Suspended,
    /// Migrating between domains
    Migrating { from: Domain, to: Domain },
    /// Completed successfully
    Completed,
    /// Failed with error
    Failed { reason: String },
    /// Cancelled by user or system
    Cancelled,
}

impl IntentState {
    /// Whether the intent is in a terminal state
    pub fn is_terminal(&self) -> bool {
        matches!(
            self,
            IntentState::Completed | IntentState::Failed { .. } | IntentState::Cancelled
        )
    }

    /// Whether the intent is actively consuming resources
    pub fn is_active(&self) -> bool {
        matches!(self, IntentState::Running { .. } | IntentState::Migrating { .. })
    }
}

// ---------------------------------------------------------------------------
// Intent
// ---------------------------------------------------------------------------

/// The fundamental unit of computation in the Zenith OS.
///
/// An Intent represents a user goal, not a process or thread.
/// The scheduler resolves the intent into a task graph and routes
/// each task to the optimal domain.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Intent {
    /// Unique intent ID
    pub id: ZTaskId,
    /// Parent session
    pub session: ZSessionId,
    /// Owning identity
    pub identity: ZIdentityId,
    /// Natural-language goal description
    pub goal: String,
    /// Classified intent type
    pub class: IntentClass,
    /// Scheduling priority (0–255)
    pub priority: Priority,
    /// Maximum acceptable latency before first result
    pub latency_budget_ms: LatencyBudgetMs,
    /// Estimated energy cost
    pub energy_cost: EnergyCost,
    /// Context score (0–255, higher = more contextually relevant)
    pub context_score: u8,
    /// Security level required (0 = public, 255 = top secret)
    pub security_level: u8,
    /// Preferred execution domain (None = let scheduler decide)
    pub preferred_domain: Option<Domain>,
    /// Capability token authorizing this intent
    pub capability: Option<CapabilityToken>,
    /// Current state
    pub state: IntentState,
    /// Submission timestamp
    pub submitted_at: ZTimestamp,
    /// Scheduling score (computed by ZIS)
    pub score: i64,
    /// Sub-tasks derived from this intent
    pub task_graph: Option<TaskGraph>,
    /// Tags for filtering and routing
    pub tags: Vec<String>,
}

impl Intent {
    /// Create a new intent with default values
    pub fn new(
        session: ZSessionId,
        identity: ZIdentityId,
        goal: impl Into<String>,
        class: IntentClass,
        priority: Priority,
    ) -> Self {
        let energy_cost = class.base_energy_cost();
        let preferred_domain = Some(class.preferred_domain());
        Self {
            id: Uuid::new_v4(),
            session,
            identity,
            goal: goal.into(),
            class,
            priority,
            latency_budget_ms: 100,
            energy_cost,
            context_score: 128,
            security_level: 0,
            preferred_domain,
            capability: None,
            state: IntentState::Pending,
            submitted_at: ZTimestamp(
                std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .unwrap_or_default()
                    .as_micros() as i64,
            ),
            score: 0,
            task_graph: None,
            tags: Vec::new(),
        }
    }

    /// Compute the scheduling score using the Zenith Intent Score formula:
    ///
    /// `score = (priority × 5) + (context × 4) + (latency_inv × 2) - energy_cost`
    pub fn compute_score(&mut self) {
        let p = self.priority as i64;
        let c = self.context_score as i64;
        let l = (255 - (self.latency_budget_ms.min(255) as i64));
        let e = self.energy_cost as i64;
        self.score = (p * 5) + (c * 4) + (l * 2) - e;
    }

    /// Transition to a new state
    pub fn transition(&mut self, new_state: IntentState) {
        self.state = new_state;
    }

    /// Add a tag
    pub fn tag(&mut self, tag: impl Into<String>) {
        self.tags.push(tag.into());
    }
}

// ---------------------------------------------------------------------------
// Task graph (DAG of sub-tasks)
// ---------------------------------------------------------------------------

/// A node in the intent task graph
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TaskNode {
    /// Unique node ID
    pub id: ZTaskId,
    /// Human-readable label
    pub label: String,
    /// Target domain for this task
    pub domain: Domain,
    /// Estimated duration in milliseconds
    pub estimated_ms: u32,
    /// Whether this task can run in parallel with siblings
    pub parallelizable: bool,
    /// Current execution state
    pub state: TaskNodeState,
}

/// State of a single task node
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum TaskNodeState {
    Pending,
    Running,
    Completed,
    Failed(String),
    Skipped,
}

/// Directed Acyclic Graph of tasks derived from an intent
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TaskGraph {
    /// All nodes in the graph
    pub nodes: Vec<TaskNode>,
    /// Edges as (from_id, to_id) dependency pairs
    pub edges: Vec<(ZTaskId, ZTaskId)>,
}

impl TaskGraph {
    /// Create an empty task graph
    pub fn new() -> Self {
        Self { nodes: Vec::new(), edges: Vec::new() }
    }

    /// Add a task node
    pub fn add_node(&mut self, node: TaskNode) {
        self.nodes.push(node);
    }

    /// Add a dependency edge (from must complete before to)
    pub fn add_edge(&mut self, from: ZTaskId, to: ZTaskId) {
        self.edges.push((from, to));
    }

    /// Get all nodes that have no predecessors (entry points)
    pub fn roots(&self) -> Vec<&TaskNode> {
        let has_predecessor: std::collections::HashSet<ZTaskId> =
            self.edges.iter().map(|(_, to)| *to).collect();
        self.nodes
            .iter()
            .filter(|n| !has_predecessor.contains(&n.id))
            .collect()
    }

    /// Get successors of a node
    pub fn successors(&self, node_id: ZTaskId) -> Vec<&TaskNode> {
        let successor_ids: std::collections::HashSet<ZTaskId> = self
            .edges
            .iter()
            .filter(|(from, _)| *from == node_id)
            .map(|(_, to)| *to)
            .collect();
        self.nodes
            .iter()
            .filter(|n| successor_ids.contains(&n.id))
            .collect()
    }

    /// Total estimated duration (critical path, simplified)
    pub fn estimated_total_ms(&self) -> u32 {
        self.nodes.iter().map(|n| n.estimated_ms).sum()
    }
}

impl Default for TaskGraph {
    fn default() -> Self {
        Self::new()
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn intent_score_ordering() {
        let session  = Uuid::new_v4();
        let identity = Uuid::new_v4();

        let mut high = Intent::new(
            session, identity,
            "open excel", IntentClass::Productivity, 200,
        );
        high.context_score = 200;
        high.energy_cost   = 10;
        high.compute_score();

        let mut low = Intent::new(
            session, identity,
            "play music", IntentClass::Media, 10,
        );
        low.context_score = 10;
        low.energy_cost   = 50;
        low.compute_score();

        assert!(high.score > low.score);
    }

    #[test]
    fn task_graph_roots() {
        let mut graph = TaskGraph::new();
        let id_a = Uuid::new_v4();
        let id_b = Uuid::new_v4();
        let id_c = Uuid::new_v4();

        graph.add_node(TaskNode {
            id: id_a, label: "OCR".into(), domain: Domain::AI,
            estimated_ms: 50, parallelizable: false,
            state: TaskNodeState::Pending,
        });
        graph.add_node(TaskNode {
            id: id_b, label: "Excel".into(), domain: Domain::Windows,
            estimated_ms: 30, parallelizable: true,
            state: TaskNodeState::Pending,
        });
        graph.add_node(TaskNode {
            id: id_c, label: "LLM".into(), domain: Domain::AI,
            estimated_ms: 200, parallelizable: false,
            state: TaskNodeState::Pending,
        });

        graph.add_edge(id_a, id_c);
        graph.add_edge(id_b, id_c);

        let roots = graph.roots();
        assert_eq!(roots.len(), 2);
    }

    #[test]
    fn intent_state_transitions() {
        let session  = Uuid::new_v4();
        let identity = Uuid::new_v4();
        let mut intent = Intent::new(
            session, identity,
            "analyze contract", IntentClass::Productivity, 150,
        );
        assert_eq!(intent.state, IntentState::Pending);
        intent.transition(IntentState::Running { domain: Domain::Windows });
        assert!(intent.state.is_active());
        intent.transition(IntentState::Completed);
        assert!(intent.state.is_terminal());
    }
}