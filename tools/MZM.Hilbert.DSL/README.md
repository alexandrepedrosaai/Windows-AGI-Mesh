# MZM Hilbert DSL

MZM Hilbert DSL provides `qmeshc`, a command-line compiler for the QMesh DSL. QMesh describes AGI meshes, agents, flows, memories and abstract quantum circuits, then lowers them into a Mesh IR and generated Q# or QIR-compatible text.

## CLI

```bash
qmeshc build examples/AGIQuantum.qmesh --output build/qmesh
qmeshc emit-qsharp examples/AGIQuantum.qmesh --output build/qsharp
qmeshc emit-qir examples/AGIQuantum.qmesh --output build/qir
qmeshc graph examples/AGIQuantum.qmesh --output build/graph
qmeshc run examples/AGIQuantum.qmesh
```

`build` produces Q#, QIR text, Graphviz DOT, YAML and JSON Mesh IR files. The package is a .NET global tool named `MZM.Hilbert.DSL` with the command name `qmeshc`.

## CI and releases

The MZM Hilbert DSL workflow runs on every push to `main`. It packages the tool as NuGet, installs it before compiling `MajoranaZenithSDK`, builds the C# and Q# project files, compiles the QMesh example, publishes binary artifacts, and creates a release named **MZM Hilbert DSL** through `github-actions[bot]`. The release tag is updated for each commit.

Every binary receives a SHA256 integrity record and all records are collected in `SHA256SUMS.txt`. SHA256 is an integrity hash, not encryption; Q# is used for quantum-language compilation and does not provide quantum encryption of arbitrary release files. Release provenance and artifact attestations should be enabled separately when cryptographic signing is required.
