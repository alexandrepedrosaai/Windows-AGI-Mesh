#!/usr/bin/env bash
set -euo pipefail
# Stop the WSL Zenith benchmark stack without deleting source or reports.
cd "$(dirname "${BASH_SOURCE[0]}")/.."
docker compose -f docker/docker-compose.yml -f docker/docker-compose.monitoring.yml down --remove-orphans
