namespace AGIMesh.Tests {

    open AGIMesh.Benchmark;

    @Test("QuantumSimulator")
    operation ConsensusTest()
    : Unit {

        let result =
            MultiAgentConsensus(
                [1, 1, 1, 1, 1, 1, 1, 1, 1, 0]
            );

        if result < 90.0 {

            fail
            "Consensus failed.";
        }
    }
}
