using System.ComponentModel.DataAnnotations;

namespace WindowsAGIMesh.Contracts;

/// <summary>
/// Represents a unit of work dispatched to one or more agents in the AGI Mesh.
/// Tasks carry input payloads, routing metadata, and execution constraints.
/// </summary>
public sealed record MeshTask
(
    // <summary>Unique identifier for this task.</summary>
    [Required]
    [StringLength(128, MinimumLength = 1)]
    string TaskId,

    // <summary>
    // Human-readable description of what the task should accomplish.
    // </summary>
    [Required]
    [StringLength(2048, MinimumLength = 1)]
    string Description,

    // <summary>
    // Priority level: "Low", "Normal", "High", "Critical".
    // </summary>
    string Priority = "Normal",

    // <summary>
    // Identifier of the agent assigned to execute this task.
    // Null means the orchestrator will assign dynamically.
    // </summary>
    string? AssignedAgentId = null,

    // <summary>UTC timestamp when the task was created.</summary>
    DateTime? CreatedAt = null,

    // <summary>
    // Optional deadline by which the task must complete.
    // </summary>
    DateTime? Deadline = null,

    // <summary>
    // Current lifecycle status: "Pending", "Running", "Completed", "Failed", "Cancelled".
    // </summary>
    string Status = "Pending",

    // <summary>
    // Arbitrary key-value metadata attached to the task (e.g. tenant, correlation IDs).
    // </summary>
    Dictionary<string, string>? Metadata = null
)
{
    /// <summary>Returns true when the task has not yet started.</summary>
    public bool IsPending =>
        string.Equals(Status, "Pending", StringComparison.OrdinalIgnoreCase);

    /// <summary>Returns true when the task finished successfully.</summary>
    public bool IsCompleted =>
        string.Equals(Status, "Completed", StringComparison.OrdinalIgnoreCase);

    /// <summary>Returns true when the task is overdue relative to its deadline.</summary>
    public bool IsOverdue =>
        Deadline.HasValue && DateTime.UtcNow > Deadline.Value && !IsCompleted;
}