namespace AGIMesh.Benchmark {

    open Microsoft.Quantum.Convert;

    function MultiAgentConsensus(
        agreeing : Int,
        total : Int
    ) : Double {

        if total == 0 {
            return 0.0;
        }

        return
            100.0 *
            IntAsDouble(agreeing) /
            IntAsDouble(total);
    }
}
