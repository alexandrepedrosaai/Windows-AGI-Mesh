# MZM Hilbert DSL Build and Release

## Purpose

This repository contains the MZM Hilbert DSL toolchain for QMesh. QMesh is a declarative language for AGI meshes, agents, flows, memory, abstract quantum circuits and workflow orchestration. The toolchain lowers QMesh through parsing, semantic validation, Mesh IR and backend generation.

The global NuGet tool is named `MZM.Hilbert.DSL` and installs the `qmeshc` command.

## QMesh CLI

```bash
qmeshc build qmesh/examples/AGIQuantum.qmesh --output build/qmesh
qmeshc emit-qsharp qmesh/examples/AGIQuantum.qmesh --output build/qsharp
qmeshc emit-qir qmesh/examples/AGIQuantum.qmesh --output build/qir
qmeshc graph qmesh/examples/AGIQuantum.qmesh --output build/graph
qmeshc run qmesh/examples/AGIQuantum.qmesh
```

The `build` command emits Q# source, QIR-compatible textual IR, Graphviz DOT, YAML and JSON Mesh IR. The implementation is split into lexer, AST, parser, semantic analysis, optimization, IR and backend stages under `tools/MZM.Hilbert.DSL`.

## GitHub Actions build

The workflow `.github/workflows/MZM-Hilbert-DSL.yml` runs on every commit to `main` and can also be started manually. It performs the following sequence:

1. Restores and packs `MZM.Hilbert.DSL` as a NuGet global tool.
2. Installs that package as `qmeshc` before the repository build.
3. Compiles the QMesh example into Q#, QIR, Graphviz, YAML and Mesh IR.
4. Builds and publishes every `.csproj` and `.qsproj` project through the .NET CLI, including the repository's C# and Q# binaries.
5. Archives the binary and QMesh outputs.
6. Generates `SHA256SUMS.txt` and one `.sha256` file for every release input.
7. Publishes the NuGet tool package to GitHub Packages.
8. Creates or updates a commit-specific tag and a GitHub Release named **MZM Hilbert DSL** using `github-actions[bot]`.

The repository contains legacy and experimental projects that do not all share one compatible SDK or dependency graph. The repo-wide binary sweep therefore uses best-effort mode: it attempts every project, publishes successful outputs, and records complete diagnostics in `build-report.txt` plus the project list in `build-failures.txt`. The MZM tool build and QMesh compilation remain fatal checks. The local script supports `scripts/build_all_binaries.sh <output> --strict` when a caller explicitly wants any project failure to stop the run.

The `MajoranaZenithSDK` and Zenith 60-module workflows also pack and install the same MZM Hilbert DSL NuGet tool before their package operations, so `qmeshc` is available on every SDK run.

## Integrity and quantum-language boundary

SHA256 files encapsulate binary integrity metadata and make accidental or unauthorized changes detectable. SHA256 is a one-way integrity hash, not encryption. Q# is used here for QMesh/Q# compilation and for the `Sha256Envelope.qs` metadata model; Q# does not provide quantum encryption of arbitrary files. If confidentiality, signing, or post-quantum cryptographic protection is required, use a dedicated cryptographic or artifact-signing service in addition to these hashes.

The workflows use GitHub's built-in `GITHUB_TOKEN` for GitHub Packages, tags and Releases. No custom token is required.
