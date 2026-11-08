#!/usr/bin/env bash
set -euo pipefail
mkdir -p build/arm64
printf 'target=arm64
source=src/arm64
' > build/arm64/manifest.txt
find src/arm64 -type f -print | sort >> build/arm64/manifest.txt
