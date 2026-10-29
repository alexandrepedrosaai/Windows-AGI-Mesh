# =============================================================================
# Windows AGI Benchmark Lab — Makefile
# Copyright (c) 2026 Microsoft Corporation. All Rights Reserved.
# =============================================================================

SHELL := /bin/bash
.DEFAULT_GOAL := help
.PHONY: help setup install build test benchmark clean docker-amd docker-nvidia \
        arm64 riscv64 qemu charts report azure deploy lint format typecheck

# -----------------------------------------------------------------------------
# Variables
# -----------------------------------------------------------------------------
PYTHON        := python3
PIP           := pip3
PROJECT       := windows-agi-benchmark
VERSION       := 1.0.0
REPORT_DIR    := benchmark/reports
BUILD_DIR     := build
SRC_DIR       := src

# Docker
COMPOSE       := docker compose
COMPOSE_BASE  := -f docker/docker-compose.yml
COMPOSE_MON   := -f docker/docker-compose.monitoring.yml
COMPOSE_AMD   := -f docker/docker-compose.amd.yml
COMPOSE_NV    := -f docker/docker-compose.nvidia.yml

# Cross-compilation
CC_ARM64      := aarch64-linux-gnu-gcc
CC_RISCV64    := riscv64-linux-gnu-gcc
CC_MIPS64     := mips64-linux-gnuabi64-gcc
AS_ARM64      := aarch64-linux-gnu-as
AS_RISCV64    := riscv64-linux-gnu-as
LD_ARM64      := aarch64-linux-gnu-ld
LD_RISCV64    := riscv64-linux-gnu-ld

# QEMU
QEMU_ARM64    := qemu-aarch64
QEMU_RISCV64  := qemu-riscv64

