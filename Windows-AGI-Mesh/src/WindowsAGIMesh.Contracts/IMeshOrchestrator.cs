namespace WindowsAGIMesh.Contracts;

/// <summary>
/// Defines the contract for the AGI Mesh orchestrator.
/// The orchestrator is responsible for dispatching tasks to agents,
/// collecting results, and enforcing governance policies.
/// </summary>
public interface IMeshOrchestrator
{
    /// <summary>
    /// Submits a task to the mesh for execution.
    /// The orchestrator selects the most suitable agent based on skills and trust level.
    /// </summary>
    /// <param name="task">The task to dispatch.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>The result produced by the executing agent.</returns>
    Task<MeshResult> DispatchAsync(
        MeshTask task,
        CancellationToken cancellationToken = default);

    /// <summary>
    /// Retrieves the current status of a previously submitted task.
    /// </summary>
    /// <param name="taskId">The unique identifier of the task.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    Task<MeshTask?> GetTaskStatusAsync(
        string taskId,
        CancellationToken cancellationToken = default);

    /// <summary>
    /// Cancels a running or pending task.
    /// </summary>
    /// <param name="taskId">The unique identifier of the task to cancel.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    Task CancelTaskAsync(
        string taskId,
        CancellationToken cancellationToken = default);

    /// <summary>
    /// Returns all results produced for a given task, including partial results
    /// from multi-agent collaborative executions.
    /// </summary>
    Task<IReadOnlyList<MeshResult>> GetResultsAsync(
        string taskId,
        CancellationToken cancellationToken = default);
}
