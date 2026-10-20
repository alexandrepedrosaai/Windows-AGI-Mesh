namespace WindowsAGIMesh.Cli;

/// <summary>
/// Routes top-level CLI commands to their handler methods.
/// Supports a verb-based command model: agimesh [command] [options...]
/// </summary>
public static class CliRouter
{
    // ─────────────────────────────────────────────────────────────────────────
    // Command registry
    // ─────────────────────────────────────────────────────────────────────────

    private static readonly Dictionary<string, Func<string[], Task<int>>> s_commands =
        new(StringComparer.OrdinalIgnoreCase)
        {
            ["benchmark"] = BenchmarkCommand.RunAsync,
            ["schema"]    = SchemaCommand.RunAsync,
            ["validate"]  = ValidateCommand.RunAsync,
            ["version"]   = VersionCommand.RunAsync,
            ["help"]      = HelpCommand.RunAsync,
        };

    // ─────────────────────────────────────────────────────────────────────────
    // Entry point
    // ─────────────────────────────────────────────────────────────────────────

    /// <summary>
    /// Dispatches the CLI arguments to the appropriate command handler.
    /// Returns the process exit code (0 = success, non-zero = error).
    /// </summary>
    public static async Task<int> DispatchAsync(string[] args)
    {
        string verb = args.Length > 0
            ? args[0].ToLowerInvariant()
            : "help";

        string[] remaining = args.Length > 1
            ? args[1..]
            : [];

        if (s_commands.TryGetValue(verb, out Func<string[], Task<int>>? handler))
        {
            try
            {
                return await handler(remaining);
            }
            catch (Exception ex)
            {
                Console.ForegroundColor = ConsoleColor.Red;
                Console.Error.WriteLine($"Error: {ex.Message}");
                Console.ResetColor();
                return 1;
            }
        }

        Console.ForegroundColor = ConsoleColor.Yellow;
        Console.Error.WriteLine($"Unknown command: '{verb}'");
        Console.ResetColor();
        Console.WriteLine();

        await HelpCommand.RunAsync([]);
        return 1;
    }

    /// <summary>Returns the list of registered command verbs.</summary>
    public static IEnumerable<string> RegisteredVerbs =>
        s_commands.Keys.Order();
}
