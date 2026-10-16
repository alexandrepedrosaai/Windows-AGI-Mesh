namespace WindowsAGIMesh.Tests {

    open WindowsAGIMesh.Quantum;
    open Microsoft.Quantum.Diagnostics;

    @Test("QuantumSimulator")
    operation TestMajoranaEnergy() : Unit {
        let energy = MajoranaPairEnergy(0.5, 0.4);
        Fact(energy > 0.0, "Majorana energy must be positive");
    }
}
