//! # Zenith Task DAG Builder
//!
//! Transforms an Intent into a Directed Acyclic Graph (DAG) of concrete tasks.
//! Each node in the DAG is a task assigned to a specific domain and hardware.
//!
//! ## Example: "Analyze contract and compare with Excel Q4"
//!
//! ```text
//!        GOAL
//!          │
//!   ┌──────┴──────┐
//!   │             │
//! Open PDF    Open XLSX
//!   │             │
//!  OCR       Parse Data
//!   │             │
//!   └──────┬──────┘
//!          │
//!         LLM
//!          │
//!       Report
//! ```

use uuid::Uuid;
use std::collections::{HashMap, HashSet, VecDeque};
use zenith_abi::intent::{Intent, IntentClass, TaskNode, TaskGraph, TaskNodeState};
use zenith_abi::domain::Domain;
use zenith_abi::task::{ZenithTask, HardwareResource};
use zenith_abi::types::ZTaskId;

// ---------------------------------------------------------------------------
// DAG node with extended metadata
// ---------------------------------------------------------------------------

/// Extended task node with scheduling metadata
#[derive(Debug, Clone)]
pub struct DagNode {
    /// Core task node
    pub node: TaskNode,
    /// Estimated memory requirement in bytes
    pub memory_bytes: u64,
    /// Estimated CPU cores needed
    pub cpu_cores: u8,
    /// Whether this node can be skipped if a dependency fails
    pub optional: bool,
    /// Retry count on failure
    pub max_retries: u32,
    /// Current retry count
    pub retry_count: u32,
    /// Hardware resource assignment
    pub hardware: HardwareResource,
}

impl DagNode {
    /// Create a new DAG node
    pub fn new(
        label: impl Into<String>,
        domain: Domain,
        estimated_ms: u32,
        hardware: HardwareResource,
    ) -> Self {
        Self {
            node: TaskNode {
                id: Uuid::new_v4(),
                label: label.into(),
                domain,
                estimated_ms,
                parallelizable: false,
                state: TaskNodeState::Pending,
            },
            memory_bytes: 64 * 1024 * 1024, // 64 MB default
            cpu_cores: 1,
            optional: false,
            max_retries: 2,
            retry_count: 0,
            hardware,
        }
    }

    /// Mark as parallelizable
    pub fn parallel(mut self) -> Self {
        self.node.parallelizable = true;
        self
    }

    /// Mark as optional
    pub fn optional(mut self) -> Self {
        self.optional = true;
        self
    }

    /// Set memory requirement
    pub fn with_memory(mut self, bytes: u64) -> Self {
        self.memory_bytes = bytes;
        self
    }

    /// Node ID
    pub fn id(&self) -> ZTaskId {
        self.node.id
    }

    /// Node label
    pub fn label(&self) -> &str {
        &self.node.label
    }

    /// Target domain
    pub fn domain(&self) -> &Domain {
        &self.node.domain
    }
}

// ---------------------------------------------------------------------------
// Extended DAG
// ---------------------------------------------------------------------------

/// Extended task DAG with scheduling metadata
#[derive(Debug, Clone)]
pub struct SchedulerDag {
    /// All nodes indexed by ID
    pub nodes: HashMap<ZTaskId, DagNode>,
    /// Edges: from → set of to (dependencies: from must complete before to)
    pub edges: HashMap<ZTaskId, HashSet<ZTaskId>>,
    /// Reverse edges: to → set of from (predecessors)
    pub reverse_edges: HashMap<ZTaskId, HashSet<ZTaskId>>,
    /// Topological order (computed once)
    pub topo_order: Vec<ZTaskId>,
    /// Critical path length in milliseconds
    pub critical_path_ms: u32,
}

impl SchedulerDag {
    /// Create an empty DAG
    pub fn new() -> Self {
        Self {
            nodes: HashMap::new(),
            edges: HashMap::new(),
            reverse_edges: HashMap::new(),
            topo_order: Vec::new(),
            critical_path_ms: 0,
        }
    }

    /// Add a node to the DAG
    pub fn add_node(&mut self, node: DagNode) -> ZTaskId {
        let id = node.id();
        self.edges.entry(id).or_default();
        self.reverse_edges.entry(id).or_default();
        self.nodes.insert(id, node);
        id
    }

