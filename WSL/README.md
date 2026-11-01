The **Windows AGI Benchmark Lab** is a professional-grade, exhaustive heterogeneous inference benchmarking platform designed to measure, compare, and validate AI inference performance across every major hardware architecture, GPU vendor, operating system layer, runtime engine, and programming paradigm — all anchored to the **Windows 11 → WSL2 → Docker** stack and deployable to **Microsoft Azure / Microsoft 365 Cloud**.

This laboratory produces reproducible, publication-quality metrics for:

- **GPU Vendors**: AMD ROCm · NVIDIA CUDA · Intel oneAPI
- **CPU Architectures**: x86_64 · ARM64 · RISC-V64 · MIPS64 · PowerPC · SPARC
- **Legacy ISAs**: Z80 · 6502 · Motorola 68000 · AVR · Xtensa
- **Modern Targets**: WebAssembly · eBPF · FPGA HDL · Microcode DSL
- **AI Runtimes**: Ollama · vLLM · llama.cpp · ONNX Runtime · PyTorch · TensorFlow · TensorRT
- **Languages**: Assembly · C · Rust · Python · Q# · Rust · Go
- **Cloud**: Microsoft Azure · Azure ML · Azure Functions · M365

---

## Architecture

```
Windows 11 Host
│
├── VS Code + GitHub Copilot
├── GitHub Desktop
├── Docker Desktop
│
▼
WSL2 Ubuntu 24.04 LTS
│
├── Docker Engine
│   ├── Ollama (AMD / NVIDIA profiles)
│   ├── OpenWebUI
│   ├── Redis 7
│   ├── Qdrant Vector DB
│   ├── Prometheus
│   └── Grafana
│
├── GPU Stacks
│   ├── AMD ROCm 6.x
│   ├── NVIDIA CUDA 12.x
│   └── Intel oneAPI
│
├── AI Runtimes
│   ├── Ollama
│   ├── vLLM
│   ├── llama.cpp
│   ├── ONNX Runtime
│   ├── PyTorch
│   └── TensorFlow
│
├── Cross-Architecture Toolchains
│   ├── aarch64-linux-gnu-gcc
│   ├── riscv64-linux-gnu-gcc
│   ├── mips64-linux-gnu-gcc
│   └── QEMU User-Mode Emulation
│
└── AGI Mesh Runtime
    ├── Multi-Agent Orchestrator
    ├── Vector Store (Qdrant)
    ├── Memory Layer (Redis)
    └── Observability (Prometheus + Grafana)

Microsoft Azure Cloud
│
├── Azure ML Workspace
├── Azure Container Registry
├── Azure Functions
├── Azure Monitor
├── Azure Blob Storage (benchmark artifacts)
└── Microsoft 365 Integration
```

---

## Repository Structure

