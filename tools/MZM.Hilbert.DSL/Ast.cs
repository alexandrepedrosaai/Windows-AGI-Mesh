namespace Mzm.Hilbert.Dsl;

public sealed record QubitDecl(string Name);
public sealed record GateCall(string Name, IReadOnlyList<string> Qubits);
public sealed record QuantumBlock(string Name, IReadOnlyList<QubitDecl> Qubits, IReadOnlyList<GateCall> Gates);
public sealed record MeshProgram(string Name, IReadOnlyList<string> Imports, IReadOnlyList<QuantumBlock> QuantumBlocks);
