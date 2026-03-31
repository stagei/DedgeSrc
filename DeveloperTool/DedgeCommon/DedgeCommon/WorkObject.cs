using System.Collections.Generic;
using System.Dynamic;
using Newtonsoft.Json;

namespace DedgeCommon
{
    /// <summary>
    /// Represents a script execution entry in the WorkObject's ScriptArray.
    /// Tracks script execution history with timestamps and output.
    /// </summary>
    public class ScriptExecutionEntry
    {
        public string Name { get; set; } = string.Empty;
        public string FirstTimestamp { get; set; } = string.Empty;
        public string LastTimestamp { get; set; } = string.Empty;
        public string Script { get; set; } = string.Empty;
        public string Output { get; set; } = string.Empty;
        
        public ScriptExecutionEntry()
        {
            FirstTimestamp = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss");
            LastTimestamp = FirstTimestamp;
        }
    }

    /// <summary>
    /// Provides a dynamic object container for accumulating data during program execution.
    /// Mimics PowerShell's PSCustomObject pattern with dynamic property addition.
    /// Can be exported to JSON and HTML formats.
    /// </summary>
    /// <remarks>
    /// Usage pattern:
    /// 1. Create workObject
    /// 2. Add properties dynamically during execution
    /// 3. Add script executions to ScriptArray
    /// 4. Export to JSON and/or HTML at completion
    /// 5. Optionally publish to web path
    /// 
    /// This class replicates PowerShell's:
    /// - New-Object PSCustomObject
    /// - Add-Member -InputObject $workObject
    /// - Add-ScriptAndOutputToWorkObject
    /// - Export-WorkObjectToJsonFile
    /// - Export-WorkObjectToHtmlFile
    /// </remarks>
    public class WorkObject : DynamicObject
    {
        private readonly Dictionary<string, object?> _properties = new();
        private readonly List<ScriptExecutionEntry> _scriptArray = new();

        /// <summary>
        /// Gets the script execution history array.
        /// </summary>
        [JsonProperty(Order = 9999)]  // Ensure ScriptArray appears last in JSON
        public List<ScriptExecutionEntry> ScriptArray => _scriptArray;

        /// <summary>
        /// Gets all dynamic properties as a dictionary (useful for enumeration).
        /// </summary>
        [JsonIgnore]
        public IReadOnlyDictionary<string, object?> Properties => _properties;

        /// <summary>
        /// Sets a property value on the work object.
        /// </summary>
        /// <param name="name">Property name</param>
        /// <param name="value">Property value</param>
        public void SetProperty(string name, object? value)
        {
            if (name == nameof(ScriptArray))
            {
                throw new ArgumentException("Cannot set ScriptArray property directly. Use AddScriptExecution instead.");
            }
            
            _properties[name] = value;
        }

        /// <summary>
        /// Gets a property value from the work object.
        /// </summary>
        /// <typeparam name="T">Expected type of the property</typeparam>
        /// <param name="name">Property name</param>
        /// <returns>Property value cast to T, or default(T) if not found</returns>
        public T? GetProperty<T>(string name)
        {
            if (_properties.TryGetValue(name, out var value))
            {
                if (value == null) return default;
                
                try
                {
                    return (T)value;
                }
                catch
                {
                    return default;
                }
            }
            return default;
        }

        /// <summary>
        /// Checks if a property exists.
        /// </summary>
        public bool HasProperty(string name)
        {
            return _properties.ContainsKey(name);
        }

        /// <summary>
        /// Adds or updates a script execution entry in the ScriptArray.
        /// If a script with the same name exists, appends to it; otherwise creates new.
        /// Mimics PowerShell Add-ScriptAndOutputToWorkObject function.
        /// </summary>
        /// <param name="name">Script name identifier</param>
        /// <param name="script">Script content/SQL executed</param>
        /// <param name="output">Output from script execution</param>
        public void AddScriptExecution(string name, string script, string? output = null)
        {
            string timestamp = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss");
            
            // Add timestamp header to script and output
            string scriptWithHeader = $"\n___________________________________________________________________________\n" +
                                    $"-- Script executed at {timestamp}\n" +
                                    $"___________________________________________________________________________\n" +
                                    $"{script}";
            
            string outputWithHeader = $"\n___________________________________________________________________________\n" +
                                     $"-- Output result from script execution at {timestamp}\n" +
                                     $"___________________________________________________________________________\n" +
                                     $"{output ?? "N/A"}";

            // Check if entry already exists
            var existingEntry = _scriptArray.FirstOrDefault(e => e.Name == name);
            
            if (existingEntry != null)
            {
                // Append to existing entry
                existingEntry.Script += scriptWithHeader;
                existingEntry.Output += outputWithHeader;
                existingEntry.LastTimestamp = timestamp;
            }
            else
            {
                // Create new entry
                _scriptArray.Add(new ScriptExecutionEntry
                {
                    Name = name,
                    FirstTimestamp = timestamp,
                    LastTimestamp = timestamp,
                    Script = scriptWithHeader,
                    Output = outputWithHeader
                });
            }
        }

        // DynamicObject implementation for dynamic property access
        public override bool TryGetMember(GetMemberBinder binder, out object? result)
        {
            return _properties.TryGetValue(binder.Name, out result);
        }

        public override bool TrySetMember(SetMemberBinder binder, object? value)
        {
            SetProperty(binder.Name, value);
            return true;
        }

        public override IEnumerable<string> GetDynamicMemberNames()
        {
            return _properties.Keys;
        }

        /// <summary>
        /// Serializes the WorkObject to JSON including all dynamic properties.
        /// Uses custom converter to handle dynamic properties properly.
        /// </summary>
        public string ToJson(bool indented = true)
        {
            var settings = new JsonSerializerSettings
            {
                Formatting = indented ? Formatting.Indented : Formatting.None,
                NullValueHandling = NullValueHandling.Include,
                Converters = new List<JsonConverter> { new WorkObjectJsonConverter() }
            };
            
            return JsonConvert.SerializeObject(this, settings);
        }

        /// <summary>
        /// Custom JSON converter for WorkObject to properly serialize dynamic properties.
        /// </summary>
        private class WorkObjectJsonConverter : JsonConverter<WorkObject>
        {
            public override void WriteJson(JsonWriter writer, WorkObject? value, JsonSerializer serializer)
            {
                if (value == null)
                {
                    writer.WriteNull();
                    return;
                }

                writer.WriteStartObject();

                // Write all dynamic properties first
                foreach (var prop in value._properties.OrderBy(p => p.Key))
                {
                    writer.WritePropertyName(prop.Key);
                    serializer.Serialize(writer, prop.Value);
                }

                // Write ScriptArray last
                writer.WritePropertyName("ScriptArray");
                serializer.Serialize(writer, value._scriptArray);

                writer.WriteEndObject();
            }

            public override WorkObject ReadJson(JsonReader reader, Type objectType, WorkObject? existingValue, bool hasExistingValue, JsonSerializer serializer)
            {
                // Reading not implemented - primarily for export
                throw new NotImplementedException("WorkObject deserialization not implemented");
            }
        }
    }
}
