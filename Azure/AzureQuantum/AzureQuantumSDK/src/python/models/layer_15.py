"""
layer_15.py — Transformer layer 15 of the 5B-parameter Windows-AGI-Mesh LLM.
Type: standard-transformer.
Architecture: 32 query heads, 8 KV heads (GQA 4:1 ratio).
FFN: SwiGLU (dim=14336).

Hardware: MAIA-300 (288GB HBM4 @ 18TB/s).
"""
from __future__ import annotations
import math, time
from typing import Dict, List, Optional, Tuple

LAYER_ID      = 15
LAYER_TYPE    = "standard-transformer"
LAYER_VERSION = "2.0.0"

HIDDEN_DIM    = 4096
NUM_HEADS     = 32
NUM_KV_HEADS  = 8
HEAD_DIM      = 128
FFN_DIM       = 14336
VOCAB_SIZE    = 131072
MAX_SEQ_LEN   = 131072
ROPE_THETA    = 500000.0
NORM_EPS      = 1e-5
NUM_EXPERTS   = 8
TOP_K_EXPERTS = 2


def rms_norm(x: List[float], weight: List[float], eps: float = NORM_EPS) -> List[float]:
    n  = len(x)
    ms = sum(v * v for v in x) / n
    sc = 1.0 / math.sqrt(ms + eps)
    return [x[j] * sc * (weight[j] if j < len(weight) else 1.0) for j in range(n)]


def rope_apply(x: List[float], position: int,
               head_dim: int = HEAD_DIM, theta: float = ROPE_THETA) -> List[float]:
    result = list(x)
    for k in range(0, head_dim, 2):
        freq  = 1.0 / (theta ** (k / head_dim))
        cos_v = math.cos(position * freq)
        sin_v = math.sin(position * freq)
        x0 = x[k]     if k     < len(x) else 0.0
        x1 = x[k + 1] if k + 1 < len(x) else 0.0
        if k     < len(result): result[k]     = x0 * cos_v - x1 * sin_v
        if k + 1 < len(result): result[k + 1] = x0 * sin_v + x1 * cos_v
    return result


def softmax(x: List[float]) -> List[float]:
    if not x:
        return []
    max_v = max(x)
    exps  = [math.exp(v - max_v) for v in x]
    total = sum(exps)
    return [e / total for e in exps] if total > 0 else exps


def silu(v: float) -> float:
    return v / (1.0 + math.exp(-v))


def swiglu(gate: List[float], up: List[float]) -> List[float]:
    return [silu(gate[j]) * up[j] for j in range(min(len(gate), len(up)))]


def linear(x: List[float], weight: List[List[float]],
           bias: Optional[List[float]] = None) -> List[float]:
    out_dim = len(weight)
    result  = [0.0] * out_dim
    for o in range(out_dim):
        s = sum(x[j] * weight[o][j] for j in range(min(len(x), len(weight[o]))))
        result[o] = s + (bias[o] if bias and o < len(bias) else 0.0)
    return result


class GroupedQueryAttention:
    """GQA: 32 query heads, 8 KV heads (4:1 ratio). Layer 15."""

    def __init__(self, hidden_dim: int = HIDDEN_DIM, num_heads: int = NUM_HEADS,
                 num_kv_heads: int = NUM_KV_HEADS, head_dim: int = HEAD_DIM,
                 max_seq_len: int = MAX_SEQ_LEN, rope_theta: float = ROPE_THETA,
                 sliding_window: Optional[int] = None) -> None:
        self.hidden_dim    = hidden_dim
        self.num_heads     = num_heads
        self.num_kv_heads  = num_kv_heads
        self.head_dim      = head_dim
        self.max_seq_len   = max_seq_len
        self.rope_theta    = rope_theta
        self.sliding_window = sliding_window
        self.groups_per_kv = num_heads // num_kv_heads
        self.scale         = 1.0 / math.sqrt(head_dim)
        self.w_q = [[0.0] * hidden_dim for _ in range(num_heads * head_dim)]
        self.w_k = [[0.0] * hidden_dim for _ in range(num_kv_heads * head_dim)]
        self.w_v = [[0.0] * hidden_dim for _ in range(num_kv_heads * head_dim)]
        self.w_o = [[0.0] * (num_heads * head_dim) for _ in range(hidden_dim)]
        self._kv_cache_k: List[List[List[float]]] = []
        self._kv_cache_v: List[List[List[float]]] = []

    @property
    def param_count(self) -> int:
        return (self.num_heads * self.head_dim * self.hidden_dim +
                self.num_kv_heads * self.head_dim * self.hidden_dim * 2 +
                self.num_heads * self.head_dim * self.hidden_dim)

    def forward(self, x: List[float], position: int,
                use_cache: bool = True) -> Tuple[List[float], Optional[Tuple]]:
        q_flat = linear(x, self.w_q)
        k_flat = linear(x, self.w_k)
        v_flat = linear(x, self.w_v)
        q_heads = [q_flat[h * self.head_dim:(h + 1) * self.head_dim]
                   for h in range(self.num_heads)]
        k_heads = [k_flat[h * self.head_dim:(h + 1) * self.head_dim]
                   for h in range(self.num_kv_heads)]
        v_heads = [v_flat[h * self.head_dim:(h + 1) * self.head_dim]
                   for h in range(self.num_kv_heads)]
        q_heads = [rope_apply(q, position, self.head_dim, self.rope_theta) for q in q_heads]
        k_heads = [rope_apply(k, position, self.head_dim, self.rope_theta) for k in k_heads]
        if use_cache:
            self._kv_cache_k.append(k_heads)
            self._kv_cache_v.append(v_heads)
            if len(self._kv_cache_k) > self.max_seq_len:
                self._kv_cache_k.pop(0)
                self._kv_cache_v.pop(0)
        context_heads = []
        for h in range(self.num_heads):
            kv_h = h // self.groups_per_kv
            q_h  = q_heads[h]
            scores = []
            for t, (k_cache, v_cache) in enumerate(zip(self._kv_cache_k, self._kv_cache_v)):
                k_t = k_cache[kv_h]
                dot = sum(q_h[d] * k_t[d] for d in range(min(len(q_h), len(k_t))))
                if self.sliding_window and t < len(self._kv_cache_k) - self.sliding_window:
                    scores.append(float("-inf"))
                else:
                    scores.append(dot * self.scale)
            attn_w = softmax(scores)
            ctx = [0.0] * self.head_dim
            for t, wt in enumerate(attn_w):
                v_t = self._kv_cache_v[t][kv_h]
                for d in range(min(self.head_dim, len(v_t))):
                    ctx[d] += wt * v_t[d]
            context_heads.append(ctx)
        ctx_flat = [v for head in context_heads for v in head]
        output   = linear(ctx_flat, self.w_o)
        return output, (k_heads, v_heads) if use_cache else None

    def clear_cache(self) -> None:
        self._kv_cache_k.clear()
        self._kv_cache_v.clear()

    def cache_size(self) -> int:
        return len(self._kv_cache_k)


