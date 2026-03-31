namespace DedgeRemoteConnect.Models;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using System.Diagnostics;

public class RequiredPortsConverter : JsonConverter<Dictionary<string, int>>
{
    public override Dictionary<string, int>? ReadJson(JsonReader reader, Type objectType, Dictionary<string, int>? existingValue, bool hasExistingValue, JsonSerializer serializer)
    {
        Dictionary<string, int> result = new();
        JObject obj = JObject.Load(reader);

        foreach (JProperty prop in obj.Properties())
        {
            if (prop.Value.Type == JTokenType.Integer)
            {
                result[prop.Name] = prop.Value.Value<int>();
            }
            else if (prop.Value.Type == JTokenType.Array)
            {
                // For arrays, take the first value
                List<int> array = prop.Value.Values<int>().ToList();
                if (array.Any())
                {
                    result[prop.Name] = array[0];
                }
            }
        }

        return result;
    }

    public override void WriteJson(JsonWriter writer, Dictionary<string, int>? value, JsonSerializer serializer)
    {
        // We don't need to implement this as we're only reading
    }
}

public class Computer
{
    public string Name { get; set; } = string.Empty;
    public string Type { get; set; } = string.Empty;
    public string Platform { get; set; } = string.Empty;
    public string Purpose { get; set; } = string.Empty;
    public List<string> Applications { get; set; } = new();
    public string Comments { get; set; } = string.Empty;
    public string DomainName { get; set; } = string.Empty;
    public bool IsActive { get; set; }
    
    // This can now be either a string or an array in JSON
    [JsonConverter(typeof(EnvironmentConverter))]
    public List<string> Environments { get; set; } = new();
    
    // Keep the old property for backward compatibility
    [JsonIgnore]
    public string Environment 
    { 
        get => Environments.FirstOrDefault() ?? string.Empty;
        set
        {
            if (!string.IsNullOrEmpty(value) && !Environments.Contains(value))
            {
                Environments.Clear();
                Environments.Add(value);
            }
        }
    }

    [JsonConverter(typeof(RequiredPortsConverter))]
    public Dictionary<string, int>? RequiredPorts { get; set; }

    public bool IsCustom { get; set; }
    public bool HasExistingRdp { get; set; }
    public string? SingleUser { get; set; }
    public string? ServiceUserName { get; set; }

    public override string ToString()
    {
        string status = IsCustom ? "" : "";
        string typeAndPlatform = string.IsNullOrEmpty(Type) ? "" : $"({Type} - {Platform})";
        string result = "";
        if (IsCustom)
            result = $"{Name}";
        else
            result = $"{Name} - {typeAndPlatform}{status}".TrimEnd('-');

        return result;
    }
}

// Custom converter to handle Environment as either string or array
public class EnvironmentConverter : JsonConverter<List<string>>
{
    public override List<string> ReadJson(JsonReader reader, Type objectType, List<string>? existingValue, bool hasExistingValue, JsonSerializer serializer)
    {
        List<string> result = new();
        
        try
        {
            if (reader.TokenType == JsonToken.Null)
            {
                return result; // Return empty list for null
            }
            else if (reader.TokenType == JsonToken.String)
            {
                // Handle single environment as string
                string value = reader.Value?.ToString() ?? string.Empty;
                if (!string.IsNullOrEmpty(value))
                {
                    result.Add(value);
                }
            }
            else if (reader.TokenType == JsonToken.StartArray)
            {
                // Handle multiple environments as array
                JArray array = JArray.Load(reader);
                foreach (var item in array)
                {
                    string value = item.ToString();
                    if (!string.IsNullOrEmpty(value))
                    {
                        result.Add(value);
                    }
                }
            }
            else
            {
                // For other token types, try to get a string value
                string value = reader.Value?.ToString() ?? string.Empty;
                if (!string.IsNullOrEmpty(value))
                {
                    result.Add(value);
                }
            }
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Error in EnvironmentConverter: {ex.Message}");
            // Return empty list on error rather than throwing
        }
        
        return result;
    }

    public override void WriteJson(JsonWriter writer, List<string>? value, JsonSerializer serializer)
    {
        if (value == null || !value.Any())
        {
            writer.WriteNull();
            return;
        }
        
        if (value.Count == 1)
        {
            writer.WriteValue(value[0]);
            return;
        }
        
        writer.WriteStartArray();
        foreach (var env in value)
        {
            writer.WriteValue(env);
        }
        writer.WriteEndArray();
    }

    public override bool CanRead => true;
    public override bool CanWrite => true;
}