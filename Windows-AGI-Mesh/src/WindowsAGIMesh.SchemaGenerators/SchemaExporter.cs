using System.Reflection;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.ComponentModel.DataAnnotations;

namespace WindowsAGIMesh.SchemaGenerator;

/// <summary>
/// Generates a JSON Schema (Draft-07 compatible) document from a CLR type
/// by reflecting over its public properties and constructor parameters.
/// </summary>
public static class SchemaExporter
{
    private static readonly JsonSerializerOptions s_writeOptions = new()
    {
        WriteIndented = true,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull
    };

    /// <summary>
    /// Generates a JSON Schema string for the given <paramref name="type"/>.
    /// </summary>
    public static string Generate(Type type)
    {
        ArgumentNullException.ThrowIfNull(type);

        var required = new List<string>();
        var properties = new Dictionary<string, object>();

        foreach (PropertyInfo prop in type.GetProperties(
            BindingFlags.Public | BindingFlags.Instance))
        {
            bool isRequired = prop.GetCustomAttribute<RequiredAttribute>() is not null;

            if (isRequired)
            {
                required.Add(prop.Name);
            }

            var propSchema = BuildPropertySchema(prop);
            properties[prop.Name] = propSchema;
        }

        var schema = new Dictionary<string, object>
        {
            ["$schema"] = "http://json-schema.org/draft-07/schema#",
            ["title"] = type.Name,
            ["description"] = $"JSON Schema for {type.FullName}",
            ["type"] = "object",
            ["properties"] = properties
        };

        if (required.Count > 0)
        {
            schema["required"] = required;
        }

        return JsonSerializer.Serialize(schema, s_writeOptions);
    }

    private static Dictionary<string, object> BuildPropertySchema(PropertyInfo prop)
    {
        var schema = new Dictionary<string, object>();

        string jsonType = MapClrTypeToJsonType(prop.PropertyType);
        schema["type"] = jsonType;

        // Attach description from XML doc summary if available via attribute
        var rangeAttr = prop.GetCustomAttribute<RangeAttribute>();
        if (rangeAttr is not null)
        {
            if (rangeAttr.Minimum is double min)
            {
                schema["minimum"] = min;
            }

            if (rangeAttr.Maximum is double max && max != double.MaxValue)
            {
                schema["maximum"] = max;
            }
        }

        var stringLengthAttr = prop.GetCustomAttribute<StringLengthAttribute>();
        if (stringLengthAttr is not null)
        {
            schema["maxLength"] = stringLengthAttr.MaximumLength;

            if (stringLengthAttr.MinimumLength > 0)
            {
                schema["minLength"] = stringLengthAttr.MinimumLength;
            }
        }

        // Handle arrays: add items schema
        if (prop.PropertyType.IsArray)
        {
            Type? elementType = prop.PropertyType.GetElementType();
            schema["items"] = new Dictionary<string, object>
            {
                ["type"] = elementType is not null
                    ? MapClrTypeToJsonType(elementType)
                    : "string"
            };
        }

        // Handle nullable types
        Type underlying = Nullable.GetUnderlyingType(prop.PropertyType)
            ?? prop.PropertyType;

        bool isNullable = prop.PropertyType != underlying
            || prop.GetCustomAttribute<RequiredAttribute>() is null
               && prop.PropertyType.IsClass;

        if (isNullable && jsonType != "array")
        {
            schema["type"] = new[] { jsonType, "null" };
        }

        return schema;
    }

    private static string MapClrTypeToJsonType(Type type)
    {
        // Unwrap nullable
        Type t = Nullable.GetUnderlyingType(type) ?? type;

        if (t == typeof(string))   return "string";
        if (t == typeof(bool))     return "boolean";
        if (t == typeof(int)
         || t == typeof(long)
         || t == typeof(short)
         || t == typeof(byte))     return "integer";
        if (t == typeof(double)
         || t == typeof(float)
         || t == typeof(decimal))  return "number";
        if (t == typeof(DateTime)
         || t == typeof(DateTimeOffset)) return "string"; // ISO 8601
        if (t.IsArray)             return "array";
        if (t.IsGenericType
         && t.GetGenericTypeDefinition() == typeof(Dictionary<,>))
                                   return "object";
        if (t.IsGenericType
         && t.GetGenericTypeDefinition() == typeof(List<>))
                                   return "array";

        return "object";
    }
}
