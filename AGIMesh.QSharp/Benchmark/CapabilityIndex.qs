namespace AGIMesh.Benchmark {

    open AGIMesh.Core;

    function CalculateCapabilityIndex(
        scores : CapabilityScores
    ) : Double {

        let (
            reasoning,
            tools,
            memory,
            coordination,
            quantum
        ) = scores!;

        return (
            reasoning +
            tools +
            memory +
            coordination +
            quantum
        ) / 5.0;
    }
}
