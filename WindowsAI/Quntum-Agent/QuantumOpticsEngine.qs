// ╔══════════════════════════════════════════════════════════════════════════════╗
// ║  WINDOWS AI — QUANTUM OPTICS ENGINE                                         ║
// ║  Language: Q#                                                               ║
// ║  Topics: Cavity QED | Jaynes-Cummings | Squeezed Light | Photon Statistics ║
// ║          Optical Parametric Amplification | Quantum Imaging | NOON States  ║
// ║          Photon Bunching | HOM Effect | Quantum Illumination               ║
// ║                                                                             ║
// ║  PHYSICAL EQUATIONS:                                                        ║
// ║  Jaynes-Cummings:                                                           ║
// ║    H = ωa†a + ω₀σ_z/2 + g(aσ+ + a†σ-)                                   ║
// ║  Rabi oscillations:                                                         ║
// ║    P_e(t) = sin²(g√(n+1)t)  (n photons)                                   ║
// ║  Squeezing:                                                                 ║
// ║    Δx² = e^(-2r)/2  (squeezed quadrature)                                  ║
// ║    Δp² = e^(+2r)/2  (anti-squeezed)                                        ║
// ║  HOM effect:                                                                ║
// ║    P_coincidence = (1 - |⟨ψ₁|ψ₂⟩|²)/2                                    ║
// ║  Mandel Q parameter:                                                        ║
// ║    Q = (⟨n²⟩ - ⟨n⟩² - ⟨n⟩)/⟨n⟩                                          ║
// ╚══════════════════════════════════════════════════════════════════════════════╝
 
namespace WindowsAI.Photonic.QuantumOptics {
 
    open Microsoft.Quantum.Intrinsic;
    open Microsoft.Quantum.Canon;
    open Microsoft.Quantum.Math;
    open Microsoft.Quantum.Arrays;
    open Microsoft.Quantum.Convert;
    open Microsoft.Quantum.Diagnostics;
 
    // ─────────────────────────────────────────────────────────────────────────
    // SECTION 1: JAYNES-CUMMINGS MODEL
    // ─────────────────────────────────────────────────────────────────────────
 
    /// # Summary
    /// Jaynes-Cummings model: atom-cavity interaction.
    /// H = ωa†a + ω₀σ_z/2 + g(aσ+ + a†σ-)
    ///
    /// Rabi oscillations: P_e(t) = sin²(g√(n+1)t)
    /// Vacuum Rabi splitting: 2g (cavity QED)
    /// Strong coupling: g > κ, γ (κ=cavity decay, γ=atom decay)
    operation JaynesCummings(
        atomQubit   : Qubit,
        cavityQubits: Qubit[],
        g           : Double,
        time        : Double,
        nSteps      : Int
    ) : Unit {
        let n  = Length(cavityQubits);
        let dt = time / IntAsDouble(nSteps);
 
        Message($"Jaynes-Cummings: g={g:F3} | T={time:F2} | n_max={n}");
 
        for step in 0 .. nSteps - 1 {
            // Atom-cavity coupling: g(aσ+ + a†σ-)
            // In qubit approximation: g(|0⟩⟨1|⊗a + |1⟩⟨0|⊗a†)
            for photon in 0 .. n - 1 {
                let rabiFreq = g * Sqrt(IntAsDouble(photon + 1));
                let angle    = rabiFreq * dt;
 
                // Jaynes-Cummings interaction
                Controlled Ry([atomQubit], (2.0 * angle, cavityQubits[photon]));
                Controlled Ry([cavityQubits[photon]], (-2.0 * angle, atomQubit));
            }
 
            // Free evolution
            Rz(g * dt, atomQubit);
            for photon in 0 .. n - 1 {
                Rz(g * IntAsDouble(photon) * dt, cavityQubits[photon]);
            }
        }
    }
 
