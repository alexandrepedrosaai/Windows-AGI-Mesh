using System.ComponentModel.DataAnnotations;

namespace WindowsAGIMesh.Contracts;

/// <summary>
/// Represents an autonomous agent registered in the AGI Mesh.
/// Agents are the primary actors that execute tasks, collaborate, and report results.
/// </summary>
public sealed record MeshAgent
(
    // <summary>Unique identifier for this agent instance.</summary>
    [Required]
    [StringLength(128, MinimumLength = 1)]
    string AgentId,

    // <summary>
    // Functional role of the agent, e.g. "Planner", "Executor", "Reviewer", "Orchestrator".
    // </summary>
    [Required]
    [StringLength(64, MinimumLength = 1)]
    string Role,

    // <summary>
    // Skill tokens this agent is capable of performing,
    // e.g. "summarization", "code-generation", "image-captioning".
    // </summary>
    string[] Skills,

    // <summary>
    // Trust level in the range [0.0, 1.0].
    // 0.0 = untrusted / sandboxed; 1.0 = fully trusted / privileged.
    // </summary>
    [Range(0.0, 1.0)]
    double TrustLevel
)
{
    /// <summary>
    /// Returns true when the agent is considered trusted (TrustLevel >= 0.8).
    /// </summary>
    public bool IsTrusted => TrustLevel >= 0.8;

    /// <summary>
    /// Returns true when the agent has the specified skill token.
    /// </summary>
    public bool HasSkill(string skill) =>
        Skills.Contains(skill, StringComparer.OrdinalIgnoreCase);
}