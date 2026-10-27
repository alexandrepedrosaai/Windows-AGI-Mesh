# MZMWindowsSDK

MZMWindowsSDK is the complete English release bundle for Windows-AGI-Mesh. Every push to `main` runs the `MZMWindowsSDK` GitHub Actions workflow and creates or updates a commit-specific tag and a GitHub Release named **MZMWindowsSDK** through `github-actions[bot]`.

## Release contents

Each release contains:

- A complete repository source snapshot in `MZMWindowsSDK-source.tar.gz`.
- The 500-file English Windows-AGI-Mesh v1.0 architecture scaffold under `mzm-windows-sdk/`.
- `MZMWindowsSDK-binaries.tar.gz` with all compatible C# and Q# outputs produced by the .NET CLI.
- QMesh compiler outputs and the `MZM.Hilbert.DSL` global tool package.
- A required pull, restore and cache of `MajoranaZenithSDK` from GitHub Packages.
- A best-effort download report and cache for all other package IDs listed by the repository manifests.
- The `MZMWindowsSDK` NuGet package, followed by `MZMWindowsSDK.Dependencies`, which references the exact same CI version of the base package.
- The VA Q-learning Neural Quantum Polymorphism executable and its published output.
- `previous-step-outputs.tar.gz`, containing the files produced by earlier workflow steps, and `all-dotnet-project-files.tar.gz`, containing every `.csproj` and `.qsproj` used by the build sweep.
- `SHA256SUMS-source.txt` with a SHA256 digest for every source file and subfile in the repository snapshot.
- `SHA256SUMS.txt` with digests for release payloads.
- Individual `.sha256` files for each release payload.
- `build-report.txt` and `build-failures.txt` for the pipeline-project build.

The 500-file scaffold is intentionally an English architecture scaffold: it makes every planned artifact and subsystem explicit without claiming that placeholder files are production implementations. The primary pipeline is QMesh -> AST -> semantic graph -> Mesh IR -> Q# IL -> QIR -> runtime.

## Build policy

The workflow always performs the critical MZM Hilbert DSL and QMesh build, then builds only the pipeline project explicitly listed in the workflow: `quantum/VAQLearningNeural/VAQLearningNeural.csproj`. The historical `.csproj` and `.qsproj` files in the repository are not compiled by this workflow. Any listed pipeline project failure stops release validation immediately, while `build-report.txt` and `build-failures.txt` are uploaded with `if: always()` for every run.

The release upload is assembled only after the preceding build, package and checksum steps succeed. It uploads the collected `release-assets` directory, rather than treating the release directory itself as an input to an earlier build step. This prevents self-referential archives and ensures the Release represents outputs from the completed workflow stages.

## Integrity versus encryption

SHA256 is a one-way integrity hash. It allows a consumer to verify that a file was not changed after release; it is not encryption and does not provide confidentiality. Q# and QMesh are used for quantum-language compilation and artifact metadata modeling, not for encrypting arbitrary release files. Use a dedicated signing or post-quantum authenticated-encryption service when those security properties are required.