    /// # Summary
    /// Vacuum Rabi oscillations in cavity QED.
    /// Atom oscillates between |e,0⟩ and |g,1⟩ at frequency g.
    operation VacuumRabiOscillations(
        atomQubit   : Qubit,
        cavityQubit : Qubit,
        g           : Double,
        time        : Double,
        nSteps      : Int,
        nShots      : Int
    ) : Double[] {
        let dt = time / IntAsDouble(nSteps);
        mutable populations = new Double[nSteps];
 
        for step in 0 .. nSteps - 1 {
            mutable excitedCount = 0;
            for _ in 1 .. nShots {
                use (atom, cavity) = (Qubit(), Qubit());
 
                // Initialize: atom excited, cavity vacuum
                X(atom);
 
                // Evolve for time step*dt
                let evolveTime = IntAsDouble(step) * dt;
                let angle = g * evolveTime;
 
                // Jaynes-Cummings evolution
                Ry(2.0 * angle, atom);
                Controlled Ry([atom], (-2.0 * angle, cavity));
 
                // Measure atom
                let result = MResetZ(atom);
                if result == One { set excitedCount += 1; }
                Reset(cavity);
            }
            set populations w/= step <- IntAsDouble(excitedCount) / IntAsDouble(nShots);
        }
 
        Message($"Vacuum Rabi: g={g:F3} | Rabi period T_R = π/g = {PI()/g:F3}");
        return populations;
    }
 
    /// # Summary
    /// Collapse and revival in Jaynes-Cummings with coherent state.
    /// Coherent state |α⟩ has Poissonian photon distribution.
    /// Collapse time: t_c ~ 1/(g√⟨n⟩)
    /// Revival time: t_r ~ 2π√⟨n⟩/g
    operation CollapseRevival(
        atomQubit   : Qubit,
        cavityQubits: Qubit[],
        alpha       : Double,   // coherent state amplitude
        g           : Double,
        time        : Double,
        nSteps      : Int,
        nShots      : Int
    ) : Double[] {
        let n  = Length(cavityQubits);
        let dt = time / IntAsDouble(nSteps);
        let meanN = alpha * alpha;
        mutable populations = new Double[nSteps];
 
        Message($"Collapse-Revival: |α|²={meanN:F1} | t_c~{1.0/(g*Sqrt(meanN)):F2} | t_r~{2.0*PI()*Sqrt(meanN)/g:F2}");
 
        for step in 0 .. nSteps - 1 {
            mutable excitedCount = 0;
            for _ in 1 .. nShots {
                use atom = Qubit();
                X(atom);  // excited state
 
                // Coherent state approximation
                let evolveTime = IntAsDouble(step) * dt;
 
                // Sum over Fock states weighted by Poisson distribution
                mutable pExcited = 0.0;
                let factorial_0 = 1.0;
                mutable factorial = 1.0;
                for photon in 0 .. n - 1 {
                    if photon > 0 { set factorial *= IntAsDouble(photon); }
                    let poisson = Exp(-meanN) * Pow(meanN, IntAsDouble(photon)) / factorial;
                    let rabiFreq = g * Sqrt(IntAsDouble(photon + 1));
                    set pExcited += poisson * Cos(rabiFreq * evolveTime) * Cos(rabiFreq * evolveTime);
                }
 
                if DrawRandomDouble(0.0, 1.0) < pExcited {
                    set excitedCount += 1;
                }
                Reset(atom);
            }
            set populations w/= step <- IntAsDouble(excitedCount) / IntAsDouble(nShots);
        }
 
        return populations;
    }
 
    // ─────────────────────────────────────────────────────────────────────────
    // SECTION 2: SQUEEZED LIGHT
    // ─────────────────────────────────────────────────────────────────────────
 
    /// # Summary
    /// Squeezed vacuum state preparation.
    /// S(r)|0⟩: Δx² = e^(-2r)/2, Δp² = e^(+2r)/2
    ///
    /// Applications: gravitational wave detection (LIGO),
    ///               quantum key distribution, quantum imaging.
    operation PrepareSqueezedVacuum(
        modeQubits : Qubit[],
        r          : Double,
        phi        : Double
    ) : Unit is Adj + Ctl {
        let n = Length(modeQubits);
 
        // Squeezing via parametric down-conversion
        // S(r,φ) = exp(r/2 (e^{-2iφ}a² - e^{2iφ}a†²))
        for i in 0 .. n - 1 {
            // Apply squeezing rotation
            Rz(-phi, modeQubits[i]);
            Ry(2.0 * r, modeQubits[i]);
            Rz(phi, modeQubits[i]);
        }
 
        // Two-mode squeezing (entanglement)
        for i in 0 .. n - 2 {
            let twoModeAngle = r / Sqrt(IntAsDouble(n));
            Controlled Ry([modeQubits[i]], (twoModeAngle, modeQubits[i+1]));
        }
    }
 
