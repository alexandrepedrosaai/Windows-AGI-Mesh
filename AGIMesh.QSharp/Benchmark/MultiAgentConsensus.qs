namespace AGIMesh.Benchmark {

    open Microsoft.Quantum.Convert;

    function MultiAgentConsensus(
        agreeing : Int,
        total : Int
    ) : Double {

        if total < 0 or agreeing < 0 or agreeing > total {
            fail "total must be nonnegative and agreeing must be between zero and total.";
        }

        if total == 0 {
            return 0.0;
        }

        return
            100.0 *
            IntAsDouble(agreeing) /
            IntAsDouble(total);
    }
}
