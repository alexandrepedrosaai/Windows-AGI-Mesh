using System.Reflection;
using WindowsAGIMesh.Contracts;
using WindowsAGIMesh.SchemaGenerator;

// ─────────────────────────────────────────────────────────────────────────────
// Windows AGI Mesh — JSON Schema Generator
// Reflects over all public record types in WindowsAGIMesh.Contracts and
// writes one .schema.json file per type into the output folder.
// ─────────────────────────────────────────────────────────────────────────────

string outputFolder = args.Length > 0
    ? args[0]
    : Path.Combine(AppContext.BaseDirectory, "generated-schemas");

Directory.CreateDirectory(outputFolder);

Console.WriteLine("Windows AGI Mesh — Schema Generator");
Console.WriteLine($"Output folder : {outputFolder}");
Console.WriteLine(new string('─', 60));

Assembly contractsAssembly = typeof(MeshNode).Assembly;

int generated = 0;
int skipped   = 0;

foreach (Type type in contractsAssembly
    .GetTypes()
    .Where(t =>
        t.IsPublic
        && !t.IsAbstract
        && !t.IsInterface
        && t.Namespace == "WindowsAGIMesh.Contracts"
        && !t.Name.StartsWith('I'))          // skip interfaces
    .OrderBy(t => t.Name))
{
    try
    {
        string schema = SchemaExporter.Generate(type);

        string filePath = Path.Combine(
            outputFolder,
            $"{type.Name}.schema.json");

        await File.WriteAllTextAsync(filePath, schema);

        Console.WriteLine($"  ✓  {type.Name,-40} → {Path.GetFileName(filePath)}");
        generated++;
    }
    catch (Exception ex)
    {
        Console.WriteLine($"  ✗  {type.Name,-40} ERROR: {ex.Message}");
        skipped++;
    }
}

Console.WriteLine(new string('─', 60));
Console.WriteLine($"Generated : {generated}");
Console.WriteLine($"Skipped   : {skipped}");
Console.WriteLine("Done.");