namespace AGIMesh.Tests {

    open AGIMesh.Agents;
    open Microsoft.Quantum.Diagnostics;

    @Test("QuantumSimulator")
    operation AgentReadinessTest() : Unit {

        if not IsAgentReady(
            90.0,
            85.0
        ) {

            fail "Agent should be ready.";
        }
    }

    @Test("QuantumSimulator")
    operation RagCompatibilityTest() : Unit {

        if not IsRagCompatible(
            true,
            true
        ) {

            fail "RAG compatibility failed.";
        }
    }
}
