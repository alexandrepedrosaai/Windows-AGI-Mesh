# Clusters

## AGI-Mesh Cluster Topology

| Node Type | Count | Hardware | Memory | Compute |
|---|---|---|---|---|
| GPU nodes | 16 | 8x H100 80GB | 512 GB | 7,912 TFLOPS BF16 |
| MAIA 300 racks | 4 | 96 chiplets | 96x288 GB HBM4 | 4x96x6,400 TFLOPS FP8 |
| Brainwave FPGA | 8 | 8x Stratix 10 280 | 256 GB | 8x8x35 TFLOPS BF16 |
| Majorana QPU | 2 | 8 physical qubits | 64 GB | 1M braid ops/sec |

## Parallelism

| Strategy | Degree |
|---|---|
| Tensor Parallel | 8 |
| Pipeline Parallel | 4 |
| Data Parallel | 16 |
| Expert Parallel | 8 |

## Network

- InfiniBand: 400 Gbps within datacenter
- NVLink: 900 GB/s between GPU nodes
- Hollow-Core Fiber: 100 Tbps between datacenters, 47% lower latency
- Catapult Fabric: 200 GB/s for Brainwave FPGA interconnect

## Scheduling Policies

round-robin, least-loaded, quantum-aware, maia-affinity,
fpga-affinity, photonic-latency, power-aware, locality-aware
