"""Classical factorization algorithms."""
import math

def gcd(a: int, b: int) -> int:
    while b: a, b = b, a % b
    return a

def mod_pow(base: int, exp: int, mod: int) -> int:
    result, b = 1, base % mod
    while exp > 0:
        if exp % 2 == 1: result = (result * b) % mod
        exp //= 2; b = (b * b) % mod
    return result

def is_prime(n: int) -> bool:
    if n < 2: return False
    if n in (2,3,5,7): return True
    if n % 2 == 0 or n % 3 == 0: return False
    i = 5
    while i*i <= n:
        if n % i == 0 or n % (i+2) == 0: return False
        i += 6
    return True

def trial_division(n: int) -> tuple:
    if n % 2 == 0: return (2, n//2)
    i = 3
    while i*i <= n:
        if n % i == 0: return (i, n//i)
        i += 2
    return (1, n)

def pollards_rho(n: int) -> int:
    if n % 2 == 0: return 2
    x, y, c, d = 2, 2, 1, 1
    while d == 1:
        x = (x*x + c) % n
        y = (y*y + c) % n; y = (y*y + c) % n
        d = gcd(abs(x-y), n)
    return d if d != n else -1
