namespace SqlMermaidApi.Models;

// Request Models
public record ConvertSqlToMmdRequest
{
    public required string Sql { get; init; }
    public bool IncludeAst { get; init; } = false;
}

public record ConvertMmdToSqlRequest
{
    public required string Mermaid { get; init; }
    public string Dialect { get; init; } = "AnsiSql";
    public bool IncludeAst { get; init; } = false;
}

public record GenerateMigrationRequest
{
    public required string BeforeMermaid { get; init; }
    public required string AfterMermaid { get; init; }
    public string Dialect { get; init; } = "AnsiSql";
}

public record ValidateLicenseRequest
{
    public required string LicenseKey { get; init; }
    public required string Email { get; init; }
}

// Response Models
public record ConversionResponse
{
    public bool Success { get; init; }
    public string? Result { get; init; }
    public string? Ast { get; init; }
    public string? Error { get; init; }
    public ConversionMetadata? Metadata { get; init; }
}

public record ConversionMetadata
{
    public int TableCount { get; init; }
    public int ColumnCount { get; init; }
    public int RelationshipCount { get; init; }
    public string? Dialect { get; init; }
}

public record ApiKeyInfo
{
    public required string Tier { get; init; }
    public required string Email { get; init; }
    public int TableLimit { get; init; }
    public int RequestsToday { get; init; }
    public int DailyLimit { get; init; }
    public DateTime ExpiresAt { get; init; }
    public bool IsActive { get; init; }
}

public record ApiErrorResponse
{
    public required string Error { get; init; }
    public string? Detail { get; init; }
    public int StatusCode { get; init; }
}

// License Models
public enum LicenseTier
{
    Free,
    Pro,
    Enterprise
}

public record ApiKey
{
    public required string Key { get; init; }
    public required string Email { get; init; }
    public required string LicenseKey { get; init; }
    public required LicenseTier Tier { get; init; }
    public DateTime CreatedAt { get; init; }
    public DateTime ExpiresAt { get; init; }
    public bool IsActive { get; init; }
    public int RequestsToday { get; init; }
    public DateTime LastRequestAt { get; init; }
}

