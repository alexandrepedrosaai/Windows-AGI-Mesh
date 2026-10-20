namespace AGIMesh.Tests {

    open AGIMesh.Benchmark;

    @Test("QuantumSimulator")
    operation BenchmarkTest()
    : Unit {

        let result =
            RunBenchmark();

        let (
            ci,
            consensus,
            qc
        ) = result!;

        if ci <= 0.0 {
            fail "Capability index invalid.";
        }

        if consensus <= 0.0 {
            fail "Consensus invalid.";
        }

        if qc <= 0.0 {
            fail "Quantum correlation invalid.";
        }
    }
}
