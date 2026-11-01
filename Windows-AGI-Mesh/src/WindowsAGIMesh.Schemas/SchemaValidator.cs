using System.Text.Json;
using System.Text.Json.Nodes;

namespace WindowsAGIMesh.Schemas;

/// <summary>
/// Provides JSON validation utilities for AGI Mesh schema documents.
/// Validates structure, required fields, and type conformance against
/// the contracts defined in WindowsAGIMesh.Contracts.
/// </summary>
public static class SchemaValidator
{
    private static readonly JsonDocumentOptions s_docOptions = new()
    {
        AllowTrailingCommas = true,
        CommentHandling = JsonCommentHandling.Skip
    };

    // ─────────────────────────────────────────────────────────────────────────
    // Public API
    // ─────────────────────────────────────────────────────────────────────────

    /// <summary>
    /// Returns true when <paramref name="json"/> is syntactically valid JSON.
    /// </summary>
    public static bool IsValidJson(string json)
    {
        if (string.IsNullOrWhiteSpace(json))
        {
            return false;
        }

        try
        {
            using JsonDocument _ = JsonDocument.Parse(json, s_docOptions);
            return true;
        }
        catch (JsonException)
        {
            return false;
        }
    }

    /// <summary>
    /// Validates that <paramref name="json"/> is a JSON object containing
    /// all of the specified <paramref name="requiredFields"/>.
    /// </summary>
    /// <param name="json">The JSON string to validate.</param>
    /// <param name="requiredFields">Field names that must be present and non-null.</param>
    /// <returns>A <see cref="ValidationResult"/> describing the outcome.</returns>
    public static ValidationResult ValidateRequiredFields(
        string json,
        params string[] requiredFields)
    {
        if (!IsValidJson(json))
        {
            return ValidationResult.Fail("Input is not valid JSON.");
        }

        using JsonDocument doc = JsonDocument.Parse(json, s_docOptions);

        if (doc.RootElement.ValueKind != JsonValueKind.Object)
        {
            return ValidationResult.Fail("Root element must be a JSON object.");
        }

        var missing = new List<string>();

        foreach (string field in requiredFields)
        {
            if (!doc.RootElement.TryGetProperty(field, out JsonElement element)
                || element.ValueKind == JsonValueKind.Null)
            {
                missing.Add(field);
            }
        }

        return missing.Count == 0
            ? ValidationResult.Ok()
            : ValidationResult.Fail(
                $"Missing required fields: {string.Join(", ", missing)}");
    }

    /// <summary>
    /// Validates that a JSON string represents a well-formed MeshNode payload.
    /// </summary>
    public static ValidationResult ValidateMeshNode(string json) =>
        ValidateRequiredFields(json, "NodeId", "NodeType", "Capabilities");

    /// <summary>
    /// Validates that a JSON string represents a well-formed MeshAgent payload.
    /// </summary>
    public static ValidationResult ValidateMeshAgent(string json) =>
        ValidateRequiredFields(json, "AgentId", "Role", "Skills");

    /// <summary>
    /// Validates that a JSON string represents a well-formed MeshTask payload.
    /// </summary>
    public static ValidationResult ValidateMeshTask(string json) =>
        ValidateRequiredFields(json, "TaskId", "Description");

    /// <summary>
    /// Validates that a JSON string represents a well-formed MeshResult payload.
    /// </summary>
    public static ValidationResult ValidateMeshResult(string json) =>
        ValidateRequiredFields(json, "ResultId", "TaskId", "AgentId", "Status");

    /// <summary>
    /// Attempts to parse a JSON string and return the root element's property count.
    /// Returns -1 on parse failure.
    /// </summary>
    public static int GetPropertyCount(string json)
    {
        if (!IsValidJson(json))
        {
            return -1;
        }

        using JsonDocument doc = JsonDocument.Parse(json, s_docOptions);

        return doc.RootElement.ValueKind == JsonValueKind.Object
            ? doc.RootElement.EnumerateObject().Count()
            : -1;
    }
}