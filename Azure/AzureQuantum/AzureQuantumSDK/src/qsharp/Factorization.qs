// =============================================================================
// Factorization.qs — Shor's algorithm and quantum period finding
// =============================================================================

namespace WindowsAGI.QuantumSDK.Factorization {

    import Std.Arrays.*;
    import Std.Convert.*;
    import Std.Intrinsic.*;
    import Std.Math.*;
    import Std.Measurement.*;

    import WindowsAGI.QuantumSDK.Circuits.*;
    import WindowsAGI.QuantumSDK.Types.*;
    import WindowsAGI.QuantumSDK.Validation.*;

    // ─────────────────────────────────────────────────────────────────────────
    // Classical GCD (Euclidean)
    // ─────────────────────────────────────────────────────────────────────────
    function GCD(a : Int, b : Int) : Int {
        mutable x = a;
        mutable y = b;
        while y != 0 {
            let tmp = y;
            set y = x % y;
            set x = tmp;
        }
        return x;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Modular exponentiation (classical)
    // ─────────────────────────────────────────────────────────────────────────
    function ModPow(base : Int, exp : Int, modulus : Int) : Int {
        if modulus == 1 { return 0; }
        mutable result = 1;
        mutable b = base % modulus;
        mutable e = exp;
        while e > 0 {
            if e % 2 == 1 { set result = (result * b) % modulus; }
            set e = e / 2;
            set b = (b * b) % modulus;
        }
        return result;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Classical primality test (Miller-Rabin, deterministic for small n)
    // ─────────────────────────────────────────────────────────────────────────
    function IsPrime(n : Int) : Bool {
        if n < 2 { return false; }
        if n == 2 or n == 3 or n == 5 or n == 7 { return true; }
        if n % 2 == 0 or n % 3 == 0 { return false; }
        let witnesses = [2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37];
        mutable d = n - 1;
        mutable r = 0;
        while d % 2 == 0 { set d = d / 2; set r += 1; }
        for a in witnesses {
            if a >= n { continue; }
            mutable x = ModPow(a, d, n);
            if x == 1 or x == n - 1 { continue; }
            mutable composite = true;
            for _ in 0..r - 2 {
                set x = ModPow(x, 2, n);
                if x == n - 1 { set composite = false; }
            }
            if composite { return false; }
        }
        return true;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Quantum modular multiplication oracle
    // ─────────────────────────────────────────────────────────────────────────
    operation ModularMultiplicationOracle(
        control  : Qubit,
        target   : Qubit[],
        a        : Int,
        n        : Int
    ) : Unit is Ctl {
        let nBits = Length(target);
        // Simplified: apply phase kickback proportional to a mod n
        let phase = 2.0 * PI() * IntAsDouble(a % n) / IntAsDouble(n);
        Controlled Rz([control], (phase, target[0]));
        for i in 1..nBits - 1 {
            Controlled Rz([control], (phase / IntAsDouble(1 <<< i), target[i]));
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Quantum period finding (core of Shor's)
    // ─────────────────────────────────────────────────────────────────────────
    operation FindPeriodQuantum(a : Int, n : Int) : Int {
        let nBits = Ceiling(Log(IntAsDouble(n)) / Log(2.0)) + 1;
        let mBits = 2 * nBits;

        use control  = Qubit[mBits];
        use register = Qubit[nBits];

        // Initialize register to |1>
        X(register[0]);

        // Hadamard on control
        ApplyToEach(H, control);

        // Controlled modular exponentiation
        for j in 0..mBits - 1 {
            let power = ModPow(a, 1 <<< j, n);
            ModularMultiplicationOracle(control[j], register, power, n);
        }

        // Inverse QFT on control
        Adjoint QFT(control);

        // Measure control
        mutable measured = 0;
        for i in 0..mBits - 1 {
            let bit = MResetZ(control[i]) == One ? 1 | 0;
            set measured += bit <<< i;
        }
        ResetAll(register);

        // Continued fractions to extract period
        if measured == 0 { return 0; }
        let denom = 1 <<< mBits;
        return ExtractPeriodCF(measured, denom, n);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Continued fractions convergent extraction
    // ─────────────────────────────────────────────────────────────────────────
    function ExtractPeriodCF(numerator : Int, denominator : Int, n : Int) : Int {
        mutable a0 = numerator;
        mutable b0 = denominator;
        mutable p0 = 0;
        mutable p1 = 1;
        mutable q0 = 1;
        mutable q1 = 0;

        for _ in 0..20 {
            if b0 == 0 { return q1; }
            let ai = a0 / b0;
            let tmp_a = b0;
            let tmp_b = a0 % b0;
            set a0 = tmp_a;
            set b0 = tmp_b;
            let tmp_p = ai * p1 + p0;
            set p0 = p1;
            set p1 = tmp_p;
            let tmp_q = ai * q1 + q0;
            set q0 = q1;
            set q1 = tmp_q;
            if q1 > 0 and q1 < n and ModPow(numerator, q1, denominator) == 0 {
                return q1;
            }
        }
        return q1;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Full Shor's algorithm
    // ─────────────────────────────────────────────────────────────────────────
    operation RunShorAlgorithm(n : Int) : FactorizationResult {
        ValidateFactorizationInput(n);

        if IsPrime(n) {
            return FactorizationResult(n, 1, n, true, "primality-test", 0, 0, 1, false, 0.0);
        }
        if n % 2 == 0 {
            return FactorizationResult(n, 2, n / 2, false, "classical-even", 0, 0, 1, false, 0.1);
        }

        let nBits = Ceiling(Log(IntAsDouble(n)) / Log(2.0)) + 1;
        let physQubits = 3 * nBits;

        mutable attempts = 0;
        repeat {
            set attempts += 1;
            let a = 2 + (attempts % (n - 2));
            let g = GCD(a, n);
            if g > 1 {
                return FactorizationResult(
                    n, g, n / g, false,
                    "classical-gcd", physQubits, 0, attempts, false, 0.0
                );
            }

            let r = FindPeriodQuantum(a, n);
            if r > 0 and r % 2 == 0 {
                let candidate1 = ModPow(a, r / 2, n) - 1;
                let candidate2 = ModPow(a, r / 2, n) + 1;
                let f1 = GCD(candidate1, n);
                let f2 = GCD(candidate2, n);
                if f1 > 1 and f1 < n {
                    return FactorizationResult(
                        n, f1, n / f1, false,
                        "shor-quantum", physQubits, 2 * nBits, attempts, true, 0.0
                    );
                }
                if f2 > 1 and f2 < n {
                    return FactorizationResult(
                        n, f2, n / f2, false,
                        "shor-quantum", physQubits, 2 * nBits, attempts, true, 0.0
                    );
                }
            }
        } until attempts >= 20;

        return FactorizationResult(n, 1, n, false, "failed", physQubits, 0, attempts, false, 0.0);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Trial division (classical fallback)
    // ─────────────────────────────────────────────────────────────────────────
    function TrialDivision(n : Int) : (Int, Int) {
        if n % 2 == 0 { return (2, n / 2); }
        mutable i = 3;
        while i * i <= n {
            if n % i == 0 { return (i, n / i); }
            set i += 2;
        }
        return (1, n);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Pollard's rho (classical, faster than trial division)
    // ─────────────────────────────────────────────────────────────────────────
    function PollardsRho(n : Int) : Int {
        if n % 2 == 0 { return 2; }
        mutable x = 2;
        mutable y = 2;
        mutable c = 1;
        mutable d = 1;
        while d == 1 {
            set x = (x * x + c) % n;
            set y = (y * y + c) % n;
            set y = (y * y + c) % n;
            let diff = if x > y { x - y } else { y - x };
            set d = GCD(diff, n);
        }
        return if d != n { d } else { -1 };
    }
}
