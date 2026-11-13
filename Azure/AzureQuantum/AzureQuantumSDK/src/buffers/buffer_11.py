"""
buffer_11.py — Specialised buffer module 11 for Windows-AGI-Mesh-QuantumSDK.
Handles: activation checkpointing pipeline stage 11.
Integrates with MAIA-300 HBM4 (288 GB @ 18 TB/s) and Brainwave FPGA on-chip SRAM.
"""
from __future__ import annotations
import math, threading, time, uuid
from typing import Any, Dict, List, Optional, Tuple
from .ring import RingBuffer, FloatRingBuffer, KVCacheRingBuffer
from .tensor import TensorBuffer

BUFFER_ID = 11
BUFFER_VERSION = "2.0.0"
BUFFER_DESCRIPTION = "Stage-11 buffer for AGI-Mesh pipeline"

class Buffer11:
    """
    Pipeline buffer stage 11.
    Checkpoints activations at layer 0.
    """

    def __init__(self, capacity: int = 65536, num_heads: int = 32,
                 head_dim: int = 128, dtype: str = "bfloat16") -> None:
        self.buffer_id   = BUFFER_ID
        self.capacity    = capacity
        self.num_heads   = num_heads
        self.head_dim    = head_dim
        self.dtype       = dtype
        self._lock       = threading.RLock()
        self._created_at = time.time()
        self._write_count = 0
        self._read_count  = 0
        self._session_id  = str(uuid.uuid4())

        # Primary storage
        self._token_buffer = RingBuffer[int](capacity)
        self._float_buffer = FloatRingBuffer(capacity)
        self._kv_cache     = KVCacheRingBuffer(num_heads, head_dim, capacity // head_dim)

        # Tensor storage for activations
        self._activation_shape = (1, capacity, head_dim * num_heads)
        self._activation_buf   = TensorBuffer(self._activation_shape, dtype)

        # Metadata
        self._metadata: Dict[str, Any] = {
            "buffer_id": BUFFER_ID,
            "version": BUFFER_VERSION,
            "description": BUFFER_DESCRIPTION,
            "capacity": capacity,
            "num_heads": num_heads,
            "head_dim": head_dim,
            "dtype": dtype,
        }

    # ── Token operations ──────────────────────────────────────────────────────
    def write_tokens(self, token_ids: List[int]) -> int:
        with self._lock:
            written = self._token_buffer.write_many(token_ids)
            self._write_count += written
            return written

    def read_tokens(self, n: int) -> List[int]:
        with self._lock:
            tokens = self._token_buffer.read_many(n)
            self._read_count += len(tokens)
            return tokens

    def peek_tokens(self, n: int) -> List[int]:
        with self._lock:
            snap = self._token_buffer.snapshot()
            return [t for t in snap[:n] if t is not None]

    # ── Float operations ──────────────────────────────────────────────────────
    def write_floats(self, values: List[float]) -> int:
        with self._lock:
            return self._float_buffer.write_many(values)

    def read_floats(self, n: int) -> List[float]:
        with self._lock:
            return self._float_buffer.read_many(n)

    def float_mean(self) -> float:
        return self._float_buffer.mean()

    def float_max(self) -> float:
        return self._float_buffer.max_val()

    # ── KV-cache operations ───────────────────────────────────────────────────
    def write_kv(self, head_idx: int, key: List[float], value: List[float]) -> None:
        with self._lock:
            self._kv_cache.write_kv(head_idx, key, value)

    def read_kv(self, head_idx: int) -> Tuple[List[float], List[float]]:
        with self._lock:
            return self._kv_cache.read_kv(head_idx)

    def flush_kv(self) -> None:
        with self._lock:
            self._kv_cache.flush_all()

    # ── Activation operations ─────────────────────────────────────────────────
    def write_activation(self, data: List[float], position: int = 0) -> None:
        with self._lock:
            inner = self.head_dim * self.num_heads
            offset = position * inner
            for i, v in enumerate(data[:inner]):
                if offset + i < self._activation_buf.size:
                    self._activation_buf._data[offset + i] = v

    def read_activation(self, position: int = 0) -> List[float]:
        with self._lock:
            inner  = self.head_dim * self.num_heads
            offset = position * inner
            return self._activation_buf._data[offset:offset + inner]

    def apply_layer_norm(self, weight: List[float], bias: List[float]) -> None:
        with self._lock:
            normed = self._activation_buf.layer_norm(weight, bias)
            self._activation_buf._data = normed._data

    def apply_rope(self, position: int, theta: float = 500000.0) -> None:
        with self._lock:
            roped = self._activation_buf.rope_embed(position, theta)
            self._activation_buf._data = roped._data

    # ── Quantization ──────────────────────────────────────────────────────────
    def quantize_activations_int8(self) -> Tuple[bytes, float, int]:
        with self._lock:
            return self._activation_buf.quantize_int8()

    def quantize_activations_int4(self) -> Tuple[bytes, float, int]:
        with self._lock:
            return self._activation_buf.quantize_int4()

    def dequantize_activations(self, data: bytes, scale: float, zp: int = 0) -> None:
        with self._lock:
            self._activation_buf.dequantize_int8(data, scale, zp)

    # ── Flush and reset ───────────────────────────────────────────────────────
    def flush_all(self) -> Dict[str, int]:
        with self._lock:
            tokens = len(self._token_buffer.flush())
            floats = len(self._float_buffer.flush())
            self._kv_cache.flush_all()
            self._activation_buf.zeros()
            return {"tokens": tokens, "floats": floats}

    def reset_stats(self) -> None:
        with self._lock:
            self._write_count = 0
            self._read_count  = 0

    # ── Properties ────────────────────────────────────────────────────────────
    @property
    def token_count(self) -> int:
        return self._token_buffer.size

    @property
    def float_count(self) -> int:
        return self._float_buffer.size

    @property
    def kv_seq_len(self) -> int:
        return self._kv_cache.seq_len

    @property
    def write_count(self) -> int:
        return self._write_count

    @property
    def read_count(self) -> int:
        return self._read_count

    @property
    def memory_bytes(self) -> int:
        return (self._kv_cache.memory_bytes +
                self._activation_buf.nbytes +
                self.capacity * 8)  # token + float buffers

    @property
    def memory_gb(self) -> float:
        return self.memory_bytes / 1e9

    @property
    def uptime_seconds(self) -> float:
        return time.time() - self._created_at

    def stats(self) -> Dict[str, Any]:
        return {
            "buffer_id": self.buffer_id,
            "session_id": self._session_id,
            "token_count": self.token_count,
            "float_count": self.float_count,
            "kv_seq_len": self.kv_seq_len,
            "write_count": self._write_count,
            "read_count": self._read_count,
            "memory_gb": round(self.memory_gb, 4),
            "uptime_seconds": round(self.uptime_seconds, 2),
        }

    def __repr__(self) -> str:
        return (f"Buffer11(tokens={self.token_count}, "
                f"kv_seq={self.kv_seq_len}, mem={self.memory_gb:.3f} GB)")
