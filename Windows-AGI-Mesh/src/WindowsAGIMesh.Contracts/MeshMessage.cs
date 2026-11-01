using System.ComponentModel.DataAnnotations;

namespace WindowsAGIMesh.Contracts;

/// <summary>
/// Represents a message exchanged between agents on the AGI Mesh message bus.
/// Messages carry typed payloads and routing envelopes for multi-agent communication.
/// </summary>
public sealed record MeshMessage
(
    // <summary>Unique identifier for this message.</summary>
    [Required]
    [StringLength(128, MinimumLength = 1)]
    string MessageId,

    // <summary>AgentId of the sender.</summary>
    [Required]
    string SenderId,

    // <summary>AgentId of the intended recipient. Null for broadcast messages.</summary>
    string? RecipientId,

    // <summary>
    // Message type token used for routing and deserialization,
    // e.g. "task.assigned", "result.ready", "heartbeat".
    // </summary>
    [Required]
    string MessageType,

    // <summary>
    // JSON-serialised payload body. Schema is determined by <see cref="MessageType"/>.
    // </summary>
    string Payload = "{}",

    // <summary>UTC timestamp when the message was created.</summary>
    DateTime? SentAt = null,

    // <summary>
    // Correlation identifier linking this message to a parent task or conversation thread.
    // </summary>
    string? CorrelationId = null
)
{
    /// <summary>Returns true when the message is a broadcast (no specific recipient).</summary>
    public bool IsBroadcast => RecipientId is null;

    /// <summary>Returns true when the message carries a heartbeat signal.</summary>
    public bool IsHeartbeat =>
        string.Equals(MessageType, "heartbeat", StringComparison.OrdinalIgnoreCase);
}