// =============================================================================
// Surface Zenith OS — Quantum Key Distribution (QKD)
// File: quantum/ZenithQKD/ZenithQuantumKeyDistribution.qs
//
// Implements BB84 Quantum Key Distribution protocol for securing
// cross-domain communication channels in the Zenith OS.
//
// BB84 Protocol:
//   1. Alice prepares qubits in random bases (Z or X)
//   2. Alice sends qubits to Bob over quantum channel
//   3. Bob measures in random bases
//   4. Alice and Bob compare bases over classical channel
//   5. Matching bases → shared secret key bits
//   6. Eavesdropper detection via error rate analysis
//
// In Zenith OS, "Alice" = source domain, "Bob" = target domain.
// The quantum channel is the QPU subsystem.
// The classical channel is the ZIB (Zenith Interdomain Bus).
// =============================================================================

namespace SurfaceZenith.Quantum.QKD {

    open Microsoft.Quantum.Canon;
    open Microsoft.Quantum.Intrinsic;
    open Microsoft.Quantum.Math;
    open Microsoft.Quantum.Arrays;
    open Microsoft.Quantum.Measurement;
    open Microsoft.Quantum.Convert;
    open Microsoft.Quantum.Random;

    // =========================================================================
    // BB84 Basis definitions
    // =========================================================================

    /// Measurement basis
    newtype Basis = (IsXBasis : Bool);

    /// Z-basis (computational basis: |0⟩, |1⟩)
    let ZBasis = Basis(IsXBasis = false);

    /// X-basis (Hadamard basis: |+⟩, |−⟩)
    let XBasis = Basis(IsXBasis = true);

    // =========================================================================
    // BB84 Key Generation
    // =========================================================================

    /// Prepare a qubit in a specific state and basis (Alice's side).
    ///
    /// # Input
    /// - bit   : the bit value to encode (true = 1, false = 0)
    /// - basis : the basis to use (Z or X)
    /// - qubit : the qubit to prepare
    operation PrepareQubit(bit : Bool, basis : Basis, qubit : Qubit) : Unit {
        // Start in |0⟩
        Reset(qubit);

        // Encode bit value
        if bit {
            X(qubit);  // |0⟩ → |1⟩
        }

        // Apply basis transformation
        if basis::IsXBasis {
            H(qubit);  // |0⟩ → |+⟩, |1⟩ → |−⟩
        }
    }

    /// Measure a qubit in a specific basis (Bob's side).
    ///
    /// # Input
    /// - basis : the basis to measure in
    /// - qubit : the qubit to measure
    ///
    /// # Output
    /// - Measured bit value
    operation MeasureInBasis(basis : Basis, qubit : Qubit) : Bool {
        if basis::IsXBasis {
            H(qubit);  // Rotate to Z-basis before measurement
        }
        return M(qubit) == One;
    }

    /// Simulate quantum channel noise with independent bit-flip and phase-flip errors.
    ///
    /// Models a noisy channel with error rate ε. No eavesdropper is modeled in this file;
    /// intercept-resend attacks are not simulated.
    ///
    /// # Input
    /// - errorRate : channel error probability (0.0–1.0)
    /// - qubit     : qubit to apply noise to
    operation ApplyChannelNoise(errorRate : Double, qubit : Qubit) : Unit {
        // Simplified: apply X error with probability errorRate
        // In production: use full depolarizing channel model
        if DrawRandomDouble(0.0, 1.0) < errorRate {
            X(qubit);  // Bit flip error
        }
        if DrawRandomDouble(0.0, 1.0) < errorRate / 2.0 {
            Z(qubit);  // Phase flip error
        }
    }

