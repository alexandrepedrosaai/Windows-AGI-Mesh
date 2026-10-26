//! # NUMA Topology Manager

use std::collections::HashMap;
use zenith_abi::domain::Domain;

/// NUMA distance between nodes (lower = faster)
pub type NumaDistance = u8;

/// NUMA topology descriptor
#[derive(Debug, Clone)]
pub struct NumaTopology {
    /// Number of NUMA nodes
    pub node_count: u8,
    /// Distance matrix (node_a × node_b → latency)
    pub distances:  Vec<Vec<NumaDistance>>,
    /// Pages per node
    pub pages_per_node: Vec<u64>,
    /// Domain → preferred node mapping
    pub domain_affinity: HashMap<String, u8>,
}

impl NumaTopology {
    /// Create a single-node (UMA) topology
    pub fn uma(total_pages: u64) -> Self {
        Self {
            node_count: 1,
            distances:  vec![vec![10]],
            pages_per_node: vec![total_pages],
            domain_affinity: HashMap::new(),
        }
    }

    /// Create a dual-node NUMA topology
    pub fn dual_node(pages_per_node: u64) -> Self {
        Self {
            node_count: 2,
            distances:  vec![
                vec![10, 20],
                vec![20, 10],
            ],
            pages_per_node: vec![pages_per_node, pages_per_node],
            domain_affinity: HashMap::new(),
        }
    }

    /// Get distance between two nodes
    pub fn distance(&self, from: u8, to: u8) -> NumaDistance {
        if from as usize >= self.distances.len() { return 255; }
        if to as usize >= self.distances[from as usize].len() { return 255; }
        self.distances[from as usize][to as usize]
    }

    /// Set domain affinity for a NUMA node
    pub fn set_affinity(&mut self, domain: &Domain, node: u8) {
        self.domain_affinity.insert(domain.name().to_string(), node);
    }

    /// Get preferred node for a domain
    pub fn preferred_node(&self, domain: &Domain) -> Option<u8> {
        self.domain_affinity.get(domain.name()).copied()
    }

    /// Find the nearest node to a given node
    pub fn nearest_node(&self, from: u8) -> u8 {
        (0..self.node_count)
            .filter(|&n| n != from)
            .min_by_key(|&n| self.distance(from, n))
            .unwrap_or(0)
    }

    /// Whether this is a NUMA system (more than 1 node)
    pub fn is_numa(&self) -> bool {
        self.node_count > 1
    }
}

/// NUMA page placement statistics
#[derive(Debug, Clone, Default)]
pub struct NumaStats {
    pub local_allocations:  u64,
    pub remote_allocations: u64,
    pub migrations:         u64,
}

impl NumaStats {
    pub fn local_ratio(&self) -> f64 {
        let total = self.local_allocations + self.remote_allocations;
        if total == 0 { return 1.0; }
        self.local_allocations as f64 / total as f64
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn numa_uma_topology() {
        let topo = NumaTopology::uma(1024);
        assert_eq!(topo.node_count, 1);
        assert!(!topo.is_numa());
        assert_eq!(topo.distance(0, 0), 10);
    }

    #[test]
    fn numa_dual_node() {
        let topo = NumaTopology::dual_node(512);
        assert_eq!(topo.node_count, 2);
        assert!(topo.is_numa());
        assert!(topo.distance(0, 1) > topo.distance(0, 0));
    }

    #[test]
    fn numa_affinity() {
        let mut topo = NumaTopology::dual_node(512);
        topo.set_affinity(&Domain::Windows, 0);
        topo.set_affinity(&Domain::Android, 1);
        assert_eq!(topo.preferred_node(&Domain::Windows), Some(0));
        assert_eq!(topo.preferred_node(&Domain::Android), Some(1));
        assert_eq!(topo.preferred_node(&Domain::AI), None);
    }

    #[test]
    fn numa_nearest_node() {
        let topo = NumaTopology::dual_node(512);
        assert_eq!(topo.nearest_node(0), 1);
        assert_eq!(topo.nearest_node(1), 0);
    }
}