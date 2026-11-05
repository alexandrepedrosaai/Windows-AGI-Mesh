#!/usr/bin/env bash
set -euo pipefail
mkdir -p benchmark/reports
if command -v nvidia-smi >/dev/null 2>&1; then nvidia-smi --query-gpu=name,temperature.gpu,memory.used,utilization.gpu --format=csv,noheader > benchmark/reports/cuda_metrics.csv; else printf 'available
false
' > benchmark/reports/cuda_metrics.csv; fi
