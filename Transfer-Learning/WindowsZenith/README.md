# AMD Ryzen AI Max+ 395 (Strix Halo) — Windows Zenith Architecture

## Hardware Specifications (Official AMD Documentation)

| Component | Specification | Source |
|-----------|--------------|--------|
| **CPU** | 16 cores / 32 threads, Zen 5 | AMD Official |
| **GPU** | AMD Radeon 8060S — 40 CUs, RDNA 3.5 | AMD Official |
| **NPU** | AMD XDNA 2 — 50 TOPS | AMD Official |
| **Memory** | 128 GB LPDDR5x @ 8000 MT/s | AMD Official |
| **Bandwidth** | 256 GB/s (Unified Memory Architecture) | AMD Official |
| **FP16** | 60 TFLOPS | AMD Official |
| **TDP** | 120W | AMD Official |
| **OS** | Windows 11 / Linux | AMD Official |
| **GPU API** | HIP (ROCm 7.1+) | rocm.docs.amd.com |

## GPU Architecture — RDNA 3.5 (40 CUs)

```
AMD Radeon 8060S (Strix Halo iGPU)
├── Compute Units: 40 CUs
│   ├── Each CU: 64 stream processors (shaders)
│   ├── Total SPs: 2560
│   ├── Wave32 / Wave64 execution
│   └── Matrix Accelerators (AI ops)
├── Memory: Unified 128 GB LPDDR5x
│   ├── Bandwidth: 256 GB/s
│   ├── No discrete VRAM — shared with CPU
│   └── UMA: zero-copy CPU↔GPU transfers
├── Cache Hierarchy
│   ├── L1: 32 KB per CU
│   ├── L2: 4 MB shared
│   └── Infinity Cache: 16 MB
└── Compute
    ├── FP32: 30 TFLOPS
    ├── FP16: 60 TFLOPS
    ├── INT8: 120 TOPS
    └── BF16: 60 TFLOPS
```

## NPU — AMD XDNA 2

```
XDNA 2 Architecture
├── AI Engines: 50 TOPS (INT8)
├── Architecture: Spatial dataflow
├── Supported ops: Conv2D, MatMul, Attention
├── Frameworks: ONNX Runtime, DirectML, ROCm
└── Windows API: DirectML / Windows ML
```

## Programming Stack

```
Windows Zenith Stack
├── HIP/ROCm 7.1+          ← GPU kernels (official AMD language)
│   ├── hipcc compiler
│   ├── rocBLAS, rocRAND, rocFFT
│   └── MIOpen (deep learning)
├── WinUI 3                ← UI layer (Windows App SDK 1.6+)
│   ├── XAML-based
│   └── .NET 8 / C#
├── .NET MAUI              ← Cross-platform UI
│   ├── Windows + Linux
│   └── C# / XAML
├── Q# + QDK               ← Quantum simulation
│   ├── Azure Quantum SDK
│   └── Quantum-classical hybrid
└── PowerShell 7.4+        ← Orchestration
    ├── ROCm management
    ├── HIP compilation
    └── Pipeline automation
```

## UMA Advantage for AI

The Strix Halo's Unified Memory Architecture (UMA) eliminates PCIe bottleneck:
- CPU and GPU share the same 128 GB pool
- Zero-copy tensor transfers
- Ideal for large LLM inference (70B+ models fit in 128 GB)
- HIP `hipMallocManaged()` leverages UMA automatically

## ROCm / HIP Compilation

```bash
# Install ROCm 7.1 on Windows (WSL2) or Linux
# Target: gfx1151 (RDNA 3.5 Strix Halo)
hipcc --offload-arch=gfx1151 -O3 -std=c++20 \
      -lrocblas -lrocrand -lhipfft \
      kernel.hip -o kernel

# Windows PowerShell (via ROCm for Windows)
hipcc.exe --offload-arch=gfx1151 -O3 kernel.hip -o kernel.exe
```

## DirectML Integration (Windows)

```csharp
// DirectML on Radeon 8060S via Windows ML
using Microsoft.ML.OnnxRuntime;
var sessionOptions = new SessionOptions();
sessionOptions.AppendExecutionProvider_DML(deviceId: 0);
var session = new InferenceSession("model.onnx", sessionOptions);
```

## References

- AMD Official: https://www.amd.com/en/products/processors/desktops/ryzen/ryzen-ai-halo/
- ROCm Docs: https://rocm.docs.amd.com/en/docs-7.1.0/
- ROCm Programming Guide: https://rocm-handbook.amd.com/projects/amd-rocm-programming-guide/
- HIP API: https://rocm.docs.amd.com/projects/HIP/
- RDNA 3.5 ISA: https://gpuopen.com/amd-rdna3-shader-instruction-set-architecture/
