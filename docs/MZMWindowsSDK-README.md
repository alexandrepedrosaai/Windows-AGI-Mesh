# MZMWindowsSDK

MZMWindowsSDK is the complete English release bundle for Windows-AGI-Mesh. Every push to `main` runs the `MZMWindowsSDK` GitHub Actions workflow and creates or updates a commit-specific tag and a GitHub Release named **MZMWindowsSDK** through `github-actions[bot]`.

## Release contents

Each release contains:

- A complete repository source snapshot in `MZMWindowsSDK-source.tar.gz`.
- The 500-file English Windows-AGI-Mesh v1.0 architecture scaffold under `mzm-windows-sdk/`.
- `MZMWindowsSDK-binaries.tar.gz` with all compatible C# and Q# outputs produced by the .NET CLI.
- QMesh compiler outputs and the `MZM.Hilbert.DSL` global tool package.
- `SHA256SUMS-source.txt` with a SHA256 digest for every source file and subfile in the repository snapshot.
- `SHA256SUMS.txt` with digests for release payloads.
- Individual `.sha256` files for each release payload.
- `build-report.txt` and `build-failures.txt` for the repository-wide project sweep.

The 500-file scaffold is intentionally an English architecture scaffold: it makes every planned artifact and subsystem explicit without claiming that placeholder files are production implementations. The primary pipeline is QMesh -> AST -> semantic graph -> Mesh IR -> Q# IL -> QIR -> runtime.

## Build policy

The workflow always performs the critical MZM Hilbert DSL and QMesh build. It also attempts every `.csproj` and `.qsproj` project in the repository. Legacy or experimental projects that use incompatible SDKs are recorded in the build reports while compatible binaries are still released. The local build script supports `--strict` when every project must compile successfully.

## Integrity versus encryption

SHA256 is a one-way integrity hash. It allows a consumer to verify that a file was not changed after release; it is not encryption and does not provide confidentiality. Q# and QMesh are used for quantum-language compilation and artifact metadata modeling, not for encrypting arbitrary release files. Use a dedicated signing or post-quantum authenticated-encryption service when those security properties are required.
