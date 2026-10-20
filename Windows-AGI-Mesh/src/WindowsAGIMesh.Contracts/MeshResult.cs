using System.ComponentModel.DataAnnotations;

namespace WindowsAGIMesh.Contracts;

/// <summary>
/// Encapsulates the outcome of a task executed by an agent in the AGI Mesh.
/// Results carry the output payload, execution metrics, and error details when applicable.
/// </summary>
public sealed record MeshResult
(
    /// <summary>Unique identifier for this result record.</summary>
    [Required]
    [StringLength(128, MinimumLength = 1)]
    string ResultId,

    /// <summary>Identifier of the task that produced this result.</summary>
    [Required]
    string TaskId,

    /// <summary>Identifier of the agent that executed the task.</summary>
    [Required]
    string AgentId,

    /// <summary>
    /// Outcome status: "Success", "Failure", "PartialSuccess", "Timeout".
    /// </summary>
    [Required]
    string Status,

    /// <summary>
    /// JSON-serialised output produced by the agent. Empty string when the task failed.
    /// </summary>
    string Output = "{}",

    /// <summary>
    /// Human-readable error message when Status is "Failure" or "Timeout".
    /// </summary>
    string? ErrorMessage = null,

    /// <summary>Wall-clock execution time in milliseconds.</summary>
    [Range(0.0, double.MaxValue)]
    double ExecutionMs = 0.0,

    /// <summary>UTC timestamp when the result was produced.</summary>
    DateTime? CompletedAt = null
)
{
    /// <summary>Returns true when the task completed without errors.</summary>
    public bool IsSuccess =>
        string.Equals(Status, "Success", StringComparison.OrdinalIgnoreCase);

    /// <summary>Returns true when the task failed or timed out.</summary>
    public bool IsFailure =>
        Status is "Failure" or "Timeout";

    /// <summary>Returns a concise summary line for logging.</summary>
    public string Summary =>
        $"[{ResultId}] Task={TaskId} Agent={AgentId} Status={Status} ExecMs={ExecutionMs:F1}";
}