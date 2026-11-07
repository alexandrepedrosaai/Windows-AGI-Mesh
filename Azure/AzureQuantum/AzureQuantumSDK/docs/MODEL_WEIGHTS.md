# Model Weights

## 5B-Parameter Model

| Component | Parameters | Size (BF16) | Size (INT4) |
|---|---|---|---|
| Embedding | ~0.54B (131,072 x 4,096) | ~1.1 GB | ~0.27 GB |
| Attention (36 layers) | ~2.4B | 4.8 GB | 1.2 GB |
| FFN (36 layers) | ~2.5B | 5.0 GB | 1.25 GB |
| Norms + LM head | ~0.1B | 0.2 GB | 0.05 GB |
| **Total** | **~5.54B** | **~11.1 GB** | **~2.8 GB** |

## Sharding (8 shards)

Each shard covers 4-5 layers. Stored in Azure Blob Storage.
Loaded via HCF photonic transport for fast inter-datacenter transfer.

## Quantization

- Classical layers: INT4 (NF4) with BF16 scales
- Quantum layers: BF16 (full precision)
- MAIA 300: FP8-E4M3 for compute, BF16 for accumulation
- Brainwave FPGA: BF16 (synthesis-specialized)