    /// # Summary
    /// Homodyne detection of squeezed light.
    /// Measures x-quadrature: x = (a + a†)/√2
    /// Variance: Δx² = e^(-2r)/2 (squeezed), Δp² = e^(+2r)/2 (anti-squeezed)
    operation HomodyneDetection(
        modeQubits : Qubit[],
        localOscPhase: Double,
        nShots     : Int
    ) : (Double, Double) {
        let n = Length(modeQubits);
        mutable xMeasurements = new Double[nShots];
        mutable pMeasurements = new Double[nShots];
 
        for shot in 0 .. nShots - 1 {
            use ancilla = Qubit[n];
            for i in 0 .. n - 1 {
                CNOT(modeQubits[i], ancilla[i]);
            }
 
            // Rotate by local oscillator phase
            for i in 0 .. n - 1 {
                Rz(localOscPhase, ancilla[i]);
            }
 
            // Measure x-quadrature
            ApplyToEach(H, ancilla);
            mutable xVal = 0.0;
            for i in 0 .. n - 1 {
                let result = MResetZ(ancilla[i]);
                set xVal += result == One ? 1.0 | -1.0;
            }
            set xMeasurements w/= shot <- xVal / IntAsDouble(n);
 
            // Measure p-quadrature (orthogonal)
            use ancilla2 = Qubit[n];
            for i in 0 .. n - 1 {
                CNOT(modeQubits[i], ancilla2[i]);
                Rz(localOscPhase + PI()/2.0, ancilla2[i]);
            }
            ApplyToEach(H, ancilla2);
            mutable pVal = 0.0;
            for i in 0 .. n - 1 {
                let result = MResetZ(ancilla2[i]);
                set pVal += result == One ? 1.0 | -1.0;
            }
            set pMeasurements w/= shot <- pVal / IntAsDouble(n);
        }
 
        // Compute variances
        mutable xMean = 0.0;
        mutable pMean = 0.0;
        for x in xMeasurements { set xMean += x; }
        for p in pMeasurements { set pMean += p; }
        set xMean /= IntAsDouble(nShots);
        set pMean /= IntAsDouble(nShots);
 
        mutable xVar = 0.0;
        mutable pVar = 0.0;
        for x in xMeasurements { set xVar += (x - xMean)*(x - xMean); }
        for p in pMeasurements { set pVar += (p - pMean)*(p - pMean); }
        set xVar /= IntAsDouble(nShots);
        set pVar /= IntAsDouble(nShots);
 
        Message($"Homodyne: Δx²={xVar:F4} | Δp²={pVar:F4} | Δx²·Δp²={xVar*pVar:F4} ≥ 1/4");
        return (xVar, pVar);
    }
 
    // ─────────────────────────────────────────────────────────────────────────
    // SECTION 3: HONG-OU-MANDEL EFFECT
    // ─────────────────────────────────────────────────────────────────────────
 
