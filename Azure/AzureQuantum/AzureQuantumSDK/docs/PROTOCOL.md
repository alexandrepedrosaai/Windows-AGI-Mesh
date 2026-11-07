# Protocol

## JSON Contract

All CLI commands output JSON:

```json
{"ok": true, "result": {}}
{"ok": false, "error": "message"}
```

## ExperimentResult Schema

```json
{
  "experiment_id": "uuid",
  "mean": 0.5234,
  "deviation": 0.0812,
  "above_threshold": true,
  "shot_count": 100,
  "qubit_count": 4,
  "ancilla_count": 2,
  "theta_z": 0.5,
  "theta_y": 0.3,
  "threshold": 0.5,
  "backend": "microsoft.simulator.full-state",
  "timestamp_utc": "2026-11-07T00:00:00Z",
  "runtime_ms": 45.2,
  "qec_cycles": 0,
  "error_rate": 0.0
}
```
