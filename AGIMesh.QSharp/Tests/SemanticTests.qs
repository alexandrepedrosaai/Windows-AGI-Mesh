namespace AGIMesh.Tests {

    open AGIMesh.Validation;

    @Test("QuantumSimulator")
    operation SemanticValidationTest() : Unit {

        let valid =
            ValidateSemanticClassification(
                "Artificial Intelligence",
                "Distributed Systems"
            );

        if not valid {
            fail "Semantic validation failed.";
        }
    }
}
