namespace AGIMesh.Tests {

    open AGIMesh.Validation;

    @Test("QuantumSimulator")
    operation ConfidenceValidationTest()
    : Unit {

        if not IsValidConfidence(
            0.95
        ) {

            fail
            "Confidence validation failed.";
        }
    }
}
