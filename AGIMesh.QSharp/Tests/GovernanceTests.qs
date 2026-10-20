namespace AGIMesh.Tests {

    open AGIMesh.Governance;
    open Microsoft.Quantum.Diagnostics;

    @Test("QuantumSimulator")
    operation ReviewWorkflowTest() : Unit {

        let result =
            ReviewApproved(
                true,
                true
            );

        if not result {
            fail "Review should pass.";
        }
    }

    @Test("QuantumSimulator")
    operation ApprovalWorkflowTest() : Unit {

        let decision =
            ApprovalDecision(
                true
            );

        if decision != "Approved" {
            fail "Approval decision invalid.";
        }
    }
}
