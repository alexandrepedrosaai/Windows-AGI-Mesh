#!/usr/bin/env bash
set -euo pipefail
TARGET="${1:-aarch64}"
command -v "qemu-${TARGET}" >/dev/null 2>&1 || { echo "qemu-${TARGET} is not installed" >&2; exit 0; }
qemu-${TARGET} --version | head -n 1
