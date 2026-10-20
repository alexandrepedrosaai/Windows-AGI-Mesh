namespace AGIMesh.Agents {

    open Microsoft.Quantum.Convert;

    function ConsensusScore(
        agreeingAgents : Int,
        totalAgents : Int
    ) : Double {

        if totalAgents <= 0 {
            return 0.0;
        }

        return
            100.0 *
            IntAsDouble(
                agreeingAgents
            )
            /
            IntAsDouble(
                totalAgents
            );
    }
}
