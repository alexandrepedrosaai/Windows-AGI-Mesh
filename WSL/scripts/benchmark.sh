#!/usr/bin/env bash
# =============================================================================
# Windows AGI Benchmark Lab — Benchmark Runner Script
# Copyright (c) 2026 Microsoft Corporation. All Rights Reserved.
# =============================================================================
# Runs the complete benchmark suite and generates reports.
#
# Usage:
#   bash scripts/benchmark.sh [OPTIONS]
#
# Options:
#   --suite all|cpu|memory|ollama|onnx|pytorch|llamacpp|assembly
#   --gpu amd|nvidia|none|auto
#   --models llama3,phi4,mistral
#   --export csv,json
#   --charts
#   --report
#   --duration <seconds>
#   --output <dir>
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Colors & Logging
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="benchmark/reports/benchmark_${TIMESTAMP}.log"
REPORT_DIR="benchmark/reports"

log()  { echo -e "${GREEN}[$(date '+%H:%M:%S')]${RESET} $*" | tee -a "$LOG_FILE"; }
warn() { echo -e "${YELLOW}[WARN]${RESET} $*" | tee -a "$LOG_FILE"; }
err()  { echo -e "${RED}[ERROR]${RESET} $*" | tee -a "$LOG_FILE"; }
step() { echo -e "\n${CYAN}${BOLD}==> $*${RESET}" | tee -a "$LOG_FILE"; }

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
SUITE="cpu,memory"
GPU_VENDOR="auto"
MODELS="llama3,phi4"
EXPORT_FORMATS="csv,json"
GENERATE_CHARTS=false
GENERATE_REPORT=false
DURATION=60
OUTPUT_DIR="$REPORT_DIR"
VERBOSE=false
DRY_RUN=false

# ---------------------------------------------------------------------------
# Argument Parsing
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case $1 in
        --suite)       SUITE="$2";          shift 2 ;;
        --gpu)         GPU_VENDOR="$2";     shift 2 ;;
        --models)      MODELS="$2";         shift 2 ;;
        --export)      EXPORT_FORMATS="$2"; shift 2 ;;
        --charts)      GENERATE_CHARTS=true; shift ;;
        --report)      GENERATE_REPORT=true; shift ;;
        --duration)    DURATION="$2";       shift 2 ;;
        --output)      OUTPUT_DIR="$2";     shift 2 ;;
        --verbose|-v)  VERBOSE=true;        shift ;;
        --dry-run)     DRY_RUN=true;        shift ;;
        --full)
            SUITE="all"
            GENERATE_CHARTS=true
            GENERATE_REPORT=true
            shift
            ;;
        --help|-h)
            cat << 'EOF'
Windows AGI Benchmark Lab — Benchmark Runner
Microsoft Corporation — Exclusive License

Usage: bash scripts/benchmark.sh [OPTIONS]

Options:
  --suite SUITES      Comma-separated suites: all,cpu,memory,ollama,onnx,pytorch,llamacpp,assembly
  --gpu VENDOR        GPU vendor: amd, nvidia, none, auto (default: auto)
  --models MODELS     Comma-separated LLM models (default: llama3,phi4)
  --export FORMATS    Export formats: csv,json (default: csv,json)
  --charts            Generate benchmark charts
  --report            Generate HTML report
  --duration SECS     Benchmark duration in seconds (default: 60)
  --output DIR        Output directory (default: benchmark/reports)
  --verbose           Verbose output
  --dry-run           Show what would be run without executing
  --full              Run all suites with charts and report
  --help              Show this help

Examples:
  bash scripts/benchmark.sh --full
  bash scripts/benchmark.sh --suite cpu,memory --export csv,json
  bash scripts/benchmark.sh --suite ollama --models llama3,phi4 --charts
  bash scripts/benchmark.sh --suite onnx --gpu amd
EOF
            exit 0
            ;;
        *)
            err "Unknown option: $1"
            exit 1
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------
mkdir -p "$OUTPUT_DIR"
mkdir -p "$(dirname "$LOG_FILE")"

