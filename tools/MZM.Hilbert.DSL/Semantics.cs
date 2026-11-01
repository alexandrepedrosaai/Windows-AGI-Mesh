using System.Text.RegularExpressions;

namespace Mzm.Hilbert.Dsl;

public static class QMeshLexer
{
    public static IReadOnlyList<string> Tokens(string source) =>
        Regex.Matches(source, @"[A-Za-z_]\w*|\d+(?:\.\d+)?|->|[{}();,:]")
            .Select(m => m.Value).ToArray();
}

public static class SemanticAnalyzer
{
    private static readonly HashSet<string> SingleQubit = ["H", "X", "Y", "Z", "T", "S"];

    public static void Validate(MeshProgram program)
    {
        if (string.IsNullOrWhiteSpace(program.Name)) throw new InvalidOperationException("Mesh name is required.");
        foreach (var block in program.QuantumBlocks)
        {
            var names = block.Qubits.Select(q => q.Name).ToHashSet(StringComparer.Ordinal);
            if (names.Count != block.Qubits.Count) throw new InvalidOperationException($"Duplicate qubit in {block.Name}.");
            foreach (var gate in block.Gates)
            {
                if (!SingleQubit.Contains(gate.Name) && gate.Name != "CNOT")
                    throw new InvalidOperationException($"Unsupported gate: {gate.Name}.");
                var expected = gate.Name == "CNOT" ? 2 : 1;
                if (gate.Qubits.Count != expected) throw new InvalidOperationException($"Gate {gate.Name} expects {expected} operands.");
                foreach (var qubit in gate.Qubits)
                    if (!names.Contains(qubit)) throw new InvalidOperationException($"Unknown qubit {qubit} in {block.Name}.");
            }
        }
    }
}

public static class MeshOptimizer
{
    public static MeshProgram Optimize(MeshProgram program) => program;
}
