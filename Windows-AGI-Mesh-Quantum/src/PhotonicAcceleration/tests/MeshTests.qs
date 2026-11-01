namespace WindowsAGIMesh.Tests {

    open WindowsAGIMesh.Core;
    open Microsoft.Quantum.Diagnostics;

    @Test("QuantumSimulator")
    operation TestMeshOrchestration() : Unit {
        let output = OrchestrateAGIMesh(1.0);
        Fact(output > 0.0, "Mesh orchestration must produce valid output");
    }
}
