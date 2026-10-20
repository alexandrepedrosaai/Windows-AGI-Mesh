namespace AGIMesh.Tests {

    open AGIMesh.Security;
    open Microsoft.Quantum.Diagnostics;

    @Test("QuantumSimulator")
    operation RiskAssessmentTest() : Unit {

        let score =
            CalculateRiskScore(
                0.95,
                0
            );

        let risk =
            RiskLevel(score);

        if risk != "Low" {
            fail "Risk classification invalid.";
        }
    }

    @Test("QuantumSimulator")
    operation ComplianceValidationTest() : Unit {

        if not IsCompliant(
            90.0
        ) {

            fail "Compliance failed.";
        }
    }
}