    /// Run the BB84 protocol to generate a shared secret key.
    ///
    /// # Input
    /// - keyLength  : desired key length in bits
    /// - errorRate  : quantum channel error rate (0.0–0.11 is acceptable)
    ///
    /// # Output
    /// - (sharedKey: Bool[], qberEstimate: Double, success: Bool)
    ///   where QBER = Quantum Bit Error Rate
    operation RunBB84Protocol(
        keyLength : Int,
        errorRate : Double
    ) : (Bool[], Double, Bool) {

        // Sifting keeps ~50% of raw bits, so 8x raw bits leaves ~4x keyLength sifted
        // bits, comfortably above the 2x keyLength threshold checked in Step 4.
        let rawBits = keyLength * 8;

        use qubits = Qubit[rawBits];

        // ---- Step 1: Alice prepares qubits ----------------------------------
        mutable aliceBits  = [false, size = rawBits];
        mutable aliceBases = [ZBasis, size = rawBits];

        for i in 0 .. rawBits - 1 {
            let bit   = DrawRandomBool(0.5);
            let useX  = DrawRandomBool(0.5);
            let basis = useX ? XBasis | ZBasis;

            set aliceBits  w/= i <- bit;
            set aliceBases w/= i <- basis;

            PrepareQubit(bit, basis, qubits[i]);
        }

        // ---- Step 2: Quantum channel (with noise) ---------------------------
        for i in 0 .. rawBits - 1 {
            ApplyChannelNoise(errorRate, qubits[i]);
        }

        // ---- Step 3: Bob measures in random bases ---------------------------
        mutable bobBases   = [ZBasis, size = rawBits];
        mutable bobResults = [false, size = rawBits];

        for i in 0 .. rawBits - 1 {
            let useX  = DrawRandomBool(0.5);
            let basis = useX ? XBasis | ZBasis;
            set bobBases   w/= i <- basis;
            set bobResults w/= i <- MeasureInBasis(basis, qubits[i]);
        }

        ResetAll(qubits);

        // ---- Step 4: Sift — keep only matching bases (classical channel) ----
        mutable siftedAlice = [false, size = 0];
        mutable siftedBob   = [false, size = 0];

        for i in 0 .. rawBits - 1 {
            if aliceBases[i]::IsXBasis == bobBases[i]::IsXBasis {
                set siftedAlice += [aliceBits[i]];
                set siftedBob   += [bobResults[i]];
            }
        }

        let siftedLength = Length(siftedAlice);
        if siftedLength < keyLength * 2 or siftedLength < 4 {
            // Not enough sifted bits — protocol failed
            return ([], 1.0, false);
        }

        // ---- Step 5: QBER estimation (sacrifice some bits) ------------------
        let checkBits = siftedLength / 4;
        mutable errors = 0;

        for i in 0 .. checkBits - 1 {
            if siftedAlice[i] != siftedBob[i] {
                set errors += 1;
            }
        }

        let qber = IntAsDouble(errors) / IntAsDouble(checkBits);

        // ---- Step 6: Security check -----------------------------------------
        // BB84 is secure if QBER < 11% (theoretical threshold).
        let securityThreshold = 0.11;
        if qber > securityThreshold {
            // Eavesdropper detected — abort
            return ([], qber, false);
        }

        // ---- Step 7: Extract final key (remaining sifted bits) --------------
        let availableKeyBits = siftedLength - checkBits;
        if availableKeyBits < keyLength {
            // Insufficient quantum-derived key material — abort instead of padding
            return ([], qber, false);
        }

        mutable finalKey = [false, size = 0];
        for i in checkBits .. checkBits + keyLength - 1 {
            set finalKey += [siftedAlice[i]];
        }

        return (finalKey, qber, true);
    }

    // =========================================================================
    // E91 Protocol (Ekert 1991) — Entanglement-based QKD
    // =========================================================================

    /// Prepare an entangled Bell pair |Φ+⟩ = (|00⟩ + |11⟩) / √2
    operation PrepareBellPair(alice : Qubit, bob : Qubit) : Unit {
        Reset(alice);
        Reset(bob);
        H(alice);
        CNOT(alice, bob);
    }