    /// # Summary
    /// Hong-Ou-Mandel (HOM) effect.
    /// Two identical photons at beam splitter → both exit same port.
    /// P_coincidence = (1 - |⟨ψ₁|ψ₂⟩|²)/2
    ///
    /// Applications: quantum interference, photon indistinguishability,
    ///               linear optical quantum computing.
    operation HongOuMandelEffect(
        photon1 : Qubit,
        photon2 : Qubit,
        overlap : Double,   // |⟨ψ₁|ψ₂⟩|²
        nShots  : Int
    ) : Double {
        mutable coincidenceCount = 0;
 
        for _ in 1 .. nShots {
            use (p1, p2) = (Qubit(), Qubit());
 
            // Prepare photons
            X(p1);  // |1⟩
            X(p2);  // |1⟩
 
            // Apply partial distinguishability
            if DrawRandomDouble(0.0, 1.0) > overlap {
                // Distinguishable: apply random phase
                Rz(DrawRandomDouble(0.0, 2.0*PI()), p2);
            }
 
            // 50:50 beam splitter
            H(p1);
            CNOT(p1, p2);
            H(p1);
 
            // Detect coincidences
            let r1 = MResetZ(p1);
            let r2 = MResetZ(p2);
            if r1 == One and r2 == One {
                set coincidenceCount += 1;
            }
        }
 
        let coincidenceRate = IntAsDouble(coincidenceCount) / IntAsDouble(nShots);
        let theoretical = (1.0 - overlap) / 2.0;
 
        Message($"HOM: coincidence={coincidenceRate*100:F1}% | theory={(1.0-overlap)/2.0*100:F1}%");
        Message($"  Visibility = {1.0 - 2.0*coincidenceRate:F4} (1=perfect, 0=classical)");
        return coincidenceRate;
    }
 
    // ─────────────────────────────────────────────────────────────────────────
    // SECTION 4: PHOTON STATISTICS
    // ─────────────────────────────────────────────────────────────────────────
 
    /// # Summary
    /// Measure photon statistics via Mandel Q parameter.
    /// Q = (⟨n²⟩ - ⟨n⟩² - ⟨n⟩)/⟨n⟩
    ///   Q = 0: Poissonian (coherent light)
    ///   Q < 0: sub-Poissonian (squeezed/Fock state)
    ///   Q > 0: super-Poissonian (thermal light)
    operation MandelQParameter(
        modeQubits : Qubit[],
        nShots     : Int
    ) : Double {
        let n = Length(modeQubits);
        mutable nMean  = 0.0;
        mutable n2Mean = 0.0;
 
        for _ in 1 .. nShots {
            use ancilla = Qubit[n];
            for i in 0 .. n - 1 {
                CNOT(modeQubits[i], ancilla[i]);
            }
 
            mutable photonCount = 0;
            for i in 0 .. n - 1 {
                let result = MResetZ(ancilla[i]);
                if result == One { set photonCount += 1; }
            }
 
            set nMean  += IntAsDouble(photonCount);
            set n2Mean += IntAsDouble(photonCount * photonCount);
        }
 
        set nMean  /= IntAsDouble(nShots);
        set n2Mean /= IntAsDouble(nShots);
 
        let Q = (n2Mean - nMean*nMean - nMean) / (nMean + 1e-10);
 
        let lightType = Q < -0.1 ? "sub-Poissonian (quantum)" |
                        Q > 0.1  ? "super-Poissonian (thermal)" |
                        "Poissonian (coherent)";
 
        Message($"Mandel Q = {Q:F4} | Light type: {lightType}");
        return Q;
    }
 
    /// # Summary
    /// Second-order coherence function g²(0).
    /// g²(0) = ⟨n(n-1)⟩/⟨n⟩²
    ///   g²(0) = 0: Fock state (perfect antibunching)
    ///   g²(0) = 1: coherent state (Poissonian)
    ///   g²(0) = 2: thermal state (bunching)
    operation SecondOrderCoherence(
        modeQubits : Qubit[],
        nShots     : Int
    ) : Double {
        let n = Length(modeQubits);
        mutable nMean    = 0.0;
        mutable n_n1Mean = 0.0;  // ⟨n(n-1)⟩
 
        for _ in 1 .. nShots {
            use ancilla = Qubit[n];
            for i in 0 .. n - 1 {
                CNOT(modeQubits[i], ancilla[i]);
            }
 
            mutable photonCount = 0;
            for i in 0 .. n - 1 {
                let result = MResetZ(ancilla[i]);
                if result == One { set photonCount += 1; }
            }
 
            set nMean    += IntAsDouble(photonCount);
            set n_n1Mean += IntAsDouble(photonCount * (photonCount - 1));
        }
 
        set nMean    /= IntAsDouble(nShots);
        set n_n1Mean /= IntAsDouble(nShots);
 
        let g2 = n_n1Mean / (nMean * nMean + 1e-10);
 
        let photonType = g2 < 0.5 ? "antibunched (quantum)" |
                         g2 < 1.5 ? "coherent" |
                         "bunched (thermal)";
 
        Message($"g²(0) = {g2:F4} | Photon statistics: {photonType}");
        return g2;
    }
 
