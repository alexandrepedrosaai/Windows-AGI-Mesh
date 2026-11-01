# Docker source packages

This directory packages every source file under:

- `WebTransporte/Microsoft Chrome. (internals)Edge AI/`
- `modules/`
- `Windows-AGI-Mesh-Quantum/src/PhotonicAcceleration/` (including subdirectories)

## Packages

- `targets/*/Dockerfile`: one independent image per source file. The complete inventory is in `manifest.json`.
- `Dockerfile.all`: one aggregate image containing all requested directories while preserving their paths.
- `entrypoint.sh` and `entrypoint-all.sh`: small, non-root inspection/runtime entrypoints.

The source files include Q#/DSL/PowerShell/assembly artifacts that do not all have standalone compilers or project files. Therefore the per-file images package and expose the source safely instead of pretending to compile an incompatible file. Python packages run `py_compile`; other packages stay available for inspection with `AGIMESH_INSPECT=1`.

## Local usage

From the repository root:

```bash
# Individual file package
docker build -f docker/targets/modules-deepspace-qs/Dockerfile -t agimesh:deepspace .
docker run --rm agimesh:deepspace

# Inspect an individual source file
docker run --rm -e AGIMESH_INSPECT=1 agimesh:deepspace

# Aggregate package
docker build -f docker/Dockerfile.all -t agimesh:all .
docker run --rm -e AGIMESH_INSPECT=1 agimesh:all
```

The workflow `.github/workflows/docker-source-packages.yml` builds every individual image on pull requests and pushes. Version tags (`v*`) publish images to GHCR with provenance and SBOM attestations.
