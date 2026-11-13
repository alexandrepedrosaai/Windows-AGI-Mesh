"""Unit tests for Python validation layer."""
import math, pytest
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", ".."))

from src.python.core.contracts import (
    ExperimentConfig, InferenceRequest, TrainingConfig,
    MAIA300Config, BrainwaveFPGAConfig, HollowCoreFiberConfig,
    MajoranaQPUConfig, MoERoutingConfig, RLHFConfig,
    QuantumBackend, HardwareAccelerator, QuantizationScheme,
    ErrorCorrectionCode, TrainingPhase,
)
from src.python.core.validation import (
    ValidationError,
    validate_experiment_config, validate_inference_request,
    validate_training_config, validate_maia300_config,
    validate_brainwave_config, validate_hcf_config,
    validate_majorana_config, validate_moe_config,
    validate_rlhf_config,
)


class TestExperimentConfigValidation:
    def _valid(self, **kwargs):
        defaults = dict(qubit_count=4, ancilla_count=2, theta_z=0.5, theta_y=0.3,
                        shot_count=100, threshold=0.5)
        defaults.update(kwargs)
        return ExperimentConfig(**defaults)

    def test_valid_config(self):
        c = self._valid()
        validate_experiment_config(c)  # should not raise

    def test_zero_qubits(self):
        with pytest.raises(ValidationError):
            validate_experiment_config(self._valid(qubit_count=0))

    def test_negative_ancillas(self):
        with pytest.raises(ValidationError):
            validate_experiment_config(self._valid(ancilla_count=-1))

    def test_zero_shots(self):
        with pytest.raises(ValidationError):
            validate_experiment_config(self._valid(shot_count=0))

    def test_threshold_out_of_range(self):
        with pytest.raises(ValidationError):
            validate_experiment_config(self._valid(threshold=1.5))
        with pytest.raises(ValidationError):
            validate_experiment_config(self._valid(threshold=-0.1))

    def test_theta_out_of_range(self):
        with pytest.raises(ValidationError):
            validate_experiment_config(self._valid(theta_z=10.0))
        with pytest.raises(ValidationError):
            validate_experiment_config(self._valid(theta_y=-10.0))

    def test_qec_requires_odd_distance(self):
        with pytest.raises(ValidationError):
            validate_experiment_config(self._valid(use_qec=True, code_distance=4))

    def test_qec_requires_min_distance(self):
        with pytest.raises(ValidationError):
            validate_experiment_config(self._valid(use_qec=True, code_distance=1))

    def test_valid_qec(self):
        c = self._valid(use_qec=True, code_distance=3)
        validate_experiment_config(c)  # should not raise

    def test_max_qubits(self):
        c = self._valid(qubit_count=1_000_000)
        validate_experiment_config(c)  # should not raise

    def test_over_max_qubits(self):
        with pytest.raises(ValidationError):
            validate_experiment_config(self._valid(qubit_count=1_000_001))


class TestInferenceRequestValidation:
    def _valid(self, **kwargs):
        defaults = dict(input_token_ids=[1,2,3,4,5], max_new_tokens=256,
                        temperature=0.7, top_p=0.9, beam_width=1, timeout_ms=30000)
        defaults.update(kwargs)
        return InferenceRequest(**defaults)

    def test_valid_request(self):
        r = self._valid()
        validate_inference_request(r)

    def test_empty_tokens(self):
        with pytest.raises(ValidationError):
            validate_inference_request(self._valid(input_token_ids=[]))

    def test_zero_max_tokens(self):
        with pytest.raises(ValidationError):
            validate_inference_request(self._valid(max_new_tokens=0))

    def test_negative_temperature(self):
        with pytest.raises(ValidationError):
            validate_inference_request(self._valid(temperature=-0.1))

    def test_top_p_out_of_range(self):
        with pytest.raises(ValidationError):
            validate_inference_request(self._valid(top_p=0.0))
        with pytest.raises(ValidationError):
            validate_inference_request(self._valid(top_p=1.1))

    def test_zero_beam_width(self):
        with pytest.raises(ValidationError):
            validate_inference_request(self._valid(beam_width=0))

    def test_context_window_exceeded(self):
        with pytest.raises(ValidationError):
            validate_inference_request(self._valid(input_token_ids=list(range(131073))))


