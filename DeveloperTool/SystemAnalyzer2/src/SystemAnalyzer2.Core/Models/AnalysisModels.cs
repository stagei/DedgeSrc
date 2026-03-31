using System.Text.Json.Serialization;

namespace SystemAnalyzer2.Core.Models;

public sealed class AnalysisIndex
{
    [JsonPropertyName("analyses")]
    public List<AnalysisMetadata> Analyses { get; set; } = [];
}

public sealed class AnalysisMetadata
{
    [JsonPropertyName("alias")]
    public string Alias { get; set; } = string.Empty;

    [JsonPropertyName("areas")]
    public List<string> Areas { get; set; } = [];

    [JsonPropertyName("created")]
    public string Created { get; set; } = string.Empty;

    [JsonPropertyName("lastRun")]
    public string LastRun { get; set; } = string.Empty;

    [JsonPropertyName("latestFolder")]
    public string LatestFolder { get; set; } = string.Empty;

    [JsonPropertyName("runs")]
    public List<AnalysisRun> Runs { get; set; } = [];

    [JsonPropertyName("allJsonSourcePath")]
    public string AllJsonSourcePath { get; set; } = string.Empty;

    [JsonPropertyName("parameters")]
    public AnalysisParameters Parameters { get; set; } = new();
}

public sealed class AnalysisRun
{
    [JsonPropertyName("folder")]
    public string Folder { get; set; } = string.Empty;

    [JsonPropertyName("timestamp")]
    public string Timestamp { get; set; } = string.Empty;
}

public sealed class AnalysisParameters
{
    [JsonPropertyName("db2Dsn")]
    public string Db2Dsn { get; set; } = string.Empty;

    [JsonPropertyName("maxCallIterations")]
    public int MaxCallIterations { get; set; } = 5;

    [JsonPropertyName("ragResults")]
    public int RagResults { get; set; } = 8;

    [JsonPropertyName("ragTableResults")]
    public int RagTableResults { get; set; } = 5;
}

public sealed class ProgramList
{
    [JsonPropertyName("title")]
    public string? Title { get; set; }

    [JsonPropertyName("generated")]
    public string? Generated { get; set; }

    [JsonPropertyName("totalPrograms")]
    public int TotalPrograms { get; set; }

    [JsonPropertyName("programs")]
    public List<ProgramInfo> Programs { get; set; } = [];
}

public sealed class ProgramInfo
{
    [JsonPropertyName("program")]
    public string Program { get; set; } = string.Empty;

    [JsonPropertyName("source")]
    public string? Source { get; set; }

    [JsonPropertyName("sourceType")]
    public string? SourceType { get; set; }

    [JsonPropertyName("sourcePath")]
    public string? SourcePath { get; set; }

    [JsonPropertyName("actualName")]
    public string? ActualName { get; set; }

    [JsonPropertyName("classification")]
    public string? Classification { get; set; }

    [JsonPropertyName("classificationConfidence")]
    public string? ClassificationConfidence { get; set; }

    [JsonPropertyName("classificationEvidence")]
    public string? ClassificationEvidence { get; set; }

    [JsonPropertyName("copyElements")]
    public List<CopyElementUsage> CopyElements { get; set; } = [];

    [JsonPropertyName("sqlOperations")]
    public List<SqlOperation> SqlOperations { get; set; } = [];

    [JsonPropertyName("callTargets")]
    public List<string> CallTargets { get; set; } = [];

    [JsonPropertyName("fileIO")]
    public List<FileIoMapping> FileIo { get; set; } = [];
}

public sealed class CopyElementUsage
{
    [JsonPropertyName("name")]
    public string Name { get; set; } = string.Empty;
}

public sealed class SqlOperation
{
    [JsonPropertyName("schema")]
    public string? Schema { get; set; }

    [JsonPropertyName("table")]
    public string? Table { get; set; }

    [JsonPropertyName("operation")]
    public string? Operation { get; set; }
}

public sealed class FileIoMapping
{
    [JsonPropertyName("logicalName")]
    public string? LogicalName { get; set; }

    [JsonPropertyName("path")]
    public string? Path { get; set; }

    [JsonPropertyName("operations")]
    public List<string> Operations { get; set; } = [];
}
