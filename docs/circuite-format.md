# `.qs` circuit reference format

Architecture and module `.qs` files use the repository's declarative circuit
format. They are design manifests, not executable code or a claim that a runtime
or parser is available. The benchmark `.qs` file contains executable Q# source.

## Conventions

- Each circuit file declares one `circuit` with a stable identifier, `version`,
  and `kind`.
- `scope` states purpose, supported boundaries, and relevant exclusions.
- `metrics` names observable measures, units, and evaluation targets. A target
  that says "report" is a measurement requirement, not an asserted result.
- `integration_pipeline` lists ordered, reviewable processing stages.
- `security.rules` expresses requirements that an eventual implementation must
  enforce; declarations alone do not provide enforcement.
- Assignments use `name = value`; strings use double quotes, lists use square
  brackets, and structured values use braces.
- Paths in the root manifest are relative to the repository root.

The syntax is intentionally readable and consistent, but remains a project
convention until a parser, formal grammar, and conformance tests are published.

## Repository layout

```text
/
├── Windows-AGI-Mesh.qs
├── benchmarks/
│   └── AGI_Mesh_Web.qs
├── docs/
│   └── circuite-format.md
├── examples/
│   └── local-edge-deployment.qs
└── modules/
    ├── DeepSpace.qs
    ├── EdgeAIApp.qs
    ├── MagneticMajorana.qs
    ├── Nemotron.qs
    └── XboxQuantumXR.qs
```
