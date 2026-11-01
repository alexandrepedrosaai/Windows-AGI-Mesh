using System.ComponentModel.DataAnnotations;

namespace WindowsAGIMesh.Contracts;

/// <summary>
/// Records a human or automated attestation event for an agent action or policy decision.
/// Attestations form the immutable audit trail required by governance policies.
/// </summary>
public sealed record MeshAttestation
(
    // <summary>Unique identifier for this attestation record.</summary>
    [Required]
    [StringLength(128, MinimumLength = 1)]
    string AttestationId,

    // <summary>
    // Identity of the reviewer — a human user principal name or an automated service account.
    // </summary>
    [Required]
    [StringLength(256, MinimumLength = 1)]
    string Reviewer,

    // <summary>UTC timestamp when the attestation was recorded.</summary>
    DateTime Timestamp,

    // <summary>
    // Identifier of the agent action or policy decision being attested.
    // </summary>
    string SubjectId = "",

    // <summary>
    // Outcome of the attestation: "Approved", "Rejected", or "Escalated".
    // </summary>
    string Outcome = "Approved",

    // <summary>
    // Optional free-text notes provided by the reviewer.
    // </summary>
    string? Notes = null
)
{
    /// <summary>Returns true when the attestation outcome is "Approved".</summary>
    public bool IsApproved =>
        string.Equals(Outcome, "Approved", StringComparison.OrdinalIgnoreCase);

    /// <summary>Returns true when the attestation outcome is "Rejected".</summary>
    public bool IsRejected =>
        string.Equals(Outcome, "Rejected", StringComparison.OrdinalIgnoreCase);

    /// <summary>
    /// Returns a human-readable summary of the attestation event.
    /// </summary>
    public string Summary =>
        $"[{AttestationId}] {Outcome} by {Reviewer} at {Timestamp:u}";
}