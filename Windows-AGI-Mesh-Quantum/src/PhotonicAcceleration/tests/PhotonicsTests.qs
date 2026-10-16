namespace WindowsAGIMesh.Tests {

    open WindowsAGIMesh.Photonics;
    open Microsoft.Quantum.Diagnostics;

    @Test("QuantumSimulator")
    operation TestPhotonicBoost() : Unit {
        let result = FiberInferenceBoost(1.0);
        Fact(result > 1.0, "Photonic boost should increase input");
    }
}
