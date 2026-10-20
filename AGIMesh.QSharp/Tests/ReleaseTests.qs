namespace AGIMesh.Tests {

    open AGIMesh.Security;

    @Test("QuantumSimulator")
    operation ReleaseValidationTest() : Unit {

        if not IsReleaseReady(
            90.0,
            90.0
        ) {

            fail "Release should be approved.";
        }
    }
}
