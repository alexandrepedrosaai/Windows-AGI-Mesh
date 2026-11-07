"""Run all benchmark cases and save results."""
import json, sys, time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "AzureQuantum"))

from src.python.core.contracts import BenchmarkCase, QuantumBackend
from src.python.core.fake_service import FakeQuantumService


def main():
    cases_dir   = ROOT / "benchmarks" / "cases"
    results_dir = ROOT / "benchmarks" / "results"
    results_dir.mkdir(exist_ok=True)

    cases = []
    for f in sorted(cases_dir.glob("*.json")):
        d = json.loads(f.read_text())
        try:
            backend = QuantumBackend(d.get("backend", "microsoft.simulator.full-state"))
        except ValueError as exc:
            raise ValueError(f"Unsupported backend in {f}: {d.get('backend')!r}") from exc
        cases.append(BenchmarkCase(
            case_id=d["case_id"], case_name=d["case_name"],
            qubit_count=d["qubit_count"], ancilla_count=d.get("ancilla_count", 0),
            theta_z=d["theta_z"], theta_y=d["theta_y"],
            shot_count=d["shot_count"], threshold=d.get("threshold", 0.5),
            expected_mean_lo=d["expected_mean_lo"], expected_mean_hi=d["expected_mean_hi"],
            backend=backend, timeout_seconds=d.get("timeout_seconds", 300),
            tags=d.get("tags", [])))

    print(f"Running {len(cases)} benchmark cases...")
    svc = FakeQuantumService(seed=42)
    results = svc.run_all_benchmarks(cases)

    passed = sum(1 for r in results if r.passed)
    failed = len(results) - passed
    print(f"Results: {passed}/{len(results)} passed ({failed} failed)")

    summary = {
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "total": len(results), "passed": passed, "failed": failed,
        "pass_rate": round(passed / max(1, len(results)) * 100, 1),
        "results": [r.to_dict() for r in results],
    }
    out = results_dir / "latest.json"
    out.write_text(json.dumps(summary, indent=2))
    print(f"Results saved to {out}")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
