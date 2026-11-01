namespace AGIMesh.Tests {

    open AGIMesh.Benchmark;

    @Microsoft.Quantum.Diagnostics.Test("QuantumSimulator")
    operation QuantumCorrelationTest() : Unit {

        let result =
            QuantumCorrelation(
                25
            );

        if result < 80.0 {
            fail "Quantum correlation too low.";
        }
    }
}