class TestMAIA300ConfigValidation:
    def test_valid_config(self):
        c = MAIA300Config()
        validate_maia300_config(c)

    def test_invalid_chiplet_id(self):
        with pytest.raises(ValidationError):
            validate_maia300_config(MAIA300Config(chiplet_id=96))

    def test_tp_pp_exceeds_chiplets(self):
        with pytest.raises(ValidationError):
            validate_maia300_config(MAIA300Config(tensor_parallel_degree=50, pipeline_parallel_degree=50))


class TestBrainwaveConfigValidation:
    def test_valid_config(self):
        c = BrainwaveFPGAConfig()
        validate_brainwave_config(c)

    def test_zero_mac_units(self):
        with pytest.raises(ValidationError):
            validate_brainwave_config(BrainwaveFPGAConfig(mac_units=0))


class TestHCFConfigValidation:
    def test_valid_config(self):
        c = HollowCoreFiberConfig()
        validate_hcf_config(c)

    def test_zero_length(self):
        with pytest.raises(ValidationError):
            validate_hcf_config(HollowCoreFiberConfig(length_km=0.0))

    def test_invalid_latency_reduction(self):
        with pytest.raises(ValidationError):
            validate_hcf_config(HollowCoreFiberConfig(latency_reduction_pct=101.0))


class TestMajoranaConfigValidation:
    def test_valid_config(self):
        c = MajoranaQPUConfig()
        validate_majorana_config(c)

    def test_logical_exceeds_physical(self):
        with pytest.raises(ValidationError):
            validate_majorana_config(MajoranaQPUConfig(physical_qubits=4, logical_qubits=8))

    def test_invalid_fidelity(self):
        with pytest.raises(ValidationError):
            validate_majorana_config(MajoranaQPUConfig(gate_fidelity_2q=1.5))

    def test_code_distance_too_small(self):
        with pytest.raises(ValidationError):
            validate_majorana_config(MajoranaQPUConfig(code_distance=2))


class TestMoEConfigValidation:
    def test_valid_config(self):
        c = MoERoutingConfig()
        validate_moe_config(c)

    def test_top_k_exceeds_experts(self):
        with pytest.raises(ValidationError):
            validate_moe_config(MoERoutingConfig(num_experts=4, top_k=5))

    def test_capacity_factor_too_low(self):
        with pytest.raises(ValidationError):
            validate_moe_config(MoERoutingConfig(capacity_factor=0.5))


class TestContractProperties:
    def test_llm_architecture_param_count(self):
        from src.python.core.contracts import LLMArchitectureConfig
        cfg = LLMArchitectureConfig()
        assert cfg.total_parameters > 4_000_000_000
        assert cfg.total_parameters < 6_000_000_000

    def test_llm_architecture_model_size(self):
        from src.python.core.contracts import LLMArchitectureConfig
        cfg = LLMArchitectureConfig()
        assert cfg.model_size_gb > 5.0  # at least 5 GB at BF16

    def test_hcf_latency_reduction(self):
        c = HollowCoreFiberConfig(length_km=100.0)
        assert c.latency_us < c.smf_latency_us
        reduction = (c.smf_latency_us - c.latency_us) / c.smf_latency_us * 100
        assert abs(reduction - 47.0) < 5.0  # approximately 47%

    def test_maia300_total_memory(self):
        c = MAIA300Config()
        assert c.total_rack_memory_gb == 288.0 * 96

    def test_majorana_logical_error_rate(self):
        c = MajoranaQPUConfig()
        assert c.logical_error_rate < 1e-3  # much better than physical

    def test_experiment_result_snr(self):
        from src.python.core.contracts import ExperimentResult
        r = ExperimentResult(experiment_id="test", mean=0.6, deviation=0.1,
            above_threshold=True, shot_count=100, qubit_count=4, ancilla_count=0,
            theta_z=0.5, theta_y=0.3, threshold=0.5, backend="sim",
            timestamp_utc="2026-11-07T00:00:00Z")
        assert abs(r.snr - 6.0) < 0.01

    def test_training_config_global_batch(self):
        c = TrainingConfig(micro_batch_size=4, gradient_accum_steps=512, data_parallel=16)
        assert c.global_batch_size == 4 * 512 * 16
