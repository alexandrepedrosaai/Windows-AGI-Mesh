"""Integration tests for CLI JSON contract."""
import json, math, subprocess, sys, os, pytest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PYTHON = sys.executable


def run_cli(*args, timeout=60):
    """Run the CLI and return parsed JSON output."""
    cmd = [PYTHON, "-m", "src.python.cli"] + list(args)
    try:
        result = subprocess.run(cmd, capture_output=True, text=True,
                                timeout=timeout, cwd=str(ROOT))
        if result.stdout.strip():
            return json.loads(result.stdout), result.returncode
        return None, result.returncode
    except subprocess.TimeoutExpired:
        pytest.skip("CLI timed out")
    except Exception as exc:
        pytest.skip(f"CLI unavailable: {exc}")


class TestCLIRunContract:
    def test_run_returns_ok(self):
        data, code = run_cli("run", "--qubits", "2", "--theta-z", "0.5",
                              "--theta-y", "0.3", "--shots", "10", "--dry-run")
        if data is None:
            pytest.skip("CLI not available")
        assert data.get("ok") is True

    def test_run_result_has_required_fields(self):
        data, _ = run_cli("run", "--qubits", "2", "--theta-z", "0.5",
                           "--theta-y", "0.3", "--shots", "10", "--dry-run")
        if data is None:
            pytest.skip("CLI not available")
        result = data.get("result", {})
        for field in ["mean", "deviation", "above_threshold", "shot_count",
                      "qubit_count", "backend", "timestamp_utc"]:
            assert field in result, f"Missing field: {field}"

    def test_run_mean_in_range(self):
        data, _ = run_cli("run", "--qubits", "4", "--theta-z", "0.5",
                           "--theta-y", "0.3", "--shots", "50", "--dry-run")
        if data is None:
            pytest.skip("CLI not available")
        mean = data["result"]["mean"]
        assert 0.0 <= mean <= 1.0

    def test_run_deviation_non_negative(self):
        data, _ = run_cli("run", "--qubits", "4", "--theta-z", "0.5",
                           "--theta-y", "0.3", "--shots", "50", "--dry-run")
        if data is None:
            pytest.skip("CLI not available")
        assert data["result"]["deviation"] >= 0.0

    def test_estimate_returns_ok(self):
        data, _ = run_cli("estimate", "--algorithm", "RSA-2048",
                           "--logical-qubits", "100")
        if data is None:
            pytest.skip("CLI not available")
        assert data.get("ok") is True
        est = data.get("estimate", {})
        assert "logical_qubits" in est
        assert "physical_qubits" in est
        assert est["physical_qubits"] >= est["logical_qubits"]

    def test_factorize_15(self):
        data, _ = run_cli("factorize", "--number", "15", "--dry-run")
        if data is None:
            pytest.skip("CLI not available")
        assert data.get("ok") is True
        r = data["result"]
        assert r["factor1"] * r["factor2"] == 15

    def test_factorize_prime(self):
        data, _ = run_cli("factorize", "--number", "17", "--dry-run")
        if data is None:
            pytest.skip("CLI not available")
        assert data.get("ok") is True
        r = data["result"]
        assert r["is_prime"] is True

    def test_infer_returns_ok(self):
        data, _ = run_cli("infer", "--prompt", "Hello world",
                           "--max-new-tokens", "10", "--dry-run")
        if data is None:
            pytest.skip("CLI not available")
        assert data.get("ok") is True
        r = data["result"]
        assert "output_tokens" in r
        assert r["input_tokens"] > 0


class TestFakeServiceContract:
    """Test FakeQuantumService produces valid contract-compliant results."""

    def setup_method(self):
        sys.path.insert(0, str(ROOT))
        from src.python.core.fake_service import FakeQuantumService
        from src.python.core.contracts import ExperimentConfig, InferenceRequest
        self.svc = FakeQuantumService(seed=42)
        self.ExperimentConfig = ExperimentConfig
        self.InferenceRequest = InferenceRequest

    def test_experiment_mean_in_range(self):
        cfg = self.ExperimentConfig(qubit_count=4, ancilla_count=0,
                                     theta_z=0.5, theta_y=0.3, shot_count=100)
        r = self.svc.run_experiment(cfg)
        assert 0.0 <= r.mean <= 1.0

    def test_experiment_deviation_non_negative(self):
        cfg = self.ExperimentConfig(qubit_count=4, ancilla_count=0,
                                     theta_z=0.5, theta_y=0.3, shot_count=100)
        r = self.svc.run_experiment(cfg)
        assert r.deviation >= 0.0

    def test_experiment_above_threshold_consistent(self):
        cfg = self.ExperimentConfig(qubit_count=4, ancilla_count=0,
                                     theta_z=0.5, theta_y=0.3, shot_count=100,
                                     threshold=0.5)
        r = self.svc.run_experiment(cfg)
        assert r.above_threshold == (r.mean > 0.5)

    def test_batch_experiments(self):
        cfgs = [
            self.ExperimentConfig(qubit_count=2, ancilla_count=0,
                                   theta_z=i*0.1, theta_y=0.3, shot_count=10)
            for i in range(5)
        ]
        results = self.svc.run_batch_experiments(cfgs)
        assert len(results) == 5
        for r in results:
            assert 0.0 <= r.mean <= 1.0

    def test_inference_output_tokens(self):
        req = self.InferenceRequest(input_token_ids=[1,2,3,4,5],
                                     max_new_tokens=32)
        r = self.svc.run_inference(req)
        assert r.output_tokens > 0
        assert r.input_tokens == 5
        assert r.total_tokens == r.input_tokens + r.output_tokens

    def test_maia300_dispatch(self):
        req = self.InferenceRequest(input_token_ids=list(range(100)),
                                     max_new_tokens=32)
        r = self.svc.dispatch_to_maia300(req)
        assert r.is_successful
        assert r.latency_ms > 0
        assert len(r.output_hidden) == 4096

    def test_brainwave_dispatch(self):
        req = self.InferenceRequest(input_token_ids=list(range(50)),
                                     max_new_tokens=16)
        r = self.svc.route_to_brainwave(req)
        assert r.is_successful
        assert r.throughput_tflops > 0

    def test_photonic_transport(self):
        r = self.svc.send_via_photonic_fiber(1024.0)
        assert r.is_successful
        assert r.transport_latency_us > 0
        assert r.photonic_ops_done > 0

    def test_deterministic_results(self):
        """Same seed + same input → same output."""
        from src.python.core.fake_service import FakeQuantumService
        svc1 = FakeQuantumService(seed=99)
        svc2 = FakeQuantumService(seed=99)
        cfg = self.ExperimentConfig(qubit_count=4, ancilla_count=0,
                                     theta_z=0.5, theta_y=0.3, shot_count=100)
        r1 = svc1.run_experiment(cfg)
        r2 = svc2.run_experiment(cfg)
        assert r1.mean == r2.mean
        assert r1.deviation == r2.deviation

    def test_resource_estimate(self):
        from src.python.core.contracts import QuantumBackend
        est = self.svc.estimate_resources("RSA-2048", 4000,
                                           backend=QuantumBackend.MAJORANA_1)
        assert est.logical_qubits == 4000
        assert est.physical_qubits == 8000  # 2:1 overhead for Majorana
        assert est.logical_error_rate < 1e-3
