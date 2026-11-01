using WindowsAGIMesh.Contracts;
using WindowsAGIMesh.SchemaGenerator;

namespace WindowsAGIMesh.Cli;

/// <summary>
/// Handles the <c>agimesh schema</c> command.
/// Usage: agimesh schema [output-folder]
///   output-folder : path where .schema.json files are written (default: ./generated-schemas)
/// </summary>
public static class SchemaCommand
{
    public static async Task<int> RunAsync(string[] args)
    {
        string outputFolder = args.Length > 0
            ? args[0]
            : Path.Combine(Directory.GetCurrentDirectory(), "generated-schemas");

        Console.WriteLine($"Generating JSON schemas → {outputFolder}");
        Console.WriteLine();

        Directory.CreateDirectory(outputFolder);

        var assembly = typeof(MeshNode).Assembly;

        int generated = 0;
        int failed    = 0;

        foreach (Type type in assembly
            .GetTypes()
            .Where(t =>
                t.IsPublic
                && !t.IsAbstract
                && !t.IsInterface
                && t.Namespace == "WindowsAGIMesh.Contracts"
                && !t.Name.StartsWith('I'))
            .OrderBy(t => t.Name))
        {
            try
            {
                string schema   = SchemaExporter.Generate(type);
                string filePath = Path.Combine(outputFolder, $"{type.Name}.schema.json");

                await File.WriteAllTextAsync(filePath, schema);

                Console.ForegroundColor = ConsoleColor.Green;
                Console.Write("  ✓ ");
                Console.ResetColor();
                Console.WriteLine($"{type.Name,-40} → {Path.GetFileName(filePath)}");

                generated++;
            }
            catch (Exception ex)
            {
                Console.ForegroundColor = ConsoleColor.Red;
                Console.Write("  ✗ ");
                Console.ResetColor();
                Console.WriteLine($"{type.Name,-40} ERROR: {ex.Message}");

                failed++;
            }
        }

        Console.WriteLine();
        Console.WriteLine($"Generated : {generated}  |  Failed : {failed}");

        return failed > 0 ? 1 : 0;
    }
}
