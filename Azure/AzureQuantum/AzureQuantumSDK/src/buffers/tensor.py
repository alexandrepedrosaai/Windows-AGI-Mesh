"""
tensor.py — Tensor buffer for LLM activations, gradients, and weight shards.
Supports: allocate, write, read, slice, reshape, quantize, dequantize.
Designed for MAIA-300 HBM4 memory layout (288 GB @ 18 TB/s).
"""
from __future__ import annotations
import math, struct
from typing import List, Optional, Tuple, Union

class TensorBuffer:
    """
    Flat tensor buffer with shape tracking.
    Stores float32 data in row-major (C-contiguous) order.
    Supports quantization to INT4/INT8/FP8 for MAIA-300 and Brainwave FPGA.
    """

    def __init__(self, shape: Tuple[int, ...], dtype: str = "float32") -> None:
        if not shape:
            raise ValueError("shape must not be empty")
        for d in shape:
            if d <= 0:
                raise ValueError(f"All dimensions must be > 0, got {shape}")
        self._shape  = shape
        self._dtype  = dtype
        self._size   = math.prod(shape)
        self._data: List[float] = [0.0] * self._size
        self._quantized: Optional[bytes] = None
        self._scale: float = 1.0
        self._zero_point: int = 0

    @property
    def shape(self) -> Tuple[int, ...]:
        return self._shape

    @property
    def dtype(self) -> str:
        return self._dtype

    @property
    def size(self) -> int:
        return self._size

    @property
    def ndim(self) -> int:
        return len(self._shape)

    @property
    def nbytes(self) -> int:
        dtype_bytes = {"float32": 4, "float16": 2, "bfloat16": 2,
                       "int8": 1, "int4": 1, "uint8": 1}
        return self._size * dtype_bytes.get(self._dtype, 4)

    def _flat_index(self, indices: Tuple[int, ...]) -> int:
        if len(indices) != len(self._shape):
            raise IndexError(f"Expected {len(self._shape)} indices, got {len(indices)}")
        flat = 0
        stride = 1
        for i in reversed(range(len(self._shape))):
            if not 0 <= indices[i] < self._shape[i]:
                raise IndexError(f"Index {indices[i]} out of range [0, {self._shape[i]}) at dim {i}")
            flat += indices[i] * stride
            stride *= self._shape[i]
        return flat

    def __getitem__(self, indices: Union[int, Tuple[int, ...]]) -> float:
        if isinstance(indices, int):
            indices = (indices,)
        return self._data[self._flat_index(indices)]

    def __setitem__(self, indices: Union[int, Tuple[int, ...]], value: float) -> None:
        if isinstance(indices, int):
            indices = (indices,)
        self._data[self._flat_index(indices)] = float(value)

    def fill(self, value: float) -> None:
        self._data = [value] * self._size

    def zeros(self) -> None:
        self.fill(0.0)

    def ones(self) -> None:
        self.fill(1.0)

    def from_list(self, data: List[float]) -> None:
        if len(data) != self._size:
            raise ValueError(f"Data length {len(data)} != tensor size {self._size}")
        self._data = list(data)

    def to_list(self) -> List[float]:
        return list(self._data)

    def reshape(self, new_shape: Tuple[int, ...]) -> "TensorBuffer":
        new_size = math.prod(new_shape)
        if new_size != self._size:
            raise ValueError(f"Cannot reshape {self._shape} (size={self._size}) to {new_shape} (size={new_size})")
        result = TensorBuffer(new_shape, self._dtype)
        result._data = list(self._data)
        return result

    def slice_dim0(self, start: int, end: int) -> "TensorBuffer":
        if self.ndim < 1:
            raise ValueError("Cannot slice 0-dim tensor")
        if not 0 <= start < end <= self._shape[0]:
            raise IndexError(f"Slice [{start}:{end}] out of range [0, {self._shape[0]}]")
        inner_size = self._size // self._shape[0]
        new_shape  = (end - start,) + self._shape[1:]
        result     = TensorBuffer(new_shape, self._dtype)
        result._data = self._data[start * inner_size : end * inner_size]
        return result

    def add_(self, other: "TensorBuffer") -> None:
        if other._size != self._size:
            raise ValueError(f"Size mismatch: {self._size} vs {other._size}")
        for i in range(self._size):
            self._data[i] += other._data[i]

    def scale_(self, factor: float) -> None:
        for i in range(self._size):
            self._data[i] *= factor

    def clip_(self, lo: float, hi: float) -> None:
        for i in range(self._size):
            self._data[i] = max(lo, min(hi, self._data[i]))

    def abs_max(self) -> float:
        return max(abs(v) for v in self._data) if self._data else 0.0

    def mean(self) -> float:
        return sum(self._data) / self._size if self._size else 0.0

    def std(self) -> float:
        m = self.mean()
        var = sum((v - m) ** 2 for v in self._data) / self._size
        return math.sqrt(max(0.0, var))

    def quantize_int8(self) -> Tuple[bytes, float, int]:
        """Quantize to INT8 symmetric. Returns (bytes, scale, zero_point)."""
        abs_max = self.abs_max()
        scale   = abs_max / 127.0 if abs_max > 0 else 1.0
        quantized = bytes([
            max(-128, min(127, round(v / scale))) & 0xFF
            for v in self._data
        ])
        self._quantized  = quantized
        self._scale      = scale
        self._zero_point = 0
        return quantized, scale, 0

    def quantize_int4(self) -> Tuple[bytes, float, int]:
        """Quantize to INT4 (packed 2 values per byte)."""
        abs_max = self.abs_max()
        scale   = abs_max / 7.0 if abs_max > 0 else 1.0
        nibbles = [max(-8, min(7, round(v / scale))) & 0xF for v in self._data]
        packed  = bytes([
            (nibbles[i] << 4) | (nibbles[i+1] if i+1 < len(nibbles) else 0)
            for i in range(0, len(nibbles), 2)
        ])
        self._quantized  = packed
        self._scale      = scale
        self._zero_point = 0
        return packed, scale, 0

    def dequantize_int8(self, quantized: bytes, scale: float, zero_point: int = 0) -> None:
        """Restore float32 from INT8."""
        self._data = [
            (int.from_bytes([b], "big", signed=True) - zero_point) * scale
            for b in quantized
        ]

    def matmul(self, other: "TensorBuffer") -> "TensorBuffer":
        """2D matrix multiplication."""
        if self.ndim != 2 or other.ndim != 2:
            raise ValueError("matmul requires 2D tensors")
        m, k1 = self._shape
        k2, n = other._shape
        if k1 != k2:
            raise ValueError(f"matmul: inner dims {k1} != {k2}")
        result = TensorBuffer((m, n), self._dtype)
        for i in range(m):
            for j in range(n):
                s = 0.0
                for k in range(k1):
                    s += self._data[i * k1 + k] * other._data[k * n + j]
                result._data[i * n + j] = s
        return result

    def softmax(self, dim: int = -1) -> "TensorBuffer":
        """Softmax along last dimension."""
        if self.ndim < 1:
            raise ValueError("softmax requires at least 1D tensor")
        result = TensorBuffer(self._shape, self._dtype)
        inner = self._shape[-1]
        outer = self._size // inner
        for o in range(outer):
            row = self._data[o * inner : (o + 1) * inner]
            max_v = max(row)
            exps  = [math.exp(v - max_v) for v in row]
            total = sum(exps)
            for i, e in enumerate(exps):
                result._data[o * inner + i] = e / total
        return result

    def layer_norm(self, weight: List[float], bias: List[float], eps: float = 1e-5) -> "TensorBuffer":
        """Layer normalization along last dimension."""
        result = TensorBuffer(self._shape, self._dtype)
        inner  = self._shape[-1]
        outer  = self._size // inner
        for o in range(outer):
            row  = self._data[o * inner : (o + 1) * inner]
            mean = sum(row) / inner
            var  = sum((v - mean) ** 2 for v in row) / inner
            std  = math.sqrt(var + eps)
            for i, v in enumerate(row):
                w = weight[i] if i < len(weight) else 1.0
                b = bias[i]   if i < len(bias)   else 0.0
                result._data[o * inner + i] = ((v - mean) / std) * w + b
        return result

    def rope_embed(self, position: int, theta: float = 500000.0) -> "TensorBuffer":
        """Apply Rotary Position Embedding (RoPE) to this tensor."""
        result = TensorBuffer(self._shape, self._dtype)
        d = self._shape[-1]
        for i in range(0, d, 2):
            freq = 1.0 / (theta ** (i / d))
            cos_val = math.cos(position * freq)
            sin_val = math.sin(position * freq)
            for o in range(self._size // d):
                base = o * d
                x0 = self._data[base + i]
                x1 = self._data[base + i + 1] if i + 1 < d else 0.0
                result._data[base + i]     = x0 * cos_val - x1 * sin_val
                if i + 1 < d:
                    result._data[base + i + 1] = x0 * sin_val + x1 * cos_val
        return result

    def __repr__(self) -> str:
        return f"TensorBuffer(shape={self._shape}, dtype={self._dtype}, nbytes={self.nbytes})"
