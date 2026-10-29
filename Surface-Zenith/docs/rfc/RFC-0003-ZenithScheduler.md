# RFC-0003: Zenith Intent Scheduler (ZIS)

**Status:** Draft  
**Version:** 0.1.0  
**Authors:** Surface Zenith Architecture Team  
**Date:** 2026-10-23

---

## Abstract

This RFC defines the Zenith Intent Scheduler (ZIS) — a third-generation scheduler that manages **goals** rather than processes or threads.

## Scheduling Generations

| Generation | System          | Question Asked                    |
|------------|-----------------|-----------------------------------|
| 1          | FIFO/RR         | Which process executes?           |
| 2          | Linux CFS / NT  | Which thread gets CPU time?       |
| 3          | Zenith ZIS      | Which intention should be realized? |

## Intent Score Formula

```
score = (priority × 5)
      + (context_score × 4)
      + ((255 - latency_budget_ms.min(255)) × 2)
      - energy_cost
      + security_bonus
      + domain_affinity_bonus
```

Where:
- `priority` ∈ [0, 255]
- `context_score` ∈ [0, 255] — relevance to current session context
- `latency_budget_ms` — lower budget = higher urgency
- `energy_cost` — estimated power consumption
- `security_bonus` ∈ {0, 250, 500} — for security-critical intents
- `domain_affinity_bonus` ∈ {0, 100} — when preferred domain is available

## Anti-Starvation

Every `aging_period_ms` (default: 1000ms) that an intent waits, its score increases by `aging_increment` (default: 10). This prevents indefinite deferral of low-priority intents.

## Task Graph (DAG)

Each intent is decomposed into a Directed Acyclic Graph of tasks:

```
GOAL
  │
  ├── Task A (Android Domain, NPU)
  │     └── Task C (AI Domain, NPU)
  └── Task B (Windows Domain, CPU)
        └── Task C (shared dependency)
```

Critical path is computed using topological sort + longest-path algorithm.

## Domain Fitness

```
fitness(class, domain) → u32  // 0–100
```

| Intent Class | Best Domain | Fitness |
|--------------|-------------|---------|
| Messaging    | Android     | 100     |
| Productivity | Windows     | 100     |
| Inference    | AI          | 100     |
| Quantum      | Quantum     | 100     |
| SensorFusion | RealTime    | 100     |
| CloudSync    | Cloud       | 100     |

## Migration Protocol

```
Task Running
    ↓
Checkpoint (serialize state)
    ↓
Transfer (ZIB SnapshotTransfer topic)
    ↓
Restore (target domain)
    ↓
Resume
```

Downtime targets:
- FullSnapshot: ~100ms
- Incremental:  ~20ms
- Live:         ~5ms

## Quantum Enhancement

The ZIS optionally uses Grover's algorithm (O(√N)) to search for the optimal domain assignment, replacing the classical O(N) linear scan. For N=6 domains, this requires ~2 Grover iterations.