```
windows-agi-benchmark/
│
├── LICENSE
├── README.md
├── .gitignore
├── pyproject.toml
├── Makefile
│
├── docker/
│   ├── docker-compose.yml
│   ├── docker-compose.amd.yml
│   ├── docker-compose.nvidia.yml
│   ├── docker-compose.intel.yml
│   ├── docker-compose.monitoring.yml
│   └── dockerfiles/
│       ├── Dockerfile.benchmark
│       ├── Dockerfile.agents
│       ├── Dockerfile.onnx
│       └── Dockerfile.llamacpp
│
├── benchmark/
│   ├── runner.py
│   ├── benchmark_ollama.py
│   ├── benchmark_vllm.py
│   ├── benchmark_onnx.py
│   ├── benchmark_llamacpp.py
│   ├── benchmark_pytorch.py
│   ├── benchmark_tensorflow.py
│   ├── benchmark_tensorrt.py
│   ├── benchmark_cpu.py
│   ├── benchmark_memory.py
│   ├── benchmark_disk.py
│   ├── benchmark_network.py
│   ├── export_csv.py
│   ├── export_json.py
│   ├── generate_charts.py
│   ├── generate_html_report.py
│   └── reports/
│
├── collectors/
│   ├── amd_rocm.py
│   ├── nvidia_cuda.py
│   ├── intel_oneapi.py
│   ├── cpu_metrics.py
│   ├── memory_metrics.py
│   └── system_metrics.py
│
├── src/
│   ├── x86_64/
│   │   ├── hello.asm
│   │   ├── matmul.asm
│   │   ├── simd_avx512.asm
│   │   └── syscall_bench.asm
│   ├── arm64/
│   │   ├── hello.s
│   │   ├── matmul.s
│   │   ├── neon_bench.s
│   │   └── sve_bench.s
│   ├── riscv64/
│   │   ├── hello.s
│   │   ├── matmul.s
│   │   └── rvv_bench.s
│   ├── mips64/
│   │   └── hello.s
│   ├── z80/
│   │   └── hello.asm
│   ├── 6502/
│   │   └── hello.asm
│   ├── avr/
│   │   └── hello.asm
│   ├── wasm/
│   │   └── bench.wat
│   ├── ebpf/
│   │   └── bench.c
│   ├── c/
│   │   ├── main.c
│   │   ├── matmul.c
│   │   ├── bench_cpu.c
│   │   └── bench_memory.c
│   ├── rust/
│   │   ├── Cargo.toml
│   │   └── src/
│   │       ├── main.rs
│   │       ├── bench.rs
│   │       └── matmul.rs
│   └── qsharp/
│       ├── quantum_bench.qs
│       └── quantum_oracle.qs
│
├── agents/
│   ├── orchestrator.py
│   ├── agent_base.py
│   ├── agent_inference.py
│   ├── agent_memory.py
│   ├── agent_search.py
│   ├── agent_code.py
│   └── mesh_runtime.py
│
├── scripts/
│   ├── setup.sh
│   ├── teardown.sh
│   ├── benchmark.sh
│   ├── collect_rocm.sh
│   ├── collect_cuda.sh
│   ├── build_arm64.sh
│   ├── build_riscv64.sh
│   ├── run_qemu.sh
│   ├── setup.ps1
│   ├── benchmark.ps1
│   └── azure_deploy.ps1
│
├── azure/
│   ├── main.bicep
│   ├── azuredeploy.json
│   ├── azure_ml_pipeline.py
│   ├── azure_functions/
│   │   ├── benchmark_trigger/
│   │   └── report_publisher/
│   └── m365/
│       ├── teams_notifier.py
│       └── sharepoint_uploader.py
│
├── observability/
│   ├── prometheus.yml
│   ├── alerting_rules.yml
│   └── grafana/
│       ├── dashboards/
│       │   ├── gpu_benchmark.json
│       │   ├── llm_inference.json
│       │   ├── system_overview.json
│       │   └── agi_mesh.json
│       └── provisioning/
│           ├── datasources.yml
│           └── dashboards.yml
│
├── ci/
│   └── .github/
│       └── workflows/
│           ├── build.yml
│           ├── benchmark.yml
│           ├── release.yml
│           ├── qemu_validation.yml
│           └── azure_deploy.yml
│
└── dashboards/
    ├── index.html
    ├── css/
    │   └── style.css
    └── js/
        └── charts.js
```

---

## Quick Start

### Prerequisites — Windows 11

```powershell
# Enable WSL2
wsl --install -d Ubuntu-24.04

# Install Docker Desktop
winget install Docker.DockerDesktop

# Install VS Code
winget install Microsoft.VisualStudioCode
```

### Prerequisites — WSL2 Ubuntu 24.04

```bash
sudo apt update && sudo apt upgrade -y

sudo apt install -y \
  docker.io docker-compose-v2 \
  build-essential cmake ninja-build \
  python3 python3-pip python3-venv \
  qemu-user qemu-user-static \
  gcc-aarch64-linux-gnu g++-aarch64-linux-gnu \
  gcc-riscv64-linux-gnu g++-riscv64-linux-gnu \
  gcc-mips64-linux-gnuabi64 \
  binutils-aarch64-linux-gnu \
  binutils-riscv64-linux-gnu \
  nasm yasm \
  git curl wget jq \
  sysbench fio \
  python3-pandas python3-matplotlib \
  python3-requests python3-psutil

pip3 install \
  onnxruntime torch torchvision \
  transformers accelerate \
  prometheus-client grafana-api \
  azure-ai-ml azure-identity \
  azure-storage-blob \
  openai anthropic \
  langchain chromadb qdrant-client \
  redis celery \
  rich typer pydantic
```

### AMD ROCm Setup

