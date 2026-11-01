namespace WindowsAGIMesh.Contracts;

/// <summary>
/// Defines the contract for the policy engine that evaluates governance rules
/// before and after agent actions are executed in the AGI Mesh.
/// </summary>
public interface IMeshPolicyEngine
{
    /// <summary>
    /// Evaluates whether a task is permitted to execute under the applicable policy.
    /// </summary>
    /// <param name="task">The task requesting execution.</param>
    /// <param name="agent">The agent that will execute the task.</param>
    /// <param name="policy">The governance policy to evaluate against.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>
    /// True when the task is permitted; false when it must be blocked or escalated.
    /// </returns>
    Task<bool> EvaluateAsync(
        MeshTask task,
        MeshAgent agent,
        MeshPolicy policy,
        CancellationToken cancellationToken = default);

    /// <summary>
    /// Records an attestation for a completed or reviewed action.
    /// </summary>
    /// <param name="attestation">The attestation record to persist.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    Task AttestAsync(
        MeshAttestation attestation,
        CancellationToken cancellationToken = default);

    /// <summary>
    /// Retrieves all attestation records associated with a given subject (task or policy decision).
    /// </summary>
    /// <param name="subjectId">The subject identifier to query.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    Task<IReadOnlyList<MeshAttestation>> GetAttestationsAsync(
        string subjectId,
        CancellationToken cancellationToken = default);

    /// <summary>
    /// Returns the active policy that governs a given agent role.
    /// Returns null when no specific policy is configured for that role.
    /// </summary>
    Task<MeshPolicy?> GetPolicyForRoleAsync(
        string agentRole,
        CancellationToken cancellationToken = default);
}