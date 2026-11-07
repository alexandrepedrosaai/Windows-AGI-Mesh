#!/usr/bin/env bash
set -euo pipefail
mkdir -p build/riscv64
printf 'target=riscv64
source=src/riscv64
' > build/riscv64/manifest.txt
find src/riscv64 -type f -print | sort >> build/riscv64/manifest.txt