print_header() {
    echo -e "${CYAN}${BOLD}"
    echo "================================================================="
    echo "  Windows AGI Benchmark Lab"
    echo "  Microsoft Corporation — Exclusive License"
    echo "================================================================="
    echo -e "${RESET}"
    echo "  Timestamp:  $TIMESTAMP"
    echo "  Suite:      $SUITE"
    echo "  GPU:        $GPU_VENDOR"
    echo "  Models:     $MODELS"
    echo "  Export:     $EXPORT_FORMATS"
    echo "  Charts:     $GENERATE_CHARTS"
    echo "  Report:     $GENERATE_REPORT"
    echo "  Output:     $OUTPUT_DIR"
    echo "  Log:        $LOG_FILE"
    echo ""
}

# ---------------------------------------------------------------------------
# GPU Detection
# ---------------------------------------------------------------------------
detect_gpu() {
    if [[ "$GPU_VENDOR" != "auto" ]]; then
        log "GPU vendor: $GPU_VENDOR (specified)"
        return
    fi

    if command -v nvidia-smi &>/dev/null && nvidia-smi &>/dev/null; then
        GPU_VENDOR="nvidia"
        GPU_MODEL=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)
        log "Detected NVIDIA GPU: $GPU_MODEL"
    elif command -v rocm-smi &>/dev/null && rocm-smi &>/dev/null; then
        GPU_VENDOR="amd"
        log "Detected AMD GPU"
    else
        GPU_VENDOR="none"
        log "No GPU detected — CPU-only mode"
    fi
}

# ---------------------------------------------------------------------------
# Benchmark Functions
# ---------------------------------------------------------------------------
run_cpu_benchmark() {
    step "CPU Benchmark"
    local cmd="python3 benchmark/benchmark_cpu.py --output ${OUTPUT_DIR}/cpu_results.json"
    [[ "$VERBOSE" == "true" ]] && cmd="$cmd --verbose"

    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] $cmd"
        return
    fi

    log "Starting CPU benchmark..."
    if eval "$cmd"; then
        log "CPU benchmark complete ✅"
    else
        warn "CPU benchmark failed ⚠️"
    fi
}

run_memory_benchmark() {
    step "Memory Benchmark"
    local cmd="python3 benchmark/benchmark_cpu.py --output ${OUTPUT_DIR}/memory_results.json"

    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] $cmd"
        return
    fi

    log "Starting memory benchmark..."
    if eval "$cmd"; then
        log "Memory benchmark complete ✅"
    else
        warn "Memory benchmark failed ⚠️"
    fi
}

run_ollama_benchmark() {
    step "Ollama LLM Benchmark"

    # Check if Ollama is running
    if ! curl -sf http://localhost:11434/api/tags &>/dev/null; then
        warn "Ollama not running at localhost:11434"
        warn "Start with: ollama serve"
        return
    fi

    local models_arg
    models_arg=$(echo "$MODELS" | tr ',' ' ')
    local cmd="python3 benchmark/benchmark_ollama.py --models $models_arg --output ${OUTPUT_DIR}/ollama_results.json"
    [[ "$VERBOSE" == "true" ]] && cmd="$cmd --verbose"

    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] $cmd"
        return
    fi

    log "Starting Ollama benchmark with models: $MODELS"
    if eval "$cmd"; then
        log "Ollama benchmark complete ✅"
    else
        warn "Ollama benchmark failed ⚠️"
    fi
}

run_onnx_benchmark() {
    step "ONNX Runtime Benchmark"

    # Check if onnxruntime is installed
    if ! python3 -c "import onnxruntime" &>/dev/null; then
        warn "onnxruntime not installed — run: pip install onnxruntime"
        return
    fi

    local cmd="python3 benchmark/benchmark_onnx.py --output ${OUTPUT_DIR}/onnx_results.json"
    [[ "$VERBOSE" == "true" ]] && cmd="$cmd --verbose"

    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] $cmd"
        return
    fi

    log "Starting ONNX Runtime benchmark..."
    if eval "$cmd"; then
        log "ONNX benchmark complete ✅"
    else
        warn "ONNX benchmark failed ⚠️"
    fi
}

