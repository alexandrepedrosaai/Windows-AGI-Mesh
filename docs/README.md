# Documentation

See [DSL.md](DSL.md) for the `.qs` circuit conventions, repository layout, and interpretation of declared metrics and security policies.

## Q# capability benchmark

[`benchmarks/AGI_Mesh_Web.qs`](../benchmarks/AGI_Mesh_Web.qs) provides a shared `ScoreFromTrials` function for converting observed successes into percentages, a typed score record for reasoning, tool usage, memory, self-correction, agent coordination, and quantum consensus, plus a Bell-pair correlation experiment. Callers supply the score record and six nonnegative weights to calculate the weighted AGI Capability Index (ACI). Scores are percentages from 0 to 100, and at least one weight must be positive.

The quantum-consensus score is the percentage of correlated measurement pairs over the requested number of simulator shots. It demonstrates a simulator-compatible quantum measurement; it does not measure AI-agent consensus or claim Azure hardware execution. Running on Azure Quantum requires a separately configured project, workspace, and supported target.