    /// Add a dependency edge (from must complete before to)
    pub fn add_edge(&mut self, from: ZTaskId, to: ZTaskId) {
        self.edges.entry(from).or_default().insert(to);
        self.reverse_edges.entry(to).or_default().insert(from);
    }

    /// Compute topological order using Kahn's algorithm
    pub fn compute_topo_order(&mut self) -> Result<(), DagError> {
        let mut in_degree: HashMap<ZTaskId, usize> = self.nodes.keys()
            .map(|&id| (id, self.reverse_edges.get(&id).map(|s| s.len()).unwrap_or(0)))
            .collect();

        let mut queue: VecDeque<ZTaskId> = in_degree.iter()
            .filter(|(_, &d)| d == 0)
            .map(|(&id, _)| id)
            .collect();

        let mut order = Vec::new();

        while let Some(id) = queue.pop_front() {
            order.push(id);
            if let Some(successors) = self.edges.get(&id) {
                for &succ in successors {
                    let deg = in_degree.get_mut(&succ).unwrap();
                    *deg -= 1;
                    if *deg == 0 {
                        queue.push_back(succ);
                    }
                }
            }
        }

        if order.len() != self.nodes.len() {
            return Err(DagError::CycleDetected);
        }

        self.topo_order = order;
        self.critical_path_ms = self.compute_critical_path();
        Ok(())
    }

    /// Compute the critical path length (longest path through the DAG)
    fn compute_critical_path(&self) -> u32 {
        let mut dist: HashMap<ZTaskId, u32> = self.nodes.keys().map(|&id| (id, 0)).collect();

        for &id in &self.topo_order {
            let node_ms = self.nodes[&id].node.estimated_ms;
            let current = dist[&id] + node_ms;
            if let Some(successors) = self.edges.get(&id) {
                for &succ in successors {
                    let d = dist.get_mut(&succ).unwrap();
                    if current > *d {
                        *d = current;
                    }
                }
            }
        }

        dist.values().copied().max().unwrap_or(0)
    }

    /// Get all root nodes (no predecessors)
    pub fn roots(&self) -> Vec<&DagNode> {
        self.nodes.values()
            .filter(|n| {
                self.reverse_edges.get(&n.id())
                    .map(|s| s.is_empty())
                    .unwrap_or(true)
            })
            .collect()
    }

    /// Get all leaf nodes (no successors)
    pub fn leaves(&self) -> Vec<&DagNode> {
        self.nodes.values()
            .filter(|n| {
                self.edges.get(&n.id())
                    .map(|s| s.is_empty())
                    .unwrap_or(true)
            })
            .collect()
    }

    /// Get successors of a node
    pub fn successors(&self, id: &ZTaskId) -> Vec<&DagNode> {
        self.edges.get(id)
            .map(|ids| ids.iter().filter_map(|i| self.nodes.get(i)).collect())
            .unwrap_or_default()
    }

    /// Get predecessors of a node
    pub fn predecessors(&self, id: &ZTaskId) -> Vec<&DagNode> {
        self.reverse_edges.get(id)
            .map(|ids| ids.iter().filter_map(|i| self.nodes.get(i)).collect())
            .unwrap_or_default()
    }

    /// Get all nodes ready to execute (all predecessors completed)
    pub fn ready_nodes(&self) -> Vec<&DagNode> {
        self.nodes.values()
            .filter(|n| {
                n.node.state == TaskNodeState::Pending
                    && self.predecessors(&n.id()).iter().all(|p| {
                        p.node.state == TaskNodeState::Completed
                    })
            })
            .collect()
    }

    /// Mark a node as completed
    pub fn complete_node(&mut self, id: &ZTaskId) {
        if let Some(node) = self.nodes.get_mut(id) {
            node.node.state = TaskNodeState::Completed;
        }
    }

    /// Mark a node as failed
    pub fn fail_node(&mut self, id: &ZTaskId, reason: impl Into<String>) {
        if let Some(node) = self.nodes.get_mut(id) {
            node.node.state = TaskNodeState::Failed(reason.into());
        }
    }

    /// Whether all nodes are completed
    pub fn is_complete(&self) -> bool {
        self.nodes.values().all(|n| n.node.state == TaskNodeState::Completed)
    }

    /// Whether any node has failed
    pub fn has_failures(&self) -> bool {
        self.nodes.values().any(|n| matches!(n.node.state, TaskNodeState::Failed(_)))
    }

