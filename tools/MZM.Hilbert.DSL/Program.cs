namespace Mzm.Hilbert.Dsl;

public static class Program
{
    public static int Main(string[] args)
    {
        if (args.Length < 2 || args[0] is "--help" or "-h")
        {
            Console.WriteLine("qmeshc build|emit-qsharp|emit-qir|graph|run <file.qmesh> [--output <path>]");
            return args.Length < 2 ? 2 : 0;
        }
        var command = args[0].ToLowerInvariant();
        var input = args[1];
        var output = GetOption(args, "--output") ?? "qmesh-out";
        try
        {
            var source = File.ReadAllText(input);
            var program = MeshOptimizer.Optimize(QMeshParser.Parse(source));
            SemanticAnalyzer.Validate(program);
            Directory.CreateDirectory(output);
            switch (command)
            {
                case "build":
                    Write(output, Path.GetFileNameWithoutExtension(input) + ".qsharp", QSharpBackend.Emit(program));
                    Write(output, Path.GetFileNameWithoutExtension(input) + ".qir", QirBackend.Emit(program));
                    Write(output, Path.GetFileNameWithoutExtension(input) + ".dot", GraphvizBackend.Emit(program));
                    Write(output, Path.GetFileNameWithoutExtension(input) + ".yaml", YamlBackend.Emit(program));
                    Write(output, Path.GetFileNameWithoutExtension(input) + ".mesh-ir.json", MeshIr.ToJson(program));
                    break;
                case "emit-qsharp": Write(output, Path.GetFileNameWithoutExtension(input) + ".qsharp", QSharpBackend.Emit(program)); break;
                case "emit-qir": Write(output, Path.GetFileNameWithoutExtension(input) + ".qir", QirBackend.Emit(program)); break;
                case "graph": Write(output, Path.GetFileNameWithoutExtension(input) + ".dot", GraphvizBackend.Emit(program)); break;
                case "run": Console.WriteLine(QSharpBackend.Emit(program)); break;
                default: Console.Error.WriteLine($"Unknown qmeshc command: {command}"); return 2;
            }
            Console.WriteLine($"qmeshc {command}: {input} -> {output}");
            return 0;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"qmeshc error: {ex.Message}");
            return 1;
        }
    }

    private static string? GetOption(string[] args, string name)
    {
        var i = Array.IndexOf(args, name);
        return i >= 0 && i + 1 < args.Length ? args[i + 1] : null;
    }

    private static void Write(string directory, string filename, string content) => File.WriteAllText(Path.Combine(directory, filename), content);
}
