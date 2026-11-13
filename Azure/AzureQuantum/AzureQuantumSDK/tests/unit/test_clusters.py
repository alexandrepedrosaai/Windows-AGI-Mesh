"""Unit tests for cluster scheduler and topology."""
import pytest, time
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", ".."))

from src.python.clusters.scheduler import (
    AGIMeshScheduler, NodeState, ScheduledTask, SchedulingPolicy, TaskStatus
)
from src.python.clusters.topology import (
    ClusterTopologyGraph, TopologyNode, NetworkLink, LinkType
)


class TestAGIMeshScheduler:
    def _make_node(self, node_id="n1", gpu_count=8, maia_count=0,
                   fpga_count=0, quantum=False, photonic=False):
        return NodeState(node_id=node_id, hostname=f"{node_id}.local",
                         ip_address="10.0.0.1", gpu_count=gpu_count,
                         maia_count=maia_count, fpga_count=fpga_count,
                         quantum_enabled=quantum, photonic_enabled=photonic)

    def test_register_node(self):
        sched = AGIMeshScheduler()
        node  = self._make_node()
        sched.register_node(node)
        assert len(sched.get_healthy_nodes()) == 1

    def test_submit_task(self):
        sched = AGIMeshScheduler()
        sched.register_node(self._make_node())
        tid = sched.submit("experiment", {"qubit_count": 4}, priority=5)
        assert tid
        assert sched.queue_depth() == 1

    def test_schedule_next(self):
        sched = AGIMeshScheduler()
        sched.register_node(self._make_node())
        sched.submit("experiment", {}, priority=5)
        result = sched.schedule_next()
        assert result is not None
        task, node = result
        assert task.status == TaskStatus.RUNNING
        assert sched.running_count() == 1

    def test_complete_task(self):
        sched = AGIMeshScheduler()
        sched.register_node(self._make_node())
        sched.submit("experiment", {}, priority=5)
        task, node = sched.schedule_next()
        sched.complete_task(task.task_id, result={"mean": 0.5})
        assert sched.running_count() == 0
        assert sched._stats["completed"] == 1

    def test_failed_task_retry(self):
        sched = AGIMeshScheduler()
        sched.register_node(self._make_node())
        sched.submit("experiment", {}, priority=5, max_retries=2)
        task, node = sched.schedule_next()
        sched.complete_task(task.task_id, error="simulated error")
        assert sched._stats["retried"] == 1
        assert sched.queue_depth() == 1  # re-queued

    def test_cancel_task(self):
        sched = AGIMeshScheduler()
        sched.register_node(self._make_node())
        tid = sched.submit("experiment", {}, priority=5)
        cancelled = sched.cancel_task(tid)
        assert cancelled
        assert sched.queue_depth() == 0

    def test_quantum_node_filter(self):
        sched = AGIMeshScheduler()
        sched.register_node(self._make_node("n1", quantum=False))
        sched.register_node(self._make_node("n2", quantum=True))
        quantum_nodes = sched.get_quantum_nodes()
        assert len(quantum_nodes) == 1
        assert quantum_nodes[0].node_id == "n2"

    def test_maia_node_filter(self):
        sched = AGIMeshScheduler()
        sched.register_node(self._make_node("n1", maia_count=0))
        sched.register_node(self._make_node("n2", maia_count=96))
        maia_nodes = sched.get_maia_nodes()
        assert len(maia_nodes) == 1

    def test_priority_ordering(self):
        sched = AGIMeshScheduler()
        sched.register_node(self._make_node())
        sched.submit("low",  {}, priority=10)
        sched.submit("high", {}, priority=1)
        result = sched.schedule_next()
        assert result is not None
        task, _ = result
        assert task.task_type == "high"

    def test_stats(self):
        sched = AGIMeshScheduler()
        sched.register_node(self._make_node())
        stats = sched.stats()
        assert "queue_depth" in stats
        assert "healthy_nodes" in stats
        assert stats["healthy_nodes"] == 1

    def test_deregister_node(self):
        sched = AGIMeshScheduler()
        node = self._make_node()
        sched.register_node(node)
        sched.deregister_node(node.node_id)
        assert len(sched.get_healthy_nodes()) == 0

    def test_round_robin_policy(self):
        sched = AGIMeshScheduler(policy=SchedulingPolicy.ROUND_ROBIN)
        sched.register_node(self._make_node("n1"))
        sched.register_node(self._make_node("n2"))
        sched.submit("t1", {})
        sched.submit("t2", {})
        r1 = sched.schedule_next()
        r2 = sched.schedule_next()
        assert r1 is not None and r2 is not None
        # Both tasks scheduled to different nodes (round-robin)
        nodes_used = {r1[1].node_id, r2[1].node_id}
        assert len(nodes_used) >= 1