    /// Total estimated execution time (sum of all nodes)
    pub fn total_estimated_ms(&self) -> u32 {
        self.nodes.values().map(|n| n.node.estimated_ms).sum()
    }

    /// Convert to the ABI TaskGraph format
    pub fn to_task_graph(&self) -> TaskGraph {
        let mut graph = TaskGraph::new();
        for node in self.nodes.values() {
            graph.add_node(node.node.clone());
        }
        for (&from, tos) in &self.edges {
            for &to in tos {
                graph.add_edge(from, to);
            }
        }
        graph
    }
}

impl Default for SchedulerDag {
    fn default() -> Self { Self::new() }
}

// ---------------------------------------------------------------------------
// DAG error
// ---------------------------------------------------------------------------

/// Errors that can occur during DAG construction or execution
#[derive(Debug, Clone, thiserror::Error)]
pub enum DagError {
    #[error("cycle detected in task graph")]
    CycleDetected,
    #[error("node not found: {id}")]
    NodeNotFound { id: String },
    #[error("graph depth exceeded maximum: {depth}")]
    DepthExceeded { depth: usize },
    #[error("empty graph")]
    EmptyGraph,
}

// ---------------------------------------------------------------------------
// DAG builder — constructs DAGs from intent classes
// ---------------------------------------------------------------------------

/// Builds task DAGs from intents based on their class
pub struct DagBuilder;

impl DagBuilder {
    /// Build a DAG for an intent
    pub fn build(intent: &Intent) -> Result<SchedulerDag, DagError> {
        match intent.class {
            IntentClass::Productivity => Self::build_productivity_dag(intent),
            IntentClass::Inference    => Self::build_inference_dag(intent),
            IntentClass::Development  => Self::build_development_dag(intent),
            IntentClass::Messaging    => Self::build_messaging_dag(intent),
            IntentClass::Graphics     => Self::build_graphics_dag(intent),
            IntentClass::Media        => Self::build_media_dag(intent),
            IntentClass::Quantum      => Self::build_quantum_dag(intent),
            _                         => Self::build_generic_dag(intent),
        }
    }

    /// Productivity DAG: document analysis workflow
    fn build_productivity_dag(intent: &Intent) -> Result<SchedulerDag, DagError> {
        let mut dag = SchedulerDag::new();

        let parse = dag.add_node(DagNode::new(
            "Parse Document", Domain::Windows,
            50, HardwareResource::Cpu { cores: 2 },
        ));
        let ocr = dag.add_node(DagNode::new(
            "OCR / Text Extraction", Domain::AI,
            80, HardwareResource::Npu { tops: 100 },
        ).parallel());
        let analyze = dag.add_node(DagNode::new(
            "Content Analysis (LLM)", Domain::AI,
            200, HardwareResource::Npu { tops: 300 },
        ));
        let format = dag.add_node(DagNode::new(
            "Format Result", Domain::Windows,
            30, HardwareResource::Cpu { cores: 1 },
        ));

        dag.add_edge(parse, ocr);
        dag.add_edge(ocr, analyze);
        dag.add_edge(analyze, format);
        dag.compute_topo_order()?;
        Ok(dag)
    }

    /// Inference DAG: AI inference workflow
    fn build_inference_dag(intent: &Intent) -> Result<SchedulerDag, DagError> {
        let mut dag = SchedulerDag::new();

        let preprocess = dag.add_node(DagNode::new(
            "Preprocess Input", Domain::AI,
            20, HardwareResource::Cpu { cores: 2 },
        ));
        let tokenize = dag.add_node(DagNode::new(
            "Tokenize", Domain::AI,
            10, HardwareResource::Npu { tops: 50 },
        ));
        let infer = dag.add_node(DagNode::new(
            "LLM Inference", Domain::AI,
            300, HardwareResource::Npu { tops: 300 },
        ));
        let postprocess = dag.add_node(DagNode::new(
            "Postprocess Output", Domain::AI,
            15, HardwareResource::Cpu { cores: 1 },
        ));

        dag.add_edge(preprocess, tokenize);
        dag.add_edge(tokenize, infer);
        dag.add_edge(infer, postprocess);
        dag.compute_topo_order()?;
        Ok(dag)
    }

