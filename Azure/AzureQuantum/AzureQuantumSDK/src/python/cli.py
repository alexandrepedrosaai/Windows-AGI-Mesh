"""
cli.py — Command-line interface for Windows-AGI-Mesh-QuantumSDK.
Supports: run, benchmark, estimate, infer, train, factorize, topology.
"""
from __future__ import annotations
import argparse, json, logging, sys, time
from pathlib import Path

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")
logger = logging.getLogger("agi-mesh-cli")

def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="agi-mesh", description="Windows-AGI-Mesh-QuantumSDK CLI")
    sub = p.add_subparsers(dest="command", required=True)

    # run
    r = sub.add_parser("run", help="Run a quantum experiment")
    r.add_argument("--qubits",    type=int,   required=True)
    r.add_argument("--ancillas",  type=int,   default=0)
    r.add_argument("--theta-z",   type=float, required=True)
    r.add_argument("--theta-y",   type=float, required=True)
    r.add_argument("--shots",     type=int,   required=True)
    r.add_argument("--threshold", type=float, default=0.5)
    r.add_argument("--backend",   type=str,   default="microsoft.simulator.full-state")
    r.add_argument("--use-qec",   action="store_true")
    r.add_argument("--braid-depth", type=int, default=0)
    r.add_argument("--dry-run",   action="store_true")
    r.add_argument("--output",    type=str,   default="-")

    # benchmark
    b = sub.add_parser("benchmark", help="Run benchmark suite")
    b.add_argument("--cases-dir", type=str, default="benchmarks/cases")
    b.add_argument("--parallel",  action="store_true")
    b.add_argument("--output",    type=str, default="benchmarks/results/latest.json")
    b.add_argument("--dry-run",   action="store_true")

    # estimate
    e = sub.add_parser("estimate", help="Estimate quantum resources")
    e.add_argument("--algorithm",       type=str, required=True)
    e.add_argument("--logical-qubits",  type=int, required=True)
    e.add_argument("--error-budget",    type=float, default=0.01)
    e.add_argument("--backend",         type=str, default="microsoft.majorana-1")

    # infer
    i = sub.add_parser("infer", help="Run LLM inference")
    i.add_argument("--prompt",          type=str, required=True)
    i.add_argument("--max-new-tokens",  type=int, default=256)
    i.add_argument("--temperature",     type=float, default=0.7)
    i.add_argument("--top-p",           type=float, default=0.9)
    i.add_argument("--use-quantum",     action="store_true")
    i.add_argument("--backend",         type=str, default="maia-300")
    i.add_argument("--dry-run",         action="store_true")

    # factorize
    f = sub.add_parser("factorize", help="Factor an integer with Shor's algorithm")
    f.add_argument("--number", type=int, required=True)
    f.add_argument("--dry-run", action="store_true")

    # topology
    t = sub.add_parser("topology", help="Show cluster topology")
    t.add_argument("--config", type=str, default="config/clusters/local.json")

    return p

def cmd_run(args, project_root: Path) -> int:
    from .core.contracts import ExperimentConfig, QuantumBackend, ErrorCorrectionCode
    from .core.service import QuantumService
    try:
        backend = QuantumBackend(args.backend)
    except ValueError:
        backend = QuantumBackend.SIMULATOR_FULL_STATE
    config = ExperimentConfig(
        qubit_count=args.qubits, ancilla_count=args.ancillas,
        theta_z=args.theta_z, theta_y=args.theta_y,
        shot_count=args.shots, threshold=args.threshold,
        backend=backend, use_qec=args.use_qec, braid_depth=args.braid_depth)
    with QuantumService(project_root, dry_run=args.dry_run) as svc:
        result = svc.run_experiment(config)
    out = json.dumps({"ok": True, "result": result.to_dict()}, indent=2)
    if args.output == "-":
        print(out)
    else:
        Path(args.output).write_text(out)
        logger.info("Result written to %s", args.output)
    return 0

def cmd_benchmark(args, project_root: Path) -> int:
    import glob
    from .core.contracts import BenchmarkCase, QuantumBackend
    from .core.service import QuantumService
    cases_dir = Path(args.cases_dir)
    cases = []
    for f in sorted(cases_dir.glob("*.json")):
        d = json.loads(f.read_text())
        try:
            backend = QuantumBackend(d.get("backend", "microsoft.simulator.full-state"))
        except ValueError:
            backend = QuantumBackend.SIMULATOR_FULL_STATE
        cases.append(BenchmarkCase(
            case_id=d["case_id"], case_name=d["case_name"],
            qubit_count=d["qubit_count"], ancilla_count=d.get("ancilla_count", 0),
            theta_z=d["theta_z"], theta_y=d["theta_y"],
            shot_count=d["shot_count"], threshold=d.get("threshold", 0.5),
            expected_mean_lo=d["expected_mean_lo"], expected_mean_hi=d["expected_mean_hi"],
            backend=backend, timeout_seconds=d.get("timeout_seconds", 300),
            tags=d.get("tags", [])))
    if not cases:
        logger.warning("No benchmark cases found in %s", cases_dir)
        return 0
    with QuantumService(project_root, dry_run=args.dry_run) as svc:
        results = svc.run_all_benchmarks(cases, parallel=args.parallel)
    passed = sum(1 for r in results if r.passed)
    failed = len(results) - passed
    summary = {"total": len(results), "passed": passed, "failed": failed,
               "results": [r.to_dict() for r in results]}
    out_path = Path(args.output)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(summary, indent=2))
    print(json.dumps({"ok": True, "passed": passed, "failed": failed, "total": len(results)}))
    return 0 if failed == 0 else 1

