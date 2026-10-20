using System.ComponentModel.DataAnnotations;

namespace WindowsAGIMesh.Contracts;

/// <summary>
/// Defines a governance policy applied to agent actions within the AGI Mesh.
/// Policies control risk thresholds, human-in-the-loop requirements, and audit trails.
/// </summary>
public sealed record MeshPolicy
(
    /// <summary>Unique identifier for this policy.</summary>
    [Required]
    [StringLength(128, MinimumLength = 1)]
    string PolicyId,

    /// <summary>
    /// Risk classification for actions governed by this policy.
    /// Accepted values: "Low", "Medium", "High", "Critical".
    /// </summary>
    [Required]
    string RiskLevel,

    /// <summary>
    /// When true, a human reviewer must approve actions before execution.
    /// </summary>
    bool HumanReview,

    /// <summary>
    /// Maximum number of autonomous retries allowed before escalation.
    /// </summary>
    [Range(0, 10)]
    int MaxRetries = 3,

    /// <summary>
    /// Whether all actions governed by this policy must be written to an audit log.
    /// </summary>
    bool AuditRequired = true
)
{
    /// <summary>
    /// Returns true when the policy is classified as high-risk or critical.
    /// </summary>
    public bool IsHighRisk =>
        RiskLevel is "High" or "Critical";

    /// <summary>
    /// Returns true when the policy requires both human review and audit logging.
    /// </summary>
    public bool RequiresFullGovernance =>
        HumanReview && AuditRequired;
}