    /// Run E91 protocol for a single bit.
    ///
    /// Alice and Bob each measure their half of an entangled pair
    /// in randomly chosen bases. Correlated measurements yield key bits.
    ///
    /// # Input
    /// - aliceBasisAngle : Alice's measurement angle (0, π/4, π/2)
    /// - bobBasisAngle   : Bob's measurement angle (0, π/4, π/2)
    ///
    /// # Output
    /// - (aliceResult: Bool, bobResult: Bool)
    operation RunE91Bit(
        aliceBasisAngle : Double,
        bobBasisAngle   : Double
    ) : (Bool, Bool) {

        use (aliceQubit, bobQubit) = (Qubit(), Qubit());

        // Prepare Bell pair
        PrepareBellPair(aliceQubit, bobQubit);

        // Alice measures in her basis
        Ry(2.0 * aliceBasisAngle, aliceQubit);
        let aliceResult = M(aliceQubit) == One;

        // Bob measures in his basis
        Ry(2.0 * bobBasisAngle, bobQubit);
        let bobResult = M(bobQubit) == One;

        Reset(aliceQubit);
        Reset(bobQubit);

        return (aliceResult, bobResult);
    }

    /// Generate a key using E91 protocol.
    ///
    /// # Input
    /// - keyLength : desired key length in bits
    ///
    /// # Output
    /// - Shared key bits (Alice's perspective)
    operation RunE91Protocol(keyLength : Int) : Bool[] {
        mutable key = [false, size = 0];

        // E91 basis angles
        // Alice: 0, π/4, π/2
        // Bob:   0, π/4, π/2
        // Key bits come from matching bases (0,0) or (π/2, π/2)
        let aliceAngles = [0.0, PI() / 4.0, PI() / 2.0];
        let bobAngles   = [0.0, PI() / 4.0, PI() / 2.0];

        mutable attempts = 0;
        let maxAttempts = keyLength * 6;

        while Length(key) < keyLength and attempts < maxAttempts {
            let aliceIdx = DrawRandomInt(0, 2);
            let bobIdx   = DrawRandomInt(0, 2);

            let (aliceResult, bobResult) = RunE91Bit(
                aliceAngles[aliceIdx],
                bobAngles[bobIdx]
            );

            // Key bit: matching bases (0,0) or (π/2,π/2)
            if aliceIdx == bobIdx and (aliceIdx == 0 or aliceIdx == 2) {
                // Matching settings on the |Φ+⟩ pair give identical outcomes, so Alice's bit is the shared key bit.
                set key += [aliceResult];
            }

            set attempts += 1;
        }

        if Length(key) < keyLength {
            fail $"E91 key exchange failed: collected {Length(key)} bits, required {keyLength}.";
        }

        return key[0 .. keyLength - 1];
    }

    // =========================================================================
    // Privacy Amplification
    // =========================================================================

    /// Apply privacy amplification to a raw key using a Toeplitz hash.
    ///
    /// Reduces key length to remove any information an eavesdropper may have.
    ///
    /// # Input
    /// - rawKey    : sifted key bits
    /// - finalLen  : desired final key length (< rawKey length)
    ///
    /// # Output
    /// - Privacy-amplified key
    function PrivacyAmplificationWithSeed(rawKey : Bool[], finalLen : Int, toeplitzSeed : Bool[]) : Bool[] {
        let rawLen = Length(rawKey);
        if finalLen >= rawLen {
            return rawKey;
        }

        let requiredSeedLen = rawLen + finalLen - 1;
        if Length(toeplitzSeed) != requiredSeedLen {
            fail "PrivacyAmplificationWithSeed: invalid Toeplitz seed length.";
        }

        // Standard Toeplitz hashing over GF(2):
        // output[i] = XOR_j (T[i,j] AND rawKey[j]), with T[i,j] = toeplitzSeed[i + j].
        mutable result = [false, size = finalLen];
        for i in 0 .. finalLen - 1 {
            mutable bit = false;
            for j in 0 .. rawLen - 1 {
                let matrixBit = toeplitzSeed[i + j];
                set bit = bit != (matrixBit and rawKey[j]);
            }
            set result w/= i <- bit;
        }

        return result;
    }

