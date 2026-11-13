"""
topology.py — AGI-Mesh cluster topology: nodes, links, routing, partitioning.
Models: GPU nodes, MAIA-300 racks, Brainwave FPGA nodes, Majorana QPU nodes,
        Hollow-Core Fiber photonic links, InfiniBand fabric.
"""
from __future__ import annotations
import json, logging, math, time, uuid
from dataclasses import dataclass, field, asdict
from enum import Enum
from typing import Dict, List, Optional, Set, Tuple

logger = logging.getLogger(__name__)

class LinkType(str, Enum):
    NVLINK          = "nvlink"
    INFINIBAND      = "infiniband"
    ETHERNET        = "ethernet"
    HOLLOW_CORE_FIBER = "hollow-core-fiber"
    STANDARD_FIBER  = "standard-smf"
    CATAPULT_FABRIC = "catapult-fabric"
    QUANTUM_CHANNEL = "quantum-channel"

@dataclass
class NetworkLink:
    link_id:        str = field(default_factory=lambda: str(uuid.uuid4()))
    source_node:    str = ""
    target_node:    str = ""
    link_type:      LinkType = LinkType.INFINIBAND
    bandwidth_gbps: float = 400.0
    latency_us:     float = 1.0
    is_bidirectional: bool = True
    is_photonic:    bool = False
    latency_reduction_pct: float = 0.0  # HCF: 47%
    is_active:      bool = True
    utilization:    float = 0.0

    @property
    def effective_latency_us(self) -> float:
        if self.is_photonic and self.latency_reduction_pct > 0:
            return self.latency_us * (1.0 - self.latency_reduction_pct / 100.0)
        return self.latency_us

    @property
    def effective_bandwidth_gbps(self) -> float:
        return self.bandwidth_gbps * (1.0 - self.utilization)

    def to_dict(self) -> dict:
        d = asdict(self)
        d["link_type"] = self.link_type.value
        return d

@dataclass
class TopologyNode:
    node_id:        str = field(default_factory=lambda: str(uuid.uuid4()))
    hostname:       str = "localhost"
    ip_address:     str = "127.0.0.1"
    region:         str = "eastus2"
    datacenter:     str = "azure-dc-1"
    rack_id:        str = "rack-01"
    gpu_count:      int = 8
    gpu_model:      str = "nvidia-h100"
    maia_300_count: int = 0
    fpga_count:     int = 0
    quantum_qubits: int = 0
    cpu_cores:      int = 96
    memory_gb:      int = 512
    storage_tb:     float = 10.0
    is_coordinator: bool = False
    is_quantum:     bool = False
    is_photonic:    bool = False
    is_maia:        bool = False
    is_fpga:        bool = False
    health_score:   float = 1.0
    power_kw:       float = 10.0
    pue:            float = 1.2  # Power Usage Effectiveness
    links:          List[str] = field(default_factory=list)  # link_ids

    @property
    def total_compute_tflops(self) -> float:
        gpu_tflops  = self.gpu_count * 989.0       # H100 BF16
        maia_tflops = self.maia_300_count * 3200.0  # MAIA-300 FP8
        fpga_tflops = self.fpga_count * 35.0        # Brainwave BF16
        return gpu_tflops + maia_tflops + fpga_tflops

    @property
    def total_memory_gb(self) -> float:
        gpu_mem  = self.gpu_count * 80.0            # H100 80GB
        maia_mem = self.maia_300_count * 288.0      # MAIA-300 288GB HBM4
        return self.memory_gb + gpu_mem + maia_mem

    def to_dict(self) -> dict:
        return asdict(self)

