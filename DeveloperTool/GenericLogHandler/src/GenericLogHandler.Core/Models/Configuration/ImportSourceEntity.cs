using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace GenericLogHandler.Core.Models.Configuration;

/// <summary>
/// Database entity for storing import source configurations.
/// Replaces the JSON-based ImportSource configuration for runtime management.
/// </summary>
[Table("import_sources")]
public class ImportSourceEntity
{
    /// <summary>
    /// Unique identifier for the import source
    /// </summary>
    [Key]
    [Column("id")]
    public Guid Id { get; set; } = Guid.NewGuid();

    /// <summary>
    /// Display name for the import source
    /// </summary>
    [Required]
    [Column("name")]
    [MaxLength(200)]
    public string Name { get; set; } = string.Empty;

    /// <summary>
    /// Type of import source: file, json, xml, database, eventlog
    /// </summary>
    [Required]
    [Column("type")]
    [MaxLength(50)]
    public string Type { get; set; } = "file";

    /// <summary>
    /// Whether this source is enabled for import
    /// </summary>
    [Column("enabled")]
    public bool Enabled { get; set; } = true;

    /// <summary>
    /// Priority order (lower = higher priority)
    /// </summary>
    [Column("priority")]
    public int Priority { get; set; } = 100;

    /// <summary>
    /// File path pattern or connection string
    /// </summary>
    [Required]
    [Column("path")]
    [MaxLength(1000)]
    public string Path { get; set; } = string.Empty;

    /// <summary>
    /// Format of the source: json, xml, powershell, raw, delimited, etc.
    /// </summary>
    [Column("format")]
    [MaxLength(50)]
    public string Format { get; set; } = "json";

    /// <summary>
    /// Whether to watch the directory for new files
    /// </summary>
    [Column("watch_directory")]
    public bool WatchDirectory { get; set; } = false;

    /// <summary>
    /// File encoding (utf-8, utf-16, etc.)
    /// </summary>
    [Column("encoding")]
    [MaxLength(50)]
    public string Encoding { get; set; } = "utf-8";

    /// <summary>
    /// Poll interval in seconds for non-watching sources
    /// </summary>
    [Column("poll_interval")]
    public int PollInterval { get; set; } = 30;

    /// <summary>
    /// Whether to process existing files on startup
    /// </summary>
    [Column("process_existing")]
    public bool ProcessExistingFiles { get; set; } = true;

    /// <summary>
    /// Whether files are append-only (like log files)
    /// </summary>
    [Column("is_append_only")]
    public bool IsAppendOnly { get; set; } = false;

    /// <summary>
    /// Maximum file age in days to process (0 = no limit)
    /// </summary>
    [Column("max_file_age_days")]
    public int MaxFileAgeDays { get; set; } = 30;

    /// <summary>
    /// Full configuration JSON for advanced settings (ImportSourceConfig serialized)
    /// </summary>
    [Column("config_json")]
    public string? ConfigJson { get; set; }

    /// <summary>
    /// Optional description of the import source
    /// </summary>
    [Column("description")]
    [MaxLength(1000)]
    public string? Description { get; set; }

    /// <summary>
    /// When the source was created
    /// </summary>
    [Column("created_at")]
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    /// <summary>
    /// When the source was last modified
    /// </summary>
    [Column("updated_at")]
    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;

    /// <summary>
    /// Who created this source
    /// </summary>
    [Column("created_by")]
    [MaxLength(200)]
    public string? CreatedBy { get; set; }

    /// <summary>
    /// Last successful import timestamp
    /// </summary>
    [Column("last_import_at")]
    public DateTime? LastImportAt { get; set; }

    /// <summary>
    /// Number of records imported in last run
    /// </summary>
    [Column("last_import_count")]
    public int LastImportCount { get; set; }

    /// <summary>
    /// Last error message if import failed
    /// </summary>
    [Column("last_error")]
    [MaxLength(2000)]
    public string? LastError { get; set; }
}
