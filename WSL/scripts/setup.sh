#!/usr/bin/env bash
# =============================================================================
# Windows AGI Benchmark Lab — Full Environment Setup Script
# Copyright (c) 2026 Microsoft Corporation. All Rights Reserved.
# =============================================================================
# Supports:
#   - Ubuntu 22.04 / 24.04 LTS (native or WSL2)
#   - Fedora 39/40
#   - Arch Linux
#   - Debian 12
#
# Usage:
#   bash scripts/setup.sh [--gpu amd|nvidia|none] [--skip-docker] [--skip-rocm]
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Colors
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
GPU_VENDOR="${GPU_VENDOR:-auto}"
SKIP_DOCKER="${SKIP_DOCKER:-false}"
SKIP_ROCM="${SKIP_ROCM:-false}"
SKIP_CUDA="${SKIP_CUDA:-false}"
SKIP_OLLAMA="${SKIP_OLLAMA:-false}"
INSTALL_QEMU="${INSTALL_QEMU:-true}"
INSTALL_RUST="${INSTALL_RUST:-true}"
LOG_FILE="/tmp/agi-bench-setup-$(date +%Y%m%d_%H%M%S).log"

# ---------------------------------------------------------------------------
# Argument Parsing
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case $1 in
        --gpu)
            GPU_VENDOR="$2"
            shift 2
            ;;
        --skip-docker)
            SKIP_DOCKER=true
            shift
            ;;
        --skip-rocm)
            SKIP_ROCM=true
            shift
            ;;
        --skip-cuda)
            SKIP_CUDA=true
            shift
            ;;
        --skip-ollama)
            SKIP_OLLAMA=true
            shift
            ;;
        --no-rust)
            INSTALL_RUST=false
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --gpu amd|nvidia|none   GPU vendor (default: auto-detect)"
            echo "  --skip-docker           Skip Docker installation"
            echo "  --skip-rocm             Skip AMD ROCm installation"
            echo "  --skip-cuda             Skip NVIDIA CUDA setup"
            echo "  --skip-ollama           Skip Ollama installation"
            echo "  --no-rust               Skip Rust installation"
            echo "  --help                  Show this help"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
log() {
    local level="$1"
    shift
    local msg="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    case "$level" in
        INFO)  echo -e "${GREEN}[INFO]${RESET}  ${msg}" | tee -a "$LOG_FILE" ;;
        WARN)  echo -e "${YELLOW}[WARN]${RESET}  ${msg}" | tee -a "$LOG_FILE" ;;
        ERROR) echo -e "${RED}[ERROR]${RESET} ${msg}" | tee -a "$LOG_FILE" ;;
        STEP)  echo -e "\n${CYAN}${BOLD}==> ${msg}${RESET}" | tee -a "$LOG_FILE" ;;
        *)     echo -e "${msg}" | tee -a "$LOG_FILE" ;;
    esac
}

# ---------------------------------------------------------------------------
# System Detection
# ---------------------------------------------------------------------------
detect_os() {
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        OS_ID="${ID:-unknown}"
        OS_VERSION="${VERSION_ID:-unknown}"
    else
        OS_ID="unknown"
        OS_VERSION="unknown"
    fi

    # WSL2 detection
    IS_WSL2=false
    if grep -qi microsoft /proc/version 2>/dev/null; then
        IS_WSL2=true
    fi

    # Architecture
    ARCH=$(uname -m)

    log INFO "OS: ${OS_ID} ${OS_VERSION} | Arch: ${ARCH} | WSL2: ${IS_WSL2}"
}

detect_gpu() {
    if [[ "$GPU_VENDOR" != "auto" ]]; then
        log INFO "GPU vendor specified: ${GPU_VENDOR}"
        return
    fi

    # Try NVIDIA
    if command -v nvidia-smi &>/dev/null; then
        GPU_VENDOR="nvidia"
        GPU_MODEL=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1 || echo "Unknown NVIDIA")
        log INFO "Detected NVIDIA GPU: ${GPU_MODEL}"
        return
    fi

    # Try AMD
    if command -v rocm-smi &>/dev/null || lspci 2>/dev/null | grep -qi "AMD\|Radeon"; then
        GPU_VENDOR="amd"
        log INFO "Detected AMD GPU"
        return
    fi

    GPU_VENDOR="none"
    log INFO "No discrete GPU detected — CPU-only mode"
}

