namespace AGIMesh {

    open AGIMesh.Benchmark;

    @EntryPoint()
    operation Main()
    : Unit {

        let result =
            RunBenchmark();

        Message(
            $"AGI Mesh Benchmark = {result}"
        );
    }
}
