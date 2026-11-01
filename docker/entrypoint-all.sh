#!/bin/sh
set -eu
root=/opt/agi-mesh/repository
count=$(find "$root/WebTransporte" "$root/modules" "$root/Windows-AGI-Mesh-Quantum/src/PhotonicAcceleration" -type f | wc -l)
printf "Windows AGI Mesh aggregate source package\nfiles: %s\n" "$count"
if [ "${AGIMESH_INSPECT:-0}" = "1" ]; then
  find "$root/WebTransporte" "$root/modules" "$root/Windows-AGI-Mesh-Quantum/src/PhotonicAcceleration" -type f -print | sort
fi
exec sleep infinity
