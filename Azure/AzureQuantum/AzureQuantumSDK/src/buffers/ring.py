"""
ring.py — High-performance ring buffer for LLM KV-cache streaming.
Supports: write, read, peek, flush, resize, snapshot, restore.
Used by MAIA-300 prefill pipeline and Brainwave FPGA attention cache.
"""
from __future__ import annotations
import threading
from typing import Any, Generic, Iterator, List, Optional, TypeVar

T = TypeVar("T")

class RingBuffer(Generic[T]):
    """Thread-safe ring buffer with O(1) read/write."""

    def __init__(self, capacity: int) -> None:
        if capacity <= 0:
            raise ValueError(f"capacity must be > 0, got {capacity}")
        self._capacity = capacity
        self._buffer: List[Optional[T]] = [None] * capacity
        self._head = 0   # write pointer
        self._tail = 0   # read pointer
        self._size = 0
        self._lock = threading.Lock()
        self._not_empty = threading.Condition(self._lock)
        self._not_full  = threading.Condition(self._lock)

    @property
    def capacity(self) -> int:
        return self._capacity

    @property
    def size(self) -> int:
        with self._lock:
            return self._size

    @property
    def is_empty(self) -> bool:
        with self._lock:
            return self._size == 0

    @property
    def is_full(self) -> bool:
        with self._lock:
            return self._size == self._capacity

    def write(self, item: T, block: bool = True, timeout: Optional[float] = None) -> bool:
        with self._not_full:
            if self._size == self._capacity:
                if not block:
                    return False
                if not self._not_full.wait(timeout=timeout):
                    return False
            self._buffer[self._head] = item
            self._head = (self._head + 1) % self._capacity
            self._size += 1
            self._not_empty.notify_all()
            return True

    def read(self, block: bool = True, timeout: Optional[float] = None) -> Optional[T]:
        with self._not_empty:
            if self._size == 0:
                if not block:
                    return None
                if not self._not_empty.wait(timeout=timeout):
                    return None
            item = self._buffer[self._tail]
            self._buffer[self._tail] = None
            self._tail = (self._tail + 1) % self._capacity
            self._size -= 1
            self._not_full.notify_all()
            return item

    def peek(self) -> Optional[T]:
        with self._lock:
            if self._size == 0:
                return None
            return self._buffer[self._tail]

    def write_many(self, items: List[T]) -> int:
        written = 0
        for item in items:
            if not self.write(item, block=False):
                break
            written += 1
        return written

    def read_many(self, n: int) -> List[T]:
        results = []
        for _ in range(n):
            item = self.read(block=False)
            if item is None:
                break
            results.append(item)
        return results

    def flush(self) -> List[T]:
        with self._lock:
            items = []
            while self._size > 0:
                items.append(self._buffer[self._tail])
                self._buffer[self._tail] = None
                self._tail = (self._tail + 1) % self._capacity
                self._size -= 1
            self._not_full.notify_all()
            return items

    def snapshot(self) -> List[Optional[T]]:
        with self._lock:
            result = []
            idx = self._tail
            for _ in range(self._size):
                result.append(self._buffer[idx])
                idx = (idx + 1) % self._capacity
            return result

    def resize(self, new_capacity: int) -> None:
        if new_capacity <= 0:
            raise ValueError(f"new_capacity must be > 0, got {new_capacity}")
        with self._lock:
            items = self.flush()
            self._capacity = new_capacity
            self._buffer   = [None] * new_capacity
            self._head = 0
            self._tail = 0
            self._size = 0
            for item in items[:new_capacity]:
                self._buffer[self._head] = item
                self._head = (self._head + 1) % new_capacity
                self._size += 1

    def __len__(self) -> int:
        return self.size

    def __iter__(self) -> Iterator[T]:
        return iter(self.snapshot())

    def __repr__(self) -> str:
        return f"RingBuffer(capacity={self._capacity}, size={self._size})"


class TokenRingBuffer(RingBuffer[int]):
    """Specialised ring buffer for LLM token IDs."""

    def write_tokens(self, token_ids: List[int]) -> int:
        return self.write_many(token_ids)

    def read_tokens(self, n: int) -> List[int]:
        return self.read_many(n)

    def to_list(self) -> List[int]:
        return [t for t in self.snapshot() if t is not None]


class FloatRingBuffer(RingBuffer[float]):
    """Ring buffer for floating-point activations (attention scores, logits)."""

    def mean(self) -> float:
        items = [x for x in self.snapshot() if x is not None]
        return sum(items) / len(items) if items else 0.0

    def max_val(self) -> float:
        items = [x for x in self.snapshot() if x is not None]
        return max(items) if items else float("-inf")

    def min_val(self) -> float:
        items = [x for x in self.snapshot() if x is not None]
        return min(items) if items else float("inf")


class KVCacheRingBuffer:
    """
    Dual ring buffer for transformer KV-cache.
    Maintains separate key and value buffers per attention head.
    Used by MAIA-300 prefill and Brainwave FPGA decode.
    """

    def __init__(self, num_heads: int, head_dim: int, max_seq_len: int) -> None:
        self.num_heads   = num_heads
        self.head_dim    = head_dim
        self.max_seq_len = max_seq_len
        self._key_buffers   = [FloatRingBuffer(max_seq_len * head_dim) for _ in range(num_heads)]
        self._value_buffers = [FloatRingBuffer(max_seq_len * head_dim) for _ in range(num_heads)]
        self._seq_len = 0

    def write_kv(self, head_idx: int, key_vec: List[float], value_vec: List[float]) -> None:
        if head_idx < 0 or head_idx >= self.num_heads:
            raise IndexError(f"head_idx {head_idx} out of range [0, {self.num_heads})")
        if len(key_vec) != self.head_dim:
            raise ValueError(f"key_vec length {len(key_vec)} != head_dim {self.head_dim}")
        if len(value_vec) != self.head_dim:
            raise ValueError(f"value_vec length {len(value_vec)} != head_dim {self.head_dim}")
        self._key_buffers[head_idx].write_many(key_vec)
        self._value_buffers[head_idx].write_many(value_vec)
        if head_idx == 0:
            self._seq_len += 1

    def read_kv(self, head_idx: int) -> tuple:
        keys   = self._key_buffers[head_idx].read_many(self.head_dim)
        values = self._value_buffers[head_idx].read_many(self.head_dim)
        return keys, values

    def flush_all(self) -> None:
        for buf in self._key_buffers + self._value_buffers:
            buf.flush()
        self._seq_len = 0

    @property
    def seq_len(self) -> int:
        return self._seq_len

    @property
    def memory_bytes(self) -> int:
        return self.num_heads * self.max_seq_len * self.head_dim * 2 * 4  # key+value, float32

    def __repr__(self) -> str:
        return (f"KVCacheRingBuffer(heads={self.num_heads}, "
                f"head_dim={self.head_dim}, seq_len={self._seq_len}/{self.max_seq_len})")
