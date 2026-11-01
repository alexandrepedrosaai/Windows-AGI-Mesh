using WindowsAGIMesh.Schemas;

namespace WindowsAGIMesh.SchemaTests;

/// <summary>
/// Unit tests for <see cref="SchemaValidator"/>.
/// </summary>
public sealed class SchemaValidatorTests
{
    // ─────────────────────────────────────────────────────────────────────────
    // IsValidJson
    // ─────────────────────────────────────────────────────────────────────────

    [Fact]
    public void IsValidJson_WithValidObject_ReturnsTrue()
    {
        bool result = SchemaValidator.IsValidJson("""{ "key": "value" }""");
        result.Should().BeTrue();
    }

    [Fact]
    public void IsValidJson_WithValidArray_ReturnsTrue()
    {
        bool result = SchemaValidator.IsValidJson("""[1, 2, 3]""");
        result.Should().BeTrue();
    }

    [Fact]
    public void IsValidJson_WithValidNumber_ReturnsTrue()
    {
        bool result = SchemaValidator.IsValidJson("42");
        result.Should().BeTrue();
    }

    [Fact]
    public void IsValidJson_WithValidNull_ReturnsTrue()
    {
        bool result = SchemaValidator.IsValidJson("null");
        result.Should().BeTrue();
    }

    [Fact]
    public void IsValidJson_WithMissingClosingBrace_ReturnsFalse()
    {
        bool result = SchemaValidator.IsValidJson("""{ "key": "value" """);
        result.Should().BeFalse();
    }

    [Fact]
    public void IsValidJson_WithUnquotedKey_ReturnsFalse()
    {
        bool result = SchemaValidator.IsValidJson("""{ key: "value" }""");
        result.Should().BeFalse();
    }

    [Fact]
    public void IsValidJson_WithEmptyString_ReturnsFalse()
    {
        bool result = SchemaValidator.IsValidJson(string.Empty);
        result.Should().BeFalse();
    }

    [Fact]
    public void IsValidJson_WithWhitespaceOnly_ReturnsFalse()
    {
        bool result = SchemaValidator.IsValidJson("   ");
        result.Should().BeFalse();
    }

    [Fact]
    public void IsValidJson_WithNestedObject_ReturnsTrue()
    {
        bool result = SchemaValidator.IsValidJson(
            """
            {
                "outer": {
                    "inner": [1, 2, 3],
                    "flag": true
                }
            }
            """);
        result.Should().BeTrue();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ValidateRequiredFields
    // ─────────────────────────────────────────────────────────────────────────

    [Fact]
    public void ValidateRequiredFields_AllPresent_ReturnsValid()
    {
        ValidationResult result = SchemaValidator.ValidateRequiredFields(
            """{ "a": 1, "b": "hello" }""",
            "a", "b");

        result.IsValid.Should().BeTrue();
        result.ErrorMessage.Should().BeNull();
    }

    [Fact]
    public void ValidateRequiredFields_MissingField_ReturnsInvalid()
    {
        ValidationResult result = SchemaValidator.ValidateRequiredFields(
            """{ "a": 1 }""",
            "a", "b");

        result.IsValid.Should().BeFalse();
        result.ErrorMessage.Should().Contain("b");
    }

    [Fact]
    public void ValidateRequiredFields_NullField_ReturnsInvalid()
    {
        ValidationResult result = SchemaValidator.ValidateRequiredFields(
            """{ "a": null }""",
            "a");

        result.IsValid.Should().BeFalse();
    }

    [Fact]
    public void ValidateRequiredFields_InvalidJson_ReturnsInvalid()
    {
        ValidationResult result = SchemaValidator.ValidateRequiredFields(
            "not-json",
            "a");

        result.IsValid.Should().BeFalse();
    }

    [Fact]
    public void ValidateRequiredFields_RootIsArray_ReturnsInvalid()
    {
        ValidationResult result = SchemaValidator.ValidateRequiredFields(
            "[1, 2, 3]",
            "a");

        result.IsValid.Should().BeFalse();
        result.ErrorMessage.Should().Contain("object");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Domain-specific validators
    // ─────────────────────────────────────────────────────────────────────────

    [Fact]
    public void ValidateMeshNode_WithAllRequiredFields_ReturnsValid()
    {
        ValidationResult result = SchemaValidator.ValidateMeshNode(
            """
            {
                "NodeId": "node-001",
                "NodeType": "EdgeDevice",
                "Capabilities": ["vision", "nlp"]
            }
            """);

        result.IsValid.Should().BeTrue();
    }

    [Fact]
    public void ValidateMeshNode_MissingNodeId_ReturnsInvalid()
    {
        ValidationResult result = SchemaValidator.ValidateMeshNode(
            """
            {
                "NodeType": "EdgeDevice",
                "Capabilities": []
            }
            """);

        result.IsValid.Should().BeFalse();
        result.ErrorMessage.Should().Contain("NodeId");
    }

    [Fact]
    public void ValidateMeshAgent_WithAllRequiredFields_ReturnsValid()
    {
        ValidationResult result = SchemaValidator.ValidateMeshAgent(
            """
            {
                "AgentId": "agent-001",
                "Role": "Executor",
                "Skills": ["nlp"]
            }
            """);

        result.IsValid.Should().BeTrue();
    }

    [Fact]
    public void ValidateMeshTask_WithAllRequiredFields_ReturnsValid()
    {
        ValidationResult result = SchemaValidator.ValidateMeshTask(
            """
            {
                "TaskId": "task-001",
                "Description": "Summarise the report."
            }
            """);

        result.IsValid.Should().BeTrue();
    }

    [Fact]
    public void ValidateMeshResult_WithAllRequiredFields_ReturnsValid()
    {
        ValidationResult result = SchemaValidator.ValidateMeshResult(
            """
            {
                "ResultId": "result-001",
                "TaskId": "task-001",
                "AgentId": "agent-001",
                "Status": "Success"
            }
            """);

        result.IsValid.Should().BeTrue();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // GetPropertyCount
    // ─────────────────────────────────────────────────────────────────────────

    [Fact]
    public void GetPropertyCount_ValidObject_ReturnsCorrectCount()
    {
        int count = SchemaValidator.GetPropertyCount(
            """{ "a": 1, "b": 2, "c": 3 }""");

        count.Should().Be(3);
    }

    [Fact]
    public void GetPropertyCount_InvalidJson_ReturnsMinusOne()
    {
        int count = SchemaValidator.GetPropertyCount("not-json");
        count.Should().Be(-1);
    }

    [Fact]
    public void GetPropertyCount_Array_ReturnsMinusOne()
    {
        int count = SchemaValidator.GetPropertyCount("[1, 2, 3]");
        count.Should().Be(-1);
    }
}