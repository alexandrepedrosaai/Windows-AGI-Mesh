namespace AGUI {
    /// A minimal quantum-agent operation reserved for the Q# runtime integration.
    operation QuantumAgentProbe() : Result {
        use qubit = Qubit();
        H(qubit);
        let result = M(qubit);
        Reset(qubit);
        return result;
    }
}
