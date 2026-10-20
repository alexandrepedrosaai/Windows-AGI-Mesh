namespace AGIMesh.Benchmark {

    open Microsoft.Quantum.Convert;
    open Microsoft.Quantum.Intrinsic;
    open Microsoft.Quantum.Measurement;

    operation QuantumCorrelation(
        shots : Int
    ) : Double {

        if shots <= 0 {
            fail "shots must be greater than zero.";
        }

        mutable matches = 0;

        for _ in 1..shots {

            use q = Qubit[2];

            H(q[0]);
            CNOT(q[0], q[1]);

            let a = MResetZ(q[0]);
            let b = MResetZ(q[1]);

            if a == b {
                set matches += 1;
            }
        }

        return
            100.0 *
            IntAsDouble(matches) /
            IntAsDouble(shots);
    }
}