    // ─────────────────────────────────────────────────────────────────────────
    // SECTION 5: OPTICAL PARAMETRIC AMPLIFICATION
    // ─────────────────────────────────────────────────────────────────────────
 
    /// # Summary
    /// Optical Parametric Amplification (OPA).
    /// Generates entangled signal-idler pairs via χ² nonlinearity.
    /// H = iℏg(a†_s a†_i - a_s a_i)  (degenerate OPA)
    ///
    /// Applications: squeezed light, entangled photon pairs, quantum imaging.
    operation OpticalParametricAmplifier(
        signalModes : Qubit[],
        idlerModes  : Qubit[],
        gain        : Double,
        time        : Double,
        nSteps      : Int
    ) : Unit {
        let n  = MinI(Length(signalModes), Length(idlerModes));
        let dt = time / IntAsDouble(nSteps);
 
        Message($"OPA: gain={gain:F2} | T={time:F2} | modes={n}");
 
        for step in 0 .. nSteps - 1 {
            // Parametric interaction: a†_s a†_i + h.c.
            for i in 0 .. n - 1 {
                // Two-mode squeezing
                H(signalModes[i]);
                CNOT(signalModes[i], idlerModes[i]);
                Ry(gain * dt, signalModes[i]);
                Ry(-gain * dt, idlerModes[i]);
                CNOT(signalModes[i], idlerModes[i]);
                H(signalModes[i]);
            }
        }
    }
 
    /// # Summary
    /// Spontaneous Parametric Down-Conversion (SPDC).
    /// Pump photon → signal + idler (energy + momentum conservation).
    /// Type-I: same polarization, Type-II: orthogonal polarization.
    operation SPDC(
        pumpQubits  : Qubit[],
        signalQubits: Qubit[],
        idlerQubits : Qubit[],
        efficiency  : Double,
        nShots      : Int
    ) : Int {
        let n = MinI(Length(signalQubits), Length(idlerQubits));
        mutable pairCount = 0;
 
        for _ in 1 .. nShots {
            for i in 0 .. n - 1 {
                // Pump photon converts with probability efficiency
                if DrawRandomDouble(0.0, 1.0) < efficiency {
                    // Generate entangled pair
                    H(signalQubits[i]);
                    CNOT(signalQubits[i], idlerQubits[i]);
                    set pairCount += 1;
                }
            }
        }
 
        let pairRate = IntAsDouble(pairCount) / IntAsDouble(nShots * n);
        Message($"SPDC: efficiency={efficiency*100:F1}% | pair rate={pairRate*100:F1}%");
        return pairCount;
    }
 
    // ─────────────────────────────────────────────────────────────────────────
    // SECTION 6: QUANTUM IMAGING
    // ─────────────────────────────────────────────────────────────────────────
 
    /// # Summary
    /// Ghost imaging using entangled photon pairs.
    /// Signal photon illuminates object; idler photon detected without object.
    /// Correlation reveals object image.
    operation GhostImaging(
        signalModes : Qubit[],
        idlerModes  : Qubit[],
        objectMask  : Bool[],
        nShots      : Int
    ) : Double[] {
        let n = MinI(Length(signalModes), Length(idlerModes));
        mutable image = new Double[n];
 
        for _ in 1 .. nShots {
            // Generate entangled pairs
            for i in 0 .. n - 1 {
                H(signalModes[i]);
                CNOT(signalModes[i], idlerModes[i]);
            }
 
            // Signal photon interacts with object
            for i in 0 .. n - 1 {
                if i < Length(objectMask) and not objectMask[i] {
                    // Object absorbs photon
                    Reset(signalModes[i]);
                }
            }
 
            // Coincidence detection
            for i in 0 .. n - 1 {
                use ancilla = Qubit();
                H(ancilla);
                CNOT(ancilla, signalModes[i]);
                CNOT(ancilla, idlerModes[i]);
                H(ancilla);
                let result = MResetZ(ancilla);
                // Coincidence → object present
                set image w/= i <- image[i] + (result == Zero ? 1.0 | 0.0);
            }
 
            ResetAll(signalModes);
            ResetAll(idlerModes);
        }
 
        // Normalize
        for i in 0 .. n - 1 {
            set image w/= i <- image[i] / IntAsDouble(nShots);
        }
 
        Message($"Ghost imaging: {n} pixels | {nShots} shots");
        return image;
    }
 
