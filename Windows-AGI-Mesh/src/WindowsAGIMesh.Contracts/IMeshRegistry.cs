namespace WindowsAGIMesh.Contracts;

/// <summary>
/// Defines the contract for a registry that tracks nodes and agents
/// participating in the AGI Mesh at runtime.
/// </summary>
public interface IMeshRegistry
{
    /// <summary>
    /// Registers a new node in the mesh.
    /// </summary>
    /// <param name="node">The node to register.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    Task RegisterNodeAsync(
        MeshNode node,
        CancellationToken cancellationToken = default);

    /// <summary>
    /// Removes a node from the mesh registry.
    /// </summary>
    /// <param name="nodeId">The unique identifier of the node to remove.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    Task UnregisterNodeAsync(
        string nodeId,
        CancellationToken cancellationToken = default);

    /// <summary>
    /// Returns all currently registered nodes.
    /// </summary>
    Task<IReadOnlyList<MeshNode>> GetNodesAsync(
        CancellationToken cancellationToken = default);

    /// <summary>
    /// Registers a new agent in the mesh.
    /// </summary>
    Task RegisterAgentAsync(
        MeshAgent agent,
        CancellationToken cancellationToken = default);

    /// <summary>
    /// Removes an agent from the mesh registry.
    /// </summary>
    Task UnregisterAgentAsync(
        string agentId,
        CancellationToken cancellationToken = default);

    /// <summary>
    /// Returns all currently registered agents.
    /// </summary>
    Task<IReadOnlyList<MeshAgent>> GetAgentsAsync(
        CancellationToken cancellationToken = default);

    /// <summary>
    /// Finds agents that possess all of the specified skill tokens.
    /// </summary>
    Task<IReadOnlyList<MeshAgent>> FindAgentsBySkillsAsync(
        IEnumerable<string> requiredSkills,
        CancellationToken cancellationToken = default);
}