namespace SqlMmdConverter.Tests.Utilities;

/// <summary>
/// Represents the result of a schema comparison operation.
/// </summary>
public class SchemaComparisonResult
{
    /// <summary>
    /// Indicates whether the schemas match.
    /// </summary>
    public bool IsMatch { get; set; }

    /// <summary>
    /// List of differences found between the schemas.
    /// </summary>
    public List<string> Differences { get; set; } = new();

    /// <summary>
    /// Similarity score between 0.0 and 1.0.
    /// </summary>
    public double SimilarityScore { get; set; }

    /// <summary>
    /// Gets a formatted string of all differences.
    /// </summary>
    public string GetDifferencesReport()
    {
        if (Differences.Count == 0)
        {
            return "No differences found";
        }

        return string.Join("\n", Differences.Select((d, i) => $"{i + 1}. {d}"));
    }
}

