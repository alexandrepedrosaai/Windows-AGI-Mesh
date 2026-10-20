namespace AGIMesh.Security {

    function IsReleaseReady(
        securityScore : Double,
        benchmarkScore : Double
    ) : Bool {

        return securityScore >= 70.0
            and benchmarkScore >= 75.0;
    }
}