# Colors
RED           := \033[0;31m
GREEN         := \033[0;32m
YELLOW        := \033[1;33m
BLUE          := \033[0;34m
CYAN          := \033[0;36m
RESET         := \033[0m

# =============================================================================
# HELP
# =============================================================================
help: ## Show this help message
	@echo ""
	@echo "$(CYAN)╔══════════════════════════════════════════════════════════════╗$(RESET)"
	@echo "$(CYAN)║     Windows AGI Benchmark Lab — Microsoft Exclusive          ║$(RESET)"
	@echo "$(CYAN)║     Version: $(VERSION)                                         ║$(RESET)"
	@echo "$(CYAN)╚══════════════════════════════════════════════════════════════╝$(RESET)"
	@echo ""
	@echo "$(YELLOW)Usage:$(RESET) make [target]"
	@echo ""
	@echo "$(GREEN)Setup:$(RESET)"
	@grep -E '^(setup|install|toolchains):.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(BLUE)%-20s$(RESET) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(GREEN)Docker:$(RESET)"
	@grep -E '^docker-.*:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(BLUE)%-20s$(RESET) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(GREEN)Build:$(RESET)"
	@grep -E '^(build|arm64|riscv64|mips64|wasm|x86):.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(BLUE)%-20s$(RESET) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(GREEN)Benchmark:$(RESET)"
	@grep -E '^(benchmark|bench-.*|qemu|charts|report):.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(BLUE)%-20s$(RESET) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(GREEN)Quality:$(RESET)"
	@grep -E '^(test|lint|format|typecheck):.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(BLUE)%-20s$(RESET) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(GREEN)Cloud:$(RESET)"
	@grep -E '^(azure|deploy):.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(BLUE)%-20s$(RESET) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(GREEN)Utilities:$(RESET)"
	@grep -E '^(clean|status|logs):.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(BLUE)%-20s$(RESET) %s\n", $$1, $$2}'
	@echo ""

# =============================================================================
# SETUP
# =============================================================================
setup: ## Full environment setup (WSL2 + toolchains + Python)
	@echo "$(CYAN)Setting up Windows AGI Benchmark Lab...$(RESET)"
	@bash scripts/setup.sh

install: ## Install Python dependencies
	@echo "$(CYAN)Installing Python dependencies...$(RESET)"
	$(PIP) install -e ".[all]"

toolchains: ## Install cross-compilation toolchains
	@echo "$(CYAN)Installing cross-compilation toolchains...$(RESET)"
	sudo apt update
	sudo apt install -y \
		gcc-aarch64-linux-gnu g++-aarch64-linux-gnu \
		gcc-riscv64-linux-gnu g++-riscv64-linux-gnu \
		gcc-mips64-linux-gnuabi64 \
		binutils-aarch64-linux-gnu \
		binutils-riscv64-linux-gnu \
		qemu-user qemu-user-static \
		nasm yasm

# =============================================================================
# DOCKER
# =============================================================================
docker-amd: ## Launch stack with AMD ROCm GPU
	@echo "$(CYAN)Launching AMD ROCm stack...$(RESET)"
	$(COMPOSE) $(COMPOSE_BASE) $(COMPOSE_AMD) $(COMPOSE_MON) --profile amd up -d
	@echo "$(GREEN)Stack running. OpenWebUI: http://localhost:3000 | Grafana: http://localhost:3001$(RESET)"

docker-nvidia: ## Launch stack with NVIDIA CUDA GPU
	@echo "$(CYAN)Launching NVIDIA CUDA stack...$(RESET)"
	$(COMPOSE) $(COMPOSE_BASE) $(COMPOSE_NV) $(COMPOSE_MON) --profile nvidia up -d
	@echo "$(GREEN)Stack running. OpenWebUI: http://localhost:3000 | Grafana: http://localhost:3001$(RESET)"

docker-cpu: ## Launch stack CPU-only (no GPU)
	@echo "$(CYAN)Launching CPU-only stack...$(RESET)"
	$(COMPOSE) $(COMPOSE_BASE) $(COMPOSE_MON) up -d

docker-down: ## Stop all containers
	@echo "$(YELLOW)Stopping all containers...$(RESET)"
	$(COMPOSE) $(COMPOSE_BASE) $(COMPOSE_AMD) $(COMPOSE_NV) $(COMPOSE_MON) down

docker-logs: ## Show container logs
	$(COMPOSE) $(COMPOSE_BASE) logs -f

docker-ps: ## Show running containers
	$(COMPOSE) $(COMPOSE_BASE) ps

docker-pull: ## Pull latest images
	$(COMPOSE) $(COMPOSE_BASE) $(COMPOSE_AMD) $(COMPOSE_NV) $(COMPOSE_MON) pull

# =============================================================================
# BUILD — CROSS ARCHITECTURE
# =============================================================================
build: arm64 riscv64 x86 ## Build all architectures
	@echo "$(GREEN)All architectures built successfully.$(RESET)"

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

x86: $(BUILD_DIR) ## Build x86_64 native
	@echo "$(CYAN)Building x86_64...$(RESET)"
	nasm -f elf64 $(SRC_DIR)/x86_64/hello.asm -o $(BUILD_DIR)/hello_x86.o
	ld $(BUILD_DIR)/hello_x86.o -o $(BUILD_DIR)/hello_x86
	gcc $(SRC_DIR)/c/main.c -O2 -o $(BUILD_DIR)/bench_x86
	@echo "$(GREEN)x86_64 build complete.$(RESET)"

arm64: $(BUILD_DIR) ## Build ARM64 cross-compiled
	@echo "$(CYAN)Building ARM64...$(RESET)"
	$(AS_ARM64) $(SRC_DIR)/arm64/hello.s -o $(BUILD_DIR)/hello_arm64.o
	$(LD_ARM64) $(BUILD_DIR)/hello_arm64.o -o $(BUILD_DIR)/hello_arm64
	$(CC_ARM64) $(SRC_DIR)/c/main.c -O2 -o $(BUILD_DIR)/bench_arm64
	@echo "$(GREEN)ARM64 build complete.$(RESET)"

riscv64: $(BUILD_DIR) ## Build RISC-V64 cross-compiled
	@echo "$(CYAN)Building RISC-V64...$(RESET)"
	$(AS_RISCV64) $(SRC_DIR)/riscv64/hello.s -o $(BUILD_DIR)/hello_riscv64.o
	$(LD_RISCV64) $(BUILD_DIR)/hello_riscv64.o -o $(BUILD_DIR)/hello_riscv64
	$(CC_RISCV64) $(SRC_DIR)/c/main.c -O2 -o $(BUILD_DIR)/bench_riscv64
	@echo "$(GREEN)RISC-V64 build complete.$(RESET)"

mips64: $(BUILD_DIR) ## Build MIPS64 cross-compiled
	@echo "$(CYAN)Building MIPS64...$(RESET)"
	$(CC_MIPS64) $(SRC_DIR)/c/main.c -O2 -o $(BUILD_DIR)/bench_mips64
	@echo "$(GREEN)MIPS64 build complete.$(RESET)"

wasm: $(BUILD_DIR) ## Build WebAssembly
	@echo "$(CYAN)Building WebAssembly...$(RESET)"
	wat2wasm $(SRC_DIR)/wasm/bench.wat -o $(BUILD_DIR)/bench.wasm
	@echo "$(GREEN)WASM build complete.$(RESET)"

rust: ## Build Rust benchmarks
	@echo "$(CYAN)Building Rust...$(RESET)"
	cd $(SRC_DIR)/rust && cargo build --release
	cp $(SRC_DIR)/rust/target/release/agi-bench-rs $(BUILD_DIR)/
	@echo "$(GREEN)Rust build complete.$(RESET)"

# =============================================================================
# QEMU VALIDATION
# =============================================================================
qemu: ## Run QEMU validation for all cross-compiled binaries
	@echo "$(CYAN)Running QEMU validation...$(RESET)"
	@echo "ARM64:"
	$(QEMU_ARM64) $(BUILD_DIR)/hello_arm64 && echo "$(GREEN)ARM64 OK$(RESET)" || echo "$(RED)ARM64 FAIL$(RESET)"
	@echo "RISC-V64:"
	$(QEMU_RISCV64) $(BUILD_DIR)/hello_riscv64 && echo "$(GREEN)RISC-V64 OK$(RESET)" || echo "$(RED)RISC-V64 FAIL$(RESET)"

# =============================================================================
# BENCHMARK
# =============================================================================
benchmark: ## Run full benchmark suite
	@echo "$(CYAN)Running full benchmark suite...$(RESET)"
	mkdir -p $(REPORT_DIR)
	$(PYTHON) benchmark/runner.py --full --export csv json --charts
	@echo "$(GREEN)Benchmark complete. Reports in $(REPORT_DIR)/$(RESET)"

bench-ollama: ## Benchmark Ollama only
	$(PYTHON) benchmark/benchmark_ollama.py

bench-onnx: ## Benchmark ONNX Runtime only
	$(PYTHON) benchmark/benchmark_onnx.py

bench-llamacpp: ## Benchmark llama.cpp only
	$(PYTHON) benchmark/benchmark_llamacpp.py

bench-pytorch: ## Benchmark PyTorch only
	$(PYTHON) benchmark/benchmark_pytorch.py

bench-vllm: ## Benchmark vLLM only
	$(PYTHON) benchmark/benchmark_vllm.py

bench-cpu: ## Benchmark CPU only
	$(PYTHON) benchmark/benchmark_cpu.py

bench-gpu-amd: ## Collect AMD GPU metrics
	bash scripts/collect_rocm.sh

bench-gpu-nvidia: ## Collect NVIDIA GPU metrics
	bash scripts/collect_cuda.sh

charts: ## Generate benchmark charts
	@echo "$(CYAN)Generating charts...$(RESET)"
	$(PYTHON) benchmark/generate_charts.py
	@echo "$(GREEN)Charts saved to $(REPORT_DIR)/$(RESET)"

report: ## Generate HTML report
	@echo "$(CYAN)Generating HTML report...$(RESET)"
	$(PYTHON) benchmark/generate_html_report.py
	@echo "$(GREEN)Report: $(REPORT_DIR)/report.html$(RESET)"

# =============================================================================
# QUALITY
# =============================================================================
test: ## Run test suite
	$(PYTHON) -m pytest tests/ -v --tb=short

test-cov: ## Run tests with coverage
	$(PYTHON) -m pytest tests/ --cov=benchmark --cov=collectors --cov=agents \
		--cov-report=html --cov-report=term-missing

lint: ## Run linter
	$(PYTHON) -m ruff check benchmark/ collectors/ agents/ azure/

format: ## Format code
	$(PYTHON) -m black benchmark/ collectors/ agents/ azure/
	$(PYTHON) -m ruff check --fix benchmark/ collectors/ agents/ azure/

typecheck: ## Run type checker
	$(PYTHON) -m mypy benchmark/ collectors/ agents/

# =============================================================================
# AZURE / CLOUD
# =============================================================================
azure: ## Deploy to Microsoft Azure
	@echo "$(CYAN)Deploying to Microsoft Azure...$(RESET)"
	bash scripts/azure_deploy.sh

deploy: ## Full cloud deployment (Azure ML + Functions)
	$(PYTHON) azure/azure_ml_pipeline.py --deploy

# =============================================================================
# UTILITIES
# =============================================================================
status: ## Show system status
	@echo "$(CYAN)=== System Status ===$(RESET)"
	@echo "Docker containers:"
	@docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || echo "Docker not running"
	@echo ""
	@echo "GPU Status:"
	@rocm-smi 2>/dev/null || nvidia-smi 2>/dev/null || echo "No GPU tools found"
	@echo ""
	@echo "Ollama models:"
	@ollama list 2>/dev/null || echo "Ollama not running"

logs: ## Show benchmark logs
	tail -f $(REPORT_DIR)/benchmark.log 2>/dev/null || echo "No log file found"

clean: ## Clean build artifacts and reports
	@echo "$(YELLOW)Cleaning build artifacts...$(RESET)"
	rm -rf $(BUILD_DIR)/
	rm -rf $(REPORT_DIR)/*.csv $(REPORT_DIR)/*.json $(REPORT_DIR)/*.png $(REPORT_DIR)/*.html
	find . -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
	find . -name "*.pyc" -delete 2>/dev/null || true
	find . -name "*.o" -delete 2>/dev/null || true
	@echo "$(GREEN)Clean complete.$(RESET)"

clean-docker: ## Remove all Docker containers and volumes
	@echo "$(RED)WARNING: This will remove all containers and volumes!$(RESET)"
	$(COMPOSE) $(COMPOSE_BASE) $(COMPOSE_AMD) $(COMPOSE_NV) $(COMPOSE_MON) down -v --remove-orphans

version: ## Show version
	@echo "$(PROJECT) v$(VERSION)"
	@echo "Microsoft Corporation — Exclusive License"
	@$(PYTHON) --version
	@docker --version 2>/dev/null || echo "Docker not found"
	@rocminfo --version 2>/dev/null || true
	@nvidia-smi --version 2>/dev/null || true