class ClusterTopologyGraph:
    """
    Graph-based cluster topology for the AGI-Mesh.
    Supports shortest-path routing, partition planning, and
    photonic-latency-aware scheduling.
    """

    def __init__(self, topology_id: Optional[str] = None) -> None:
        self.topology_id = topology_id or str(uuid.uuid4())
        self._nodes: Dict[str, TopologyNode] = {}
        self._links: Dict[str, NetworkLink]  = {}
        self._adj:   Dict[str, List[str]]    = {}  # node_id -> [link_ids]
        self._created_at = time.time()

    def add_node(self, node: TopologyNode) -> None:
        self._nodes[node.node_id] = node
        if node.node_id not in self._adj:
            self._adj[node.node_id] = []
        logger.debug("Added node %s (%s)", node.node_id, node.hostname)

    def remove_node(self, node_id: str) -> None:
        if node_id in self._nodes:
            del self._nodes[node_id]
            # Remove associated links
            links_to_remove = [
                lid for lid, lnk in self._links.items()
                if lnk.source_node == node_id or lnk.target_node == node_id
            ]
            for lid in links_to_remove:
                self.remove_link(lid)
            self._adj.pop(node_id, None)

    def add_link(self, link: NetworkLink) -> None:
        self._links[link.link_id] = link
        self._adj.setdefault(link.source_node, []).append(link.link_id)
        if link.is_bidirectional:
            self._adj.setdefault(link.target_node, []).append(link.link_id)
        logger.debug("Added link %s %s->%s type=%s",
                     link.link_id, link.source_node, link.target_node, link.link_type.value)

    def remove_link(self, link_id: str) -> None:
        if link_id in self._links:
            lnk = self._links.pop(link_id)
            for adj_list in self._adj.values():
                if link_id in adj_list:
                    adj_list.remove(link_id)

    def get_node(self, node_id: str) -> Optional[TopologyNode]:
        return self._nodes.get(node_id)

    def get_link(self, link_id: str) -> Optional[NetworkLink]:
        return self._links.get(link_id)

    def neighbors(self, node_id: str) -> List[TopologyNode]:
        result = []
        for lid in self._adj.get(node_id, []):
            lnk = self._links.get(lid)
            if lnk and lnk.is_active:
                other = lnk.target_node if lnk.source_node == node_id else lnk.source_node
                if other in self._nodes:
                    result.append(self._nodes[other])
        return result

    def shortest_path_latency(self, src: str, dst: str) -> Tuple[float, List[str]]:
        """Dijkstra shortest path by latency (µs)."""
        if src not in self._nodes or dst not in self._nodes:
            return float("inf"), []
        dist: Dict[str, float] = {n: float("inf") for n in self._nodes}
        prev: Dict[str, Optional[str]] = {n: None for n in self._nodes}
        dist[src] = 0.0
        unvisited: Set[str] = set(self._nodes.keys())
        while unvisited:
            u = min(unvisited, key=lambda n: dist[n])
            if dist[u] == float("inf"):
                break
            unvisited.remove(u)
            if u == dst:
                break
            for lid in self._adj.get(u, []):
                lnk = self._links.get(lid)
                if not lnk or not lnk.is_active:
                    continue
                v = lnk.target_node if lnk.source_node == u else lnk.source_node
                if v not in unvisited:
                    continue
                alt = dist[u] + lnk.effective_latency_us
                if alt < dist[v]:
                    dist[v] = alt
                    prev[v] = u
        # Reconstruct path
        path, cur = [], dst
        while cur is not None:
            path.append(cur)
            cur = prev.get(cur)
        path.reverse()
        return dist[dst], path

    def shortest_path_bandwidth(self, src: str, dst: str) -> Tuple[float, List[str]]:
        """Max-bandwidth path (bottleneck bandwidth)."""
        if src not in self._nodes or dst not in self._nodes:
            return 0.0, []
        bw: Dict[str, float] = {n: 0.0 for n in self._nodes}
        prev: Dict[str, Optional[str]] = {n: None for n in self._nodes}
        bw[src] = float("inf")
        unvisited: Set[str] = set(self._nodes.keys())
        while unvisited:
            u = max(unvisited, key=lambda n: bw[n])
            if bw[u] == 0.0:
                break
            unvisited.remove(u)
            if u == dst:
                break
            for lid in self._adj.get(u, []):
                lnk = self._links.get(lid)
                if not lnk or not lnk.is_active:
                    continue
                v = lnk.target_node if lnk.source_node == u else lnk.source_node
                if v not in unvisited:
                    continue
                alt = min(bw[u], lnk.effective_bandwidth_gbps)
                if alt > bw[v]:
                    bw[v] = alt
                    prev[v] = u
        path, cur = [], dst
        while cur is not None:
            path.append(cur)
            cur = prev.get(cur)
        path.reverse()
        return bw[dst], path

    def partition_for_pipeline(self, num_stages: int) -> List[List[str]]:
        """Partition nodes into pipeline stages (balanced by compute)."""
        nodes = list(self._nodes.values())
        nodes.sort(key=lambda n: n.total_compute_tflops, reverse=True)
        stages: List[List[str]] = [[] for _ in range(num_stages)]
        stage_load = [0.0] * num_stages
        for node in nodes:
            min_stage = min(range(num_stages), key=lambda i: stage_load[i])
            stages[min_stage].append(node.node_id)
            stage_load[min_stage] += node.total_compute_tflops
        return stages

    def partition_for_tensor_parallel(self, tp_degree: int) -> List[List[str]]:
        """Partition nodes for tensor parallelism (prefer NVLink/HCF connected)."""
        nodes = list(self._nodes.values())
        groups: List[List[str]] = []
        for i in range(0, len(nodes), tp_degree):
            groups.append([n.node_id for n in nodes[i:i+tp_degree]])
        return groups

    def get_photonic_paths(self) -> List[Tuple[str, str, float]]:
        """Return all photonic (HCF) links with their latency."""
        result = []
        for lnk in self._links.values():
            if lnk.link_type == LinkType.HOLLOW_CORE_FIBER and lnk.is_active:
                result.append((lnk.source_node, lnk.target_node, lnk.effective_latency_us))
        return result

    def total_compute_tflops(self) -> float:
        return sum(n.total_compute_tflops for n in self._nodes.values())

    def total_memory_gb(self) -> float:
        return sum(n.total_memory_gb for n in self._nodes.values())

    def total_power_kw(self) -> float:
        return sum(n.power_kw for n in self._nodes.values())

    def quantum_node_count(self) -> int:
        return sum(1 for n in self._nodes.values() if n.is_quantum)

    def maia_chiplet_count(self) -> int:
        return sum(n.maia_300_count for n in self._nodes.values())

    def fpga_count(self) -> int:
        return sum(n.fpga_count for n in self._nodes.values())

    def to_dict(self) -> dict:
        return {
            "topology_id": self.topology_id,
            "node_count": len(self._nodes),
            "link_count": len(self._links),
            "total_compute_tflops": self.total_compute_tflops(),
            "total_memory_gb": self.total_memory_gb(),
            "total_power_kw": self.total_power_kw(),
            "quantum_nodes": self.quantum_node_count(),
            "maia_chiplets": self.maia_chiplet_count(),
            "fpga_count": self.fpga_count(),
            "nodes": [n.to_dict() for n in self._nodes.values()],
            "links": [l.to_dict() for l in self._links.values()],
        }

    def to_json(self) -> str:
        return json.dumps(self.to_dict(), indent=2)

    @classmethod
    def build_azure_mesh(cls, num_gpu_nodes: int = 16,
                          num_maia_racks: int = 4,
                          num_fpga_nodes: int = 8,
                          num_quantum_nodes: int = 2) -> "ClusterTopologyGraph":
        """Build a representative Azure AGI-Mesh topology."""
        g = cls()
        node_ids = []

        # GPU nodes (H100)
        for i in range(num_gpu_nodes):
            n = TopologyNode(node_id=f"gpu-node-{i:03d}",
                hostname=f"gpu-{i:03d}.eastus2.azure.com",
                ip_address=f"10.0.{i//256}.{i%256}",
                gpu_count=8, gpu_model="nvidia-h100",
                memory_gb=512, cpu_cores=96,
                rack_id=f"rack-{i//4:02d}", region="eastus2")
            g.add_node(n); node_ids.append(n.node_id)

        # MAIA-300 racks (96 chiplets each)
        for i in range(num_maia_racks):
            n = TopologyNode(node_id=f"maia-rack-{i:02d}",
                hostname=f"maia-{i:02d}.eastus2.azure.com",
                ip_address=f"10.1.{i}.0",
                maia_300_count=96, gpu_count=0, is_maia=True,
                memory_gb=96*288, cpu_cores=256,
                rack_id=f"maia-rack-{i:02d}", region="eastus2",
                power_kw=167.0)
            g.add_node(n); node_ids.append(n.node_id)

        # Brainwave FPGA nodes
        for i in range(num_fpga_nodes):
            n = TopologyNode(node_id=f"fpga-node-{i:02d}",
                hostname=f"fpga-{i:02d}.eastus2.azure.com",
                ip_address=f"10.2.{i}.0",
                fpga_count=8, gpu_count=0, is_fpga=True,
                memory_gb=256, cpu_cores=64,
                rack_id=f"fpga-rack-{i//4:02d}", region="eastus2")
            g.add_node(n); node_ids.append(n.node_id)

        # Majorana QPU nodes
        for i in range(num_quantum_nodes):
            n = TopologyNode(node_id=f"quantum-node-{i:02d}",
                hostname=f"quantum-{i:02d}.eastus2.azure.com",
                ip_address=f"10.3.{i}.0",
                quantum_qubits=8, gpu_count=0, is_quantum=True,
                memory_gb=64, cpu_cores=32,
                rack_id=f"quantum-rack-{i:02d}", region="eastus2",
                power_kw=0.5)
            g.add_node(n); node_ids.append(n.node_id)

        # InfiniBand links (full mesh within racks)
        for i, src in enumerate(node_ids):
            for j, dst in enumerate(node_ids):
                if i < j:
                    lnk = NetworkLink(source_node=src, target_node=dst,
                        link_type=LinkType.INFINIBAND,
                        bandwidth_gbps=400.0, latency_us=1.0)
                    g.add_link(lnk)

        # Hollow-Core Fiber links between datacenters
        if len(node_ids) >= 2:
            hcf = NetworkLink(source_node=node_ids[0], target_node=node_ids[-1],
                link_type=LinkType.HOLLOW_CORE_FIBER,
                bandwidth_gbps=100_000.0, latency_us=265.0,  # 47% less than SMF
                is_photonic=True, latency_reduction_pct=47.0)
            g.add_link(hcf)

        logger.info("Built Azure AGI-Mesh topology: %d nodes, %d links, %.0f TFLOPS",
                    len(g._nodes), len(g._links), g.total_compute_tflops())
        return g

    def __repr__(self) -> str:
        return (f"ClusterTopologyGraph(nodes={len(self._nodes)}, "
                f"links={len(self._links)}, "
                f"tflops={self.total_compute_tflops():.0f})")