```bash
# Add ROCm repository
wget https://repo.radeon.com/amdgpu-install/6.1/ubuntu/jammy/amdgpu-install_6.1.60100-1_all.deb
sudo dpkg -i amdgpu-install_6.1.60100-1_all.deb
sudo amdgpu-install --usecase=rocm

# Add user to groups
sudo usermod -a -G render $USER
sudo usermod -a -G video $USER

# Verify
rocminfo
rocm-smi
```

### NVIDIA CUDA Setup

```bash
# Install CUDA toolkit
sudo apt install -y nvidia-cuda-toolkit

# Verify
nvidia-smi
nvcc --version
```

### Launch Stack

```bash
# Clone repository
git clone https://github.com/microsoft/windows-agi-benchmark
cd windows-agi-benchmark

# AMD GPU
docker compose --profile amd -f docker/docker-compose.yml \
  -f docker/docker-compose.amd.yml \
  -f docker/docker-compose.monitoring.yml up -d

# NVIDIA GPU
docker compose --profile nvidia -f docker/docker-compose.yml \
  -f docker/docker-compose.nvidia.yml \
  -f docker/docker-compose.monitoring.yml up -d

# Run full benchmark suite
python benchmark/runner.py --full --export csv json --charts
```

---

## Benchmark Metrics

| Category | Metric | Unit |
|---|---|---|
| Inference | Prompt Latency | ms |
| Inference | First Token Latency (TTFT) | ms |
| Inference | Tokens per Second | tok/s |
| Inference | Context Length | tokens |
| Memory | VRAM Usage | GB |
| Memory | RAM Usage | GB |
| Power | GPU Power Draw | W |
| Power | System TDP | W |
| Thermal | GPU Temperature | °C |
| System | CPU Utilization | % |
| System | GPU Utilization | % |
| System | NPU Utilization | % |
| Storage | Disk Read | MB/s |
| Storage | Disk Write | MB/s |
| Network | Throughput | Gbps |
| Agent | Agent Throughput | req/s |
| Vector | Search Latency | ms |
| Container | Startup Time | s |
| Model | Load Time | s |
| Cost | Cost per Million Tokens | USD |

---

## Supported Hardware

### CPUs
| Vendor | Models |
|---|---|
| Intel | i5, i7, i9, Xeon Scalable |
| AMD | Ryzen 5/7/9, EPYC |
| ARM | Snapdragon X Elite, Ampere Altra |
| RISC-V | StarFive VisionFive 2, SiFive HiFive |

### GPUs
| Vendor | Models |
|---|---|
| NVIDIA | RTX 3060/4060/4070/4080/4090, H100, A100 |
| AMD | RX 7600/7700XT/7800XT/7900GRE/7900XT/7900XTX, MI210/MI250/MI300 |
| Intel | Arc A770, Gaudi 2 |

---

## Assembly Coverage

| ISA | Variants |
|---|---|
| x86 | 8086, 80286, 80386, Pentium, SSE, AVX, AVX2, AVX-512 |
| ARM | ARMv7, ARMv8, ARM64, NEON, SVE, SVE2 |
| RISC-V | RV32I, RV64I, RVV (Vector) |
| MIPS | MIPS32, MIPS64, microMIPS |
| Legacy | Z80, 6502, Motorola 68000, AVR, Xtensa |
| Modern | WebAssembly, eBPF, FPGA HDL, Microcode DSL |
| Other | PowerPC, SPARC |

---

## Cloud Deployment — Microsoft Azure

```bash
# Deploy to Azure
cd azure
az login
az deployment group create \
  --resource-group rg-agi-benchmark \
  --template-file main.bicep \
  --parameters @parameters.json
```

---

## Observability

| Service | URL | Purpose |
|---|---|---|
| Grafana | http://localhost:3001 | Dashboards |
| Prometheus | http://localhost:9090 | Metrics |
| OpenWebUI | http://localhost:3000 | LLM Interface |
| Qdrant | http://localhost:6333 | Vector DB |

---

## Microsoft Exclusive Property

This project is the exclusive intellectual property of **Microsoft Corporation**.  
All rights reserved. Unauthorized use, reproduction, or distribution is strictly prohibited.

© 2026 Microsoft Corporation — Windows AGI Benchmark Lab
