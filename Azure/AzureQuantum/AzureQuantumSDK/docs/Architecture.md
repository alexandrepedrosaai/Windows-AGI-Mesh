# Architecture

## LLM Architecture (5B parameters)

| Parameter | Value |
|---|---|
| Layers | 36 |
| Hidden dim | 4,096 |
| Query heads | 32 (GQA) |
| KV heads | 8 |
| Head dim | 128 |
| FFN dim | 14,336 (SwiGLU) |
| Vocab size | 131,072 |
| Max seq len | 131,072 |
| RoPE theta | 500,000 |
| Experts | 8 (MoE layers 4,10,16) |
| Quantum layers | 1, 7, 13, 19 |
| Training tokens | 15T |

## Hardware Pipeline

### Prefill: MAIA 300
- 8-shard tensor parallel, FP8 compute
- 288 GB HBM4 KV-cache per chiplet
- Flash attention + speculative decoding (5 draft tokens)

### Decode: Brainwave FPGA
- Batch=1 real-time AI, <1ms latency
- Intel Stratix 10 280, 96,000 MAC units
- Synthesis-specialized at compile time

### Quantum Layers: Majorana 1 QPU
- Q# variational circuits for attention scoring
- Topological protection: T1=1000us, 2Q fidelity=99.9%
- MWPM decoder, code distance=3, 2:1 overhead
- 1M braid operations/sec

### Transport: Hollow-Core Fiber
- 47% lower latency vs standard SMF
- 100 Tbps bandwidth, refractive index 1.0003
- In-transit photonic compute (10x speedup)
- Heraeus Covantics manufacturing

## Q# Modules

- Types.qs: UDTs for all SDK types
- Validation.qs: Input validation
- Arrays.qs: Array utilities, matrix ops
- Circuits.qs: HEA, QFT, QAOA, quantum attention, Majorana braiding
- Sampling.qs: Shot-based sampling, Majorana-protected, QMCMC
- Factorization.qs: Shor's algorithm, period finding
- Api.qs: Public API surface
- Entrypoint.qs: CLI entry point
- Benchmarks.qs: Full benchmark suite
- Buffers.qs: Quantum ring buffer, KV-cache

## PowerShell Module (30 cmdlets)

Invoke-QuantumExperiment, Invoke-MajoranaExperiment, Invoke-BatchExperiment,
Invoke-LLMInference, Invoke-MAIA300Task, Invoke-BrainwaveFPGATask,
Send-PhotonicData, Invoke-MajoranaQEC, Get-ResourceEstimate,
Invoke-QuantumBenchmark, Invoke-QuantumFactorize, Invoke-QuantumSampling,
Get-QuantumSdkInfo, Get-QuantumBackends, Get-HardwareStatus,
Get-ClusterTopology, Register-QuantumNode, Get-ModelRegistry,
Get-WeightShardInfo, Get-MoERoutingStats, Invoke-AlignmentCheck,
Get-PhotonicLinkStats, Set-QuantumBackend, Reset-KVCache,
Export-ExperimentResults, Import-ExperimentConfig, Test-QuantumBackend,
Measure-QuantumFidelity, Start-QuantumTraining, Get-SamplingStats