# ---------------------------------------------------------------------------
# Package Installation
# ---------------------------------------------------------------------------
install_base_packages() {
    log STEP "Installing base packages"

    case "$OS_ID" in
        ubuntu|debian)
            sudo apt-get update -qq
            sudo apt-get install -y --no-install-recommends \
                build-essential \
                cmake \
                ninja-build \
                git \
                curl \
                wget \
                jq \
                htop \
                tmux \
                vim \
                tree \
                rsync \
                zip \
                unzip \
                ca-certificates \
                gnupg \
                lsb-release \
                software-properties-common \
                apt-transport-https \
                python3 \
                python3-pip \
                python3-venv \
                python3-dev \
                libssl-dev \
                libffi-dev \
                libgomp1 \
                pkg-config \
                nasm \
                yasm \
                sysbench \
                fio \
                iperf3 \
                bc \
                pciutils \
                usbutils
            ;;
        fedora)
            sudo dnf install -y \
                gcc gcc-c++ cmake ninja-build git curl wget jq htop tmux vim \
                tree rsync zip unzip ca-certificates gnupg \
                python3 python3-pip python3-devel \
                openssl-devel libffi-devel \
                nasm yasm sysbench fio iperf3 bc pciutils
            ;;
        arch)
            sudo pacman -Syu --noconfirm \
                base-devel cmake ninja git curl wget jq htop tmux vim \
                tree rsync zip unzip ca-certificates gnupg \
                python python-pip \
                openssl libffi \
                nasm yasm sysbench fio iperf3 bc pciutils
            ;;
        *)
            log WARN "Unknown OS: ${OS_ID} — attempting apt-get"
            sudo apt-get update -qq && sudo apt-get install -y build-essential python3 python3-pip git curl wget || true
            ;;
    esac

    log INFO "Base packages installed"
}

install_cross_compilation_toolchains() {
    log STEP "Installing cross-compilation toolchains"

    case "$OS_ID" in
        ubuntu|debian)
            sudo apt-get install -y --no-install-recommends \
                gcc-aarch64-linux-gnu \
                g++-aarch64-linux-gnu \
                binutils-aarch64-linux-gnu \
                gcc-riscv64-linux-gnu \
                g++-riscv64-linux-gnu \
                binutils-riscv64-linux-gnu \
                libc6-dev-arm64-cross \
                libc6-dev-riscv64-cross || true

            # MIPS64 (may not be available on all Ubuntu versions)
            sudo apt-get install -y \
                gcc-mips64-linux-gnuabi64 \
                binutils-mips64-linux-gnuabi64 || log WARN "MIPS64 toolchain not available"
            ;;
        fedora)
            sudo dnf install -y \
                gcc-aarch64-linux-gnu \
                gcc-riscv64-linux-gnu || true
            ;;
        *)
            log WARN "Cross-compilation toolchains: manual installation required for ${OS_ID}"
            ;;
    esac

    log INFO "Cross-compilation toolchains installed"
}

install_qemu() {
    if [[ "$INSTALL_QEMU" != "true" ]]; then
        log INFO "Skipping QEMU installation"
        return
    fi

    log STEP "Installing QEMU user-mode emulation"

    case "$OS_ID" in
        ubuntu|debian)
            sudo apt-get install -y --no-install-recommends \
                qemu-user \
                qemu-user-static \
                binfmt-support
            # Register binfmt handlers
            sudo update-binfmts --enable qemu-aarch64 2>/dev/null || true
            sudo update-binfmts --enable qemu-riscv64 2>/dev/null || true
            ;;
        fedora)
            sudo dnf install -y qemu-user qemu-user-binfmt || true
            ;;
        arch)
            sudo pacman -S --noconfirm qemu-user-static || true
            ;;
    esac

    # Verify QEMU
    if command -v qemu-aarch64 &>/dev/null; then
        log INFO "QEMU ARM64: $(qemu-aarch64 --version | head -1)"
    fi
    if command -v qemu-riscv64 &>/dev/null; then
        log INFO "QEMU RISC-V: $(qemu-riscv64 --version | head -1)"
    fi
}

install_python_packages() {
    log STEP "Installing Python packages"

    # Upgrade pip
    python3 -m pip install --upgrade pip setuptools wheel

    # Core packages
    pip3 install \
        requests \
        httpx \
        aiohttp \
        pydantic \
        pydantic-settings \
        typer \
        rich \
        loguru \
        pyyaml \
        toml \
        tqdm \
        click \
        psutil \
        prometheus-client

    # Data & visualization
    pip3 install \
        pandas \
        numpy \
        matplotlib \
        seaborn \
        plotly \
        kaleido

    # AI/ML
    pip3 install \
        onnxruntime \
        transformers \
        accelerate \
        langchain \
        langchain-community \
        openai

    # Vector & cache
    pip3 install \
        qdrant-client \
        redis \
        celery

    # Azure SDK
    pip3 install \
        azure-ai-ml \
        azure-identity \
        azure-storage-blob \
        azure-monitor-opentelemetry || log WARN "Azure SDK installation failed — skipping"

    log INFO "Python packages installed"
}

