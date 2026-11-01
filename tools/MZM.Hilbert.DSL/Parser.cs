using System.Text.RegularExpressions;

namespace Mzm.Hilbert.Dsl;

public static class QMeshParser
{
    private static readonly Regex ImportPattern = new(@"\bimport\s+""([^""]+)""\s*;", RegexOptions.Compiled);
    private static readonly Regex MeshPattern = new(@"\bmesh\s+(\w+)\s*\{(?<body>.*)\}\s*$", RegexOptions.Compiled | RegexOptions.Singleline);
    private static readonly Regex QuantumPattern = new(@"\bquantum\s+(\w+)\s*\{(?<body>.*?)\}", RegexOptions.Compiled | RegexOptions.Singleline);
    private static readonly Regex QubitPattern = new(@"\bqubit\s+(\w+)\s*;", RegexOptions.Compiled);
    private static readonly Regex GatePattern = new(@"\b(H|X|Y|Z|T|S|CNOT)\s+([\w\s,]+)\s*;", RegexOptions.Compiled);

    public static MeshProgram Parse(string source)
    {
        var imports = ImportPattern.Matches(source).Select(m => m.Groups[1].Value).ToArray();
        var mesh = MeshPattern.Match(source);
        var meshName = mesh.Success ? mesh.Groups[1].Value : "QMeshProgram";
        var body = mesh.Success ? mesh.Groups["body"].Value : source;
        var blocks = new List<QuantumBlock>();
        foreach (Match match in QuantumPattern.Matches(body))
        {
            var blockBody = match.Groups["body"].Value;
            var qubits = QubitPattern.Matches(blockBody).Select(m => new QubitDecl(m.Groups[1].Value)).ToArray();
            var gates = new List<GateCall>();
            foreach (Match gate in GatePattern.Matches(blockBody))
            {
                var operands = gate.Groups[2].Value.Split(',', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries);
                gates.Add(new GateCall(gate.Groups[1].Value, operands));
            }
            blocks.Add(new QuantumBlock(match.Groups[1].Value, qubits, gates));
        }
        if (blocks.Count == 0)
            throw new InvalidOperationException("QMesh source contains no quantum block.");
        return new MeshProgram(meshName, imports, blocks);
    }
}
