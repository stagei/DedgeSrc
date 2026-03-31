using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace GenericLogHandler.Core.Models.Configuration;

/// <summary>
/// Configures minimum log level filtering per file pattern during import.
/// Entries below the minimum level are skipped.
/// </summary>
[Table("import_level_filters")]
public class ImportLevelFilter
{
    /// <summary>
    /// Unique identifier
    /// </summary>
    [Key]
    [Column("id")]
    public Guid Id { get; set; } = Guid.NewGuid();

    /// <summary>
    /// Display name for this filter rule
    /// </summary>
    [Required]
    [Column("name")]
    [MaxLength(200)]
    public string Name { get; set; } = string.Empty;

    /// <summary>
    /// Regex pattern to match against file paths
    /// </summary>
    [Required]
    [Column("file_pattern")]
    [MaxLength(500)]
    public string FilePattern { get; set; } = string.Empty;

    /// <summary>
    /// Minimum log level to import (inclusive).
    /// Logs below this level are skipped.
    /// Values: TRACE=0, DEBUG=1, INFO=2, WARN=3, ERROR=4, FATAL=5
    /// </summary>
    [Required]
    [Column("min_level")]
    public int MinLevel { get; set; } = 0; // Default: import all

    /// <summary>
    /// Whether this filter is active
    /// </summary>
    [Column("is_enabled")]
    public bool IsEnabled { get; set; } = true;

    /// <summary>
    /// Priority order (lower = higher priority, checked first)
    /// </summary>
    [Column("priority")]
    public int Priority { get; set; } = 100;

    /// <summary>
    /// Optional description of what this filter does
    /// </summary>
    [Column("description")]
    [MaxLength(1000)]
    public string? Description { get; set; }

    /// <summary>
    /// When the filter was created
    /// </summary>
    [Column("created_at")]
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    /// <summary>
    /// When the filter was last modified
    /// </summary>
    [Column("updated_at")]
    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;

    /// <summary>
    /// Who created this filter
    /// </summary>
    [Column("created_by")]
    [MaxLength(200)]
    public string? CreatedBy { get; set; }

    /// <summary>
    /// Helper to get log level name from numeric value
    /// </summary>
    [NotMapped]
    public string MinLevelName => MinLevel switch
    {
        0 => "TRACE",
        1 => "DEBUG",
        2 => "INFO",
        3 => "WARN",
        4 => "ERROR",
        5 => "FATAL",
        _ => "UNKNOWN"
    };

    /// <summary>
    /// Checks if a given log level should be imported based on this filter
    /// </summary>
    public bool ShouldImport(string logLevel)
    {
        var levelValue = logLevel?.ToUpperInvariant() switch
        {
            "TRACE" => 0,
            "DEBUG" => 1,
            "INFO" => 2,
            "WARN" or "WARNING" => 3,
            "ERROR" => 4,
            "FATAL" or "CRITICAL" => 5,
            _ => 2 // Default to INFO
        };

        return levelValue >= MinLevel;
    }
}