run_pytorch_benchmark() {
    step "PyTorch Benchmark"

    if ! python3 -c "import torch" &>/dev/null; then
        warn "PyTorch not installed — run: pip install torch"
        return
    fi

    local device="cpu"
    [[ "$GPU_VENDOR" == "nvidia" ]] && device="cuda"
    [[ "$GPU_VENDOR" == "amd" ]] && device="cuda"  # ROCm uses CUDA API

    local cmd="python3 benchmark/benchmark_pytorch.py --device $device --vendor $GPU_VENDOR --output ${OUTPUT_DIR}/pytorch_results.json"
    [[ "$VERBOSE" == "true" ]] && cmd="$cmd --verbose"

    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] $cmd"
        return
    fi

    log "Starting PyTorch benchmark (device=$device)..."
    if eval "$cmd"; then
        log "PyTorch benchmark complete ✅"
    else
        warn "PyTorch benchmark failed ⚠️"
    fi
}

run_llamacpp_benchmark() {
    step "llama.cpp Benchmark"

    if [[ ! -f "llama.cpp/build/bin/llama-cli" ]] && [[ ! -f "llama.cpp/build/bin/main" ]]; then
        warn "llama.cpp not built — run: bash scripts/build_llamacpp.sh"
        return
    fi

    local cmd="python3 benchmark/benchmark_llamacpp.py --output ${OUTPUT_DIR}/llamacpp_results.json"
    [[ "$VERBOSE" == "true" ]] && cmd="$cmd --verbose"

    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] $cmd"
        return
    fi

    log "Starting llama.cpp benchmark..."
    if eval "$cmd"; then
        log "llama.cpp benchmark complete ✅"
    else
        warn "llama.cpp benchmark failed ⚠️"
    fi
}

run_assembly_benchmark() {
    step "Assembly Benchmark"

    local results=()

    # x86_64
    if [[ -f "build/x86_64/bench_c" ]]; then
        log "Running x86_64 C benchmark..."
        if [[ "$DRY_RUN" != "true" ]]; then
            ./build/x86_64/bench_c 2>&1 | tee "${OUTPUT_DIR}/assembly_x86_results.txt" || true
        fi
        results+=("x86_64")
    fi

    # ARM64 via QEMU
    if [[ -f "build/arm64/bench_arm64" ]] && command -v qemu-aarch64 &>/dev/null; then
        log "Running ARM64 benchmark via QEMU..."
        if [[ "$DRY_RUN" != "true" ]]; then
            qemu-aarch64 -L /usr/aarch64-linux-gnu build/arm64/bench_arm64 2>&1 | \
                tee "${OUTPUT_DIR}/assembly_arm64_results.txt" || true
        fi
        results+=("arm64")
    fi

    # RISC-V via QEMU
    if [[ -f "build/riscv64/bench_riscv64" ]] && command -v qemu-riscv64 &>/dev/null; then
        log "Running RISC-V benchmark via QEMU..."
        if [[ "$DRY_RUN" != "true" ]]; then
            qemu-riscv64 -L /usr/riscv64-linux-gnu build/riscv64/bench_riscv64 2>&1 | \
                tee "${OUTPUT_DIR}/assembly_riscv64_results.txt" || true
        fi
        results+=("riscv64")
    fi

    log "Assembly benchmarks complete: ${results[*]:-none} ✅"
}

run_gpu_metrics() {
    step "GPU Metrics Collection"

    if [[ "$GPU_VENDOR" == "amd" ]]; then
        log "Collecting AMD ROCm metrics..."
        if [[ "$DRY_RUN" != "true" ]]; then
            python3 collectors/amd_rocm.py \
                --benchmark \
                --duration "$DURATION" \
                --output "${OUTPUT_DIR}/amd_metrics.json" || warn "AMD metrics collection failed"
        fi
    elif [[ "$GPU_VENDOR" == "nvidia" ]]; then
        log "Collecting NVIDIA CUDA metrics..."
        if [[ "$DRY_RUN" != "true" ]]; then
            python3 collectors/nvidia_cuda.py \
                --benchmark \
                --duration "$DURATION" \
                --output "${OUTPUT_DIR}/nvidia_metrics.json" || warn "NVIDIA metrics collection failed"
        fi
    else
        log "No GPU — skipping GPU metrics"
    fi
}

run_system_metrics() {
    step "System Metrics Collection"

    if [[ "$DRY_RUN" != "true" ]]; then
        python3 collectors/system_metrics.py \
            --output "${OUTPUT_DIR}/system_metrics.json" || warn "System metrics collection failed"
    else
        log "[DRY RUN] python3 collectors/system_metrics.py"
    fi
}

