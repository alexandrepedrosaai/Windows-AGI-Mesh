"""
registry.py — Model registry for Windows-AGI-Mesh-QuantumSDK.
Manages model versions, weight shards, quantization configs, and deployment.
"""
from __future__ import annotations
import hashlib, json, logging, time, uuid
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any, Dict, List, Optional

logger = logging.getLogger(__name__)

@dataclass
class ModelVersion:
    model_id:        str   = field(default_factory=lambda: str(uuid.uuid4()))
    name:            str   = "windows-agi-mesh-5b"
    version:         str   = "1.0.0"
    description:     str   = ""
    parameter_count: int   = 5_000_000_000
    hidden_dim:      int   = 4096
    num_layers:      int   = 36
    num_heads:       int   = 32
    num_kv_heads:    int   = 8
    head_dim:        int   = 128
    ffn_dim:         int   = 14336
    vocab_size:      int   = 131072
    max_seq_len:     int   = 131072
    quantization:    str   = "hybrid-q4-bf16"
    architecture:    str   = "transformer-gqa-moe-quantum"
    training_tokens: int   = 15_000_000_000_000
    created_at:      float = field(default_factory=time.time)
    is_active:       bool  = True
    shard_count:     int   = 8
    shard_urls:      List[str] = field(default_factory=list)
    checksum:        str   = ""
    tags:            List[str] = field(default_factory=list)

    @property
    def size_gb_bf16(self) -> float:
        return self.parameter_count * 2 / 1e9

    @property
    def size_gb_int4(self) -> float:
        return self.parameter_count * 0.5 / 1e9

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)

    def to_json(self) -> str:
        return json.dumps(self.to_dict(), indent=2)


class ModelRegistry:
    """Central registry for all model versions and weight shards."""

    def __init__(self, registry_path: Optional[Path] = None) -> None:
        self._registry_path = registry_path or Path("models/registry.json")
        self._models: Dict[str, ModelVersion] = {}
        self._active_model: Optional[str] = None
        self._load()

    def _load(self) -> None:
        if self._registry_path.exists():
            try:
                data = json.loads(self._registry_path.read_text())
                for d in data.get("models", []):
                    m = ModelVersion(**{k: v for k, v in d.items()
                                        if k in ModelVersion.__dataclass_fields__})
                    self._models[m.model_id] = m
                self._active_model = data.get("active_model")
                logger.info("Loaded %d models from registry", len(self._models))
            except Exception as exc:
                logger.error("Failed to load registry: %s", exc)

    def _save(self) -> None:
        self._registry_path.parent.mkdir(parents=True, exist_ok=True)
        data = {"active_model": self._active_model,
                "models": [m.to_dict() for m in self._models.values()]}
        self._registry_path.write_text(json.dumps(data, indent=2))

    def register(self, model: ModelVersion) -> str:
        self._models[model.model_id] = model
        if not self._active_model:
            self._active_model = model.model_id
        self._save()
        logger.info("Registered model %s v%s (%.1f GB BF16)",
                    model.name, model.version, model.size_gb_bf16)
        return model.model_id

    def get(self, model_id: str) -> Optional[ModelVersion]:
        return self._models.get(model_id)

    def get_active(self) -> Optional[ModelVersion]:
        return self._models.get(self._active_model) if self._active_model else None

    def activate(self, model_id: str) -> None:
        if model_id not in self._models:
            raise KeyError(f"Model {model_id} not found")
        self._active_model = model_id
        self._save()

    def list_models(self, active_only: bool = False) -> List[ModelVersion]:
        models = list(self._models.values())
        if active_only:
            models = [m for m in models if m.is_active]
        return sorted(models, key=lambda m: m.created_at, reverse=True)

    def delete(self, model_id: str) -> bool:
        if model_id in self._models:
            del self._models[model_id]
            if self._active_model == model_id:
                self._active_model = None
            self._save()
            return True
        return False

    def stats(self) -> Dict[str, Any]:
        models = list(self._models.values())
        return {"total_models": len(models), "active_model": self._active_model,
                "total_parameters": sum(m.parameter_count for m in models),
                "total_size_gb_bf16": sum(m.size_gb_bf16 for m in models)}

    def __repr__(self) -> str:
        return f"ModelRegistry(models={len(self._models)}, active={self._active_model!r})"


_default_registry: Optional[ModelRegistry] = None

def get_registry(path: Optional[Path] = None) -> ModelRegistry:
    global _default_registry
    if _default_registry is None:
        _default_registry = ModelRegistry(path)
    return _default_registry

def register_default_model() -> str:
    registry = get_registry()
    model = ModelVersion(
        name="windows-agi-mesh-5b", version="1.0.0",
        description="5B-param LLM: quantum-hybrid layers, MoE, GQA, 15T tokens.",
        parameter_count=5_000_000_000, quantization="hybrid-q4-bf16",
        architecture="transformer-gqa-moe-quantum",
        training_tokens=15_000_000_000_000,
        tags=["production", "quantum-hybrid", "moe", "gqa", "maia-300"])
    return registry.register(model)