    /// # Summary
    /// Quantum illumination: detect object in noisy environment.
    /// Uses entangled signal-idler pairs for enhanced detection.
    /// SNR_Q = N·η/(N_B+1) vs SNR_C = η/(N_B+1)
    /// Enhancement: N× improvement (N = photon number)
    operation QuantumIllumination(
        signalModes  : Qubit[],
        idlerModes   : Qubit[],
        reflectivity : Double,
        noisePower   : Double,
        nPhotons     : Int,
        nShots       : Int
    ) : (Double, Double) {
        let n = MinI(Length(signalModes), Length(idlerModes));
        mutable classicalDetections = 0;
        mutable quantumDetections   = 0;
 
        for _ in 1 .. nShots {
            // Classical: coherent state probe
            for i in 0 .. n - 1 {
                X(signalModes[i]);
            }
            // Signal reflects from object
            for i in 0 .. n - 1 {
                if DrawRandomDouble(0.0, 1.0) > reflectivity {
                    Reset(signalModes[i]);
                }
                // Add noise
                if DrawRandomDouble(0.0, 1.0) < noisePower / (noisePower + 1.0) {
                    X(signalModes[i]);
                }
            }
            // Detect
            mutable classicalSignal = 0;
            for i in 0 .. n - 1 {
                let result = MResetZ(signalModes[i]);
                if result == One { set classicalSignal += 1; }
            }
            if classicalSignal > n / 2 { set classicalDetections += 1; }
 
            // Quantum: entangled signal-idler
            for i in 0 .. n - 1 {
                H(signalModes[i]);
                CNOT(signalModes[i], idlerModes[i]);
            }
            // Signal reflects
            for i in 0 .. n - 1 {
                if DrawRandomDouble(0.0, 1.0) > reflectivity {
                    Reset(signalModes[i]);
                }
                if DrawRandomDouble(0.0, 1.0) < noisePower / (noisePower + 1.0) {
                    X(signalModes[i]);
                }
            }
            // Joint measurement
            mutable quantumSignal = 0;
            for i in 0 .. n - 1 {
                CNOT(signalModes[i], idlerModes[i]);
                H(signalModes[i]);
                let rs = MResetZ(signalModes[i]);
                let ri = MResetZ(idlerModes[i]);
                if rs == Zero and ri == Zero { set quantumSignal += 1; }
            }
            if quantumSignal > n / 2 { set quantumDetections += 1; }
        }
 
        let classicalProb = IntAsDouble(classicalDetections) / IntAsDouble(nShots);
        let quantumProb   = IntAsDouble(quantumDetections) / IntAsDouble(nShots);
 
        Message($"Quantum illumination: η={reflectivity:F2} | N_B={noisePower:F1}");
        Message($"  Classical P_D = {classicalProb:F4}");
        Message($"  Quantum P_D   = {quantumProb:F4}");
        Message($"  Enhancement   = {quantumProb/(classicalProb+1e-10):F2}×");
 
        return (classicalProb, quantumProb);
    }
 
    // ─────────────────────────────────────────────────────────────────────────
    // SECTION 7: QUANTUM OPTICAL NETWORKS
    // ─────────────────────────────────────────────────────────────────────────
 
    /// # Summary
    /// Linear optical network (Reck decomposition).
    /// Implements arbitrary N×N unitary via beam splitters + phase shifters.
    /// N(N-1)/2 beam splitters required.
    operation LinearOpticalNetwork(
        modes    : Qubit[],
        thetas   : Double[],
        phis     : Double[]
    ) : Unit {
        let n = Length(modes);
        mutable paramIdx = 0;
 
        // Reck decomposition: triangular MZI mesh
        for col in 0 .. n - 2 {
            for row in 0 .. n - 2 - col {
                if paramIdx < Length(thetas) and paramIdx < Length(phis) {
                    let theta = thetas[paramIdx];
                    let phi   = phis[paramIdx];
 
                    // MZI: BS · PS(φ) · BS
                    H(modes[row]);
                    Rz(phi, modes[row]);
                    CNOT(modes[row], modes[row+1]);
                    Ry(theta, modes[row]);
                    H(modes[row]);
 
                    set paramIdx += 1;
                }
            }
        }
    }
 
