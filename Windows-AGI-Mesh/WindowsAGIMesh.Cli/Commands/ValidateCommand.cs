using WindowsAGIMesh.Schemas;

namespace WindowsAGIMesh.Cli;

/// <summary>
/// Handles the <c>agimesh validate</c> command.
/// Usage: agimesh validate [type] [file-or-json]
///   type         : node | agent | task | result | json  (default: json)
///   file-or-json : path to a JSON file, or a raw JSON string
/// </summary>
public static class ValidateCommand
{
    public static async Task<int> RunAsync(string[] args)
    {
        if (args.Length < 2)
        {
            Console.Error.WriteLine(
                "Usage: agimesh validate [type] [file-or-json]");
            Console.Error.WriteLine(
                "  type : node | agent | task | result | json");
            return 1;
        }

        string type  = args[0].ToLowerInvariant();
        string input = args[1];

        // Resolve input: file path or inline JSON
        string json;

        if (File.Exists(input))
        {
            json = await File.ReadAllTextAsync(input);
            Console.WriteLine($"Validating file : {input}");
        }
        else
        {
            json = input;
            Console.WriteLine("Validating inline JSON...");
        }

        Console.WriteLine($"Type            : {type}");
        Console.WriteLine();

        ValidationResult result;

        switch (type)
        {
            case "node":
                result = SchemaValidator.ValidateMeshNode(json);
                break;

            case "agent":
                result = SchemaValidator.ValidateMeshAgent(json);
                break;

            case "task":
                result = SchemaValidator.ValidateMeshTask(json);
                break;

            case "result":
                result = SchemaValidator.ValidateMeshResult(json);
                break;

            case "json":
                result = SchemaValidator.IsValidJson(json)
                    ? ValidationResult.Ok()
                    : ValidationResult.Fail("Input is not valid JSON.");
                break;

            default:
                Console.Error.WriteLine(
                    $"Unknown type '{type}'. Valid: node, agent, task, result, json");
                return 1;
        }

        if (result.IsValid)
        {
            Console.ForegroundColor = ConsoleColor.Green;
            Console.WriteLine("  ✓  Validation passed.");
        }
        else
        {
            Console.ForegroundColor = ConsoleColor.Red;
            Console.WriteLine($"  ✗  Validation failed: {result.ErrorMessage}");
        }

        Console.ResetColor();

        return result.IsValid ? 0 : 1;
    }
}