    operation PrivacyAmplification(rawKey : Bool[], finalLen : Int) : Bool[] {
        let rawLen = Length(rawKey);
        if finalLen >= rawLen {
            return rawKey;
        }

        // Draw an independent random Toeplitz seed of length (rawLen + finalLen - 1).
        let seedLen = rawLen + finalLen - 1;
        mutable toeplitzSeed = [false, size = seedLen];
        for k in 0 .. seedLen - 1 {
            set toeplitzSeed w/= k <- DrawRandomBool(0.5);
        }

        return PrivacyAmplificationWithSeed(rawKey, finalLen, toeplitzSeed);
    }

    // =========================================================================
    // Zenith Domain Channel Key Exchange
    // =========================================================================

    /// Establish a quantum-secured channel between two Zenith domains.
    ///
    /// This is the main entry point called by the Zenith Security Broker
    /// when establishing a secure cross-domain communication channel.
    ///
    /// # Input
    /// - sourceDomain : source domain index (0–5)
    /// - targetDomain : target domain index (0–5)
    /// - keyBits      : desired key length in bits (typically 256)
    ///
    /// # Output
    /// - (key: Bool[], qber: Double, success: Bool)
    @EntryPoint()
    operation EstablishDomainChannel(
        sourceDomain : Int,
        targetDomain : Int,
        keyBits      : Int
    ) : (Bool[], Double, Bool) {

        if sourceDomain < 0 or sourceDomain > 5 or targetDomain < 0 or targetDomain > 5 or keyBits <= 0 {
            fail "Domain indices must be in 0..5 and keyBits must be positive";
        }

        // Use BB84 for standard channels
        // Use E91 for high-security channels (Quantum domain)
        let useE91 = sourceDomain == 3 or targetDomain == 3; // Quantum domain

        if useE91 {
            let rawKey = RunE91Protocol(keyBits * 2);
            let finalKey = PrivacyAmplification(rawKey, keyBits);

            // Do not report a hardcoded perfect channel.
            // Estimate channel error from raw key statistics and fail closed on high error.
            // (A full E91 implementation should expose CHSH/Bell-test metrics here.)
            mutable ones = 0;
            for bit in rawKey {
                if bit {
                    set ones += 1;
                }
            }
            let rawLen = Length(rawKey);
            let qber =
    /// Return a non-secret summary of key material suitable for diagnostics.
    /// Does NOT expose key bits or reversible encodings.
                    1.0
        let keyLength = Length(key);
        mutable onesCount = 0;
        for bit in key {
            if bit {
                set onesCount += 1;
            if not success {
            }
        return $"[key-summary len={keyLength}, ones={onesCount}]";
            return (finalKey, qber, Length(finalKey) == keyBits);
        }
    }

    /// Convert a Bool[] key to a hex string for logging
    function KeyToHexString(key : Bool[]) : String {
        mutable hex = "";
        let nBytes = Length(key) / 8;
        for byteIdx in 0 .. nBytes - 1 {
            mutable byteVal = 0;
            for bitIdx in 0 .. 7 {
                let globalBit = byteIdx * 8 + bitIdx;
                if globalBit < Length(key) and key[globalBit] {
                    set byteVal += 1 <<< bitIdx;
                }
            }
            set hex += $"{byteVal:X2}";
        }
        return hex;
    }

    /// Entry point: Run BB84 and return QBER
    operation RunQBERTest(keyLength : Int, errorRate : Double) : Double {
        let (_, qber, _) = RunBB84Protocol(keyLength, errorRate);
        return qber;
    }

    /// Entry point: Check if a channel is secure (QBER < threshold)
    operation IsChannelSecure(keyLength : Int, errorRate : Double) : Bool {
        let (_, _, success) = RunBB84Protocol(keyLength, errorRate);
        return success;
    }
}