    /// Development DAG: build and compile workflow
    fn build_development_dag(intent: &Intent) -> Result<SchedulerDag, DagError> {
        let mut dag = SchedulerDag::new();

        let parse_src = dag.add_node(DagNode::new(
            "Parse Source", Domain::Windows,
            100, HardwareResource::Cpu { cores: 4 },
        ));
        let type_check = dag.add_node(DagNode::new(
            "Type Check", Domain::Windows,
            150, HardwareResource::Cpu { cores: 4 },
        ).parallel());
        let codegen = dag.add_node(DagNode::new(
            "Code Generation", Domain::Windows,
            200, HardwareResource::Cpu { cores: 8 },
        ));
        let link = dag.add_node(DagNode::new(
            "Link", Domain::Windows,
            80, HardwareResource::Cpu { cores: 2 },
        ));
        let test = dag.add_node(DagNode::new(
            "Run Tests", Domain::Windows,
            300, HardwareResource::Cpu { cores: 4 },
        ).optional());

        dag.add_edge(parse_src, type_check);
        dag.add_edge(type_check, codegen);
        dag.add_edge(codegen, link);
        dag.add_edge(link, test);
        dag.compute_topo_order()?;
        Ok(dag)
    }

    /// Messaging DAG: send/receive message workflow
    fn build_messaging_dag(intent: &Intent) -> Result<SchedulerDag, DagError> {
        let mut dag = SchedulerDag::new();

        let compose = dag.add_node(DagNode::new(
            "Compose Message", Domain::Android,
            10, HardwareResource::Cpu { cores: 1 },
        ));
        let encrypt = dag.add_node(DagNode::new(
            "Encrypt (E2E)", Domain::Android,
            5, HardwareResource::Cpu { cores: 1 },
        ));
        let send = dag.add_node(DagNode::new(
            "Send via Modem", Domain::Android,
            20, HardwareResource::Modem,
        ));

        dag.add_edge(compose, encrypt);
        dag.add_edge(encrypt, send);
        dag.compute_topo_order()?;
        Ok(dag)
    }

    /// Graphics DAG: render workflow
    fn build_graphics_dag(intent: &Intent) -> Result<SchedulerDag, DagError> {
        let mut dag = SchedulerDag::new();

        let load_assets = dag.add_node(DagNode::new(
            "Load Assets", Domain::Windows,
            50, HardwareResource::Storage,
        ));
        let vertex_shader = dag.add_node(DagNode::new(
            "Vertex Shader", Domain::Windows,
            30, HardwareResource::Gpu { vram_mb: 2048 },
        ).parallel());
        let fragment_shader = dag.add_node(DagNode::new(
            "Fragment Shader", Domain::Windows,
            40, HardwareResource::Gpu { vram_mb: 2048 },
        ).parallel());
        let composite = dag.add_node(DagNode::new(
            "Composite & Present", Domain::Windows,
            20, HardwareResource::Gpu { vram_mb: 512 },
        ));

        dag.add_edge(load_assets, vertex_shader);
        dag.add_edge(load_assets, fragment_shader);
        dag.add_edge(vertex_shader, composite);
        dag.add_edge(fragment_shader, composite);
        dag.compute_topo_order()?;
        Ok(dag)
    }

    /// Media DAG: decode and play workflow
    fn build_media_dag(intent: &Intent) -> Result<SchedulerDag, DagError> {
        let mut dag = SchedulerDag::new();

        let demux = dag.add_node(DagNode::new(
            "Demux Container", Domain::Android,
            10, HardwareResource::Cpu { cores: 1 },
        ));
        let decode_video = dag.add_node(DagNode::new(
            "Decode Video (HW)", Domain::Android,
            30, HardwareResource::Gpu { vram_mb: 512 },
        ).parallel());
        let decode_audio = dag.add_node(DagNode::new(
            "Decode Audio (DSP)", Domain::RealTime,
            5, HardwareResource::Dsp,
        ).parallel());
        let sync = dag.add_node(DagNode::new(
            "A/V Sync", Domain::Android,
            5, HardwareResource::Cpu { cores: 1 },
        ));
        let render = dag.add_node(DagNode::new(
            "Render Frame", Domain::Android,
            16, HardwareResource::Gpu { vram_mb: 256 },
        ));

        dag.add_edge(demux, decode_video);
        dag.add_edge(demux, decode_audio);
        dag.add_edge(decode_video, sync);
        dag.add_edge(decode_audio, sync);
        dag.add_edge(sync, render);
        dag.compute_topo_order()?;
        Ok(dag)
    }

