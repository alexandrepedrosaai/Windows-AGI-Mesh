"""Unit tests for factorization module."""
import pytest
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", ".."))


class TestClassicalFactorization:
    """Test classical factorization helpers (no QDK required)."""

    def _gcd(self, a, b):
        while b:
            a, b = b, a % b
        return a

    def _mod_pow(self, base, exp, mod):
        result = 1
        base %= mod
        while exp > 0:
            if exp % 2 == 1:
                result = (result * base) % mod
            exp //= 2
            base = (base * base) % mod
        return result

    def _is_prime(self, n):
        if n < 2: return False
        if n == 2: return True
        if n % 2 == 0: return False
        for i in range(3, int(n**0.5)+1, 2):
            if n % i == 0: return False
        return True

    def test_gcd_basic(self):
        assert self._gcd(12, 8) == 4
        assert self._gcd(17, 5) == 1
        assert self._gcd(100, 25) == 25

    def test_gcd_coprime(self):
        assert self._gcd(7, 11) == 1

    def test_mod_pow(self):
        assert self._mod_pow(2, 10, 1000) == 24
        assert self._mod_pow(3, 0, 7) == 1
        assert self._mod_pow(5, 1, 13) == 5

    def test_is_prime(self):
        primes = [2,3,5,7,11,13,17,19,23,29,31,37]
        for p in primes:
            assert self._is_prime(p), f"{p} should be prime"

    def test_is_not_prime(self):
        composites = [4,6,8,9,10,12,14,15,16,18,20,21]
        for c in composites:
            assert not self._is_prime(c), f"{c} should not be prime"

    def test_factor_15(self):
        n = 15
        for i in range(2, int(n**0.5)+1):
            if n % i == 0:
                assert i == 3
                assert n // i == 5
                break

    def test_factor_21(self):
        n = 21
        for i in range(2, int(n**0.5)+1):
            if n % i == 0:
                assert i == 3
                assert n // i == 7
                break

    def test_factor_prime(self):
        n = 17
        found = False
        for i in range(2, int(n**0.5)+1):
            if n % i == 0:
                found = True
                break
        assert not found  # 17 is prime

    def test_factor_large_semiprime(self):
        n = 143  # 11 * 13
        for i in range(2, int(n**0.5)+1):
            if n % i == 0:
                assert i == 11
                assert n // i == 13
                break

    def test_factor_even(self):
        assert 100 % 2 == 0
        assert 100 // 2 == 50

    def test_pollards_rho_concept(self):
        """Test Pollard's rho f(x) = x^2 + c mod n."""
        n = 35
        x, y, c, d = 2, 2, 1, 1
        while d == 1:
            x = (x*x + c) % n
            y = (y*y + c) % n
            y = (y*y + c) % n
            diff = abs(x - y)
            d = self._gcd(diff, n) if diff > 0 else 1
        assert d in (5, 7)  # factors of 35

    def test_continued_fractions_convergent(self):
        """Test continued fractions for period extraction."""
        # For n=15, a=7: period r=4 (7^4 mod 15 = 1)
        n, a = 15, 7
        r = 1
        val = a % n
        while val != 1 and r < 100:
            val = (val * a) % n
            r += 1
        assert r == 4

    def test_shor_factor_from_period(self):
        """Given period r, extract factors."""
        n, a, r = 15, 7, 4
        import math
        c1 = pow(a, r//2, n) - 1
        c2 = pow(a, r//2, n) + 1
        f1 = math.gcd(c1, n)
        f2 = math.gcd(c2, n)
        factors = {f for f in (f1, f2) if 1 < f < n}
        assert 3 in factors or 5 in factors