class SwiGLUFFN:
    """SwiGLU FFN for layer 15. hidden=4096, ffn=14336."""

    def __init__(self, hidden_dim: int = HIDDEN_DIM, ffn_dim: int = FFN_DIM) -> None:
        self.hidden_dim = hidden_dim
        self.ffn_dim    = ffn_dim
        self.w_gate = [[0.0] * hidden_dim for _ in range(ffn_dim)]
        self.w_up   = [[0.0] * hidden_dim for _ in range(ffn_dim)]
        self.w_down = [[0.0] * ffn_dim    for _ in range(hidden_dim)]

    @property
    def param_count(self) -> int:
        return self.hidden_dim * self.ffn_dim * 3

    def forward(self, x: List[float]) -> List[float]:
        gate_out  = linear(x, self.w_gate)
        up_out    = linear(x, self.w_up)
        activated = swiglu(gate_out, up_out)
        return linear(activated, self.w_down)


class TransformerLayer15:
    """
    Full transformer layer 15 (standard-transformer).
    Attention: GroupedQueryAttention. FFN: SwiGLUFFN.
    Params: ~243M per layer.
    """

    def __init__(self, hidden_dim: int = HIDDEN_DIM, num_heads: int = NUM_HEADS,
                 num_kv_heads: int = NUM_KV_HEADS, head_dim: int = HEAD_DIM,
                 ffn_dim: int = FFN_DIM, norm_eps: float = NORM_EPS) -> None:
        self.layer_id   = LAYER_ID
        self.layer_type = LAYER_TYPE
        self.hidden_dim = hidden_dim
        self.attn_norm_weight = [1.0] * hidden_dim
        self.ffn_norm_weight  = [1.0] * hidden_dim
        self.attention = GroupedQueryAttention(hidden_dim, num_heads, num_kv_heads, head_dim)
        self.ffn = SwiGLUFFN(hidden_dim, ffn_dim)
        self._forward_count    = 0
        self._total_latency_ms = 0.0

    @property
    def param_count(self) -> int:
        attn_p = getattr(self.attention, "param_count",
                         getattr(getattr(self.attention, "classical_attn", None),
                                 "param_count", 0))
        ffn_p  = getattr(self.ffn, "param_count", 0)
        return attn_p + ffn_p + self.hidden_dim * 2

    def forward(self, x: List[float], position: int = 0,
                use_cache: bool = True) -> Tuple[List[float], Dict]:
        t0 = time.perf_counter()
        normed_x = rms_norm(x, self.attn_norm_weight)
        attn_out, cache = self.attention.forward(normed_x, position, use_cache)
        x = [x[j] + attn_out[j] for j in range(min(len(x), len(attn_out)))]
        normed_x = rms_norm(x, self.ffn_norm_weight)
        ffn_out = self.ffn.forward(normed_x); aux_loss = 0.0
        x = [x[j] + ffn_out[j] for j in range(min(len(x), len(ffn_out)))]
        elapsed_ms = (time.perf_counter() - t0) * 1000.0
        self._forward_count    += 1
        self._total_latency_ms += elapsed_ms
        meta = {
            "layer_id": self.layer_id,
            "layer_type": self.layer_type,
            "forward_count": self._forward_count,
            "latency_ms": elapsed_ms,
            "avg_latency_ms": self._total_latency_ms / self._forward_count,
            "aux_loss": aux_loss,
        }
        return x, meta

    def clear_cache(self) -> None:
        if hasattr(self.attention, "clear_cache"):
            self.attention.clear_cache()
        elif hasattr(self.attention, "classical_attn"):
            self.attention.classical_attn.clear_cache()

    def __repr__(self) -> str:
        return (f"TransformerLayer15(type={self.layer_type}, "
                f"params={self.param_count:,}, forwards={self._forward_count})")
