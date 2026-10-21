// ─────────────────────────────────────────────────────────────────────────────
// Windows AGI Mesh — Benchmark Runner
// Usage:
//   dotnet run --project src/WindowsAGIMesh.Benchmarks [suite] [iterations]
//
//   suite      : all | reasoning | serialization   (default: all)
//   iterations : positive integer                  (default: 1000000)
// ─────────────────────────────────────────────────────────────────────────────

using WindowsAGIMesh.Benchmarks;

string suite      = args.Length > 0 ? args[0].ToLowerInvariant() : "all";
int    iterations = args.Length > 1 && int.TryParse(args[1], out int n) ? n : 1_000_000;

Console.WriteLine("╔══════════════════════════════════════════════════════════╗");
Console.WriteLine("║         Windows AGI Mesh — Performance Benchmarks        ║");
Console.WriteLine("╚══════════════════════════════════════════════════════════╝");
Console.WriteLine($"  Suite      : {suite}");
Console.WriteLine($"  Iterations : {iterations:N0}");
Console.WriteLine();

switch (suite)
{
    case "reasoning":
        ReasoningBenchmark.Run(iterations);
        break;

    case "serialization":
        SerializationBenchmark.Run(
            Math.Min(iterations, 500_000)); // cap for serialisation suite
        break;

    case "all":
    default:
        ReasoningBenchmark.Run(iterations);
        SerializationBenchmark.Run(
            Math.Min(iterations, 500_000));
        break;
}

Console.WriteLine("All benchmarks complete.");
