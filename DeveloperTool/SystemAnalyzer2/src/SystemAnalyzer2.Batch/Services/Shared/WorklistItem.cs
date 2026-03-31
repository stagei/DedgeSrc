namespace SystemAnalyzer2.Batch.Services.Shared;

/// <summary>
/// Represents one item in the worklist folder. Serialized as JSON in .work files.
/// </summary>
public class WorklistItem
{
    public string? LocalPath { get; set; }
    public string? UncPath { get; set; }
    public string? RepoName { get; set; }
    public string? RepoUrl { get; set; }
    public string? RepoLocalPath { get; set; }
    public string? RelativePath { get; set; }
    public string? CommitId { get; set; }
    public string? ParserType { get; set; }
    public string? FileName { get; set; }
    public string? TableName { get; set; }
    public string? AlterTime { get; set; }
}
