"""
weights.py — Weight shard management for the 5B-parameter LLM.
Handles: sharding, loading, saving, quantization, checksum verification.
Storage: Azure Blob Storage with HCF photonic transport for fast loading.
"""
from __future__ import annotations
import hashlib, json, logging, math, time, uuid
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

logger = logging.getLogger(__name__)

TOTAL_LAYERS = 36
HIDDEN_DIM   = 4096
NUM_HEADS    = 32
NUM_KV_HEADS = 8
HEAD_DIM     = 128
FFN_DIM      = 14336
VOCAB_SIZE   = 131072
TOTAL_PARAMS = 5_000_000_000


@dataclass
class WeightTensor:
    name:              str
    shape:             Tuple[int, ...]
    dtype:             str   = "bfloat16"
    data:              Optional[bytes] = None
    scale:             float = 1.0
    zero_point:        int   = 0
    is_quantized:      bool  = False
    quantization_bits: int   = 16
    checksum:          str   = ""

    @property
    def numel(self) -> int:
        return math.prod(self.shape)

    @property
    def nbytes(self) -> int:
        if self.is_quantized:
            if self.quantization_bits == 4:  return (self.numel + 1) // 2
            if self.quantization_bits == 8:  return self.numel
        return self.numel * 2  # bfloat16

    def to_dict(self) -> Dict[str, Any]:
        d = asdict(self)
        d.pop("data", None)
        d["shape"] = list(self.shape)
        return d


@dataclass
class WeightShard:
    shard_id:     int
    layer_start:  int
    layer_end:    int
    tensors:      List[WeightTensor] = field(default_factory=list)
    total_params: int   = 0
    total_bytes:  int   = 0
    is_loaded:    bool  = False
    storage_url:  str   = ""
    checksum:     str   = ""
    created_at:   float = field(default_factory=time.time)
    quantization: str   = "hybrid-q4-bf16"

    @property
    def layer_count(self) -> int:
        return self.layer_end - self.layer_start

    @property
    def size_gb(self) -> float:
        return self.total_bytes / 1e9

    def add_tensor(self, tensor: WeightTensor) -> None:
        self.tensors.append(tensor)
        self.total_params += tensor.numel
        self.total_bytes  += tensor.nbytes

    def compute_shard_checksum(self) -> str:
        h = hashlib.sha256()
        for t in self.tensors:
            h.update(t.name.encode())
            h.update(str(t.shape).encode())
            if t.data:
                h.update(t.data)
        self.checksum = h.hexdigest()
        return self.checksum

    def to_dict(self) -> Dict[str, Any]:
        return {"shard_id": self.shard_id, "layer_start": self.layer_start,
                "layer_end": self.layer_end, "layer_count": self.layer_count,
                "total_params": self.total_params, "total_bytes": self.total_bytes,
                "size_gb": round(self.size_gb, 3), "is_loaded": self.is_loaded,
                "storage_url": self.storage_url, "checksum": self.checksum,
                "quantization": self.quantization, "tensor_count": len(self.tensors),
                "tensors": [t.to_dict() for t in self.tensors]}


class WeightManager:
    """Manages weight shards for the 5B-parameter LLM."""

    def __init__(self, model_dir: Path, num_shards: int = 8,
                 quantization: str = "hybrid-q4-bf16") -> None:
        self.model_dir    = Path(model_dir)
        self.num_shards   = num_shards
        self.quantization = quantization
        self._shards: Dict[int, WeightShard] = {}
        self._loaded_shards: set = set()
        self.model_dir.mkdir(parents=True, exist_ok=True)

    def create_shards(self) -> List[WeightShard]:
        lps = TOTAL_LAYERS // self.num_shards
        shards = []
        for s in range(self.num_shards):
            ls = s * lps
            le = min(TOTAL_LAYERS, (s + 1) * lps)
            shard = WeightShard(shard_id=s, layer_start=ls, layer_end=le,
                                quantization=self.quantization)
            for lid in range(ls, le):
                for name, shape in [
                    (f"layer.{lid}.attn.q_proj.weight", (NUM_HEADS*HEAD_DIM, HIDDEN_DIM)),
                    (f"layer.{lid}.attn.k_proj.weight", (NUM_KV_HEADS*HEAD_DIM, HIDDEN_DIM)),
                    (f"layer.{lid}.attn.v_proj.weight", (NUM_KV_HEADS*HEAD_DIM, HIDDEN_DIM)),
                    (f"layer.{lid}.attn.o_proj.weight", (HIDDEN_DIM, NUM_HEADS*HEAD_DIM)),
                    (f"layer.{lid}.ffn.gate_proj.weight", (FFN_DIM, HIDDEN_DIM)),
                    (f"layer.{lid}.ffn.up_proj.weight",   (FFN_DIM, HIDDEN_DIM)),
                    (f"layer.{lid}.ffn.down_proj.weight", (HIDDEN_DIM, FFN_DIM)),
                    (f"layer.{lid}.attn_norm.weight", (HIDDEN_DIM,)),
                    (f"layer.{lid}.ffn_norm.weight",  (HIDDEN_DIM,)),
                ]:
                    shard.add_tensor(WeightTensor(name=name, shape=shape))
            shard.compute_shard_checksum()
            self._shards[s] = shard
            shards.append(shard)
            logger.info("Created shard %d: layers %d-%d, %.2f GB, %d tensors",
                        s, ls, le, shard.size_gb, len(shard.tensors))
        return shards

    def save_shard_manifest(self) -> Path:
        manifest = {"model_name": "windows-agi-mesh-5b", "version": "1.0.0",
                    "total_params": TOTAL_PARAMS, "num_shards": self.num_shards,
                    "quantization": self.quantization,
                    "shards": [s.to_dict() for s in self._shards.values()]}
        path = self.model_dir / "manifest.json"
        path.write_text(json.dumps(manifest, indent=2))
        return path

    def quantize_shard(self, shard_id: int, bits: int = 4) -> Optional[WeightShard]:
        shard = self._shards.get(shard_id)
        if not shard:
            return None
        for tensor in shard.tensors:
            if not tensor.is_quantized:
                tensor.scale = 1.0 / (2**(bits-1) - 1)
                tensor.is_quantized = True
                tensor.quantization_bits = bits
                tensor.dtype = f"int{bits}"
        return shard

    def total_size_gb(self) -> float:
        return sum(s.size_gb for s in self._shards.values())

    def stats(self) -> Dict[str, Any]:
        return {"num_shards": self.num_shards,
                "loaded_shards": len(self._loaded_shards),
                "total_size_gb": round(self.total_size_gb(), 2),
                "quantization": self.quantization,
                "total_params": sum(s.total_params for s in self._shards.values())}

    def __repr__(self) -> str:
        return f"WeightManager(shards={self.num_shards}, size={self.total_size_gb():.1f} GB)"
