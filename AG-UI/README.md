# AG-UI Runtime

AG-UI is a starter multi-runtime foundation for Windows-AGI-Mesh. It defines a small, portable contract for interaction between users, agents, tools, memory, and execution environments.

## Layout

- `src/csharp/` contains the managed runtime host.
- `src/c/` contains the native runtime entry point and lifecycle helpers.
- `src/il/` contains MSIL reference modules for low-level hosts.
- `src/qsharp/` contains the quantum-agent contract placeholder.
- `src/schemas/` contains agent, task, and workflow JSON Schemas.
- `runtimes/` contains Linux ARM64, Windows x64, and container launchers.
- `agents/` contains planner, coder, and reviewer skill definitions.
- `tests/` reserves unit and integration test locations.

## Quick Start

### .NET host

```bash
dotnet run --project src/csharp/AGUI.csproj
```

The repository may add a project file around the starter sources when integrating AG-UI into a larger .NET solution.

### Linux ARM64

```bash
./runtimes/linux-arm64/run.sh
```

### Windows x64

```bat
runtimes\windows-x64\run.cmd
```

### Container

```bash
docker compose -f runtimes/containers/compose.yaml up --build
```

## Configuration

The default configuration is in `appsettings.json`. Agent definitions must satisfy `agui.schema.json`; task and workflow payloads should use the schemas in `src/schemas/`.

## Design Goals

1. Keep the runtime contract language-neutral.
2. Keep platform launchers replaceable.
3. Make validation explicit through JSON Schema.
4. Allow native, managed, MSIL, quantum, and container hosts to coexist.
5. Keep agent skills documented in English and version-controlled.
