using WindowsAGIMesh.Benchmarks;

namespace WindowsAGIMesh.Cli;

/// <summary>
/// Handles the <c>agimesh benchmark</c> command.
/// Usage: agimesh benchmark [suite] [iterations]
///   suite      : all | reasoning | serialization  (default: all)
///   iterations : positive integer                 (default: 1000000)
/// </summary>
public static class BenchmarkCommand
{
    public static Task<int> RunAsync(string[] args)
    {
        string suite      = args.Length > 0 ? args[0] : "all";
        int    iterations = args.Length > 1
            && int.TryParse(args[1], out int n) && n > 0
                ? n
                : 1_000_000;

        Console.WriteLine($"Running benchmark suite '{suite}' with {iterations:N0} iterations...");
        Console.WriteLine();

        switch (suite.ToLowerInvariant())
        {
            case "reasoning":
                ReasoningBenchmark.Run(iterations);
                break;

            case "serialization":
                SerializationBenchmark.Run(Math.Min(iterations, 500_000));
                break;

            case "all":
                ReasoningBenchmark.Run(iterations);
                SerializationBenchmark.Run(Math.Min(iterations, 500_000));
                break;

            default:
                Console.Error.WriteLine(
                    $"Unknown suite '{suite}'. Valid options: all, reasoning, serialization");
                return Task.FromResult(1);
        }

        return Task.FromResult(0);
    }
}
