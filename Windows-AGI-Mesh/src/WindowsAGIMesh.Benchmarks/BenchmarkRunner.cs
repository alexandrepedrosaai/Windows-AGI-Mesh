using System.Diagnostics;

namespace WindowsAGIMesh.Benchmarks;

/// <summary>
/// Lightweight benchmark harness that measures wall-clock time and throughput
/// for a named workload without external dependencies.
/// </summary>
public static class BenchmarkRunner
{
    /// <summary>
    /// Runs a synchronous benchmark and returns the result.
    /// </summary>
    /// <param name="name">Display name for the benchmark.</param>
    /// <param name="iterations">Number of iterations to execute.</param>
    /// <param name="workload">The action to benchmark.</param>
    public static BenchmarkResult Run(
        string name,
        int iterations,
        Action workload)
    {
        ArgumentNullException.ThrowIfNull(workload);
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(iterations);

        // Warm-up: one un-timed iteration to JIT-compile the workload
        workload();

        GC.Collect(2, GCCollectionMode.Forced, blocking: true);
        GC.WaitForPendingFinalizers();
        GC.Collect(2, GCCollectionMode.Forced, blocking: true);

        Stopwatch sw = Stopwatch.StartNew();

        for (int i = 0; i < iterations; i++)
        {
            workload();
        }

        sw.Stop();

        return new BenchmarkResult(
            Name:           name,
            Iterations:     iterations,
            TotalMs:        sw.Elapsed.TotalMilliseconds,
            AverageMs:      sw.Elapsed.TotalMilliseconds / iterations,
            OpsPerSecond:   iterations / sw.Elapsed.TotalSeconds);
    }

    /// <summary>
    /// Runs an async benchmark and returns the result.
    /// </summary>
    public static async Task<BenchmarkResult> RunAsync(
        string name,
        int iterations,
        Func<Task> workload)
    {
        ArgumentNullException.ThrowIfNull(workload);
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(iterations);

        // Warm-up
        await workload();

        GC.Collect(2, GCCollectionMode.Forced, blocking: true);
        GC.WaitForPendingFinalizers();

        Stopwatch sw = Stopwatch.StartNew();

        for (int i = 0; i < iterations; i++)
        {
            await workload();
        }

        sw.Stop();

        return new BenchmarkResult(
            Name:           name,
            Iterations:     iterations,
            TotalMs:        sw.Elapsed.TotalMilliseconds,
            AverageMs:      sw.Elapsed.TotalMilliseconds / iterations,
            OpsPerSecond:   iterations / sw.Elapsed.TotalSeconds);
    }
}
