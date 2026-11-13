"""Quantum factorization planning."""
import math
from .classical import gcd, mod_pow, is_prime

def plan_shors(n: int) -> dict:
    if n < 2: raise ValueError(f"n must be >= 2, got {n}")
    if is_prime(n): return {"n": n, "is_prime": True, "algorithm": "primality-test"}
    if n % 2 == 0: return {"n": n, "factor1": 2, "factor2": n//2, "algorithm": "classical-even"}
    n_bits = math.ceil(math.log2(n)) + 1
    return {
        "n": n, "n_bits": n_bits,
        "control_qubits": 2 * n_bits,
        "register_qubits": n_bits,
        "total_qubits": 3 * n_bits,
        "circuit_depth": 2 * n_bits * n_bits,
        "t_gate_count": n_bits * 100,
        "algorithm": "shor-quantum",
        "backend_recommendation": "microsoft.majorana-1" if n_bits <= 10 else "microsoft.resource-estimator",
    }