    /// Quantum DAG: quantum circuit execution workflow
    fn build_quantum_dag(intent: &Intent) -> Result<SchedulerDag, DagError> {
        let mut dag = SchedulerDag::new();

        let compile_circuit = dag.add_node(DagNode::new(
            "Compile QASM Circuit", Domain::Quantum,
            50, HardwareResource::Cpu { cores: 2 },
        ));
        let optimize = dag.add_node(DagNode::new(
            "Optimize Gate Sequence", Domain::Quantum,
            100, HardwareResource::Cpu { cores: 4 },
        ));
        let execute = dag.add_node(DagNode::new(
            "Execute on QPU", Domain::Quantum,
            500, HardwareResource::Qpu,
        ));
        let error_correct = dag.add_node(DagNode::new(
            "Error Correction", Domain::Quantum,
            200, HardwareResource::Cpu { cores: 4 },
        ));
        let measure = dag.add_node(DagNode::new(
            "Measure & Collapse", Domain::Quantum,
            50, HardwareResource::Qpu,
        ));

        dag.add_edge(compile_circuit, optimize);
        dag.add_edge(optimize, execute);
        dag.add_edge(execute, error_correct);
        dag.add_edge(error_correct, measure);
        dag.compute_topo_order()?;
        Ok(dag)
    }

    /// Generic DAG for unknown intent classes
    fn build_generic_dag(intent: &Intent) -> Result<SchedulerDag, DagError> {
        let mut dag = SchedulerDag::new();

        let classify = dag.add_node(DagNode::new(
            "Classify Intent (AI)", Domain::AI,
            50, HardwareResource::Npu { tops: 100 },
        ));
        let execute = dag.add_node(DagNode::new(
            "Execute Task", Domain::Windows,
            100, HardwareResource::Cpu { cores: 2 },
        ));

        dag.add_edge(classify, execute);
        dag.compute_topo_order()?;
        Ok(dag)
    }
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
    fn productivity_dag_structure() {
        let intent = make_intent(IntentClass::Productivity);
        let dag = DagBuilder::build(&intent).unwrap();
        assert!(dag.nodes.len() >= 3);
        assert!(!dag.topo_order.is_empty());
        assert!(dag.critical_path_ms > 0);
    }

    #[test]
    fn dag_topo_order_valid() {
        let intent = make_intent(IntentClass::Development);
        let dag = DagBuilder::build(&intent).unwrap();
        // Every node should appear in topo order
        assert_eq!(dag.topo_order.len(), dag.nodes.len());
    }

    #[test]
    fn dag_roots_and_leaves() {
        let intent = make_intent(IntentClass::Inference);
        let dag = DagBuilder::build(&intent).unwrap();
        assert_eq!(dag.roots().len(), 1);
        assert_eq!(dag.leaves().len(), 1);
    }

    #[test]
    fn dag_ready_nodes_initially_roots() {
        let intent = make_intent(IntentClass::Messaging);
        let dag = DagBuilder::build(&intent).unwrap();
        let ready = dag.ready_nodes();
        let roots = dag.roots();
        assert_eq!(ready.len(), roots.len());
    }

    #[test]
    fn quantum_dag_uses_qpu() {
        let intent = make_intent(IntentClass::Quantum);
        let dag = DagBuilder::build(&intent).unwrap();
        let has_qpu = dag.nodes.values().any(|n| {
            matches!(n.hardware, HardwareResource::Qpu)
        });
        assert!(has_qpu);
    }

    #[test]
    fn graphics_dag_parallel_shaders() {
        let intent = make_intent(IntentClass::Graphics);
        let dag = DagBuilder::build(&intent).unwrap();
        let parallel_count = dag.nodes.values()
            .filter(|n| n.node.parallelizable)
            .count();
        assert!(parallel_count >= 2);
    }

    #[test]
    fn dag_complete_tracking() {
        let intent = make_intent(IntentClass::Messaging);
        let mut dag = DagBuilder::build(&intent).unwrap();
        assert!(!dag.is_complete());
        let ids: Vec<ZTaskId> = dag.nodes.keys().copied().collect();
        for id in ids {
            dag.complete_node(&id);
        }
        assert!(dag.is_complete());
    }
}