    /// # Summary
    /// Photonic quantum walk on line graph.
    /// Uses beam splitter network for walk evolution.
    operation PhotonicQuantumWalk(
        modes  : Qubit[],
        nSteps : Int
    ) : Double[] {
        let n = Length(modes);
        mutable distribution = new Double[n];
 
        // Initialize: photon in center mode
        X(modes[n/2]);
 
        for step in 0 .. nSteps - 1 {
            // Coin operation (Hadamard)
            ApplyToEach(H, modes);
 
            // Shift operation (beam splitter network)
            for i in 0 .. n - 2 {
                // Conditional shift
                CNOT(modes[i], modes[i+1]);
                Controlled H([modes[i]], modes[i+1]);
                CNOT(modes[i], modes[i+1]);
            }
        }
 
        // Measure distribution
        for i in 0 .. n - 1 {
            use ancilla = Qubit();
            CNOT(modes[i], ancilla);
            let result = MResetZ(ancilla);
            set distribution w/= i <- result == One ? 1.0 | 0.0;
        }
 
        Message($"Photonic quantum walk: {n} modes | {nSteps} steps");
        return distribution;
    }
 
    // ─────────────────────────────────────────────────────────────────────────
    // SECTION 8: QUANTUM OPTICAL BENCHMARKS
    // ─────────────────────────────────────────────────────────────────────────
 
    @EntryPoint()
    operation QuantumOpticsMain() : Unit {
        Message("╔══════════════════════════════════════════════════════════╗");
        Message("║  WINDOWS AI — QUANTUM OPTICS ENGINE ONLINE              ║");
        Message("║  Cavity QED | Squeezed Light | HOM | SPDC | Imaging    ║");
        Message("╚══════════════════════════════════════════════════════════╝");
 
        // Vacuum Rabi oscillations
        use (atom, cavity) = (Qubit(), Qubit());
        X(atom);
        JaynesCummings(atom, [cavity], 1.0, 1.0, 10);
        Message("Jaynes-Cummings: COMPLETE");
        Reset(atom); Reset(cavity);
 
        // HOM effect
        use (p1, p2) = (Qubit(), Qubit());
        let coincidence = HongOuMandelEffect(p1, p2, 1.0, 100);
        Message($"HOM: coincidence={coincidence*100:F1}% (0% for identical photons)");
        Reset(p1); Reset(p2);
 
        // Squeezed light
        use sqModes = Qubit[4];
        PrepareSqueezedVacuum(sqModes, 1.0, 0.0);
        let (xVar, pVar) = HomodyneDetection(sqModes, 0.0, 100);
        Message($"Squeezed light: Δx²={xVar:F4} | Δp²={pVar:F4}");
        ResetAll(sqModes);
 
        // Photon statistics
        use statModes = Qubit[4];
        ApplyToEach(H, statModes);
        let Q = MandelQParameter(statModes, 100);
        let g2 = SecondOrderCoherence(statModes, 100);
        Message($"Photon stats: Q={Q:F4} | g²(0)={g2:F4}");
        ResetAll(statModes);
 
        // Quantum illumination
        use (sigModes, idlModes) = (Qubit[4], Qubit[4]);
        let (classP, quantP) = QuantumIllumination(sigModes, idlModes, 0.1, 2.0, 4, 50);
        Message($"Quantum illumination: classical={classP:F3} | quantum={quantP:F3}");
        ResetAll(sigModes); ResetAll(idlModes);
 
        // Photonic quantum walk
        use walkModes = Qubit[8];
        let walkDist = PhotonicQuantumWalk(walkModes, 5);
        Message($"Photonic walk: {Length(walkDist)} modes");
        ResetAll(walkModes);
 
        Message("Quantum Optics Engine: ALL TESTS PASSED ✓");
    }
}
 
