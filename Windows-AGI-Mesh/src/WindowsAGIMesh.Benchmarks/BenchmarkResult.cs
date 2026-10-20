/// <summary>
/// Immutable record that captures the outcome of a single benchmark run.
/// </summary>
public sealed record BenchmarkResult
(
    /// <summary>Display name of the benchmark.</summary>
    string Name,

    /// <summary>Total number of iterations executed.</summary>
    int Iterations,

    /// <summary>Total wall-clock time in milliseconds.</summary>
    double TotalMs,

    /// <summary>Average time per iteration in milliseconds.</summary>
    double AverageMs,

    /// <summary>Throughput expressed as operations per second.</summary>
    double OpsPerSecond
)
{
    /// <summary>
    /// Prints a formatted summary of the benchmark result to the console.
    /// </summary>
    public void Print()
    {
        Console.WriteLine($"  Benchmark   : {Name}");
        Console.WriteLine($"  Iterations  : {Iterations:N0}");
        Console.WriteLine($"  Total       : {TotalMs:F2} ms");
        Console.WriteLine($"  Average     : {AverageMs:F4} ms / op");
        Console.WriteLine($"  Throughput  : {OpsPerSecond:N0} ops/sec");
        Console.WriteLine();
    }

    /// <summary>
    /// Returns a single-line CSV representation suitable for logging or export.
    /// </summary>
    public string ToCsv() =>
        $"{Name},{Iterations},{TotalMs:F4},{AverageMs:F6},{OpsPerSecond:F2}";

    /// <summary>CSV header row matching <see cref="ToCsv"/>.</summary>
    public static string CsvHeader =>
        "Name,Iterations,TotalMs,AverageMs,OpsPerSecond";
}
