namespace WindowsAGIMesh.Schemas;

/// <summary>
/// Represents the outcome of a schema or payload validation operation.
/// </summary>
public sealed class ValidationResult
{
    /// <summary>Whether the validation passed.</summary>
    public bool IsValid { get; }

    /// <summary>
    /// Human-readable error message when <see cref="IsValid"/> is false.
    /// Null when validation succeeded.
    /// </summary>
    public string? ErrorMessage { get; }

    private ValidationResult(bool isValid, string? errorMessage)
    {
        IsValid      = isValid;
        ErrorMessage = errorMessage;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Factory methods
    // ─────────────────────────────────────────────────────────────────────────

    /// <summary>Creates a successful validation result.</summary>
    public static ValidationResult Ok() =>
        new(isValid: true, errorMessage: null);

    /// <summary>Creates a failed validation result with the given error message.</summary>
    /// <param name="errorMessage">Description of why validation failed.</param>
    public static ValidationResult Fail(string errorMessage) =>
        new(isValid: false, errorMessage: errorMessage);

    // ─────────────────────────────────────────────────────────────────────────
    // Helpers
    // ─────────────────────────────────────────────────────────────────────────

    /// <summary>
    /// Throws an <see cref="InvalidOperationException"/> when validation failed.
    /// </summary>
    public void ThrowIfInvalid()
    {
        if (!IsValid)
        {
            throw new InvalidOperationException(
                ErrorMessage ?? "Validation failed.");
        }
    }

    /// <inheritdoc/>
    public override string ToString() =>
        IsValid
            ? "Valid"
            : $"Invalid: {ErrorMessage}";

    /// <summary>
    /// Implicit conversion to bool for use in conditional expressions.
    /// </summary>
    public static implicit operator bool(ValidationResult result) =>
        result.IsValid;
}
