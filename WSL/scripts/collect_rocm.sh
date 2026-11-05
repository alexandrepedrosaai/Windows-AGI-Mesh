#!/usr/bin/env bash
set -euo pipefail
mkdir -p benchmark/reports
if command -v rocm-smi >/dev/null 2>&1; then rocm-smi --showuse --showmemuse --json > benchmark/reports/rocm_metrics.json; else printf '{"available":false}
' > benchmark/reports/rocm_metrics.json; fi
