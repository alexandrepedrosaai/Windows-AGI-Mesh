namespace AGIMesh.Tests {

    open AGIMesh.Core;
    open AGIMesh.Benchmark;

    @Test("QuantumSimulator")
    operation CapabilityIndexTest() : Unit {

        let scores =
            CapabilityScores(
                90.0,
                88.0,
                87.0,
                92.0,
                100.0
            );

        let result =
            CalculateCapabilityIndex(
                scores
            );

        if result <= 0.0 {
            fail "Capability index invalid.";
        }
    }
}