class TestClusterTopologyGraph:
    def test_add_node(self):
        g = ClusterTopologyGraph()
        n = TopologyNode(node_id="n1", hostname="n1.local")
        g.add_node(n)
        assert g.get_node("n1") is not None

    def test_add_link(self):
        g = ClusterTopologyGraph()
        g.add_node(TopologyNode(node_id="n1"))
        g.add_node(TopologyNode(node_id="n2"))
        lnk = NetworkLink(source_node="n1", target_node="n2",
                          link_type=LinkType.INFINIBAND, bandwidth_gbps=400.0)
        g.add_link(lnk)
        assert g.get_link(lnk.link_id) is not None

    def test_neighbors(self):
        g = ClusterTopologyGraph()
        g.add_node(TopologyNode(node_id="n1"))
        g.add_node(TopologyNode(node_id="n2"))
        g.add_node(TopologyNode(node_id="n3"))
        g.add_link(NetworkLink(source_node="n1", target_node="n2"))
        g.add_link(NetworkLink(source_node="n1", target_node="n3"))
        neighbors = g.neighbors("n1")
        assert len(neighbors) == 2

    def test_shortest_path(self):
        g = ClusterTopologyGraph()
        for nid in ["n1","n2","n3"]:
            g.add_node(TopologyNode(node_id=nid))
        g.add_link(NetworkLink(source_node="n1", target_node="n2", latency_us=1.0))
        g.add_link(NetworkLink(source_node="n2", target_node="n3", latency_us=2.0))
        dist, path = g.shortest_path_latency("n1", "n3")
        assert dist == 3.0
        assert path == ["n1","n2","n3"]

    def test_remove_node(self):
        g = ClusterTopologyGraph()
        g.add_node(TopologyNode(node_id="n1"))
        g.remove_node("n1")
        assert g.get_node("n1") is None

    def test_build_azure_mesh(self):
        g = ClusterTopologyGraph.build_azure_mesh(
            num_gpu_nodes=4, num_maia_racks=1, num_fpga_nodes=2, num_quantum_nodes=1)
        assert len(g._nodes) == 8
        assert g.total_compute_tflops() > 0
        assert g.maia_chiplet_count() == 96
        assert g.quantum_node_count() == 1

    def test_hcf_photonic_paths(self):
        g = ClusterTopologyGraph.build_azure_mesh(num_gpu_nodes=2)
        paths = g.get_photonic_paths()
        assert len(paths) >= 1
        for src, dst, lat in paths:
            assert lat > 0

    def test_partition_pipeline(self):
        g = ClusterTopologyGraph.build_azure_mesh(num_gpu_nodes=8)
        stages = g.partition_for_pipeline(4)
        assert len(stages) == 4
        all_nodes = [n for stage in stages for n in stage]
        assert len(all_nodes) > 0

    def test_total_memory(self):
        g = ClusterTopologyGraph.build_azure_mesh(num_maia_racks=1)
        assert g.total_memory_gb() > 0

    def test_to_dict(self):
        g = ClusterTopologyGraph.build_azure_mesh(num_gpu_nodes=2)
        d = g.to_dict()
        assert "topology_id" in d
        assert "node_count" in d
        assert d["node_count"] > 0