install_docker() {
    if [[ "$SKIP_DOCKER" == "true" ]]; then
        log INFO "Skipping Docker installation"
        return
    fi

    if command -v docker &>/dev/null; then
        log INFO "Docker already installed: $(docker --version)"
        return
    fi

    log STEP "Installing Docker Engine"

    case "$OS_ID" in
        ubuntu|debian)
            # Add Docker's official GPG key
            sudo install -m 0755 -d /etc/apt/keyrings
            curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
                sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            sudo chmod a+r /etc/apt/keyrings/docker.gpg

            # Add Docker repository
            echo \
                "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
                https://download.docker.com/linux/ubuntu \
                $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
                sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

            sudo apt-get update -qq
            sudo apt-get install -y \
                docker-ce \
                docker-ce-cli \
                containerd.io \
                docker-buildx-plugin \
                docker-compose-plugin
            ;;
        fedora)
            sudo dnf install -y docker docker-compose
            ;;
        arch)
            sudo pacman -S --noconfirm docker docker-compose
            ;;
    esac

    # Add user to docker group
    sudo usermod -aG docker "$USER"
    sudo systemctl enable --now docker

    log INFO "Docker installed: $(docker --version)"
    log WARN "Log out and back in for Docker group membership to take effect"
}

install_rocm() {
    if [[ "$SKIP_ROCM" == "true" ]] || [[ "$GPU_VENDOR" != "amd" ]]; then
        log INFO "Skipping AMD ROCm installation"
        return
    fi

    log STEP "Installing AMD ROCm"

    # Add user to required groups
    sudo usermod -aG render "$USER" 2>/dev/null || true
    sudo usermod -aG video "$USER" 2>/dev/null || true

    case "$OS_ID" in
        ubuntu)
            # Download and install amdgpu-install
            ROCM_VERSION="6.1"
            AMDGPU_DEB="amdgpu-install_6.1.60100-1_all.deb"
            AMDGPU_URL="https://repo.radeon.com/amdgpu-install/${ROCM_VERSION}/ubuntu/jammy/${AMDGPU_DEB}"

            wget -q "$AMDGPU_URL" -O "/tmp/${AMDGPU_DEB}" || {
                log WARN "Failed to download amdgpu-install — skipping ROCm"
                return
            }

            sudo dpkg -i "/tmp/${AMDGPU_DEB}"
            sudo amdgpu-install --usecase=rocm --no-dkms -y || log WARN "ROCm installation failed"
            ;;
        *)
            log WARN "ROCm auto-install not supported for ${OS_ID} — install manually"
            log INFO "See: https://rocm.docs.amd.com/en/latest/deploy/linux/index.html"
            ;;
    esac

    # Verify ROCm
    if command -v rocminfo &>/dev/null; then
        log INFO "ROCm installed: $(rocminfo | grep 'ROCm' | head -1 || echo 'ROCm available')"
    fi
}

install_ollama() {
    if [[ "$SKIP_OLLAMA" == "true" ]]; then
        log INFO "Skipping Ollama installation"
        return
    fi

    if command -v ollama &>/dev/null; then
        log INFO "Ollama already installed: $(ollama --version 2>/dev/null || echo 'installed')"
        return
    fi

    log STEP "Installing Ollama"

    curl -fsSL https://ollama.ai/install.sh | sh || {
        log WARN "Ollama installation failed — install manually from https://ollama.ai"
        return
    }

    log INFO "Ollama installed"
    log INFO "Start Ollama: ollama serve"
    log INFO "Pull a model: ollama pull llama3"
}

install_rust() {
    if [[ "$INSTALL_RUST" != "true" ]]; then
        log INFO "Skipping Rust installation"
        return
    fi

    if command -v cargo &>/dev/null; then
        log INFO "Rust already installed: $(rustc --version)"
        return
    fi

    log STEP "Installing Rust"

    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable

    # Source cargo env
    source "$HOME/.cargo/env"

    # Add cross-compilation targets
    rustup target add aarch64-unknown-linux-gnu
    rustup target add riscv64gc-unknown-linux-gnu
    rustup target add wasm32-unknown-unknown

    log INFO "Rust installed: $(rustc --version)"
    log INFO "Cargo: $(cargo --version)"
}

install_llamacpp() {
    log STEP "Building llama.cpp"

    if [[ -d "llama.cpp" ]]; then
        log INFO "llama.cpp already cloned — updating"
        cd llama.cpp && git pull && cd ..
    else
        git clone --depth 1 https://github.com/ggerganov/llama.cpp
    fi

    cd llama.cpp

    # Build with GPU support if available
    if [[ "$GPU_VENDOR" == "nvidia" ]]; then
        cmake -B build -DLLAMA_CUDA=ON -DCMAKE_BUILD_TYPE=Release
    elif [[ "$GPU_VENDOR" == "amd" ]]; then
        cmake -B build -DLLAMA_HIPBLAS=ON -DCMAKE_BUILD_TYPE=Release
    else
        cmake -B build -DCMAKE_BUILD_TYPE=Release
    fi

    cmake --build build --config Release -j"$(nproc)" || log WARN "llama.cpp build failed"

    cd ..
    log INFO "llama.cpp build complete"
}

