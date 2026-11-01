namespace WindowsAGIMesh.Cli;

/// <summary>
/// Handles the <c>agimesh help</c> command (and the default no-argument case).
/// Prints usage information for all registered commands.
/// </summary>
public static class HelpCommand
{
    public static Task<int> RunAsync(string[] args)
    {
        Console.WriteLine("╔══════════════════════════════════════════════════════════╗");
        Console.WriteLine("║              Windows AGI Mesh CLI  (agimesh)             ║");
        Console.WriteLine("╚══════════════════════════════════════════════════════════╝");
        Console.WriteLine();
        Console.WriteLine("USAGE");
        Console.WriteLine("  agimesh <command> [options]");
        Console.WriteLine();
        Console.WriteLine("COMMANDS");
        Console.WriteLine();

        PrintCommand(
            "benchmark [suite] [iterations]",
            "Run performance benchmarks.",
            [
                "suite      : all | reasoning | serialization  (default: all)",
                "iterations : number of iterations             (default: 1000000)"
            ]);

        PrintCommand(
            "schema [output-folder]",
            "Generate JSON Schema files from contract types.",
            [
                "output-folder : destination directory  (default: ./generated-schemas)"
            ]);

        PrintCommand(
            "validate [type] [file-or-json]",
            "Validate a JSON payload against a contract schema.",
            [
                "type         : node | agent | task | result | json",
                "file-or-json : path to a .json file, or an inline JSON string"
            ]);

        PrintCommand(
            "version",
            "Display version and runtime information.",
            []);

        PrintCommand(
            "help",
            "Display this help message.",
            []);

        Console.WriteLine("EXAMPLES");
        Console.WriteLine("  agimesh benchmark reasoning 500000");
        Console.WriteLine("  agimesh schema ./schemas");
        Console.WriteLine(@"  agimesh validate node '{""NodeId"":""n1"",""NodeType"":""Edge"",""Capabilities"":[]}'");
        Console.WriteLine("  agimesh validate agent ./samples/agent.json");
        Console.WriteLine("  agimesh version");
        Console.WriteLine();

        return Task.FromResult(0);
    }

    private static void PrintCommand(
        string syntax,
        string description,
        string[] options)
    {
        Console.ForegroundColor = ConsoleColor.Cyan;
        Console.Write($"  agimesh {syntax}");
        Console.ResetColor();
        Console.WriteLine();
        Console.WriteLine($"    {description}");

        foreach (string opt in options)
        {
            Console.WriteLine($"      {opt}");
        }

        Console.WriteLine();
    }
}