def cmd_estimate(args, project_root: Path) -> int:
    from .core.contracts import QuantumBackend
    from .core.service import QuantumService
    try:
        backend = QuantumBackend(args.backend)
    except ValueError:
        backend = QuantumBackend.MAJORANA_1
    with QuantumService(project_root, dry_run=True) as svc:
        est = svc.estimate_resources(args.algorithm, args.logical_qubits,
                                      args.error_budget, backend)
    print(json.dumps({"ok": True, "estimate": est.to_dict()}, indent=2))
    return 0

def cmd_infer(args, project_root: Path) -> int:
    from .core.contracts import InferenceRequest, HardwareAccelerator
    from .core.service import QuantumService
    try:
        backend = HardwareAccelerator(args.backend)
    except ValueError:
        backend = HardwareAccelerator.MAIA_300
    # Simple tokenization: split on spaces, map to IDs
    token_ids = [hash(w) % 50000 + 1 for w in args.prompt.split()]
    request = InferenceRequest(
        input_token_ids=token_ids, max_new_tokens=args.max_new_tokens,
        temperature=args.temperature, top_p=args.top_p,
        use_quantum_sampling=args.use_quantum, target_backend=backend,
        user_prompt=args.prompt)
    with QuantumService(project_root, dry_run=args.dry_run) as svc:
        result = svc.run_inference(request)
    print(json.dumps({"ok": True, "result": result.to_dict()}, indent=2))
    return 0

def cmd_factorize(args, project_root: Path) -> int:
    from .core.service import QuantumService
    with QuantumService(project_root, dry_run=args.dry_run) as svc:
        if svc._qdk_initialized and svc._qdk:
            from .core.contracts import ExperimentConfig
            # Use Q# factorization
            try:
                raw = svc._qdk.code.FactorInteger(n=args.number)
                n,f1,f2,isPrime,algo,qubits,depth,steps,qAdv,rt = raw
                result = {"n": int(n), "factor1": int(f1), "factor2": int(f2),
                          "is_prime": bool(isPrime), "algorithm": str(algo),
                          "qubit_count": int(qubits), "circuit_depth": int(depth),
                          "classical_steps": int(steps), "quantum_advantage": bool(qAdv)}
            except Exception as exc:
                logger.error("Q# factorization failed: %s", exc)
                result = _classical_factor(args.number)
        else:
            result = _classical_factor(args.number)
    print(json.dumps({"ok": True, "result": result}, indent=2))
    return 0

def _classical_factor(n: int) -> dict:
    import math
    if n < 2: return {"n": n, "factor1": 1, "factor2": n, "is_prime": False, "algorithm": "trivial"}
    for i in range(2, int(math.isqrt(n))+1):
        if n % i == 0:
            return {"n": n, "factor1": i, "factor2": n//i, "is_prime": False, "algorithm": "trial-division"}
    return {"n": n, "factor1": 1, "factor2": n, "is_prime": True, "algorithm": "trial-division"}

def cmd_topology(args, project_root: Path) -> int:
    config_path = Path(args.config)
    if config_path.exists():
        data = json.loads(config_path.read_text())
        print(json.dumps({"ok": True, "topology": data}, indent=2))
    else:
        print(json.dumps({"ok": False, "error": f"Config not found: {config_path}"}))
        return 1
    return 0

def main() -> int:
    parser = build_parser()
    args   = parser.parse_args()
    project_root = Path(__file__).resolve().parents[3]
    dispatch = {
        "run":       cmd_run,
        "benchmark": cmd_benchmark,
        "estimate":  cmd_estimate,
        "infer":     cmd_infer,
        "factorize": cmd_factorize,
        "topology":  cmd_topology,
    }
    try:
        return dispatch[args.command](args, project_root)
    except Exception as exc:
        print(json.dumps({"ok": False, "error": str(exc)}))
        logger.exception("CLI command %s failed", args.command)
        return 1

if __name__ == "__main__":
    sys.exit(main())