# ---------------------------------------------------------------------------
# Verification
# ---------------------------------------------------------------------------
verify_installation() {
    log STEP "Verifying installation"

    local errors=0

    check() {
        local name="$1"
        local cmd="$2"
        if eval "$cmd" &>/dev/null; then
            log INFO "✅ ${name}"
        else
            log WARN "❌ ${name} — not found or failed"
            ((errors++)) || true
        fi
    }

    check "Python 3"          "python3 --version"
    check "pip"               "pip3 --version"
    check "gcc"               "gcc --version"
    check "nasm"              "nasm --version"
    check "git"               "git --version"
    check "curl"              "curl --version"
    check "docker"            "docker --version"
    check "ARM64 toolchain"   "aarch64-linux-gnu-gcc --version"
    check "RISC-V toolchain"  "riscv64-linux-gnu-gcc --version"
    check "QEMU ARM64"        "qemu-aarch64 --version"
    check "QEMU RISC-V"       "qemu-riscv64 --version"
    check "ollama"            "ollama --version"
    check "cargo (Rust)"      "cargo --version"

    if [[ "$GPU_VENDOR" == "amd" ]]; then
        check "rocm-smi"      "rocm-smi --version"
        check "rocminfo"      "rocminfo"
    elif [[ "$GPU_VENDOR" == "nvidia" ]]; then
        check "nvidia-smi"    "nvidia-smi"
        check "nvcc"          "nvcc --version"
    fi

    if [[ $errors -eq 0 ]]; then
        log INFO "All checks passed!"
    else
        log WARN "${errors} check(s) failed — some features may not work"
    fi
}

# ---------------------------------------------------------------------------
# Print Summary
# ---------------------------------------------------------------------------
print_summary() {
    echo ""
    echo -e "${CYAN}${BOLD}=================================================================${RESET}"
    echo -e "${CYAN}${BOLD}  Windows AGI Benchmark Lab — Setup Complete${RESET}"
    echo -e "${CYAN}${BOLD}  Microsoft Corporation — Exclusive License${RESET}"
    echo -e "${CYAN}${BOLD}=================================================================${RESET}"
    echo ""
    echo -e "  ${GREEN}OS:${RESET}          ${OS_ID} ${OS_VERSION}"
    echo -e "  ${GREEN}Architecture:${RESET} ${ARCH}"
    echo -e "  ${GREEN}WSL2:${RESET}        ${IS_WSL2}"
    echo -e "  ${GREEN}GPU Vendor:${RESET}  ${GPU_VENDOR}"
    echo ""
    echo -e "  ${YELLOW}Next Steps:${RESET}"
    echo ""
    echo -e "  1. Launch Docker stack (AMD GPU):"
    echo -e "     ${BLUE}docker compose --profile amd -f docker/docker-compose.yml \\"
    echo -e "       -f docker/docker-compose.amd.yml \\"
    echo -e "       -f docker/docker-compose.monitoring.yml up -d${RESET}"
    echo ""
    echo -e "  2. Pull an LLM model:"
    echo -e "     ${BLUE}ollama pull llama3${RESET}"
    echo ""
    echo -e "  3. Run benchmarks:"
    echo -e "     ${BLUE}python benchmark/runner.py --full --export csv json --charts${RESET}"
    echo ""
    echo -e "  4. View dashboards:"
    echo -e "     ${BLUE}OpenWebUI:  http://localhost:3000${RESET}"
    echo -e "     ${BLUE}Grafana:    http://localhost:3001${RESET}"
    echo -e "     ${BLUE}Prometheus: http://localhost:9090${RESET}"
    echo ""
    echo -e "  ${YELLOW}Log file:${RESET} ${LOG_FILE}"
    echo ""
    echo -e "${CYAN}${BOLD}=================================================================${RESET}"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    echo -e "${CYAN}${BOLD}"
    echo "================================================================="
    echo "  Windows AGI Benchmark Lab — Environment Setup"
    echo "  Microsoft Corporation — Exclusive License"
    echo "================================================================="
    echo -e "${RESET}"

    log INFO "Setup started at $(date)"
    log INFO "Log file: ${LOG_FILE}"

    detect_os
    detect_gpu

    install_base_packages
    install_cross_compilation_toolchains
    install_qemu
    install_python_packages
    install_docker
    install_rocm
    install_ollama
    install_rust

    # Build llama.cpp (optional — comment out if not needed)
    # install_llamacpp

    verify_installation
    print_summary

    log INFO "Setup complete at $(date)"
}

main "$@"