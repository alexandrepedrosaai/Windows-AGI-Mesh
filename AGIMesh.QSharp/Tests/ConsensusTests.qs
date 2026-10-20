namespace AGIMesh.Tests {

    open AGIMesh.Benchmark;

    @Test("QuantumSimulator")
    operation ConsensusTest()
    : Unit {

        let result =
            MultiAgentConsensus(
                9,
                10
            );

        if result < 90.0 {

            fail
            "Consensus failed.";
        }
    }
}
