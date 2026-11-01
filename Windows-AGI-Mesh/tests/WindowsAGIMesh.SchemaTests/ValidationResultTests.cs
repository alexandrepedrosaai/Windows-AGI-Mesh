using WindowsAGIMesh.Schemas;

namespace WindowsAGIMesh.SchemaTests;

/// <summary>
/// Unit tests for <see cref="ValidationResult"/>.
/// </summary>
public sealed class ValidationResultTests
{
    [Fact]
    public void Ok_IsValid_ReturnsTrue()
    {
        ValidationResult result = ValidationResult.Ok();
        result.IsValid.Should().BeTrue();
    }

    [Fact]
    public void Ok_ErrorMessage_IsNull()
    {
        ValidationResult result = ValidationResult.Ok();
        result.ErrorMessage.Should().BeNull();
    }

    [Fact]
    public void Fail_IsValid_ReturnsFalse()
    {
        ValidationResult result = ValidationResult.Fail("Something went wrong.");
        result.IsValid.Should().BeFalse();
    }

    [Fact]
    public void Fail_ErrorMessage_ContainsMessage()
    {
        const string message = "Field 'NodeId' is required.";
        ValidationResult result = ValidationResult.Fail(message);
        result.ErrorMessage.Should().Be(message);
    }

    [Fact]
    public void ToString_WhenValid_ReturnsValid()
    {
        ValidationResult result = ValidationResult.Ok();
        result.ToString().Should().Be("Valid");
    }

    [Fact]
    public void ToString_WhenInvalid_ContainsErrorMessage()
    {
        ValidationResult result = ValidationResult.Fail("Missing field.");
        result.ToString().Should().Contain("Missing field.");
    }

    [Fact]
    public void ImplicitBoolConversion_WhenValid_ReturnsTrue()
    {
        ValidationResult result = ValidationResult.Ok();
        bool value = result;
        value.Should().BeTrue();
    }

    [Fact]
    public void ImplicitBoolConversion_WhenInvalid_ReturnsFalse()
    {
        ValidationResult result = ValidationResult.Fail("Error.");
        bool value = result;
        value.Should().BeFalse();
    }

    [Fact]
    public void ThrowIfInvalid_WhenValid_DoesNotThrow()
    {
        ValidationResult result = ValidationResult.Ok();
        Action act = () => result.ThrowIfInvalid();
        act.Should().NotThrow();
    }

    [Fact]
    public void ThrowIfInvalid_WhenInvalid_ThrowsInvalidOperationException()
    {
        ValidationResult result = ValidationResult.Fail("Validation failed.");
        Action act = () => result.ThrowIfInvalid();
        act.Should().Throw<InvalidOperationException>()
            .WithMessage("*Validation failed*");
    }
}