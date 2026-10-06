# `.q#circuite` reference format

`.q#circuite` is the repository's declarative specification format for describing
Windows-AGI-Mesh modules. These files are design manifests, not executable code
or a claim that a runtime or parser is available.

## Conventions

- Each file declares one `circuit` with a stable identifier and `format_version`.
- `scope` states purpose, supported boundaries, and relevant exclusions.
- `metrics` names observable measures, units, and reporting targets. A target
  that says "report" is a measurement requirement, not an asserted result.
- `integration_pipeline` lists ordered, reviewable processing stages.
- `security.rules` expresses requirements that an eventual implementation must
  enforce; declarations alone do not provide enforcement.
- Quoted strings carry prose and identifiers. Lists use square brackets, and
  nested declarations use braces. Keys and stages are separated from values
  with a colon; declarations are newline-delimited.
- Paths in the root manifest are relative to the repository root.

The syntax is intentionally readable and consistent, but remains a project
convention until a parser, formal grammar, and conformance tests are published.

## Repository layout

```text
/
├── Windows-AGI-Mesh.q#circuite
├── benchmarks/
│   └── AGI_Mesh_Web.q#circuite
├── docs/
│   └── circuite-format.md
├── examples/
│   └── local-edge-deployment.q#circuite
└── modules/
    ├── DeepSpace.q#circuite
    ├── EdgeAIApp.q#circuite
    ├── MagneticMajorana.q#circuite
    ├── Nemotron.q#circuite
    └── XboxQuantumXR.q#circuite
```
