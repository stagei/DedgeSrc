namespace AiDoc.WebNew.Models;

public class RagRegistry
{
    public string Host { get; set; } = "";
    public List<RagRegistryEntry> Rags { get; set; } = new();
}

public class RagRegistryEntry
{
    public string Name { get; set; } = "";
    public int Port { get; set; }
    public string Description { get; set; } = "";
}

public class RagIndexInfo
{
    public string Name { get; set; } = "";
    public string Description { get; set; } = "";
    public int Port { get; set; }
    public string Status { get; set; } = "unknown";
    public DateTime? BuiltAt { get; set; }
    public string? SourceHash { get; set; }
    public int SourceFileCount { get; set; }
    public long TotalSizeBytes { get; set; }
    public List<string> SourceFolders { get; set; } = new();
    public string? UncPath { get; set; }
}

public class RagSourceInfo
{
    public string RelativePath { get; set; } = "";
    public string FileName { get; set; } = "";
    public long SizeBytes { get; set; }
    public DateTime LastModified { get; set; }
    public bool IsDirectory { get; set; }
}

public class CreateRagRequest
{
    public string Name { get; set; } = "";
    public string Description { get; set; } = "";
    public int Port { get; set; }
}

public class AddSourceRequest
{
    public string SourcePath { get; set; } = "";
    public string? DisplayName { get; set; }
}

public class RebuildResult
{
    public bool Started { get; set; }
    public int? Pid { get; set; }
    public string? LogFile { get; set; }
}

public class RebuildStatus
{
    public bool Building { get; set; }
    public string? RagName { get; set; }
    public string? StartedAt { get; set; }
    public string? StartedBy { get; set; }
    public string? Server { get; set; }
    public int? Pid { get; set; }
    public int? Indexed { get; set; }
    public int? Total { get; set; }
    public double? Percentage { get; set; }
    public string? UpdatedAt { get; set; }
}

public class UploadResult
{
    public int Saved { get; set; }
    public int Converted { get; set; }
    public int Failed { get; set; }
    public List<string> Errors { get; set; } = new();
}

public class QueryRequest
{
    public string Query { get; set; } = "";
    public int NResults { get; set; } = 6;
}

public class IntegrationConfig
{
    public string Platform { get; set; } = "";
    public string Title { get; set; } = "";
    public string Description { get; set; } = "";
    public List<IntegrationStep> Steps { get; set; } = new();
    public object? ConfigTemplate { get; set; }
}

public class IntegrationStep
{
    public int Order { get; set; }
    public string Title { get; set; } = "";
    public string Description { get; set; } = "";
    public string? Code { get; set; }
    public string? Language { get; set; }
}
