# Circuit DSL

The `.q#circuite` files are declarative specifications for the Windows-AGI-Mesh modules; they are not executable programs or claims that the described capabilities have already been implemented. The syntax is intentionally consistent and human-readable so that a future parser can validate it.

## Structure

Each circuit has a unique `circuit` identifier, a `version`, and a `kind`. It declares:

- `scope`: purpose, inputs, outputs, and limitations.
- `metrics`: measurable outcomes, units, and evaluation targets or reporting rules.
- `integration_pipeline`: ordered `stage` entries with their actions.
- `security`: mandatory policy rules.

The main architecture circuit additionally declares its objective, module paths, mesh principles, and roadmap. The benchmark and modules add domain-specific fields such as benchmark protocol, dataset provenance, storage recovery, or local inference.

Assignments use `name = value`; strings use double quotes, lists use brackets, and structured metric values use braces. Targets are evaluation criteria, not claims of achieved performance. Module references are relative to the repository root.

## Repository layout

- `Windows-AGI-Mesh.q#circuite`: top-level objective, architecture, integration, metrics, security, and roadmap.
- `modules/`: dataset, storage, quantum-persistence study, XR, and local edge application circuits.
- `benchmarks/`: general-intelligence evaluation circuit.
- `docs/`: architecture and DSL documentation.
- `examples/`: an end-to-end example using the declared mesh interfaces.

Any future implementation should validate syntax and module contracts before execution, and enforce each circuit's security rules in the runtime rather than treating declarations as enforcement by themselves.
