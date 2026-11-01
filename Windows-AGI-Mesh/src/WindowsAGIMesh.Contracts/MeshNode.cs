using System.ComponentModel.DataAnnotations;

namespace WindowsAGIMesh.Contracts;

/// <summary>
/// Represents a physical or virtual node participating in the AGI Mesh network.
/// A node exposes hardware capabilities (CPU, GPU, NPU) and a set of functional capabilities.
/// </summary>
public sealed record MeshNode
(
    // <summary>Unique identifier for this node.</summary>
    [Required]
    [StringLength(128, MinimumLength = 1)]
    string NodeId,

    // <summary>
    // Logical type of the node, e.g. "EdgeDevice", "CloudWorker", "OrchestratorHub".
    // </summary>
    [Required]
    [StringLength(64, MinimumLength = 1)]
    string NodeType,

    // <summary>
    // List of capability tokens this node advertises, e.g. "vision", "nlp", "code-exec".
    // </summary>
    string[] Capabilities,

    // <summary>Whether the node exposes CPU compute for inference workloads.</summary>
    bool SupportsCpu,

    // <summary>Whether the node exposes a discrete or integrated GPU.</summary>
    bool SupportsGpu,

    // <summary>Whether the node exposes a Neural Processing Unit (NPU / AI accelerator).</summary>
    bool SupportsNpu
)
{
    /// <summary>
    /// Returns a human-readable summary of the node's hardware profile.
    /// </summary>
    public string HardwareProfile =>
        $"CPU={SupportsCpu} | GPU={SupportsGpu} | NPU={SupportsNpu}";

    /// <summary>
    /// Returns true when the node supports at least one accelerated compute path.
    /// </summary>
    public bool IsAccelerated => SupportsGpu || SupportsNpu;
}