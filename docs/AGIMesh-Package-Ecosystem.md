# AGIMesh Package Ecosystem Catalog

This catalog is the English, machine-readable implementation of the package roadmap supplied for Windows-AGI-Mesh. It contains **131 package entries** across five dependency layers and five distribution ecosystems.

## Inventory

| Ecosystem | Entries |
|---|---:|
| NuGet | 60 |
| npm | 27 |
| Maven | 19 |
| RubyGems | 8 |
| OCI containers | 17 |
| **Total** | **131** |

## Dependency layers

- **Level 0 — Independent:** packages can be built without another catalog package.
- **Level 1 — Core-dependent:** packages depend on the core layer.
- **Level 2 — Co-dependent:** packages belong to the quantum and AI stacks and are built after the core and agent layers.
- **Level 3 — Ecosystem:** Windows, Azure, Microsoft 365, and GitHub integration packages.
- **Ultra-Layer:** AGIMesh cognitive-fabric and platform packages.

## Workflow behavior

`.github/workflows/AGIMesh-Ecosystem-Catalog.yml` is a separate workflow. It does not replace the AzureQuantumSDK workflows. It runs on changes to this catalog or to the workflow itself, installs the toolchains for all supported ecosystems, and processes every catalog entry in a matrix.

The five layer jobs are sequential. Every matrix entry creates a deterministic package-shaped artifact, a metadata record, and a SHA-256 digest. NuGet, npm, Maven, RubyGems, and OCI entries are packed using their native tooling. The final job downloads every matrix artifact, creates an aggregate digest, and creates a draft GitHub release. All files are uploaded before the release is made public.

The workflow deliberately publishes release assets rather than silently claiming that every external registry is configured. Publishing to a public NuGet, npm, Maven, RubyGems, or container registry requires the corresponding repository permissions and registry policy. The GitHub Actions `GITHUB_TOKEN` is used for GitHub Packages and GHCR when enabled by repository settings.

## Generated artifacts

Each package artifact contains:

- the package name, ecosystem, dependency level, and category;
- a native package archive where the toolchain supports one;
- a deterministic `metadata.json` file;
- SHA-256 checksums for every generated file.

The final release contains the complete catalog, all per-package artifacts, and `all-artifacts.sha256`.
