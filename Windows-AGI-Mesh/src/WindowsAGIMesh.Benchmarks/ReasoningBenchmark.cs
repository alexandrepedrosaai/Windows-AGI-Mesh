using WindowsAGIMesh.Contracts;

namespace WindowsAGIMesh.Benchmarks;

/// <summary>
/// Benchmarks CPU-bound reasoning workloads representative of AGI Mesh agent tasks:
/// mathematical computation, record allocation, and string processing.
/// </summary>
public static class ReasoningBenchmark
{
    private const int DefaultIterations = 1_000_000;

    // ─────────────────────────────────────────────────────────────────────────
    // Entry point
    // ─────────────────────────────────────────────────────────────────────────

    /// <summary>
    /// Runs all reasoning benchmarks and prints results to the console.
    /// </summary>
    /// <param name="iterations">Number of iterations per benchmark (default 1 000 000).</param>
    public static IReadOnlyList<BenchmarkResult> Run(
        int iterations = DefaultIterations)
    {
        Console.WriteLine("── Reasoning Benchmarks ──────────────────────────────────");
        Console.WriteLine();

        var results = new List<BenchmarkResult>
        {
            RunMathBenchmark(iterations),
            RunRecordAllocationBenchmark(iterations),
            RunStringProcessingBenchmark(iterations)
        };

        PrintSummary(results);

        return results;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Individual benchmarks
    // ─────────────────────────────────────────────────────────────────────────

    /// <summary>
    /// Measures floating-point throughput using square-root accumulation —
    /// a proxy for numerical reasoning workloads.
    /// </summary>
    public static BenchmarkResult RunMathBenchmark(int iterations = DefaultIterations)
    {
        double accumulator = 0;

        BenchmarkResult result = BenchmarkRunner.Run(
            name:       "Math (sqrt accumulation)",
            iterations: iterations,
            workload:   () =>
            {
                for (int i = 0; i < 100; i++)
                {
                    accumulator += Math.Sqrt(i);
                }
            });

        // Prevent the compiler from optimising away the loop
        _ = accumulator;

        result.Print();
        return result;
    }

    /// <summary>
    /// Measures the cost of allocating and discarding <see cref="MeshAgent"/> records —
    /// representative of high-frequency agent registry operations.
    /// </summary>
    public static BenchmarkResult RunRecordAllocationBenchmark(
        int iterations = DefaultIterations)
    {
        BenchmarkResult result = BenchmarkRunner.Run(
            name:       "Record allocation (MeshAgent)",
            iterations: iterations,
            workload:   () =>
            {
                _ = new MeshAgent(
                    AgentId:    Guid.NewGuid().ToString(),
                    Role:       "Executor",
                    Skills:     ["nlp", "code-gen"],
                    TrustLevel: 0.9);
            });

        result.Print();
        return result;
    }

    /// <summary>
    /// Measures string interpolation and formatting throughput —
    /// representative of log-line and message-envelope construction.
    /// </summary>
    public static BenchmarkResult RunStringProcessingBenchmark(
        int iterations = DefaultIterations)
    {
        BenchmarkResult result = BenchmarkRunner.Run(
            name:       "String processing (interpolation)",
            iterations: iterations,
            workload:   () =>
            {
                string id    = Guid.NewGuid().ToString("N");
                string label = $"[AGI-MESH] node={id} ts={DateTime.UtcNow:O}";
                _ = label.Length;
            });

        result.Print();
        return result;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Summary
    // ─────────────────────────────────────────────────────────────────────────

    private static void PrintSummary(IReadOnlyList<BenchmarkResult> results)
    {
        Console.WriteLine("── Summary ───────────────────────────────────────────────");
        Console.WriteLine(BenchmarkResult.CsvHeader);

        foreach (BenchmarkResult r in results)
        {
            Console.WriteLine(r.ToCsv());
        }

        Console.WriteLine("──────────────────────────────────────────────────────────");
    }
}
