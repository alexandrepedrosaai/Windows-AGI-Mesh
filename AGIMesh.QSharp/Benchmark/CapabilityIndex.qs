namespace AGIMesh.Benchmark {

    open AGIMesh.Core;

    function CalculateCapabilityIndex(
        scores : CapabilityScores
    ) : Double {

        let (
            reasoning,
            tools,
            memory,
            selfCorrection,
            coordination,
            quantum
        ) = scores!;

        return (
            reasoning +
            tools +
            memory +
            selfCorrection +
            coordination +
            quantum
        ) / 6.0;
    }
}
