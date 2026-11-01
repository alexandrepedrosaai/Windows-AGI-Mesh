using System.Text.Json;
using WindowsAGIMesh.Contracts;
using WindowsAGIMesh.Schemas;

namespace WindowsAGIMesh.Benchmarks;

/// <summary>
/// Benchmarks JSON serialisation and deserialisation throughput for core
/// AGI Mesh contract types, and measures schema validation overhead.
/// </summary>
public static class SerializationBenchmark
{
    private const int DefaultIterations = 500_000;

    private static readonly JsonSerializerOptions s_options = new()
    {
        WriteIndented = false,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase
    };

    // ─────────────────────────────────────────────────────────────────────────
    // Sample data
    // ─────────────────────────────────────────────────────────────────────────

    private static readonly MeshNode s_sampleNode = new(
        NodeId:       "node-001",
        NodeType:     "EdgeDevice",
        Capabilities: ["vision", "nlp", "code-exec"],
        SupportsCpu:  true,
        SupportsGpu:  true,
        SupportsNpu:  false);

    private static readonly MeshAgent s_sampleAgent = new(
        AgentId:    "agent-001",
        Role:       "Executor",
        Skills:     ["summarization", "code-generation"],
        TrustLevel: 0.95);

    private static readonly MeshTask s_sampleTask = new(
        TaskId:      "task-001",
        Description: "Summarise the quarterly earnings report.",
        Priority:    "High",
        CreatedAt:   DateTime.UtcNow);

    // ─────────────────────────────────────────────────────────────────────────
    // Entry point
    // ─────────────────────────────────────────────────────────────────────────

    /// <summary>
    /// Runs all serialisation benchmarks and returns the results.
    /// </summary>
    public static IReadOnlyList<BenchmarkResult> Run(
        int iterations = DefaultIterations)
    {
        Console.WriteLine("── Serialisation Benchmarks ──────────────────────────────");
        Console.WriteLine();

        var results = new List<BenchmarkResult>
        {
            RunSerializeBenchmark(iterations),
            RunDeserializeBenchmark(iterations),
            RunValidationBenchmark(iterations)
        };

        Console.WriteLine("── Serialisation Summary ─────────────────────────────────");
        Console.WriteLine(BenchmarkResult.CsvHeader);

        foreach (BenchmarkResult r in results)
        {
            Console.WriteLine(r.ToCsv());
        }

        Console.WriteLine("──────────────────────────────────────────────────────────");

        return results;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Individual benchmarks
    // ─────────────────────────────────────────────────────────────────────────

    private static BenchmarkResult RunSerializeBenchmark(int iterations)
    {
        BenchmarkResult result = BenchmarkRunner.Run(
            name:       "JSON Serialize (MeshNode + MeshAgent + MeshTask)",
            iterations: iterations,
            workload:   () =>
            {
                _ = JsonSerializer.Serialize(s_sampleNode,  s_options);
                _ = JsonSerializer.Serialize(s_sampleAgent, s_options);
                _ = JsonSerializer.Serialize(s_sampleTask,  s_options);
            });

        result.Print();
        return result;
    }

    private static BenchmarkResult RunDeserializeBenchmark(int iterations)
    {
        string nodeJson  = JsonSerializer.Serialize(s_sampleNode,  s_options);
        string agentJson = JsonSerializer.Serialize(s_sampleAgent, s_options);
        string taskJson  = JsonSerializer.Serialize(s_sampleTask,  s_options);

        BenchmarkResult result = BenchmarkRunner.Run(
            name:       "JSON Deserialize (MeshNode + MeshAgent + MeshTask)",
            iterations: iterations,
            workload:   () =>
            {
                _ = JsonSerializer.Deserialize<MeshNode>(nodeJson,   s_options);
                _ = JsonSerializer.Deserialize<MeshAgent>(agentJson, s_options);
                _ = JsonSerializer.Deserialize<MeshTask>(taskJson,   s_options);
            });

        result.Print();
        return result;
    }

    private static BenchmarkResult RunValidationBenchmark(int iterations)
    {
        string nodeJson = JsonSerializer.Serialize(s_sampleNode, s_options);

        BenchmarkResult result = BenchmarkRunner.Run(
            name:       "Schema Validation (MeshNode)",
            iterations: iterations,
            workload:   () =>
            {
                _ = SchemaValidator.ValidateMeshNode(nodeJson);
            });

        result.Print();
        return result;
    }
}
