using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Serialization;
using SystemAnalyzer2.Core.Models.AutoDoc;

namespace SystemAnalyzer2.Batch.Services.Shared;

/// <summary>
/// Writes per-file JSON result files alongside HTML output.
/// Used by all parsers to serialize their structured data.
/// </summary>
public static class JsonResultWriter
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
        Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping
    };

    /// <summary>
    /// Write a DocFileResult (or subclass) as JSON to the output folder.
    /// File name: {baseFileName}.json (e.g. BSAUTOS.CBL.json)
    /// </summary>
    public static void WriteResult<T>(T result, string outputFolder, string baseFileName) where T : DocFileResult
    {
        try
        {
            string jsonPath = Path.Combine(outputFolder, baseFileName + ".json");
            string json = JsonSerializer.Serialize(result, JsonOptions);
            File.WriteAllText(jsonPath, json, Encoding.UTF8);
            AutoDocLogger.LogMessage($"Saved JSON result: {jsonPath}", LogLevel.INFO);
        }
        catch (Exception ex)
        {
            AutoDocLogger.LogMessage($"Failed to write JSON result for {baseFileName}: {ex.Message}", LogLevel.WARN);
        }
    }
}
