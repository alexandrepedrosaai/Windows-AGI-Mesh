using System.ComponentModel.DataAnnotations;

namespace WindowsAGIMesh.Contracts;

/// <summary>
/// Captures the result of a performance benchmark run against a mesh node or agent.
/// Benchmarks measure reasoning throughput, latency, and hardware utilisation.
/// </summary>
public sealed record MeshBenchmark
(
    // <summary>Unique identifier for this benchmark run.</summary>
    [Required]
    [StringLength(128, MinimumLength = 1)]
    string BenchmarkId,

    // <summary>
    // Normalised performance score in the range [0.0, 100.0].
    // Higher is better.
    // </summary>
    [Range(0.0, 100.0)]
    double Score,

    // <summary>
    // End-to-end latency measured in milliseconds for the benchmark workload.
    // </summary>
    [Range(0.0, double.MaxValue)]
    double LatencyMs,

    // <summary>
    // Identifier of the node or agent that produced this result.
    // </summary>
    string TargetId = "",

    // <summary>
    // UTC timestamp when the benchmark was executed.
    // </summary>
    DateTime? ExecutedAt = null
)
{
    /// <summary>
    /// Returns true when the benchmark score meets the minimum passing threshold (>= 60.0).
    /// </summary>
    public bool Passed => Score >= 60.0;

    /// <summary>
    /// Returns a human-readable summary of the benchmark result.
    /// </summary>
    public string Summary =>
        $"[{BenchmarkId}] Score={Score:F2} | Latency={LatencyMs:F2}ms | Passed={Passed}";
}