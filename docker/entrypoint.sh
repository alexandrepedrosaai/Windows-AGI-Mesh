#!/bin/sh
set -eu
source="${AGIMESH_SOURCE:-}"
if [ -z "$source" ] || [ ! -f "$source" ]; then
  echo "AGIMESH_SOURCE is missing or is not a file" >&2
  exit 2
fi
printf "Windows AGI Mesh source package\nfile: %s\ntype: %s\n" "$source" "${AGIMESH_SOURCE_TYPE:-unknown}"
case "${AGIMESH_SOURCE_TYPE:-unknown}" in
  python)
    exec env PYTHONPYCACHEPREFIX=/tmp/agimesh-pycache python3 -m py_compile "$source"
    ;;
  *)
    # Q#, DSL, PowerShell manifests and assembly are source artifacts; keep the
    # container alive only when explicitly requested for inspection.
    if [ "${AGIMESH_INSPECT:-0}" = "1" ]; then
      exec sed -n "1,160p" "$source"
    fi
    exec sh -c 'echo "Source packaged successfully. Set AGIMESH_INSPECT=1 to inspect it."; exec sleep infinity'
    ;;
esac