generate_charts() {
    if [[ "$GENERATE_CHARTS" != "true" ]]; then
        return
    fi

    step "Generating Charts"

    if [[ "$DRY_RUN" != "true" ]]; then
        python3 benchmark/generate_charts.py \
            --input "${OUTPUT_DIR}/benchmark_latest.csv" \
            --output "$OUTPUT_DIR" \
            --sample \
            --verbose || warn "Chart generation failed"
        log "Charts saved to: $OUTPUT_DIR"
    else
        log "[DRY RUN] python3 benchmark/generate_charts.py"
    fi
}

generate_report() {
    if [[ "$GENERATE_REPORT" != "true" ]]; then
        return
    fi

    step "Generating HTML Report"

    if [[ "$DRY_RUN" != "true" ]]; then
        python3 benchmark/generate_html_report.py \
            --csv "${OUTPUT_DIR}/benchmark_latest.csv" \
            --json "${OUTPUT_DIR}/benchmark_latest.json" \
            --output "${OUTPUT_DIR}/report_${TIMESTAMP}.html" || warn "Report generation failed"

        # Copy as latest
        cp "${OUTPUT_DIR}/report_${TIMESTAMP}.html" "${OUTPUT_DIR}/report.html" 2>/dev/null || true
        log "HTML report: ${OUTPUT_DIR}/report.html"
    else
        log "[DRY RUN] python3 benchmark/generate_html_report.py"
    fi
}

# ---------------------------------------------------------------------------
# Main Execution
# ---------------------------------------------------------------------------
print_header
detect_gpu

log "Starting benchmark suite: $SUITE"
START_TIME=$(date +%s)

# Parse suite list
IFS=',' read -ra SUITES <<< "$SUITE"

for suite in "${SUITES[@]}"; do
    suite=$(echo "$suite" | tr -d ' ')
    case "$suite" in
        all)
            run_cpu_benchmark
            run_memory_benchmark
            run_ollama_benchmark
            run_onnx_benchmark
            run_pytorch_benchmark
            run_llamacpp_benchmark
            run_assembly_benchmark
            run_gpu_metrics
            run_system_metrics
            ;;
        cpu)        run_cpu_benchmark ;;
        memory)     run_memory_benchmark ;;
        ollama)     run_ollama_benchmark ;;
        onnx)       run_onnx_benchmark ;;
        pytorch)    run_pytorch_benchmark ;;
        llamacpp)   run_llamacpp_benchmark ;;
        assembly)   run_assembly_benchmark ;;
        gpu)        run_gpu_metrics ;;
        system)     run_system_metrics ;;
        *)
            warn "Unknown suite: $suite — skipping"
            ;;
    esac
done

# Post-processing
generate_charts
generate_report

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

echo ""
echo -e "${CYAN}${BOLD}=================================================================${RESET}"
echo -e "${CYAN}${BOLD}  Benchmark Complete${RESET}"
echo -e "${CYAN}${BOLD}=================================================================${RESET}"
echo ""
echo -e "  ${GREEN}Duration:${RESET}  ${ELAPSED}s"
echo -e "  ${GREEN}Output:${RESET}    ${OUTPUT_DIR}/"
echo -e "  ${GREEN}Log:${RESET}       ${LOG_FILE}"
echo ""

# List generated files
if [[ "$DRY_RUN" != "true" ]]; then
    echo -e "  ${YELLOW}Generated Files:${RESET}"
    find "$OUTPUT_DIR" -newer "$LOG_FILE" -type f 2>/dev/null | sort | while read -r f; do
        size=$(du -sh "$f" 2>/dev/null | cut -f1)
        echo -e "    ${BLUE}${f}${RESET} (${size})"
    done
fi

echo ""
echo -e "  ${YELLOW}View Results:${RESET}"
echo -e "    ${BLUE}cat ${OUTPUT_DIR}/benchmark_latest.json | jq .meta${RESET}"
[[ "$GENERATE_REPORT" == "true" ]] && \
    echo -e "    ${BLUE}open ${OUTPUT_DIR}/report.html${RESET}"
echo ""
echo -e "${CYAN}${BOLD}  Microsoft Corporation — Windows AGI Benchmark Lab${RESET}"
echo -e "${CYAN}${BOLD}=================================================================${RESET}"