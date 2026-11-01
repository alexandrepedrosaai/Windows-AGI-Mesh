# AG-UI Skill

## Name
AG-UI Runtime

## Purpose
Provide a portable interaction layer between users, agents, tools, memory, and execution runtimes.

## Inputs
- User messages
- Tasks
- Files
- Events
- Runtime configuration

## Outputs
- Responses
- Actions
- Execution plans
- Runtime events

## Supported Platforms
- Windows x64
- Linux ARM64
- Containers

## Supported Languages
- C
- C#/.NET
- MSIL
- Q#

## Runtime Contract
The runtime accepts a validated agent definition and emits structured events. Platform launchers under `runtimes/` are intentionally small so they can be replaced by production hosts without changing the AG-UI schemas.
